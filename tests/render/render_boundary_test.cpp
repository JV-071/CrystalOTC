#include <gtest/gtest.h>

// The producer API is private on DrawPool and reached through DrawPoolManager, which needs
// initialised globals and a GL context. Tests drive the pool directly through the
// DrawPoolTestAccess friend declared in drawpool.h.
//
// NOT via `#define private public`, which is what this file used at first: it links on
// Itanium-ABI toolchains and cannot link on MSVC, which encodes access specifiers into mangled
// names, so the test emitted calls to `public:` symbols the library never defined.
#include <framework/graphics/drawpool.h>

#include <framework/graphics/render/atlasprogram.h>
#include <framework/graphics/render/frameassembler.h>
#include <framework/graphics/render/linetriangulation.h>
#include <framework/graphics/render/materialregistry.h>
#include <framework/graphics/render/metal/metalmodulematerials.h>
#include <framework/graphics/render/poolcompiler.h>
#include <framework/graphics/render/recordingbackend.h>
#include <framework/graphics/texture.h>

#include <set>
#include <string>

// Must be at global scope: drawpool.h befriends ::DrawPoolTestAccess. Everything here is a
// thin forward to DrawPool's producer API, so the tests exercise the real recording path
// rather than a reimplementation of it.
struct DrawPoolTestAccess
{
    static DrawPool* create(const DrawPoolType type) { return DrawPool::create(type); }

    static void addRect(DrawPool& pool, const Rect& dest, const Color& color)
    {
        pool.add(color, nullptr, DrawPool::DrawMethod{
            .type = DrawPool::DrawMethodType::RECT, .dest = dest });
    }

    static void addTexturedRect(DrawPool& pool, const Rect& dest, const Rect& src, const TexturePtr& texture)
    {
        pool.add(Color::white, texture, DrawPool::DrawMethod{
            .type = DrawPool::DrawMethodType::RECT, .dest = dest, .src = src });
    }

    static void addAction(DrawPool& pool, const std::function<void()>& action, const ActionIdiom idiom)
    { pool.addAction(action, idiom); }

    static void setClipRect(DrawPool& pool, const Rect& rect) { pool.setClipRect(rect); }
    static void resetClipRect(DrawPool& pool) { pool.resetClipRect(); }

    static void setOpacity(DrawPool& pool, const float opacity, const bool onlyOnce = false)
    { pool.setOpacity(opacity, onlyOnce); }

    static void setCompositionMode(DrawPool& pool, const CompositionMode mode, const bool onlyOnce = false)
    { pool.setCompositionMode(mode, onlyOnce); }
    static void resetCompositionMode(DrawPool& pool) { pool.resetCompositionMode(); }

    static void addLightOverlay(DrawPool& pool, const TexturePtr& texture, const Rect& dest,
                                const Rect& src, const uint16_t tileSize)
    { pool.addLightOverlay(texture, dest, src, tileSize, [] {}); }

    static void addTextureUpload(DrawPool& pool, const TextureHandle texture, const Size& size,
                                 const uint8_t* pixels, const size_t byteCount)
    { pool.addTextureUpload(texture, size, pixels, byteCount); }

    static void bindFrameBuffer(DrawPool& pool, const Size& size) { pool.bindFrameBuffer(size); }

    static void releaseFrameBuffer(DrawPool& pool, const Rect& dest) { pool.releaseFrameBuffer(dest); }
    static void releaseFrameBuffer(DrawPool& pool, const Rect& dest, const uint8_t flip)
    { pool.releaseFrameBuffer(dest, flip); }
};

namespace {

    constexpr Size VIEWPORT{ 800, 600 };

    // LIGHT is the pool with the least machinery: no framebuffer, so nothing here can reach
    // GL, and no always-group batching to obscure which packet came from which draw.
    struct Pool
    {
        DrawPool* p{ DrawPoolTestAccess::create(DrawPoolType::LIGHT) };
        ~Pool() { delete p; }

        void rect(const Rect& dest, const Color& color = Color::white)
        {
            DrawPoolTestAccess::addRect(*p, dest, color);
        }

        void texturedRect(const Rect& dest, const Rect& src, const TexturePtr& texture)
        {
            DrawPoolTestAccess::addTexturedRect(*p, dest, src, texture);
        }

        void compile(PoolProgram& out)
        {
            p->release();
            PoolCompiler::compile(*p, VIEWPORT, out);
        }
    };

    TEST(RenderBoundary, FilledRectCompilesToOnePacket)
    {
        Pool pool;
        pool.rect(Rect(10, 20, 30, 40), Color::red);

        PoolProgram program;
        pool.compile(program);

        ASSERT_TRUE(program.isComplete());
        ASSERT_EQ(program.passes.size(), 1u);

        const auto& pass = program.passes[0];
        // A pool with no target draws on top of whatever the backbuffer already holds.
        EXPECT_TRUE(pass.target.isBackbuffer());
        EXPECT_EQ(pass.load, LoadAction::Keep);
        ASSERT_EQ(pass.packets.size(), 1u);

        const auto& packet = pass.packets[0];
        EXPECT_EQ(packet.vertexCount, 6u);      // one rect == two triangles
        EXPECT_FALSE(packet.textured);
        EXPECT_FALSE(packet.texture.isValid());
        EXPECT_EQ(packet.blend, BlendMode::Normal);
        EXPECT_TRUE(packet.blendEnabled);
        EXPECT_EQ(packet.color, Color::red);
    }

    TEST(RenderBoundary, BlendBracketScopesExactlyOnePacket)
    {
        Pool pool;
        pool.rect(Rect(0, 0, 10, 10));
        DrawPoolTestAccess::addAction(*pool.p, [] {}, ActionIdiom::BlendOff);
        pool.rect(Rect(20, 20, 10, 10), Color::alpha); // the map-hole punch
        DrawPoolTestAccess::addAction(*pool.p, [] {}, ActionIdiom::BlendOn);
        pool.rect(Rect(40, 40, 10, 10));

        PoolProgram program;
        pool.compile(program);

        ASSERT_TRUE(program.isComplete());
        ASSERT_EQ(program.passes.size(), 1u);
        ASSERT_EQ(program.passes[0].packets.size(), 3u);

        EXPECT_TRUE(program.passes[0].packets[0].blendEnabled);
        EXPECT_FALSE(program.passes[0].packets[1].blendEnabled);
        EXPECT_TRUE(program.passes[0].packets[2].blendEnabled);
    }

    TEST(RenderBoundary, TemporaryFramebufferSplitsThePass)
    {
        Pool pool;
        pool.rect(Rect(0, 0, 10, 10));
        DrawPoolTestAccess::bindFrameBuffer(*pool.p, Size(64, 64));
        pool.rect(Rect(1, 1, 8, 8));
        DrawPoolTestAccess::releaseFrameBuffer(*pool.p, Rect(100, 100, 64, 64));
        pool.rect(Rect(40, 40, 10, 10));

        PoolProgram program;
        pool.compile(program);

        ASSERT_TRUE(program.isComplete());
        // before / nested / continuation
        ASSERT_EQ(program.passes.size(), 3u);

        EXPECT_TRUE(program.passes[0].target.isBackbuffer());
        EXPECT_EQ(program.passes[0].packets.size(), 1u);

        // The nested target is cleared, sized to the bind, and drawn into first - it must
        // precede the pass that samples it.
        EXPECT_FALSE(program.passes[1].target.isBackbuffer());
        EXPECT_EQ(program.passes[1].load, LoadAction::Clear);
        EXPECT_EQ(program.passes[1].viewport, Rect(0, 0, 64, 64));
        EXPECT_EQ(program.passes[1].packets.size(), 1u);

        // The continuation LOADS what the first segment left behind rather than clearing it.
        EXPECT_TRUE(program.passes[2].target.isBackbuffer());
        EXPECT_EQ(program.passes[2].load, LoadAction::Keep);
        ASSERT_EQ(program.passes[2].packets.size(), 2u);

        // First packet of the continuation is the blit, sampling the nested target.
        const auto& blit = program.passes[2].packets[0];
        EXPECT_TRUE(blit.textured);
        EXPECT_EQ(blit.texture.id, program.passes[1].target.id);
        EXPECT_EQ(blit.vertexCount, 6u);
    }

    TEST(RenderBoundary, NestedTemporaryFramebuffersUseDistinctTargets)
    {
        Pool pool;
        DrawPoolTestAccess::bindFrameBuffer(*pool.p, Size(64, 64));
        pool.rect(Rect(0, 0, 8, 8));
        DrawPoolTestAccess::bindFrameBuffer(*pool.p, Size(32, 32));
        pool.rect(Rect(0, 0, 4, 4));
        DrawPoolTestAccess::releaseFrameBuffer(*pool.p, Rect(0, 0, 32, 32));
        DrawPoolTestAccess::releaseFrameBuffer(*pool.p, Rect(0, 0, 64, 64));

        PoolProgram program;
        pool.compile(program);

        ASSERT_TRUE(program.isComplete());

        // Depth 0 and depth 1 must be different targets, or the inner blit would sample the
        // target it is drawing into.
        const auto depth0 = RenderHandles::transientTarget(DrawPoolType::LIGHT, 0);
        const auto depth1 = RenderHandles::transientTarget(DrawPoolType::LIGHT, 1);
        EXPECT_NE(depth0.id, depth1.id);

        bool sawDepth0 = false, sawDepth1 = false;
        for (const auto& pass : program.passes) {
            sawDepth0 |= pass.target.id == depth0.id;
            sawDepth1 |= pass.target.id == depth1.id;
        }
        EXPECT_TRUE(sawDepth0);
        EXPECT_TRUE(sawDepth1);
    }

    TEST(RenderBoundary, UnbalancedReleaseIsANoOpRatherThanMemoryCorruption)
    {
        // This used to be undefined behaviour, not a no-op: the state-stack index is unsigned,
        // so popping with nothing pushed wrapped it and the next read indexed far outside the
        // fixed m_states array. macOS tolerated it silently; a Linux runner segfaulted on the
        // first test that ever tried it.
        Pool pool;
        DrawPoolTestAccess::releaseFrameBuffer(*pool.p, Rect(0, 0, 10, 10));
        pool.rect(Rect(0, 0, 10, 10));

        PoolProgram program;
        pool.compile(program);

        // The stray release contributes nothing and does not disturb the draw that follows it.
        EXPECT_TRUE(program.isComplete());
        ASSERT_EQ(program.passes.size(), 1u);
        EXPECT_EQ(program.passes[0].packets.size(), 1u);
    }

    TEST(RenderBoundary, FramebufferNestingCannotOverflowTheStateStack)
    {
        // The other end of the same fixed array. Binding past its depth must refuse rather
        // than write past the end.
        Pool pool;
        for (int i = 0; i < 40; ++i)
            DrawPoolTestAccess::bindFrameBuffer(*pool.p, Size(8, 8));
        pool.rect(Rect(0, 0, 4, 4));
        for (int i = 0; i < 40; ++i)
            DrawPoolTestAccess::releaseFrameBuffer(*pool.p, Rect(0, 0, 8, 8));

        PoolProgram program;
        pool.compile(program);

        EXPECT_TRUE(program.isComplete()) << (program.unsupported.empty() ? "" : program.unsupported[0]);
        EXPECT_FALSE(program.passes.empty());

        // Scope note, so this is not mistaken for more coverage than it is: what this asserts
        // is that overflowing the stack neither crashes nor unbalances the marker stream. It
        // does NOT discriminate the refused-bind/refused-release pairing in DrawPool - with a
        // run of binds followed by a run of releases the surplus releases are stopped by the
        // empty-stack guard anyway, so removing the pairing still passes. Pairing matters for
        // interleaved nesting past depth 9, where a release would otherwise blit a state
        // belonging to a different bind. That case is guarded but untested; the surveyed call
        // sites nest one or two deep, so building a fixture for it was judged disproportionate.
    }

    TEST(RenderBoundary, LightOverlayCompilesToAMultiplyQuadAndAnUpload)
    {
        // The light pass is not geometry the way the rest of the frame is: LightView computes an
        // RGBA bitmap of one texel per visible tile on the CPU, uploads it when its hash changed,
        // and draws ONE multiply-blended quad over the map. Both halves have to survive
        // compilation, and the upload has to appear only when the producer declared one - a
        // compiled frame that uploaded every frame would do strictly more work than the GL path.
        const auto light = std::make_shared<Texture>();
        const std::vector<uint8_t> pixels(4 * 4 * 4, 0x40);

        Pool pool;
        DrawPoolTestAccess::addTextureUpload(*pool.p, TextureHandle{ light->getUniqueId() },
                                             Size(4, 4), pixels.data(), pixels.size());
        DrawPoolTestAccess::addLightOverlay(*pool.p, light, Rect(0, 0, 128, 128),
                                            Rect(0, 0, 128, 128), 32);

        PoolProgram program;
        pool.compile(program);

        ASSERT_TRUE(program.isComplete());

        ASSERT_EQ(program.uploads.size(), 1u);
        EXPECT_EQ(program.uploads[0].texture.id, light->getUniqueId());
        EXPECT_EQ(program.uploads[0].size, Size(4, 4));
        EXPECT_EQ(program.uploads[0].pixels.size(), pixels.size());

        ASSERT_EQ(program.passes.size(), 1u);
        ASSERT_EQ(program.passes[0].packets.size(), 1u);

        const auto& quad = program.passes[0].packets[0];
        EXPECT_TRUE(quad.textured);
        EXPECT_EQ(quad.texture.id, light->getUniqueId());
        // Multiply, not Normal. The light texture darkens what is already on the backbuffer;
        // blending it normally would paint a grey sheet over the map instead.
        EXPECT_EQ(quad.blend, BlendMode::Multiply);
        EXPECT_TRUE(quad.blendEnabled);
        EXPECT_EQ(quad.vertexCount, 6u);
    }

    TEST(RenderBoundary, MapHolePunchIsAnUnblendedTransparentRect)
    {
        // UIMap punches a transparent hole through the FOREGROUND target so the map composited
        // underneath shows through. On GL that is glDisable(GL_BLEND) around a Color::alpha rect;
        // a packet has to state the same thing, because with blending ON an alpha-zero rect is a
        // no-op and the game view would be covered by the UI panel instead.
        //
        // Note the compiler reproduces this from the BlendOff/BlendOn tags rather than by
        // recognising the rect: inferring the hole from "untextured and alpha 0" was tried and it
        // cut holes through any widget that happened to be faded to zero.
        Pool pool;
        DrawPoolTestAccess::addAction(*pool.p, [] {}, ActionIdiom::BlendOff);
        pool.rect(Rect(177, 0, 666, 521), Color::alpha);
        DrawPoolTestAccess::addAction(*pool.p, [] {}, ActionIdiom::BlendOn);

        PoolProgram program;
        pool.compile(program);

        ASSERT_TRUE(program.isComplete());
        ASSERT_EQ(program.passes.size(), 1u);
        ASSERT_EQ(program.passes[0].packets.size(), 1u);

        const auto& hole = program.passes[0].packets[0];
        EXPECT_FALSE(hole.blendEnabled);
        EXPECT_FALSE(hole.textured);
        EXPECT_EQ(hole.color, Color::alpha);
        EXPECT_EQ(hole.vertexCount, 6u);
    }

    TEST(RenderBoundary, UntaggedActionPoisonsTheProgram)
    {
        Pool pool;
        pool.rect(Rect(0, 0, 10, 10));
        DrawPoolTestAccess::addAction(*pool.p, [] {}, ActionIdiom::Opaque); // the default

        PoolProgram program;
        pool.compile(program);

        // The geometry still compiled, but the program must refuse to claim it is faithful.
        ASSERT_FALSE(program.passes.empty());
        EXPECT_EQ(program.passes[0].packets.size(), 1u);
        EXPECT_FALSE(program.isComplete());
    }

    TEST(RenderBoundary, ScissorIsClampedToTheTarget)
    {
        Pool pool;
        DrawPoolTestAccess::setClipRect(*pool.p, Rect(-50, -50, 10000, 10000));
        pool.rect(Rect(0, 0, 10, 10));

        PoolProgram program;
        pool.compile(program);

        ASSERT_EQ(program.passes[0].packets.size(), 1u);
        // Metal validates scissor rects and kills the encoder on an out-of-bounds one; GL
        // silently forgave them. Clamping here means neither backend has to care.
        EXPECT_EQ(program.passes[0].packets[0].scissor, Rect(0, 0, VIEWPORT.width(), VIEWPORT.height()));
    }

    TEST(RenderBoundary, ClipRectThatMissesTheTargetClipsEverything)
    {
        Pool pool;
        DrawPoolTestAccess::bindFrameBuffer(*pool.p, Size(64, 64));
        // A clip rect entirely outside the target it is drawn into - a widget scrolled away.
        DrawPoolTestAccess::setClipRect(*pool.p, Rect(900, 900, 100, 50));
        pool.rect(Rect(0, 0, 10, 10));
        DrawPoolTestAccess::releaseFrameBuffer(*pool.p, Rect(0, 0, 64, 64));

        PoolProgram program;
        pool.compile(program);

        ASSERT_TRUE(program.isComplete());
        ASSERT_GE(program.passes.size(), 2u);
        ASSERT_EQ(program.passes[1].packets.size(), 1u);

        const auto& packet = program.passes[1].packets[0];
        // Scissoring must be ON and empty. If it compiled to "disabled" the geometry would be
        // drawn across the whole target, where GL clipped it away entirely - the exact inverse
        // of the intent.
        EXPECT_TRUE(packet.scissorEnabled);
        EXPECT_FALSE(packet.scissor.isValid());
    }

    TEST(RenderBoundary, OnlyOnceStateRestoresThePreviousValueNotTheDefault)
    {
        Pool pool;
        DrawPoolTestAccess::setOpacity(*pool.p, 0.5f);              // a standing, non-default value
        pool.rect(Rect(0, 0, 10, 10));
        DrawPoolTestAccess::setOpacity(*pool.p, 0.25f, true);       // onlyOnce override
        pool.rect(Rect(20, 20, 10, 10));
        pool.rect(Rect(40, 40, 10, 10));       // must be back at 0.5, NOT at 1.0

        PoolProgram program;
        pool.compile(program);

        ASSERT_FALSE(program.passes.empty());
        ASSERT_EQ(program.passes[0].packets.size(), 3u);
        EXPECT_FLOAT_EQ(program.passes[0].packets[0].opacity, 0.5f);
        EXPECT_FLOAT_EQ(program.passes[0].packets[1].opacity, 0.25f);
        // The survey is explicit that onlyOnce restores the PREVIOUS value rather than
        // resetting to a default, and that the compiler must reproduce the scoping exactly.
        EXPECT_FLOAT_EQ(program.passes[0].packets[2].opacity, 0.5f);
    }

    TEST(RenderBoundary, OnlyOnceCompositionModeIsScopedToOneDraw)
    {
        Pool pool;
        DrawPoolTestAccess::setCompositionMode(*pool.p, CompositionMode::MULTIPLY, true);
        pool.rect(Rect(0, 0, 10, 10));
        pool.rect(Rect(20, 20, 10, 10));

        PoolProgram program;
        pool.compile(program);

        ASSERT_FALSE(program.passes.empty());
        ASSERT_EQ(program.passes[0].packets.size(), 2u);
        EXPECT_EQ(program.passes[0].packets[0].blend, BlendMode::Multiply);
        EXPECT_EQ(program.passes[0].packets[1].blend, BlendMode::Normal);
    }

    TEST(RenderBoundary, CompositionNeverBorrowsAnotherPoolsGeometry)
    {
        // A pool that draws STRAIGHT to the backbuffer, followed by one that composites a
        // retained target. The composition packet's vertex offsets index the assembler's own
        // arena, so it must not be appended into the direct pool's backbuffer pass - that pass
        // points at the direct pool's arena, and the offsets would mean nothing there.
        Pool direct;
        direct.rect(Rect(0, 0, 10, 10));

        PoolProgram directProgram;
        direct.compile(directProgram);

        PoolProgram composited;
        composited.type = DrawPoolType::FOREGROUND;
        composited.hasComposition = true;
        composited.compositionSource = RenderHandles::poolTarget(DrawPoolType::FOREGROUND);
        composited.compositionDest = Rect(0, 0, 800, 600);
        composited.compositionSrc = Rect(0, 0, 800, 600);

        RenderFrame frame;
        FrameAssembler assembler;
        FrameAssembler::Programs programs{};
        programs[static_cast<size_t>(DrawPoolType::LIGHT)] = &directProgram;
        programs[static_cast<size_t>(DrawPoolType::FOREGROUND)] = &composited;
        assembler.assemble(programs, VIEWPORT, 0.f, frame);

        // Find the pass holding the composition packet and prove it is not the direct pool's.
        const RenderPass* compositionPass = nullptr;
        for (const auto& pass : frame.passes) {
            for (const auto& packet : pass.packets) {
                if (packet.texture.id == composited.compositionSource.id)
                    compositionPass = &pass;
            }
        }
        ASSERT_NE(compositionPass, nullptr);
        EXPECT_NE(compositionPass->arena, directProgram.passes[0].arena);
        ASSERT_NE(compositionPass->arena, nullptr);
        // ...and the packet's slice must actually exist in the arena it points at.
        for (const auto& packet : compositionPass->packets)
            EXPECT_LE(packet.vertexOffset + packet.vertexCount, compositionPass->arena->vertexCount());
    }

    // Builds a program that owns a retained target, the way MAP and FOREGROUND do.
    void makeComposited(PoolProgram& program, const size_t contentHash, const DrawPoolType type)
    {
        program.type = type;
        program.contentHash = contentHash;
        program.hasComposition = true;
        program.compositionSource = RenderHandles::poolTarget(type);
        program.compositionDest = Rect(0, 0, 800, 600);
        program.compositionSrc = Rect(0, 0, 800, 600);

        auto& pass = program.passes.emplace_back();
        pass.target = program.compositionSource;
        pass.load = LoadAction::Clear;
        pass.viewport = Rect(0, 0, 800, 600);
        pass.label = "pool-target";
        pass.packets.emplace_back();
        program.bindArena();
    }

    size_t passesTargeting(const RenderFrame& frame, const RenderTargetHandle target)
    {
        size_t n = 0;
        for (const auto& pass : frame.passes)
            n += (pass.target.id == target.id);
        return n;
    }

    TEST(RenderBoundary, UnchangedPoolIsRecompositedWithoutBeingRedrawn)
    {
        PoolProgram program;
        makeComposited(program, 0xABCD, DrawPoolType::FOREGROUND);

        FrameAssembler assembler;
        FrameAssembler::Programs programs{};
        programs[static_cast<size_t>(DrawPoolType::FOREGROUND)] = &program;

        RenderFrame first, second;
        assembler.assemble(programs, VIEWPORT, 0.f, first);
        assembler.assemble(programs, VIEWPORT, 0.f, second);

        const auto target = RenderHandles::poolTarget(DrawPoolType::FOREGROUND);

        // First frame renders the target and composites it.
        EXPECT_EQ(passesTargeting(first, target), 1u);
        // Second frame must NOT re-render it - this caching is what carries the client's
        // performance, and a clear-and-redraw-every-frame model would destroy it.
        EXPECT_EQ(passesTargeting(second, target), 0u);

        // ...but the composition still happens, or the pool would vanish from the frame.
        size_t composites = 0;
        for (const auto& pass : second.passes)
            for (const auto& packet : pass.packets)
                composites += (packet.texture.id == target.id);
        EXPECT_EQ(composites, 1u);
    }

    TEST(RenderBoundary, ChangedContentRedrawsTheTarget)
    {
        PoolProgram first, second;
        makeComposited(first, 0x1111, DrawPoolType::FOREGROUND);
        makeComposited(second, 0x2222, DrawPoolType::FOREGROUND);

        FrameAssembler assembler;
        FrameAssembler::Programs a{}, b{};
        a[static_cast<size_t>(DrawPoolType::FOREGROUND)] = &first;
        b[static_cast<size_t>(DrawPoolType::FOREGROUND)] = &second;

        RenderFrame f1, f2;
        assembler.assemble(a, VIEWPORT, 0.f, f1);
        assembler.assemble(b, VIEWPORT, 0.f, f2);

        const auto target = RenderHandles::poolTarget(DrawPoolType::FOREGROUND);
        EXPECT_EQ(passesTargeting(f2, target), 1u);
    }

    TEST(RenderBoundary, InvalidatingRetainedTargetsForcesARedraw)
    {
        PoolProgram program;
        makeComposited(program, 0xABCD, DrawPoolType::FOREGROUND);

        FrameAssembler assembler;
        FrameAssembler::Programs programs{};
        programs[static_cast<size_t>(DrawPoolType::FOREGROUND)] = &program;

        RenderFrame f1, f2, f3;
        assembler.assemble(programs, VIEWPORT, 0.f, f1);
        assembler.assemble(programs, VIEWPORT, 0.f, f2);
        // A resize or a device loss leaves the target holding the wrong pixels while the
        // objects that drew into it are unchanged, so the hash alone cannot notice.
        assembler.invalidateRetainedTargets();
        assembler.assemble(programs, VIEWPORT, 0.f, f3);

        const auto target = RenderHandles::poolTarget(DrawPoolType::FOREGROUND);
        EXPECT_EQ(passesTargeting(f2, target), 0u);
        EXPECT_EQ(passesTargeting(f3, target), 1u);
    }

    TEST(RenderBoundary, PoolsDrawingStraightToTheBackbufferAreNeverSkipped)
    {
        // No retained target holds their result, so skipping them would simply not draw them.
        Pool pool;
        pool.rect(Rect(0, 0, 10, 10));

        PoolProgram program;
        pool.compile(program);
        ASSERT_FALSE(program.hasComposition);

        FrameAssembler assembler;
        FrameAssembler::Programs programs{};
        programs[static_cast<size_t>(DrawPoolType::LIGHT)] = &program;

        RenderFrame f1, f2;
        assembler.assemble(programs, VIEWPORT, 0.f, f1);
        assembler.assemble(programs, VIEWPORT, 0.f, f2);

        EXPECT_EQ(f1.packetCount(), 1u);
        EXPECT_EQ(f2.packetCount(), 1u);
    }

    TEST(RenderBoundary, APoolThatGainsATargetRendersItBeforeCompositingIt)
    {
        // A pool can acquire a framebuffer at runtime (DrawPool::setFramebuffer). If the
        // assembler had recorded a content hash for it while it was still drawing straight to
        // the backbuffer, an unchanged hash would let the very first composition skip
        // rendering a target that has never been drawn into - compositing a blank texture.
        constexpr size_t SAME_CONTENT = 0x5150;

        PoolProgram direct;
        direct.type = DrawPoolType::FOREGROUND;
        direct.contentHash = SAME_CONTENT;
        {
            auto& pass = direct.passes.emplace_back();
            pass.target = RenderTargetHandle{ RenderTargetHandle::BACKBUFFER };
            pass.load = LoadAction::Keep;
            pass.packets.emplace_back();
            direct.bindArena();
        }

        PoolProgram composited;
        makeComposited(composited, SAME_CONTENT, DrawPoolType::FOREGROUND);

        FrameAssembler assembler;
        FrameAssembler::Programs a{}, b{};
        a[static_cast<size_t>(DrawPoolType::FOREGROUND)] = &direct;
        b[static_cast<size_t>(DrawPoolType::FOREGROUND)] = &composited;

        RenderFrame f1, f2;
        assembler.assemble(a, VIEWPORT, 0.f, f1);   // no target yet
        assembler.assemble(b, VIEWPORT, 0.f, f2);   // target appears, same content hash

        EXPECT_EQ(passesTargeting(f2, RenderHandles::poolTarget(DrawPoolType::FOREGROUND)), 1u);
    }

    TEST(RenderBoundary, ReleaseCompilesOnlyWhenCompilingIsEnabled)
    {
        DrawPool::setCompileFrames(false);
        {
            Pool pool;
            pool.rect(Rect(0, 0, 10, 10));
            pool.p->release();
            // Off by default: the GL path ships, does not read a PoolProgram, and must not
            // pay for one.
            EXPECT_EQ(pool.p->getCompiledProgram(), nullptr);
        }

        DrawPool::setCompileFrames(true);
        {
            Pool pool;
            pool.rect(Rect(0, 0, 10, 10));
            pool.p->release();

            const auto* program = pool.p->getCompiledProgram();
            ASSERT_NE(program, nullptr);
            EXPECT_TRUE(program->isComplete());
            ASSERT_FALSE(program->passes.empty());
            EXPECT_EQ(program->passes[0].packets.size(), 1u);
        }
        DrawPool::setCompileFrames(false);
    }

    TEST(RenderBoundary, AtlasMaintenanceIsDeclaredAsUnmodelled)
    {
        // The LIGHT pool owns no atlas, so nothing is owed.
        Pool pool;
        pool.rect(Rect(0, 0, 10, 10));

        PoolProgram program;
        pool.compile(program);

        EXPECT_FALSE(program.requiresAtlasMaintenance);
        // Not modelling the atlas must not poison the program - it is a stated omission with
        // a known owner, not an idiom the compiler failed to express.
        EXPECT_TRUE(program.isComplete());
    }

    TEST(RenderBoundary, ContentHashTracksTheCompiledOutput)
    {
        Pool same1, same2, different;
        same1.rect(Rect(0, 0, 10, 10), Color::red);
        same2.rect(Rect(0, 0, 10, 10), Color::red);
        different.rect(Rect(0, 0, 10, 10), Color::green);

        PoolProgram a, b, c;
        same1.compile(a);
        same2.compile(b);
        different.compile(c);

        EXPECT_EQ(a.contentHash, b.contentHash);
        EXPECT_NE(a.contentHash, c.contentHash);
        EXPECT_NE(a.contentHash, 0u);
    }

    TEST(RenderBoundary, ContentHashSeesPixelsThatChangedUnderAStableHandle)
    {
        // The one thing a hash of the compiled output cannot see by itself.
        //
        // An AnimatedTexture is a single Texture whose logical handle stays deliberately stable
        // while the pixels behind it advance every tick; an in-place updatePixels does the same
        // with no motion at all. Either way the program compiles to byte-identical output, so a
        // retained target still holding the previous frame looks current and is re-composited
        // instead of re-rendered - and the animation stops on screen.
        //
        // Phase 3 caught the OpenGL half of this by folding in the native texture id, which an
        // AnimatedTexture re-aims as it advances. A backend that creates no GL textures leaves
        // that id at zero for every texture in the client, so the term is constant and the defect
        // returns. Texture::getContentRevision is the signal that exists on both.
        const auto texture = std::make_shared<Texture>();
        const Rect dest(0, 0, 16, 16);
        const Rect src(0, 0, 16, 16);

        Pool before, unchanged, after;
        before.texturedRect(dest, src, texture);
        unchanged.texturedRect(dest, src, texture);

        PoolProgram a, b, c;
        before.compile(a);
        unchanged.compile(b);
        EXPECT_EQ(a.contentHash, b.contentHash);

        texture->bumpContentRevision();
        after.texturedRect(dest, src, texture);
        after.compile(c);

        // Same handle, same geometry, same state - and the compiled packets really are identical,
        // which is exactly why the hash has to be told about the pixels.
        ASSERT_EQ(a.passes.size(), c.passes.size());
        ASSERT_EQ(a.passes[0].packets.size(), c.passes[0].packets.size());
        EXPECT_EQ(a.passes[0].packets[0].texture, c.passes[0].packets[0].texture);
        EXPECT_NE(a.contentHash, c.contentHash);
    }

    TEST(RenderBoundary, CompositionModeMapsToTheSurveyedBlendFormula)
    {
        // ADD is NOT classic additive - it is (1-src, 1-src), and particles depend on it.
        EXPECT_EQ(blendModeOf(CompositionMode::ADD), BlendMode::AddWeird);
        EXPECT_EQ(blendModeOf(CompositionMode::LIGHT), BlendMode::LightModulate);
        EXPECT_EQ(blendModeOf(CompositionMode::NORMAL), BlendMode::Normal);
        EXPECT_EQ(blendModeOf(CompositionMode::MULTIPLY), BlendMode::Multiply);
        EXPECT_EQ(blendModeOf(CompositionMode::REPLACE), BlendMode::Replace);
        EXPECT_EQ(blendModeOf(CompositionMode::DESTINATION_BLENDING), BlendMode::DestBlend);
    }

    TEST(RenderBoundary, MultiplyCompositionSurvivesCompilation)
    {
        Pool pool;
        DrawPoolTestAccess::setCompositionMode(*pool.p, CompositionMode::MULTIPLY);
        pool.rect(Rect(0, 0, 10, 10));

        PoolProgram program;
        pool.compile(program);

        ASSERT_FALSE(program.passes.empty());
        ASSERT_EQ(program.passes[0].packets.size(), 1u);
        EXPECT_EQ(program.passes[0].packets[0].blend, BlendMode::Multiply);
    }

    TEST(RenderBoundary, LineStripTriangulatesToQuadsPerSegment)
    {
        CoordsBuffer buffer;
        RenderLines::triangulateStrip(buffer, { Point(0, 10), Point(100, 10) }, 4.f);

        // One segment -> one quad -> two triangles -> six vertices.
        ASSERT_EQ(buffer.getVertexCount(), 6);

        const float* v = buffer.getVertexArray();
        // A horizontal segment of width 4 spans EXACTLY y = 8 and y = 12, and x runs the full
        // 0..100. Asserting the exact values matters: a range check passes a triangulation that
        // collapses every quad to a zero-area sliver, which draws nothing at all.
        int atTop = 0, atBottom = 0, atLeft = 0, atRight = 0;
        for (int i = 0; i < 6; ++i) {
            const float x = v[i * 2], y = v[i * 2 + 1];
            EXPECT_TRUE(y == 8.f || y == 12.f) << "y=" << y;
            EXPECT_TRUE(x == 0.f || x == 100.f) << "x=" << x;
            atTop += (y == 8.f); atBottom += (y == 12.f);
            atLeft += (x == 0.f); atRight += (x == 100.f);
        }
        EXPECT_EQ(atTop, 3);    EXPECT_EQ(atBottom, 3);
        EXPECT_EQ(atLeft, 3);   EXPECT_EQ(atRight, 3);
    }

    TEST(RenderBoundary, DegenerateLineSegmentsAreSkipped)
    {
        CoordsBuffer buffer;
        RenderLines::triangulateStrip(buffer, { Point(5, 5), Point(5, 5) }, 2.f);
        EXPECT_EQ(buffer.getVertexCount(), 0);
    }

    TEST(RenderBoundary, CompilationIsDeterministic)
    {
        const auto build = [](Pool& pool) {
            pool.rect(Rect(0, 0, 10, 10), Color::green);
            DrawPoolTestAccess::bindFrameBuffer(*pool.p, Size(16, 16));
            pool.rect(Rect(1, 1, 4, 4));
            DrawPoolTestAccess::releaseFrameBuffer(*pool.p, Rect(2, 2, 16, 16), 1 /* horizontal flip */);
        };

        Pool a, b;
        build(a);
        build(b);

        PoolProgram pa, pb;
        a.compile(pa);
        b.compile(pb);

        RenderFrame fa, fb;
        FrameAssembler assemblerA, assemblerB;
        FrameAssembler::Programs programsA{}, programsB{};
        programsA[static_cast<size_t>(DrawPoolType::LIGHT)] = &pa;
        programsB[static_cast<size_t>(DrawPoolType::LIGHT)] = &pb;
        assemblerA.assemble(programsA, VIEWPORT, 2.f, fa);
        assemblerB.assemble(programsB, VIEWPORT, 2.f, fb);

        // Byte-identical recordings are what make golden-frame diffs meaningful, and what
        // lets a GL-versus-Metal disagreement be bisected to one side of the boundary.
        EXPECT_EQ(RecordingBackend::record(fa), RecordingBackend::record(fb));
        EXPECT_FALSE(RecordingBackend::record(fa).empty());
    }

    TEST(RenderBoundary, FlipDirectionChangesTheCompiledGeometry)
    {
        Pool plain, flipped;
        for (auto* pool : { &plain, &flipped }) {
            DrawPoolTestAccess::bindFrameBuffer(*pool->p, Size(16, 16));
            pool->rect(Rect(0, 0, 4, 4));
        }
        DrawPoolTestAccess::releaseFrameBuffer(*plain.p, Rect(0, 0, 16, 16), 0);
        DrawPoolTestAccess::releaseFrameBuffer(*flipped.p, Rect(0, 0, 16, 16), 2 /* vertical */);

        PoolProgram a, b;
        plain.compile(a);
        flipped.compile(b);

        // The flip is resolved into the compiled texture coordinates, so no backend needs to
        // know a flip happened.
        RenderFrame fa, fb;
        FrameAssembler asmA, asmB;
        FrameAssembler::Programs pa{}, pb{};
        pa[static_cast<size_t>(DrawPoolType::LIGHT)] = &a;
        pb[static_cast<size_t>(DrawPoolType::LIGHT)] = &b;
        asmA.assemble(pa, VIEWPORT, 0.f, fa);
        asmB.assemble(pb, VIEWPORT, 0.f, fb);
        EXPECT_NE(RecordingBackend::record(fa), RecordingBackend::record(fb));
    }

    TEST(RenderBoundary, MaterialParamsAbiIsFrozen)
    {
        // These mirror the static_asserts in materialparams.h. Phase 6's GLSL -> SPIR-V -> MSL
        // step generates a matching std140 block, so a silent layout change here would produce
        // shaders that read the wrong fields.
        EXPECT_EQ(sizeof(MaterialParams), 80u);
        EXPECT_EQ(offsetof(MaterialParams, time), 0u);
        // These are the offsets a naturally written std140 block produces: six floats, then
        // 8-byte-aligned pairs starting at 24. No mid-block padding.
        EXPECT_EQ(offsetof(MaterialParams, resolution), 24u);
        EXPECT_EQ(offsetof(MaterialParams, walkOffset), 32u);
        EXPECT_EQ(offsetof(MaterialParams, textCenter), 64u);
        EXPECT_EQ(sizeof(MaterialParams) % 16, 0u);
    }

    TEST(RenderBoundary, HandleZeroConventionsAreDistinct)
    {
        EXPECT_FALSE(TextureHandle{}.isValid());        // 0 = no texture
        EXPECT_TRUE(RenderTargetHandle{}.isBackbuffer()); // 0 = a real, ordinary target
        EXPECT_TRUE(MaterialHandle{}.isDefault());       // 0 = the default built-in
    }

    TEST(RenderBoundary, TargetHandlesDecodeBackToTheirPoolAndDepth)
    {
        // A backend gets a handle and has to find the object it names. The encoding is
        // arithmetic, so the decoding is too - and the two have to agree for every pool, not
        // just the one somebody happened to try.
        for (int8_t i = -1; ++i < static_cast<int8_t>(DrawPoolType::LAST);) {
            const auto type = static_cast<DrawPoolType>(i);

            const auto pool = RenderHandles::poolTarget(type);
            EXPECT_TRUE(RenderHandles::isPoolTarget(pool));
            EXPECT_FALSE(RenderHandles::isTransientTarget(pool));
            EXPECT_EQ(RenderHandles::poolOf(pool), type);

            for (uint32_t depth = 0; depth < RenderHandles::TRANSIENT_TARGETS_PER_POOL; ++depth) {
                const auto transient = RenderHandles::transientTarget(type, depth);
                EXPECT_TRUE(RenderHandles::isTransientTarget(transient));
                EXPECT_FALSE(RenderHandles::isPoolTarget(transient));
                EXPECT_EQ(RenderHandles::poolOf(transient), type);
                EXPECT_EQ(RenderHandles::transientDepthOf(transient), depth);
            }
        }

        // The backbuffer is neither, which is what stops it being decoded into pool 0's target.
        const RenderTargetHandle backbuffer;
        EXPECT_FALSE(RenderHandles::isPoolTarget(backbuffer));
        EXPECT_FALSE(RenderHandles::isTransientTarget(backbuffer));
    }

    TEST(RenderBoundary, AtlasLayerTargetsAreADistinctThirdKind)
    {
        // The whole target space is decoded by arithmetic range checks, not by a tag, so a third
        // family is only safe while it overlaps neither of the first two. `poolOf` in particular
        // has no kind guard - it would happily decode an atlas handle into a garbage DrawPoolType
        // - which is exactly why the frame runner must test kind before it decodes.
        for (int atlas = 0; atlas < Fw::TextureAtlasType::LAST; ++atlas) {
            for (const bool smooth : { false, true }) {
                for (uint32_t layer = 0; layer < RenderHandles::ATLAS_LAYERS_PER_GROUP; ++layer) {
                    const auto handle = RenderHandles::atlasTarget(
                        static_cast<Fw::TextureAtlasType>(atlas), smooth, layer);

                    EXPECT_TRUE(RenderHandles::isAtlasTarget(handle));
                    EXPECT_FALSE(RenderHandles::isPoolTarget(handle));
                    EXPECT_FALSE(RenderHandles::isTransientTarget(handle));
                    EXPECT_FALSE(handle.isBackbuffer());

                    // An atlas layer is SAMPLED through its target-texture twin, so the handle
                    // has to stay inside the render-target texture range or a packet naming it
                    // would resolve to a sprite instead.
                    EXPECT_TRUE(RenderHandles::isRenderTargetTexture(
                        RenderHandles::targetTexture(handle)));
                }
            }
        }

        // Every (atlas, filter group, layer) triple is its own target. Getting one multiplication
        // wrong here would silently composite the nearest-filtered layers into the linear ones.
        std::set<uint32_t> seen;
        for (int atlas = 0; atlas < Fw::TextureAtlasType::LAST; ++atlas) {
            for (const bool smooth : { false, true }) {
                for (uint32_t layer = 0; layer < RenderHandles::ATLAS_LAYERS_PER_GROUP; ++layer) {
                    const auto handle = RenderHandles::atlasTarget(
                        static_cast<Fw::TextureAtlasType>(atlas), smooth, layer);
                    EXPECT_TRUE(seen.insert(handle.id).second)
                        << "duplicate atlas target handle " << handle.id;
                }
            }
        }

        // Neither of the other two kinds may wander into the atlas range.
        for (int8_t i = -1; ++i < static_cast<int8_t>(DrawPoolType::LAST);) {
            const auto type = static_cast<DrawPoolType>(i);
            EXPECT_FALSE(RenderHandles::isAtlasTarget(RenderHandles::poolTarget(type)));
            for (uint32_t depth = 0; depth < RenderHandles::TRANSIENT_TARGETS_PER_POOL; ++depth)
                EXPECT_FALSE(RenderHandles::isAtlasTarget(RenderHandles::transientTarget(type, depth)));
        }
    }

    TEST(RenderBoundary, AtlasMaintenancePassesComeBeforeEveryPool)
    {
        // Atlas maintenance writes the layers that pool draws SAMPLE, so it goes ahead of every
        // pool - which is where the GL path already does it, flushing each atlas before any pool
        // is drawn. Built by hand rather than from a TextureAtlas: constructing one reaches
        // glGenFramebuffers, and in a unit-test process X11Window reports a GL context it does
        // not have (PlatformWindow::hasGLContext defaults to true) while every GLEW pointer is
        // null.
        AtlasProgram atlas;
        {
            auto& pass = atlas.passes.emplace_back();
            pass.target = RenderHandles::atlasTarget(Fw::TextureAtlasType::FOREGROUND, true, 0);
            pass.load = LoadAction::Keep;
            pass.viewport = Rect(0, 0, 2048, 2048);
            pass.label = "atlas-linear";

            CoordsBuffer quad;
            quad.addRect(Rect(0, 0, 32, 32));
            const auto slice = atlas.arena.append(quad);

            auto& packet = pass.packets.emplace_back();
            packet.vertexOffset = slice.offset;
            packet.vertexCount = slice.count;
            packet.blendEnabled = false;
            packet.alphaWrite = true;
        }
        atlas.bindArena();

        Pool pool;
        pool.rect(Rect(0, 0, 10, 10));

        PoolProgram program;
        pool.compile(program);
        ASSERT_TRUE(program.isComplete());

        RenderFrame frame;
        FrameAssembler assembler;
        FrameAssembler::Programs programs{};
        programs[static_cast<size_t>(DrawPoolType::LIGHT)] = &program;

        FrameAssembler::AtlasPrograms atlases{};
        atlases[Fw::TextureAtlasType::FOREGROUND] = &atlas;

        assembler.assemble(programs, atlases, VIEWPORT, 0.f, frame);

        ASSERT_GE(frame.passes.size(), 2u);
        EXPECT_TRUE(RenderHandles::isAtlasTarget(frame.passes.front().target));

        // Keep, not Clear. Atlas layers accumulate across frames, so clearing one would erase
        // every sprite packed into it in every earlier frame.
        EXPECT_EQ(frame.passes.front().load, LoadAction::Keep);
        ASSERT_EQ(frame.passes.front().packets.size(), 1u);
        EXPECT_FALSE(frame.passes.front().packets[0].blendEnabled);

        // The pass must point at the ATLAS's arena, not the pool's - the same aliasing hazard
        // the composition packets have, reached from a second producer of frame geometry.
        EXPECT_EQ(frame.passes.front().arena, &atlas.arena);

        // ...and no pool pass may have been reordered ahead of it.
        for (size_t i = 1; i < frame.passes.size(); ++i)
            EXPECT_FALSE(RenderHandles::isAtlasTarget(frame.passes[i].target));
    }

    TEST(RenderBoundary, AFrameWithNoAtlasWorkCarriesNoAtlasPasses)
    {
        // The common case by far: an atlas packs new sprites only when something new is drawn,
        // so nearly every frame owes no maintenance at all and must not pay for an empty pass.
        Pool pool;
        pool.rect(Rect(0, 0, 10, 10));

        PoolProgram program;
        pool.compile(program);

        RenderFrame frame;
        FrameAssembler assembler;
        FrameAssembler::Programs programs{};
        programs[static_cast<size_t>(DrawPoolType::LIGHT)] = &program;

        assembler.assemble(programs, FrameAssembler::AtlasPrograms{}, VIEWPORT, 0.f, frame);

        for (const auto& pass : frame.passes)
            EXPECT_FALSE(RenderHandles::isAtlasTarget(pass.target));
    }

    TEST(RenderBoundary, BackbufferPacketsDoNotWriteAlphaButTransientOnesDo)
    {
        // GL keeps alpha writing in one global that FrameBuffer::bind sets and release never
        // restores. What is well defined is the value each target is ENTERED with: a pool
        // drawing straight to the backbuffer inherits drawPool's reset, which is off; a
        // temporary framebuffer keeps FrameBuffer's default, which is on.
        Pool pool;
        pool.rect(Rect(0, 0, 10, 10));
        DrawPoolTestAccess::bindFrameBuffer(*pool.p, Size(32, 32));
        pool.rect(Rect(0, 0, 8, 8));
        DrawPoolTestAccess::releaseFrameBuffer(*pool.p, Rect(50, 50, 32, 32));

        PoolProgram program;
        pool.compile(program);

        ASSERT_TRUE(program.isComplete());
        ASSERT_EQ(program.passes.size(), 3u);

        ASSERT_EQ(program.passes[0].packets.size(), 1u);
        EXPECT_FALSE(program.passes[0].packets[0].alphaWrite);

        ASSERT_EQ(program.passes[1].packets.size(), 1u);
        EXPECT_TRUE(program.passes[1].packets[0].alphaWrite);

        // The blit lands back on the backbuffer and takes that target's value, not the nested
        // one it is sampling.
        ASSERT_EQ(program.passes[2].packets.size(), 1u);
        EXPECT_FALSE(program.passes[2].packets[0].alphaWrite);
    }

    TEST(RenderBoundary, FramebufferBlitCarriesTheOuterState)
    {
        // The `useFramebuffer` shader route exists so that a shader applies AT the blit rather
        // than to each wrapped draw, and GL implements that by capturing the OUTER state and
        // applying it before FrameBuffer::draw. A blit packet that carried only the opacity
        // silently dropped the material, the colour and the clip - which is exactly what
        // un-shaded every Outline outfit.
        Pool pool;
        DrawPoolTestAccess::setOpacity(*pool.p, 0.25f);
        DrawPoolTestAccess::setClipRect(*pool.p, Rect(10, 10, 40, 40));

        DrawPoolTestAccess::bindFrameBuffer(*pool.p, Size(32, 32));
        pool.rect(Rect(0, 0, 8, 8), Color::green);
        DrawPoolTestAccess::releaseFrameBuffer(*pool.p, Rect(0, 0, 32, 32));

        PoolProgram program;
        pool.compile(program);

        ASSERT_TRUE(program.isComplete());
        ASSERT_FALSE(program.passes.empty());

        const auto& blitPass = program.passes.back();
        ASSERT_EQ(blitPass.packets.size(), 1u);

        const auto& blit = blitPass.packets[0];
        EXPECT_TRUE(blit.textured);
        EXPECT_FLOAT_EQ(blit.opacity, 0.25f);
        EXPECT_TRUE(blit.scissorEnabled);
        EXPECT_EQ(blit.scissor, Rect(10, 10, 40, 40));

        // The nested draw itself is scoped to the temporary target and must NOT inherit the
        // outer clip rect, which is in the outer target's coordinates.
        const auto& nested = program.passes[program.passes.size() - 2];
        ASSERT_EQ(nested.packets.size(), 1u);
        EXPECT_FALSE(nested.packets[0].scissorEnabled);
    }

    TEST(RenderBoundary, UnregisteredShaderProgramsDoNotBecomeModuleMaterials)
    {
        // Painter's own built-in programs never reach ShaderManager, so they carry id 0. The
        // replace-colour one genuinely reaches pool state - every marked creature and item binds
        // it - and mapping it through the module range produced a handle no backend could
        // resolve. A null program is still the default material.
        EXPECT_TRUE(PoolCompiler::materialOf(nullptr).isDefault());
    }

    TEST(RenderBoundary, RenderTargetTexturesCannotAliasRealTextures)
    {
        // The invariant is that no REAL texture's handle can land in the render-target range.
        // Asserting only over RenderHandles' own constants would not test that at all - it has
        // to reach the actual counter seed, which is why texture.h exposes it.
        EXPECT_GE(TEXTURE_UNIQUE_ID_SEED, RenderHandles::RENDER_TARGET_TEXTURE_LIMIT);

        const auto target = RenderHandles::targetTexture(RenderHandles::poolTarget(DrawPoolType::MAP));
        EXPECT_TRUE(RenderHandles::isRenderTargetTexture(target));
        EXPECT_FALSE(RenderHandles::isRenderTargetTexture(TextureHandle{ TEXTURE_UNIQUE_ID_SEED }));
    }

}

namespace {

    // ---------------------------------------------------------------------------------------
    // Golden frame.
    //
    // A representative frame - direct geometry, a non-default blend, a nested transient target
    // with a horizontal flip, and the blend-off hole punch - compiled and serialised, compared
    // against a checked-in expectation.
    //
    // This is the regression instrument the migration needs most: a refactor that reorders
    // passes, loses a state bit or perturbs geometry fails HERE, on a runner with no GPU and no
    // window server, instead of shipping as a rendering bug. The recording is deliberately
    // platform-stable (fixed float precision, FNV-1a over float bits rather than std::hash), so
    // this same text is expected on every platform's CI.
    // ---------------------------------------------------------------------------------------
    constexpr const char* GOLDEN_FRAME =
        "frame 800x600\n"
        "  pass[0] target=0 load=Keep clear=0 viewport=0,0,800x600 label=pool-direct\n"
        "    packet[0] verts=6 geom=12345224582227486187 tex=0 texMat=0 mat=0 blend=Normal blendOn=1 alphaW=0 opacity=1.0000 color=0:0:0:255 scissor=off\n"
        "    packet[1] verts=6 geom=10406223313678849225 tex=0 texMat=0 mat=0 blend=Multiply blendOn=1 alphaW=0 opacity=1.0000 color=255:0:0:255 scissor=off\n"
        "  pass[1] target=96 load=Clear clear=0 viewport=0,0,32x32 label=transient\n"
        "    packet[0] verts=6 geom=12080383858203200517 tex=0 texMat=0 mat=0 blend=Normal blendOn=1 alphaW=1 opacity=1.0000 color=0:255:0:255 scissor=off\n"
        "  pass[2] target=0 load=Keep clear=0 viewport=0,0,800x600 label=pool-direct\n"
        "    packet[0] verts=6 geom=7678018406283462290 tex=96 texMat=0 mat=0 blend=Normal blendOn=1 alphaW=0 opacity=1.0000 color=255:255:255:255 scissor=off\n"
        "    packet[1] verts=6 geom=8811809492208675301 tex=0 texMat=0 mat=0 blend=Normal blendOn=0 alphaW=0 opacity=1.0000 color=0:0:0:0 scissor=off\n"
        "    packet[2] verts=6 geom=2370055488363448093 tex=0 texMat=0 mat=0 blend=Normal blendOn=1 alphaW=0 opacity=1.0000 color=255:255:255:255 scissor=400,400,100x100\n";

    std::string buildRepresentativeFrame(RenderFrame& frame, FrameAssembler& assembler,
                                         PoolProgram& program, Pool& pool)
    {
        pool.rect(Rect(0, 0, 800, 600), Color::black);
        DrawPoolTestAccess::setCompositionMode(*pool.p, CompositionMode::MULTIPLY);
        pool.rect(Rect(10, 10, 100, 50), Color::red);
        DrawPoolTestAccess::resetCompositionMode(*pool.p);
        DrawPoolTestAccess::bindFrameBuffer(*pool.p, Size(32, 32));
        pool.rect(Rect(0, 0, 32, 32), Color::green);
        DrawPoolTestAccess::releaseFrameBuffer(*pool.p, Rect(200, 100, 64, 64), 1 /* horizontal flip */);
        DrawPoolTestAccess::addAction(*pool.p, [] {}, ActionIdiom::BlendOff);
        pool.rect(Rect(300, 300, 40, 40), Color::alpha); // the map-hole punch
        DrawPoolTestAccess::addAction(*pool.p, [] {}, ActionIdiom::BlendOn);
        DrawPoolTestAccess::setClipRect(*pool.p, Rect(400, 400, 100, 100));   // so the golden covers a live scissor
        pool.rect(Rect(400, 400, 200, 200), Color::white);
        DrawPoolTestAccess::resetClipRect(*pool.p);

        pool.compile(program);

        FrameAssembler::Programs programs{};
        programs[static_cast<size_t>(DrawPoolType::LIGHT)] = &program;
        assembler.assemble(programs, VIEWPORT, 2.f, frame);

        return RecordingBackend::record(frame);
    }

    // ---------------------------------------------------------------------------------------
// Phase 6: module materials
//
// None of these constructs a PainterShaderProgram, and none can. In a test process
// X11Window inherits PlatformWindow::hasGLContext() == true while every GLEW entry point is
// a null pointer, so ShaderProgram's constructor jumps to address 0 - recorded in the Phase 4
// handoff and again in Phase 5 for TextureAtlas. What is testable without one is everything
// the boundary itself carries: the registry that publishes what a handle names, the
// parameter block the assembler supplies, and the shape of the generated MSL table.
// ---------------------------------------------------------------------------------------

TEST(RenderBoundary, MaterialRegistryPublishesWhatAHandleNames)
{
    auto& registry = MaterialRegistry::instance();
    registry.clear();

    const auto handle = materialHandleOf(BuiltinMaterial::FirstModule);
    registry.registerMaterial(handle, MaterialDesc{ "Map - Fog", "fog" });

    const auto* desc = registry.resolve(handle);
    ASSERT_NE(desc, nullptr);
    EXPECT_EQ(desc->name, "Map - Fog");
    EXPECT_EQ(desc->sourceKey, "fog");

    // A handle nothing registered resolves to nothing, which is how a backend knows to fall
    // back to the default built-in rather than to guess.
    EXPECT_EQ(registry.resolve(MaterialHandle{ 9999 }), nullptr);

    // The default handle is not a material and must never occupy a slot.
    registry.registerMaterial(MaterialHandle{}, MaterialDesc{ "nope", "nope" });
    EXPECT_EQ(registry.resolve(MaterialHandle{}), nullptr);

    registry.clear();
    EXPECT_EQ(registry.resolve(handle), nullptr);
}

TEST(RenderBoundary, EveryMaterialPacketIsGivenParameters)
{
    // Until Phase 6 only the map-composition packet carried a MaterialParams block, which was
    // invisible on OpenGL because Painter uploads u_Time and u_Resolution itself on every
    // single draw. A backend with no Painter under it has no such side channel, so an outfit
    // shader reading u_Time would have rendered at time zero for the life of the process.
    PoolProgram program;
    program.type = DrawPoolType::FOREGROUND;

    auto& pass = program.passes.emplace_back();
    pass.target = RenderHandles::poolTarget(DrawPoolType::FOREGROUND);
    pass.viewport = Rect(0, 0, Size{ 320, 240 });
    pass.load = LoadAction::Clear;

    auto& shaded = pass.packets.emplace_back();
    shaded.material = materialHandleOf(BuiltinMaterial::FirstModule);
    auto& plain = pass.packets.emplace_back();
    plain.material = MaterialHandle{};

    program.bindArena();

    FrameAssembler assembler;
    FrameAssembler::Programs programs{};
    programs[static_cast<size_t>(DrawPoolType::FOREGROUND)] = &program;

    RenderFrame frame;
    assembler.assemble(programs, VIEWPORT, 2.f, frame);

    ASSERT_EQ(frame.passes.size(), 1u);
    ASSERT_EQ(frame.passes[0].packets.size(), 2u);

    const auto& shadedOut = frame.passes[0].packets[0];
    ASSERT_NE(shadedOut.params, nullptr);
    EXPECT_FLOAT_EQ(shadedOut.params->time, 2.f);
    // The resolution a material reads is the size of the TARGET being drawn into, which is
    // what Painter reports on the GL side because FrameBuffer::bind sets it to exactly that.
    EXPECT_FLOAT_EQ(shadedOut.params->resolution.x, 320.f);
    EXPECT_FLOAT_EQ(shadedOut.params->resolution.y, 240.f);

    // A packet with no material reads no parameters, so it is given none.
    EXPECT_EQ(frame.passes[0].packets[1].params, nullptr);

    // Both shaded packets in one pass share one block rather than each getting a copy.
    auto& second = frame.passes[0].packets[1];
    EXPECT_EQ(second.params, nullptr);
}

TEST(RenderBoundary, TranslatedModuleMaterialsAreWellFormed)
{
    // The generated header is plain C++ - string views, no Metal types - so this runs on every
    // toolchain rather than only where the backend that consumes it is built. It is the closed
    // set the Phase 6 toolchain enforces, and the thing most likely to rot is the agreement
    // between a table entry and the MSL it points at.
    EXPECT_FALSE(METAL_MODULE_MATERIALS.empty());

    std::set<std::string_view> keys;
    for (const auto& material : METAL_MODULE_MATERIALS) {
        EXPECT_FALSE(material.key.empty());
        EXPECT_TRUE(keys.insert(material.key).second) << "duplicate key " << material.key;

        // A material resolves by .frag basename, and both entry points are derived from it, so
        // a mismatch here means a table that names functions its own source does not define.
        EXPECT_EQ(material.vertexEntry, std::string{ "crystalotc_vert_" } + std::string{ material.key });
        EXPECT_EQ(material.fragmentEntry, std::string{ "crystalotc_frag_" } + std::string{ material.key });
        EXPECT_NE(material.source.find(material.vertexEntry), std::string_view::npos);
        EXPECT_NE(material.source.find(material.fragmentEntry), std::string_view::npos);

        // The pinned bindings are the contract with MetalABI; --msl-decoration-binding turns
        // the generator's GLSL binding numbers straight into these.
        EXPECT_NE(material.source.find("[[buffer(2)]]"), std::string_view::npos)
            << material.key << " has no vertex parameter block";
    }
}

TEST(RenderBoundary, ModuleMaterialSourcesDeclareNoLegacyGlsl)
{
    // The shipped .frag sources are GLSL 1.10-era and SPIR-V accepts none of it. If any of
    // these spellings survived into the MSL the translation silently did nothing.
    for (const auto& material : METAL_MODULE_MATERIALS) {
        EXPECT_EQ(material.source.find("gl_FragColor"), std::string_view::npos) << material.key;
        EXPECT_EQ(material.source.find("texture2D("), std::string_view::npos) << material.key;
        EXPECT_EQ(material.source.find("varying"), std::string_view::npos) << material.key;
    }
}

TEST(RenderGoldenFrame, RepresentativeFrameMatchesTheBaseline)
    {
        Pool pool;
        PoolProgram program;
        RenderFrame frame;
        FrameAssembler assembler;

        const auto recorded = buildRepresentativeFrame(frame, assembler, program, pool);

        ASSERT_TRUE(program.isComplete());
        EXPECT_EQ(recorded, GOLDEN_FRAME);
    }

    TEST(RenderGoldenFrame, StructureViewIsStableToo)
    {
        Pool pool;
        PoolProgram program;
        RenderFrame frame;
        FrameAssembler assembler;

        buildRepresentativeFrame(frame, assembler, program, pool);

        EXPECT_EQ(RecordingBackend::recordStructure(frame),
                  "frame 800x600 passes=3 uploads=0 readbacks=0\n"
                  "  pass[0] target=0 load=Keep viewport=0,0,800x600 packets=2 label=pool-direct\n"
                  "  pass[1] target=96 load=Clear viewport=0,0,32x32 packets=1 label=transient\n"
                  "  pass[2] target=0 load=Keep viewport=0,0,800x600 packets=3 label=pool-direct\n");
    }

}
