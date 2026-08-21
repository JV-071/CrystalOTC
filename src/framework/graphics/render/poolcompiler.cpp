/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "poolcompiler.h"

#include <framework/graphics/drawpool.h>
#include <framework/graphics/paintershaderprogram.h>

namespace
{
    // A target being built up. Passes are emitted in EXECUTION order, so a nested target has
    // to be flushed to the pass list before the packet that samples it exists - which means
    // an outer target is split into segments: everything before the nested pass, then the
    // nested pass, then a continuation that loads what the first segment left behind.
    struct OpenSegment
    {
        RenderTargetHandle target;
        Rect viewport;
        Color clearColor{ Color::alpha };
        LoadAction firstLoad{ LoadAction::Clear };
        bool flushedOnce{ false };
        std::string label;
        std::vector<DrawPacket> packets;
    };

    struct ClampedScissor
    {
        Rect rect;
        bool enabled{ false };
    };

    // Folds a packet into the program's content identity. Everything that could change what
    // the target ends up looking like has to go in - including the geometry, via the slice,
    // since two packets can share state and draw different things.
    void foldPacket(size_t& hash, const DrawPacket& p, const VertexArena& arena)
    {
        stdext::hash_combine(hash, p.vertexOffset);
        stdext::hash_combine(hash, p.vertexCount);
        stdext::hash_combine(hash, p.texture.id);
        stdext::hash_combine(hash, p.textureMatrixId);
        stdext::hash_combine(hash, p.material.id);
        stdext::hash_combine(hash, static_cast<uint32_t>(p.blend));
        stdext::hash_combine(hash, static_cast<uint32_t>(p.blendEnabled));
        stdext::hash_combine(hash, static_cast<uint32_t>(p.alphaWrite));
        stdext::hash_combine(hash, static_cast<uint32_t>(p.textured));
        stdext::hash_combine(hash, p.opacity);
        stdext::hash_union(hash, p.color.hash());
        if (p.scissorEnabled)
            stdext::hash_union(hash, p.scissor.isValid() ? p.scissor.hash() : size_t{ 1 });
        if (p.transform != DEFAULT_MATRIX3)
            stdext::hash_union(hash, p.transform.hash());

        const float* pos = arena.positions();
        for (uint32_t i = 0; i < p.vertexCount * 2; ++i)
            stdext::hash_combine(hash, pos[static_cast<size_t>(p.vertexOffset) * 2 + i]);
    }

    // Scissor rects arrive from the producer unclamped. GL forgave out-of-bounds ones; Metal
    // validates and kills the encoder. Clamping here means neither backend has to care.
    ClampedScissor clampScissor(const Rect& scissor, const Rect& viewport)
    {
        if (!scissor.isValid())
            return { {}, false }; // no clipping was requested

        const Rect clamped = scissor.intersection(viewport);
        if (!clamped.isValid())
            return { Rect(viewport.left(), viewport.top(), 0, 0), true }; // misses the target: clips everything

        return { clamped, true };
    }
}

MaterialHandle PoolCompiler::materialOf(const PainterShaderProgram* program)
{
    if (!program)
        return {};

    // ShaderManager numbers programs from 0 as they register; offsetting by FirstModule keeps
    // them clear of the built-ins forever.
    return MaterialHandle{ static_cast<uint16_t>(
        static_cast<uint16_t>(BuiltinMaterial::FirstModule) + program->getId()) };
}

void PoolCompiler::compile(const DrawPool& pool, const Size& viewportSize, PoolProgram& out)
{
    out.clear();
    out.type = pool.m_type;
    out.uploads = pool.m_uploads;
    out.requiresAtlasMaintenance = pool.m_atlas != nullptr;

    const bool hasTarget = pool.m_framebuffer != nullptr && pool.m_framebuffer->isValid();

    // Root segment: the pool's own retained target, or the backbuffer when it has none.
    OpenSegment root;
    if (hasTarget) {
        root.target = RenderHandles::poolTarget(pool.m_type);
        root.viewport = Rect(0, 0, pool.m_framebuffer->getSize());
        root.clearColor = Color::alpha;
        root.firstLoad = LoadAction::Clear;
        root.label = "pool-target";
    } else {
        root.target = RenderTargetHandle{ RenderTargetHandle::BACKBUFFER };
        root.viewport = Rect(0, 0, viewportSize);
        // A pool with no target draws ON TOP of whatever is already on the backbuffer.
        root.firstLoad = LoadAction::Keep;
        root.label = "pool-direct";
    }

    std::vector<OpenSegment> stack;
    stack.push_back(std::move(root));

    // Set by a BlendOff action and cleared by BlendOn - the exact scope the GL bracket has.
    bool blendDisabled = false;

    const auto flush = [&out](OpenSegment& seg, const bool force) {
        if (seg.packets.empty() && (seg.flushedOnce || !force))
            return;

        auto& pass = out.passes.emplace_back();
        pass.target = seg.target;
        pass.load = seg.flushedOnce ? LoadAction::Keep : seg.firstLoad;
        pass.clearColor = seg.clearColor;
        pass.viewport = seg.viewport;
        pass.label = seg.label;
        pass.packets.swap(seg.packets);

        seg.flushedOnce = true;
    };

    const auto emitGeometry = [&](OpenSegment& seg, const DrawPool::DrawObject& obj) {
        if (!obj.coords)
            return;

        const auto slice = out.arena.append(*obj.coords);
        if (slice.isEmpty())
            return;

        auto& packet = seg.packets.emplace_back();
        packet.vertexOffset = slice.offset;
        packet.vertexCount = slice.count;
        packet.textured = slice.textured && obj.state.textureHandle.isValid();
        packet.texture = packet.textured ? obj.state.textureHandle : TextureHandle{};
        packet.textureMatrixId = obj.state.textureMatrixId;
        packet.material = materialOf(obj.state.shaderProgram);
        packet.transform = obj.state.transformMatrix;
        const auto scissor = clampScissor(obj.state.clipRect, seg.viewport);
        packet.scissor = scissor.rect;
        packet.scissorEnabled = scissor.enabled;
        packet.color = obj.state.color;
        packet.opacity = obj.state.opacity;
        packet.blend = blendModeOf(obj.state.compositionMode);
        packet.blendEnabled = !blendDisabled;
        packet.alphaWrite = true;
    };

    for (const auto& obj : pool.m_objectsDraw[0]) {
        // Framebuffer markers first: they are declared independently of the idiom tag,
        // because the shipped Vulkan feeder consumes them as raw 1/2 and this migration does
        // not change code it cannot compile and run.
        if (obj.fbMarker == 1) {
            flush(stack.back(), /*force*/ true);

            const auto depth = static_cast<uint32_t>(stack.size() - 1);
            if (depth >= RenderHandles::TRANSIENT_TARGETS_PER_POOL) {
                // Past this depth the handle would land in the NEXT pool's reserved slice and
                // two pools' transient targets would alias. The surveyed sites nest one or two
                // deep, so this is a guard rather than a limit anyone should meet.
                out.unsupported.emplace_back("temporary framebuffer nesting deeper than the handle space allows");
                continue;
            }

            OpenSegment nested;
            nested.target = RenderHandles::transientTarget(pool.m_type, depth);
            nested.viewport = Rect(0, 0, obj.fbSize);
            nested.clearColor = Color::alpha;
            nested.firstLoad = LoadAction::Clear;
            nested.label = "transient";
            stack.push_back(std::move(nested));
            continue;
        }

        if (obj.fbMarker == 2) {
            if (stack.size() < 2) {
                out.unsupported.emplace_back("releaseFrameBuffer without a matching bind");
                continue;
            }

            auto nested = std::move(stack.back());
            stack.pop_back();
            flush(nested, /*force*/ true);

            // The blit back out. GL builds this with CoordsBuffer::addQuad and draws it as a
            // TRIANGLE_STRIP - but addQuad already emits six vertices in triangle-list order,
            // so drawing them as a strip yields the same two triangles plus two degenerate
            // ones. Emitting triangles here is therefore pixel-identical, not merely close.
            CoordsBuffer blit;
            const Rect src(0, 0, nested.viewport.size());
            if (obj.fbFlip == 1)
                blit.addHorizontallyFlippedQuad(obj.fbDest, src);
            else if (obj.fbFlip == 2)
                blit.addVerticallyFlippedQuad(obj.fbDest, src);
            else
                blit.addQuad(obj.fbDest, src);

            const auto slice = out.arena.append(blit);
            auto& seg = stack.back();
            auto& packet = seg.packets.emplace_back();
            packet.vertexOffset = slice.offset;
            packet.vertexCount = slice.count;
            packet.textured = true;
            packet.texture = RenderHandles::targetTexture(nested.target);
            packet.opacity = obj.fbOpacity;
            packet.blend = BlendMode::Normal;
            packet.blendEnabled = !blendDisabled;
            const auto blitScissor = clampScissor(obj.state.clipRect, seg.viewport);
            packet.scissor = blitScissor.rect;
            packet.scissorEnabled = blitScissor.enabled;
            continue;
        }

        if (obj.action) {
            switch (obj.idiom) {
                case ActionIdiom::BlendOff:
                    blendDisabled = true;
                    break;

                case ActionIdiom::BlendOn:
                    blendDisabled = false;
                    break;

                case ActionIdiom::PoolTargetPrepare:
                    // Pure metadata. The rects it would have set are already declared on the
                    // pool (m_fbDest / m_fbSrc) and are read below as composition parameters.
                    break;

                case ActionIdiom::LineStrip:
                case ActionIdiom::LightOverlay:
                    // Declared: the object carries the geometry and state the callback would
                    // have produced, so it compiles exactly like ordinary geometry.
                    emitGeometry(stack.back(), obj);
                    break;

                case ActionIdiom::MapShaderBind:
                    // Installs the composition hooks; the material it selects is declared on
                    // the pool and read below. Nothing to emit into a pass.
                    break;

                case ActionIdiom::Opaque:
                default:
                    out.unsupported.emplace_back("untagged action callback");
                    break;
            }
            continue;
        }

        emitGeometry(stack.back(), obj);
    }

    if (stack.size() != 1)
        out.unsupported.emplace_back("unbalanced framebuffer bind/release");

    while (!stack.empty()) {
        flush(stack.back(), /*force*/ true);
        stack.pop_back();
    }

    if (hasTarget) {
        out.hasComposition = true;
        out.compositionSource = RenderHandles::poolTarget(pool.m_type);
        out.compositionDest = pool.m_fbDest.isValid() ? pool.m_fbDest : Rect(0, 0, pool.m_framebuffer->getSize());
        out.compositionSrc = pool.m_fbSrc.isValid() ? pool.m_fbSrc : Rect(0, 0, pool.m_framebuffer->getSize());

        // The MAP target composites with blending OFF and no alpha write: its pixels replace
        // rather than blend. Every other pool target composites normally.
        out.compositionBlendEnabled = !pool.m_framebuffer->isBlendDisabled();
        out.compositionAlphaWrite = pool.m_framebuffer->hasAlphaWriting();
        out.compositionMaterial = pool.m_compositionMaterial;
        out.compositionParams = pool.m_compositionParams;
        out.compositionOpacity = pool.m_compositionOpacity;
    }

    // Content identity, computed once the passes are final.
    size_t hash = 0;
    for (const auto& pass : out.passes) {
        stdext::hash_combine(hash, pass.target.id);
        stdext::hash_combine(hash, static_cast<uint32_t>(pass.load));
        for (const auto& packet : pass.packets)
            foldPacket(hash, packet, out.arena);
    }
    out.contentHash = hash;

    out.bindArena();
}
