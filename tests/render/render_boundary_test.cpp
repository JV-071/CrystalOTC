#include <gtest/gtest.h>

// The producer API is private on DrawPool and reached through DrawPoolManager, which needs
// initialised globals and a GL context. Tests drive the pool directly instead, using the same
// access seam tests/map/map_spectators_test.cpp already uses.
#define private public
#define protected public
#include <framework/graphics/drawpool.h>
#undef protected
#undef private

#include <framework/graphics/render/frameassembler.h>
#include <framework/graphics/render/linetriangulation.h>
#include <framework/graphics/render/poolcompiler.h>
#include <framework/graphics/render/recordingbackend.h>

namespace {

    constexpr Size VIEWPORT{ 800, 600 };

    // LIGHT is the pool with the least machinery: no framebuffer, so nothing here can reach
    // GL, and no always-group batching to obscure which packet came from which draw.
    struct Pool
    {
        DrawPool* p{ DrawPool::create(DrawPoolType::LIGHT) };
        ~Pool() { delete p; }

        void rect(const Rect& dest, const Color& color = Color::white)
        {
            p->add(color, nullptr, DrawPool::DrawMethod{
                .type = DrawPool::DrawMethodType::RECT, .dest = dest });
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
        pool.p->addAction([] {}, ActionIdiom::BlendOff);
        pool.rect(Rect(20, 20, 10, 10), Color::alpha); // the map-hole punch
        pool.p->addAction([] {}, ActionIdiom::BlendOn);
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
        pool.p->bindFrameBuffer(Size(64, 64));
        pool.rect(Rect(1, 1, 8, 8));
        pool.p->releaseFrameBuffer(Rect(100, 100, 64, 64));
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
        pool.p->bindFrameBuffer(Size(64, 64));
        pool.rect(Rect(0, 0, 8, 8));
        pool.p->bindFrameBuffer(Size(32, 32));
        pool.rect(Rect(0, 0, 4, 4));
        pool.p->releaseFrameBuffer(Rect(0, 0, 32, 32));
        pool.p->releaseFrameBuffer(Rect(0, 0, 64, 64));

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

    TEST(RenderBoundary, UnbalancedReleaseIsReportedNotSwallowed)
    {
        Pool pool;
        pool.p->releaseFrameBuffer(Rect(0, 0, 10, 10));

        PoolProgram program;
        pool.compile(program);

        EXPECT_FALSE(program.isComplete());
        EXPECT_FALSE(program.unsupported.empty());
    }

    TEST(RenderBoundary, UntaggedActionPoisonsTheProgram)
    {
        Pool pool;
        pool.rect(Rect(0, 0, 10, 10));
        pool.p->addAction([] {}); // defaults to ActionIdiom::Opaque

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
        pool.p->setClipRect(Rect(-50, -50, 10000, 10000));
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
        pool.p->bindFrameBuffer(Size(64, 64));
        // A clip rect entirely outside the target it is drawn into - a widget scrolled away.
        pool.p->setClipRect(Rect(900, 900, 100, 50));
        pool.rect(Rect(0, 0, 10, 10));
        pool.p->releaseFrameBuffer(Rect(0, 0, 64, 64));

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
        pool.p->setOpacity(0.5f);              // a standing, non-default value
        pool.rect(Rect(0, 0, 10, 10));
        pool.p->setOpacity(0.25f, true);       // onlyOnce override
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
        pool.p->setCompositionMode(CompositionMode::MULTIPLY, true);
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
        pool.p->setCompositionMode(CompositionMode::MULTIPLY);
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
            pool.p->bindFrameBuffer(Size(16, 16));
            pool.rect(Rect(1, 1, 4, 4));
            pool.p->releaseFrameBuffer(Rect(2, 2, 16, 16), 1 /* horizontal flip */);
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
            pool->p->bindFrameBuffer(Size(16, 16));
            pool->rect(Rect(0, 0, 4, 4));
        }
        plain.p->releaseFrameBuffer(Rect(0, 0, 16, 16), 0);
        flipped.p->releaseFrameBuffer(Rect(0, 0, 16, 16), 2 /* vertical */);

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
        "    packet[0] verts=6 geom=12345224582227486187 tex=0 texMat=0 mat=0 blend=Normal blendOn=1 alphaW=1 opacity=1.0000 color=0:0:0:255 scissor=off\n"
        "    packet[1] verts=6 geom=10406223313678849225 tex=0 texMat=0 mat=0 blend=Multiply blendOn=1 alphaW=1 opacity=1.0000 color=255:0:0:255 scissor=off\n"
        "  pass[1] target=96 load=Clear clear=0 viewport=0,0,32x32 label=transient\n"
        "    packet[0] verts=6 geom=12080383858203200517 tex=0 texMat=0 mat=0 blend=Normal blendOn=1 alphaW=1 opacity=1.0000 color=0:255:0:255 scissor=off\n"
        "  pass[2] target=0 load=Keep clear=0 viewport=0,0,800x600 label=pool-direct\n"
        "    packet[0] verts=6 geom=7678018406283462290 tex=96 texMat=0 mat=0 blend=Normal blendOn=1 alphaW=1 opacity=1.0000 color=255:255:255:255 scissor=off\n"
        "    packet[1] verts=6 geom=8811809492208675301 tex=0 texMat=0 mat=0 blend=Normal blendOn=0 alphaW=1 opacity=1.0000 color=0:0:0:0 scissor=off\n"
        "    packet[2] verts=6 geom=2370055488363448093 tex=0 texMat=0 mat=0 blend=Normal blendOn=1 alphaW=1 opacity=1.0000 color=255:255:255:255 scissor=400,400,100x100\n";

    std::string buildRepresentativeFrame(RenderFrame& frame, FrameAssembler& assembler,
                                         PoolProgram& program, Pool& pool)
    {
        pool.rect(Rect(0, 0, 800, 600), Color::black);
        pool.p->setCompositionMode(CompositionMode::MULTIPLY);
        pool.rect(Rect(10, 10, 100, 50), Color::red);
        pool.p->resetCompositionMode();
        pool.p->bindFrameBuffer(Size(32, 32));
        pool.rect(Rect(0, 0, 32, 32), Color::green);
        pool.p->releaseFrameBuffer(Rect(200, 100, 64, 64), 1 /* horizontal flip */);
        pool.p->addAction([] {}, ActionIdiom::BlendOff);
        pool.rect(Rect(300, 300, 40, 40), Color::alpha); // the map-hole punch
        pool.p->addAction([] {}, ActionIdiom::BlendOn);
        pool.p->setClipRect(Rect(400, 400, 100, 100));   // so the golden covers a live scissor
        pool.rect(Rect(400, 400, 200, 200), Color::white);
        pool.p->resetClipRect();

        pool.compile(program);

        FrameAssembler::Programs programs{};
        programs[static_cast<size_t>(DrawPoolType::LIGHT)] = &program;
        assembler.assemble(programs, VIEWPORT, 2.f, frame);

        return RecordingBackend::record(frame);
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
