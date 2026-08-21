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

#include "frameassembler.h"

#include "renderhandles.h"

#include <cassert>

namespace
{
    // Composition draws land on the backbuffer one after another, separated only by whichever
    // pools draw straight to it. Opening a fresh pass for each would multiply encoder churn
    // for no reason, so adjacent backbuffer work shares a pass.
    RenderPass& backbufferPass(RenderFrame& out, const Size& drawableSize, const VertexArena& arena)
    {
        if (!out.passes.empty()) {
            auto& last = out.passes.back();
            // The arena check is not optional. A pool with no target compiles its own root
            // segment to the BACKBUFFER, and that pass points at THAT POOL's arena. Reusing it
            // for a composition packet - whose vertex offsets index the assembler's arena -
            // would read another pool's geometry, or run off the end of it.
            if (last.target.isBackbuffer() && last.arena == &arena)
                return last;
        }

        auto& pass = out.passes.emplace_back();
        pass.target = RenderTargetHandle{ RenderTargetHandle::BACKBUFFER };
        pass.load = LoadAction::Keep;
        pass.viewport = Rect(0, 0, drawableSize);
        pass.arena = &arena;
        pass.label = "backbuffer";
        return pass;
    }
}

void FrameAssembler::invalidateRetainedTargets()
{
    m_targetValid.fill(false);
    m_targetContent.fill(0);
}

bool FrameAssembler::isComplete(const Programs& programs)
{
    for (const auto* program : programs) {
        if (program && !program->isComplete())
            return false;
    }
    return true;
}

void FrameAssembler::assemble(const Programs& programs, const Size& drawableSize,
                              const float frameTime, RenderFrame& out)
{
    out.clear();
    out.drawableSize = drawableSize;

    m_arena.clear();
    m_params.clear();
    // Packets hold RAW POINTERS into m_params, so a reallocation mid-loop would leave them
    // dangling. At most one entry is appended per program, so reserving the program count is
    // provably sufficient - asserted below rather than merely intended.
    m_params.reserve(programs.size());
    const auto paramsCapacity = m_params.capacity();

    // Uploads are applied before any pass, so a texture a pass samples already holds this
    // frame's pixels. LightView is the only producer today.
    for (const auto* program : programs) {
        if (!program)
            continue;
        for (const auto& upload : program->uploads)
            out.uploads.push_back(upload);
    }

    // Pools composite in enum order - the order DrawPoolManager::draw walks them in.
    for (const auto* program : programs) {
        if (!program)
            continue;

        // A pool that draws STRAIGHT to the backbuffer is never skipped: there is no retained
        // target holding its result, so not emitting its passes would simply not draw it. The
        // GL path makes the same distinction - drawObjects' early return is gated on the pool
        // having a framebuffer.
        const auto poolIndex = static_cast<size_t>(program->type);
        const bool canReuseTarget =
            program->hasComposition &&
            poolIndex < m_targetValid.size() &&
            m_targetValid[poolIndex] &&
            m_targetContent[poolIndex] == program->contentHash;

        if (!canReuseTarget) {
            // The pool's own passes: its retained target plus any nested transient targets.
            for (const auto& pass : program->passes)
                out.passes.push_back(pass);

            if (program->hasComposition && poolIndex < m_targetValid.size()) {
                m_targetContent[poolIndex] = program->contentHash;
                m_targetValid[poolIndex] = true;
            }
        }

        if (!program->hasComposition)
            continue;

        // The composition quad is the assembler's own geometry. GL builds the same quad with
        // CoordsBuffer::addQuad inside FrameBuffer::prepare.
        CoordsBuffer quad;
        quad.addQuad(program->compositionDest, program->compositionSrc);
        const auto slice = m_arena.append(quad);

        auto& params = m_params.emplace_back(program->compositionParams);
        params.time = frameTime;

        auto& pass = backbufferPass(out, drawableSize, m_arena);
        auto& packet = pass.packets.emplace_back();
        packet.vertexOffset = slice.offset;
        packet.vertexCount = slice.count;
        packet.textured = true;
        packet.texture = RenderHandles::targetTexture(program->compositionSource);
        packet.material = program->compositionMaterial;
        packet.params = program->compositionMaterial.isDefault() ? nullptr : &params;
        packet.opacity = program->compositionOpacity;
        packet.blend = BlendMode::Normal;
        packet.blendEnabled = program->compositionBlendEnabled;
        packet.alphaWrite = program->compositionAlphaWrite;
    }

    // Passes hold a pointer to the ARENA OBJECT, not to its storage, so growth during the loop
    // is harmless - positions() is resolved when a backend reads it. The pool passes carry
    // their own program's arena pointer, set by PoolProgram::bindArena.
    assert(m_params.capacity() == paramsCapacity && "MaterialParams reallocated; packet pointers dangle");
}
