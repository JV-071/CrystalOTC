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

#ifdef CRYSTALOTC_COCOA_WINDOW

#include "metalcontext.h"

#include <unordered_map>

/*
 * MetalPipelineCache - the immutable half of the state a packet carries.
 *
 * OpenGL lets blending, the colour mask and the bound program change independently at any moment;
 * Metal folds all three into one compiled object that has to exist before the draw. The packet
 * already states every one of them, so the translation is mechanical - and the key is small,
 * because the surveyed live state space is around 25-30 combinations rather than a combinatorial
 * explosion. Nothing here is created lazily out of fear; it is created lazily because that is
 * simpler than enumerating a space this shape.
 */
struct MetalPipelineKey
{
    uint16_t material{ 0 };
    BlendMode blend{ BlendMode::Normal };
    bool blendEnabled{ true };
    bool alphaWrite{ true };
    bool textured{ false };

    [[nodiscard]] uint32_t pack() const
    {
        return (static_cast<uint32_t>(material) << 16)
             | (static_cast<uint32_t>(blend) << 8)
             | (blendEnabled ? 1u << 2 : 0u)
             | (alphaWrite ? 1u << 1 : 0u)
             | (textured ? 1u : 0u);
    }
};

class MetalPipelineCache
{
public:
    bool initialize(MetalContext* context);
    void shutdown();

    // Null only if the pipeline could not be compiled, which on a fixed built-in set means a
    // driver problem rather than a content problem.
    id<MTLRenderPipelineState> get(const MetalPipelineKey& key);

    [[nodiscard]] MTLVertexDescriptor* vertexDescriptor() const { return m_vertexDescriptor; }

private:
    // Null for a material with no MSL function - the module programs, which arrive with the
    // Phase 6 shader toolchain. The caller falls back to the default built-in, which draws the
    // geometry unshaded rather than not at all.
    id<MTLFunction> fragmentFunctionFor(uint16_t material, bool textured);

    MetalContext* m_context{ nullptr };

    id<MTLLibrary> m_library{ nil };
    id<MTLFunction> m_vertexFunction{ nil };
    id<MTLFunction> m_texturedFunction{ nil };
    id<MTLFunction> m_solidFunction{ nil };
    id<MTLFunction> m_replaceColorFunction{ nil };

    MTLVertexDescriptor* m_vertexDescriptor{ nil };

    std::unordered_map<uint32_t, id<MTLRenderPipelineState>> m_pipelines;

    bool m_loggedModuleMaterial{ false };
};

#endif // CRYSTALOTC_COCOA_WINDOW
