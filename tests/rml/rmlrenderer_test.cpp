#include <gtest/gtest.h>

#include <framework/graphics/image.h>
#include <framework/graphics/texturemanager.h>
#include <framework/rml/rmlbackend.h>
#include <framework/rml/rmlrenderer.h>

#include <RmlUi/Core/RenderInterface.h>
#include <RmlUi/Core/Vertex.h>

#include <atomic>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace {

    using Log = std::vector<std::string>;

    // What the tests can observe. Shared with the fake backend, which RmlRenderer owns and destroys.
    struct Probe
    {
        Log log;
        std::vector<Rml::byte> lastTextureBytes;
        std::vector<const RmlTargetTexture*> targets;
        std::vector<const RmlBackend*> results;
        int created{ 0 };
        bool quiet{ false };          // do not log calls (stress tests)
        bool refuseShaders{ false };  // CompileShader returns 0 (unknown shader name)
        bool refuseFilters{ false };  // CompileFilter returns 0 (unknown filter name)
        int lastFilterCount{ -1 };    // filters handed to the last CompositeLayers
        int completeTextures{ 0 };    // GenerateTexture calls that carried all their bytes
        int incompleteTextures{ 0 };
        int releasedTextures{ 0 };
        bool failCreation{ false };
        ImagePtr image;
    };

    // Stands in for a GPU executor: hands out real handles from 1000 and records every call.
    class FakeBackend final : public RmlBackend, public Rml::RenderInterface
    {
    public:
        explicit FakeBackend(std::shared_ptr<Probe> probe) : m_probe(std::move(probe)) {}
        ~FakeBackend() override { note("destroyed"); }

        std::string name() const override { return "Fake"; }
        bool supportsAdvancedEffects() const override { return true; }
        Rml::RenderInterface& renderInterface() override { return *this; }
        void beginReplay() override { note("beginReplay"); }
        void endReplay() override { note("endReplay"); }
        void beginFrame(const RmlTargetTexturePtr& target) override
        {
            note("beginFrame");
            m_probe->targets.emplace_back(target.get());
        }
        void endFrame() override { note("endFrame"); }

        Rml::CompiledGeometryHandle CompileGeometry(Rml::Span<const Rml::Vertex>, Rml::Span<const int>) override
        {
            const auto handle = next();
            note("CompileGeometry:" + std::to_string(handle));
            return handle;
        }
        void RenderGeometry(const Rml::CompiledGeometryHandle geometry, Rml::Vector2f, const Rml::TextureHandle texture) override
        {
            note("RenderGeometry:" + std::to_string(geometry) + ":" + std::to_string(texture));
        }
        void ReleaseGeometry(const Rml::CompiledGeometryHandle geometry) override { note("ReleaseGeometry:" + std::to_string(geometry)); }

        Rml::TextureHandle LoadTexture(Rml::Vector2i&, const Rml::String&) override
        {
            note("LoadTexture"); // RmlRenderer loads images itself; the backend must never be asked
            return 0;
        }
        Rml::TextureHandle GenerateTexture(const Rml::Span<const Rml::byte> source, const Rml::Vector2i dimensions) override
        {
            const auto handle = next();
            m_probe->lastTextureBytes.assign(source.begin(), source.end());
            if (source.size() == static_cast<size_t>(dimensions.x) * dimensions.y * 4)
                ++m_probe->completeTextures;
            else
                ++m_probe->incompleteTextures;
            note("GenerateTexture:" + std::to_string(handle));
            return handle;
        }
        void ReleaseTexture(const Rml::TextureHandle texture) override
        {
            ++m_probe->releasedTextures;
            note("ReleaseTexture:" + std::to_string(texture));
        }

        void EnableScissorRegion(bool) override {}
        void SetScissorRegion(Rml::Rectanglei) override {}

        Rml::LayerHandle PushLayer() override
        {
            const auto handle = next();
            note("PushLayer:" + std::to_string(handle));
            return handle;
        }
        void CompositeLayers(const Rml::LayerHandle source, const Rml::LayerHandle destination, Rml::BlendMode,
                             const Rml::Span<const Rml::CompiledFilterHandle> filters) override
        {
            m_probe->lastFilterCount = static_cast<int>(filters.size());
            for (const auto filter : filters)
                EXPECT_NE(filter, 0u) << "an unresolved filter reached the backend";
            note("CompositeLayers:" + std::to_string(source) + ":" + std::to_string(destination));
        }
        void PopLayer() override { note("PopLayer"); }
        Rml::CompiledFilterHandle SaveLayerAsMaskImage() override
        {
            const auto handle = next();
            note("SaveLayerAsMaskImage:" + std::to_string(handle));
            return handle;
        }

        void RenderToClipMask(Rml::ClipMaskOperation, const Rml::CompiledGeometryHandle geometry, Rml::Vector2f) override
        {
            note("RenderToClipMask:" + std::to_string(geometry));
        }

        Rml::CompiledFilterHandle CompileFilter(const Rml::String& name, const Rml::Dictionary&) override
        {
            const auto handle = m_probe->refuseFilters ? 0 : next();
            note("CompileFilter:" + name + ":" + std::to_string(handle));
            return handle;
        }
        void ReleaseFilter(const Rml::CompiledFilterHandle filter) override { note("ReleaseFilter:" + std::to_string(filter)); }

        Rml::CompiledShaderHandle CompileShader(const Rml::String& name, const Rml::Dictionary&) override
        {
            const auto handle = m_probe->refuseShaders ? 0 : next();
            note("CompileShader:" + name + ":" + std::to_string(handle));
            return handle;
        }
        void RenderShader(const Rml::CompiledShaderHandle shader, const Rml::CompiledGeometryHandle geometry, Rml::Vector2f,
                          Rml::TextureHandle) override
        {
            note("RenderShader:" + std::to_string(shader) + ":" + std::to_string(geometry));
        }
        void ReleaseShader(const Rml::CompiledShaderHandle shader) override { note("ReleaseShader:" + std::to_string(shader)); }

    private:
        uintptr_t next() { return m_nextHandle++; }
        void note(std::string entry) const
        {
            if (!m_probe->quiet)
                m_probe->log.emplace_back(std::move(entry));
        }

        std::shared_ptr<Probe> m_probe;
        uintptr_t m_nextHandle{ 1000 };
    };

    RmlRendererHooks hooksFor(const std::shared_ptr<Probe>& probe)
    {
        RmlRendererHooks hooks;
        hooks.createBackend = [probe]() -> RmlBackendPtr {
            ++probe->created;
            if (probe->failCreation)
                return nullptr;
            return std::make_unique<FakeBackend>(probe);
        };
        hooks.loadImage = [probe](const std::string&) { return probe->image; };
        hooks.onBackendResult = [probe](const RmlBackend* backend) { probe->results.emplace_back(backend); };
        return hooks;
    }

    RmlTargetTexturePtr makeTarget() { return std::make_shared<RmlTargetTexture>(Size(64, 48)); }

    const std::vector<Rml::Vertex> kTriangle(3);
    const std::vector<int> kIndices{ 0, 1, 2 };

    bool contains(const Log& log, const std::string& prefix)
    {
        for (const auto& entry : log)
            if (entry.rfind(prefix, 0) == 0)
                return true;
        return false;
    }

    TEST(RmlRenderer, ReplayWithoutCommandsCreatesNoBackend)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));

        renderer.replay();

        EXPECT_EQ(probe->created, 0);
        EXPECT_TRUE(probe->log.empty());
        EXPECT_TRUE(probe->results.empty());
    }

    TEST(RmlRenderer, ProxyHandlesMapToBackendHandles)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));

        renderer.beginFrame(makeTarget());
        const auto geometry = renderer.CompileGeometry(kTriangle, kIndices);
        renderer.RenderGeometry(geometry, { 1.f, 2.f }, 0);
        renderer.endFrame();
        renderer.replay();

        EXPECT_NE(geometry, 0u);
        EXPECT_NE(geometry, 1000u); // RmlUi only ever sees the proxy
        const Log expected{ "beginReplay", "beginFrame", "CompileGeometry:1000", "RenderGeometry:1000:0", "endFrame", "endReplay" };
        EXPECT_EQ(probe->log, expected);
        ASSERT_EQ(probe->results.size(), 1u);
        EXPECT_NE(probe->results.front(), nullptr);
        EXPECT_FALSE(renderer.backendFailed());
        EXPECT_TRUE(renderer.hasAdvancedEffects());
    }

    TEST(RmlRenderer, ReleaseErasesMapping)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));

        renderer.beginFrame(makeTarget());
        const auto geometry = renderer.CompileGeometry(kTriangle, kIndices);
        renderer.ReleaseGeometry(geometry);
        renderer.endFrame();
        renderer.replay();
        ASSERT_TRUE(contains(probe->log, "ReleaseGeometry:1000"));

        probe->log.clear();
        renderer.beginFrame(makeTarget());
        renderer.RenderGeometry(geometry, {}, 0);
        renderer.endFrame();
        renderer.replay();

        EXPECT_FALSE(contains(probe->log, "RenderGeometry"));
    }

    TEST(RmlRenderer, ResourcesCreatedOutsideFrameRunBeforeTheFrame)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const std::vector<Rml::byte> pixel{ 1, 2, 3, 4 };

        const auto texture = renderer.GenerateTexture(pixel, { 1, 1 }); // e.g. during Context::Update
        renderer.beginFrame(makeTarget());
        renderer.RenderGeometry(renderer.CompileGeometry(kTriangle, kIndices), {}, texture);
        renderer.endFrame();
        renderer.replay();

        const Log expected{ "beginReplay", "GenerateTexture:1000", "beginFrame", "CompileGeometry:1001",
                            "RenderGeometry:1001:1000", "endFrame", "endReplay" };
        EXPECT_EQ(probe->log, expected);
    }

    TEST(RmlRenderer, LayerHandlesExpireAtEndOfFrame)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));

        renderer.beginFrame(makeTarget());
        const auto layer = renderer.PushLayer();
        renderer.CompositeLayers(layer, 0, Rml::BlendMode::Blend, {});
        renderer.PopLayer();
        renderer.endFrame();
        renderer.replay();
        ASSERT_TRUE(contains(probe->log, "CompositeLayers:1000:0")); // valid inside its own frame

        probe->log.clear();
        renderer.beginFrame(makeTarget());
        renderer.CompositeLayers(layer, 0, Rml::BlendMode::Blend, {});
        renderer.endFrame();
        renderer.replay();

        EXPECT_TRUE(contains(probe->log, "CompositeLayers:0:0"));
    }

    TEST(RmlRenderer, BackendCreationFailureIsReportedOnce)
    {
        const auto probe = std::make_shared<Probe>();
        probe->failCreation = true;
        RmlRenderer renderer(hooksFor(probe));

        for (int frame = 0; frame < 3; ++frame) {
            renderer.beginFrame(makeTarget());
            renderer.RenderGeometry(renderer.CompileGeometry(kTriangle, kIndices), {}, 0);
            renderer.endFrame();
            renderer.replay();
        }

        EXPECT_EQ(probe->created, 1);
        ASSERT_EQ(probe->results.size(), 1u);
        EXPECT_EQ(probe->results.front(), nullptr);
        EXPECT_TRUE(renderer.backendFailed());
        EXPECT_FALSE(renderer.hasAdvancedEffects());
        EXPECT_TRUE(probe->log.empty());
    }

    TEST(RmlRenderer, RetireStopsRecordingButKeepsReleases)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const std::vector<Rml::byte> pixel{ 1, 2, 3, 4 };

        renderer.beginFrame(makeTarget());
        const auto texture = renderer.GenerateTexture(pixel, { 1, 1 });
        const auto geometry = renderer.CompileGeometry(kTriangle, kIndices);
        renderer.endFrame();
        renderer.replay();

        probe->log.clear();
        renderer.retire();
        EXPECT_EQ(renderer.CompileGeometry(kTriangle, kIndices), 0u);
        renderer.RenderGeometry(geometry, {}, texture);
        renderer.ReleaseTexture(texture);
        renderer.ReleaseGeometry(geometry);
        renderer.releaseBackend();

        EXPECT_FALSE(contains(probe->log, "RenderGeometry"));
        EXPECT_FALSE(contains(probe->log, "CompileGeometry"));
        EXPECT_TRUE(contains(probe->log, "ReleaseTexture:1000"));
        EXPECT_TRUE(contains(probe->log, "ReleaseGeometry:1001"));
    }

    TEST(RmlRenderer, ReleaseBackendDestroysBackendAfterPendingReleases)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const std::vector<Rml::byte> pixel{ 1, 2, 3, 4 };

        renderer.beginFrame(makeTarget());
        const auto texture = renderer.GenerateTexture(pixel, { 1, 1 });
        renderer.endFrame();
        renderer.replay();

        probe->log.clear();
        renderer.retire();
        renderer.ReleaseTexture(texture);
        renderer.releaseBackend();

        const Log expected{ "beginReplay", "ReleaseTexture:1000", "endReplay", "destroyed" };
        EXPECT_EQ(probe->log, expected);

        // Nothing is left to run against: later calls are inert.
        probe->log.clear();
        renderer.replay();
        renderer.releaseBackend();
        EXPECT_TRUE(probe->log.empty());
        EXPECT_EQ(probe->created, 1);
    }

    TEST(RmlRenderer, LoadTexturePremultipliesAlpha)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const uint8_t rgba[4]{ 200, 100, 50, 128 };
        probe->image = std::make_shared<Image>(Size(1, 1), 4, rgba);

        Rml::Vector2i dimensions;
        const auto texture = renderer.LoadTexture(dimensions, "item/3031.png");
        renderer.replay();

        EXPECT_NE(texture, 0u);
        EXPECT_EQ(dimensions, Rml::Vector2i(1, 1));
        const std::vector<Rml::byte> expected{ 100, 50, 25, 128 };
        EXPECT_EQ(probe->lastTextureBytes, expected);
        EXPECT_FALSE(contains(probe->log, "LoadTexture"));
    }

    TEST(RmlRenderer, LoadTextureOfMissingImageReturnsNoHandle)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        probe->image = nullptr;

        Rml::Vector2i dimensions;
        const auto texture = renderer.LoadTexture(dimensions, "nope.png");
        renderer.replay();

        EXPECT_EQ(texture, 0u);
        EXPECT_EQ(probe->created, 0);
    }

    TEST(RmlRenderer, EachFrameReachesItsTarget)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const auto first = makeTarget();
        const auto second = makeTarget();

        renderer.beginFrame(first);
        renderer.endFrame();
        renderer.beginFrame(second);
        renderer.endFrame();
        renderer.replay();

        const std::vector<const RmlTargetTexture*> expected{ first.get(), second.get() };
        EXPECT_EQ(probe->targets, expected);
    }

    TEST(RmlRenderer, ReplayIsBracketedByBeginEndReplay)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));

        renderer.beginFrame(makeTarget());
        renderer.endFrame();
        renderer.replay();

        ASSERT_FALSE(probe->log.empty());
        EXPECT_EQ(probe->log.front(), "beginReplay");
        EXPECT_EQ(probe->log.back(), "endReplay");

        probe->log.clear();
        renderer.replay(); // nothing queued: the backend is not touched
        EXPECT_TRUE(probe->log.empty());
    }

    // RmlUi creates and releases resources outside of a frame too (Context::Update on the UI
    // thread) while the graphics thread is replaying. A command must only become visible to
    // the graphics thread once it is completely filled in.
    TEST(RmlRenderer, CommandsRecordedOutsideAFrameAreCompleteWhenReplayedConcurrently)
    {
        const auto probe = std::make_shared<Probe>();
        probe->quiet = true;
        RmlRenderer renderer(hooksFor(probe));
        const std::vector<Rml::byte> pixels(64 * 64 * 4, 0x7F);
        constexpr int kRounds = 20000;

        std::atomic_bool stop{ false };
        std::thread graphics([&] {
            while (!stop.load(std::memory_order_relaxed))
                renderer.replay();
        });

        for (int i = 0; i < kRounds; ++i) {
            const auto texture = renderer.GenerateTexture(pixels, { 64, 64 });
            renderer.ReleaseTexture(texture);
        }

        stop = true;
        graphics.join();
        renderer.replay(); // whatever is still queued

        EXPECT_EQ(probe->incompleteTextures, 0);
        EXPECT_EQ(probe->completeTextures, kRounds);
        EXPECT_EQ(probe->releasedTextures, kRounds);
    }

    // A backend may refuse a shader or a filter (unknown name in the RCSS, e.g. decorator:
    // shader("x")). RmlUi only ever holds our proxy, so it keeps using it: the refusal must be
    // absorbed here instead of reaching the backend as a null handle.
    TEST(RmlRenderer, RenderShaderWithARefusedShaderIsSkipped)
    {
        const auto probe = std::make_shared<Probe>();
        probe->refuseShaders = true;
        RmlRenderer renderer(hooksFor(probe));

        renderer.beginFrame(makeTarget());
        const auto geometry = renderer.CompileGeometry(kTriangle, kIndices);
        const auto shader = renderer.CompileShader("x", {});
        renderer.RenderShader(shader, geometry, {}, 0);
        renderer.ReleaseShader(shader);
        renderer.endFrame();
        renderer.replay();

        EXPECT_NE(shader, 0u);
        EXPECT_TRUE(contains(probe->log, "CompileShader:x:0"));
        EXPECT_FALSE(contains(probe->log, "RenderShader"));
        EXPECT_FALSE(contains(probe->log, "ReleaseShader"));
    }

    TEST(RmlRenderer, RenderShaderWithUnresolvedGeometryIsSkipped)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));

        renderer.beginFrame(makeTarget());
        const auto geometry = renderer.CompileGeometry(kTriangle, kIndices);
        const auto shader = renderer.CompileShader("linear-gradient", {});
        renderer.ReleaseGeometry(geometry);
        renderer.RenderShader(shader, geometry, {}, 0);
        renderer.endFrame();
        renderer.replay();

        EXPECT_FALSE(contains(probe->log, "RenderShader"));
    }

    TEST(RmlRenderer, CompositeLayersDropsRefusedFilters)
    {
        const auto probe = std::make_shared<Probe>();
        probe->refuseFilters = true;
        RmlRenderer renderer(hooksFor(probe));

        renderer.beginFrame(makeTarget());
        const auto layer = renderer.PushLayer();
        const auto filter = renderer.CompileFilter("x", {});
        const std::vector<Rml::CompiledFilterHandle> filters{ filter };
        renderer.CompositeLayers(layer, 0, Rml::BlendMode::Blend, filters);
        renderer.PopLayer();
        renderer.endFrame();
        renderer.replay();

        EXPECT_TRUE(contains(probe->log, "CompositeLayers"));
        EXPECT_EQ(probe->lastFilterCount, 0);
    }

    TEST(RmlRenderer, RenderToClipMaskWithUnresolvedGeometryIsSkipped)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));

        renderer.beginFrame(makeTarget());
        const auto geometry = renderer.CompileGeometry(kTriangle, kIndices);
        renderer.ReleaseGeometry(geometry);
        renderer.RenderToClipMask(Rml::ClipMaskOperation::Set, geometry, {});
        renderer.endFrame();
        renderer.replay();

        EXPECT_FALSE(contains(probe->log, "RenderToClipMask"));
    }

    // The UI pass renders the document far more often than its content changes. A frame that is
    // command-for-command the previous one must not be queued, replayed or redrawn.
    TEST(RmlRenderer, AFrameIdenticalToThePreviousOneIsNotQueued)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const auto target = makeTarget();

        renderer.beginFrame(target);
        const auto geometry = renderer.CompileGeometry(kTriangle, kIndices);
        renderer.RenderGeometry(geometry, { 1.f, 1.f }, 0);
        const auto first = renderer.endFrame();

        renderer.beginFrame(target);
        renderer.RenderGeometry(geometry, { 1.f, 1.f }, 0);
        const auto second = renderer.endFrame();

        renderer.beginFrame(target);
        renderer.RenderGeometry(geometry, { 1.f, 1.f }, 0);
        const auto third = renderer.endFrame();
        renderer.replay();

        EXPECT_NE(first, 0u);
        // The first frame also compiled the geometry, but it drew the same thing: creating a
        // resource is no reason to draw the next, identical frame again.
        EXPECT_EQ(first, second);
        EXPECT_EQ(second, third);
        EXPECT_EQ(probe->targets.size(), 1u);

        // still identical after the replay: nothing new to draw
        renderer.beginFrame(target);
        renderer.RenderGeometry(geometry, { 1.f, 1.f }, 0);
        EXPECT_EQ(renderer.endFrame(), third);
        renderer.replay();
        EXPECT_EQ(probe->targets.size(), 1u);
    }

    TEST(RmlRenderer, AFrameThatDiffersIsQueued)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const auto target = makeTarget();

        renderer.beginFrame(target);
        const auto geometry = renderer.CompileGeometry(kTriangle, kIndices);
        renderer.RenderGeometry(geometry, { 1.f, 1.f }, 0);
        renderer.endFrame();

        renderer.beginFrame(target);
        renderer.RenderGeometry(geometry, { 1.f, 1.f }, 0);
        const auto still = renderer.endFrame();

        renderer.beginFrame(target);
        renderer.RenderGeometry(geometry, { 2.f, 1.f }, 0); // the element moved by one pixel
        const auto moved = renderer.endFrame();

        renderer.beginFrame(makeTarget()); // same commands into a new target (widget resized)
        renderer.RenderGeometry(geometry, { 2.f, 1.f }, 0);
        const auto retargeted = renderer.endFrame();
        renderer.replay();

        EXPECT_NE(still, moved);
        EXPECT_NE(moved, retargeted);
        EXPECT_EQ(probe->targets.size(), 3u); // every frame but the one that stood still
    }

    TEST(RmlRenderer, ReplayedFramesAreCounted)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const auto before = RmlRenderer::replayedFrameCount();

        for (int i = 0; i < 3; ++i) {
            renderer.beginFrame(makeTarget());
            renderer.endFrame();
        }
        renderer.replay();

        EXPECT_EQ(RmlRenderer::replayedFrameCount() - before, 3u);
    }

    // Layer handles only live inside one frame and get a fresh number every time; that alone
    // must not make two frames look different (every document with a filter or an opacity
    // would otherwise be redrawn forever).
    TEST(RmlRenderer, AFrameWithLayersIsStillRecognisedAsIdentical)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const auto target = makeTarget();

        renderer.beginFrame(target);
        const auto geometry = renderer.CompileGeometry(kTriangle, kIndices);
        renderer.endFrame();

        uint64_t serials[2]{};
        for (auto& serial : serials) {
            renderer.beginFrame(target);
            const auto layer = renderer.PushLayer();
            renderer.RenderGeometry(geometry, {}, 0);
            renderer.CompositeLayers(layer, 0, Rml::BlendMode::Blend, {});
            renderer.PopLayer();
            serial = renderer.endFrame();
        }
        renderer.replay();

        EXPECT_EQ(serials[0], serials[1]);
        EXPECT_EQ(probe->targets.size(), 2u);
    }

    // mask-image: the mask is saved from a layer and released again inside the same frame.
    TEST(RmlRenderer, AFrameWithAMaskImageIsStillRecognisedAsIdentical)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const auto target = makeTarget();

        uint64_t serials[2]{};
        for (auto& serial : serials) {
            renderer.beginFrame(target);
            const auto layer = renderer.PushLayer();
            const auto mask = renderer.SaveLayerAsMaskImage();
            const std::vector<Rml::CompiledFilterHandle> filters{ mask };
            renderer.CompositeLayers(layer, 0, Rml::BlendMode::Blend, filters);
            renderer.ReleaseFilter(mask);
            renderer.PopLayer();
            serial = renderer.endFrame();
        }
        renderer.replay();

        EXPECT_EQ(serials[0], serials[1]);
        EXPECT_EQ(probe->targets.size(), 1u);
        EXPECT_EQ(probe->lastFilterCount, 1);
    }

    // A frame that creates or releases something RmlUi keeps using afterwards has to reach the
    // backend even when its content repeats: dropping it would leave RmlUi with a dead handle.
    TEST(RmlRenderer, AFrameThatCreatesOrReleasesAResourceIsNeverDropped)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const auto target = makeTarget();

        Rml::CompiledGeometryHandle geometry[2]{};
        for (auto& handle : geometry) {
            renderer.beginFrame(target);
            handle = renderer.CompileGeometry(kTriangle, kIndices);
            renderer.RenderGeometry(handle, {}, 0);
            renderer.endFrame();
        }
        for (const auto handle : geometry) {
            renderer.beginFrame(target);
            renderer.ReleaseGeometry(handle);
            renderer.endFrame();
        }
        renderer.replay();

        EXPECT_EQ(probe->targets.size(), 4u);
        EXPECT_TRUE(contains(probe->log, "CompileGeometry:1001"));
        EXPECT_TRUE(contains(probe->log, "ReleaseGeometry:1001"));
    }

    // A widget that is retired in the middle of everything must not keep its target alive.
    TEST(RmlRenderer, RetireDropsTheRememberedTarget)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        auto target = makeTarget();
        const std::weak_ptr<RmlTargetTexture> watch = target;

        renderer.beginFrame(target);
        renderer.endFrame();
        renderer.retire();
        renderer.releaseBackend();
        target = nullptr;

        EXPECT_TRUE(watch.expired());
    }

    // What RmlUi does when content changes: the frame that shows the change also builds the new
    // geometry. The UI pass that follows renders the document again; that second frame draws the
    // same thing with the geometry that now exists and must not cost a second replay.
    TEST(RmlRenderer, ARepeatOfAFrameThatAlsoCreatedItsResourcesIsDropped)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const auto target = makeTarget();

        for (int change = 0; change < 3; ++change) {
            renderer.beginFrame(target);
            const auto geometry = renderer.CompileGeometry(kTriangle, kIndices);
            renderer.RenderGeometry(geometry, {}, 0);
            const auto changed = renderer.endFrame();

            renderer.beginFrame(target);
            renderer.RenderGeometry(geometry, {}, 0);
            EXPECT_EQ(renderer.endFrame(), changed);
        }
        renderer.replay();

        EXPECT_EQ(probe->targets.size(), 3u);
    }

    // A cached effect: the first frame draws into a layer and saves it as a texture, the next
    // ones only draw that texture. Those are different drawings even though they look alike.
    TEST(RmlRenderer, AFrameThatDrawsLessThanTheOneThatBuiltItsTextureIsQueued)
    {
        const auto probe = std::make_shared<Probe>();
        RmlRenderer renderer(hooksFor(probe));
        const auto target = makeTarget();

        renderer.beginFrame(target);
        const auto geometry = renderer.CompileGeometry(kTriangle, kIndices);
        renderer.PushLayer();
        renderer.RenderGeometry(geometry, {}, 0);
        const auto texture = renderer.SaveLayerAsTexture();
        renderer.PopLayer();
        renderer.RenderGeometry(geometry, {}, texture);
        const auto built = renderer.endFrame();

        renderer.beginFrame(target);
        renderer.RenderGeometry(geometry, {}, texture);
        const auto reused = renderer.endFrame();
        renderer.replay();

        EXPECT_NE(built, reused);
        EXPECT_EQ(probe->targets.size(), 2u);
    }

    // A target is created by the UI thread. The table of texture matrices has no lock and
    // belongs to the graphics thread, so creating a target must not register anything there;
    // the backend does it when it gives the target its GPU storage.
    TEST(RmlTargetTexture, CreatingATargetDoesNotTouchTheTextureMatrixTable)
    {
        const auto before = g_textures.getMatrixId(Size(9001, 7001), true);
        const RmlTargetTexture target(Size(9003, 7003));
        const auto after = g_textures.getMatrixId(Size(9005, 7005), true);

        EXPECT_EQ(target.getSize(), Size(9003, 7003));
        EXPECT_EQ(after, before + 1); // nothing was registered in between
    }

}
