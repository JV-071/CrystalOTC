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

#pragma once

#include "renderframe.h"
#include "renderhandles.h"

#include <string>
#include <vector>

/*
 * PoolProgram - one pool's published object list, compiled.
 *
 * It holds the passes that RENDER the pool (its own target, plus any nested temporary
 * targets), the geometry those passes address, and the metadata the frame assembler needs to
 * COMPOSITE the result. Compositing is not in here on purpose: it targets the backbuffer and
 * has to interleave with the other pools, which only the assembler can order.
 *
 * Copy and move are deleted because every pass points into `arena`. A PoolProgram lives in
 * place, double-buffered next to the object list it was compiled from.
 */
struct PoolProgram
{
    PoolProgram() = default;
    PoolProgram(const PoolProgram&) = delete;
    PoolProgram& operator=(const PoolProgram&) = delete;
    PoolProgram(PoolProgram&&) = delete;
    PoolProgram& operator=(PoolProgram&&) = delete;

    DrawPoolType type{ DrawPoolType::LAST };

    VertexArena arena;
    std::vector<RenderPass> passes;
    std::vector<TextureUpdate> uploads;

    // --- composition -------------------------------------------------------------------
    // Set only for pools that own a retained target (MAP and FOREGROUND). The assembler turns
    // this into one textured packet on the backbuffer.
    bool hasComposition{ false };
    RenderTargetHandle compositionSource;
    Rect compositionDest;
    Rect compositionSrc;
    bool compositionBlendEnabled{ true };
    bool compositionAlphaWrite{ true };
    MaterialHandle compositionMaterial;
    MaterialParams compositionParams;
    float compositionOpacity{ 1.f };

    // --- honesty -----------------------------------------------------------------------
    // Anything the compiler met and could not express. A non-empty list means this program is
    // NOT a faithful description of the frame and must not drive a backend. Reporting beats
    // skipping: a frame that quietly omits a draw is far worse than one that refuses to build.
    std::vector<std::string> unsupported;

    [[nodiscard]] bool isComplete() const { return unsupported.empty(); }

    void clear()
    {
        arena.clear();
        passes.clear();
        uploads.clear();
        hasComposition = false;
        compositionSource = {};
        compositionDest = {};
        compositionSrc = {};
        compositionBlendEnabled = true;
        compositionAlphaWrite = true;
        compositionMaterial = {};
        compositionParams = {};
        compositionOpacity = 1.f;
        unsupported.clear();
    }

    // Every pass draws from this program's arena. Re-pointing is separated out so the
    // compiler can grow the arena freely while building and fix the pointers once at the end,
    // rather than caching a pointer that reallocation would invalidate.
    void bindArena()
    {
        for (auto& pass : passes)
            pass.arena = &arena;
    }
};
