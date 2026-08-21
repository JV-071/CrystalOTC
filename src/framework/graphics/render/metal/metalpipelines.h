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

#include <string>
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
    // A material is a pair of functions, not a fragment variant against one shared vertex stage.
    // The built-ins share `m_vertexFunction` because they were written to; a translated module
    // material carries its own, because SPIRV-Cross derives the fragment's [[stage_in]] struct
    // from the same varying interface it derived the vertex's output from, and pairing a
    // generated fragment with a hand-written vertex would make that agreement a matter of
    // inspection rather than of construction.
    struct MaterialFunctions
    {
        id<MTLFunction> vertex{ nil };
        id<MTLFunction> fragment{ nil };
    };

    // Falls back to the built-ins for a module material with no translated source - one
    // registered from inline code, or one whose .frag the toolchain does not cover - and says so
    // once per material rather than once per process, because "which effect is missing" is the
    // useful question.
    MaterialFunctions functionsFor(uint16_t material, bool textured);

    // Compiles one material's MSL into its own MTLLibrary, on first use. Returns a pair of nils
    // if there is no source for the key or the compile fails; both outcomes are cached, so a
    // failure costs one compile rather than one per frame.
    MaterialFunctions moduleFunctions(const std::string& sourceKey);

    MetalContext* m_context{ nullptr };

    id<MTLLibrary> m_library{ nil };
    id<MTLFunction> m_vertexFunction{ nil };
    id<MTLFunction> m_texturedFunction{ nil };
    id<MTLFunction> m_solidFunction{ nil };
    id<MTLFunction> m_replaceColorFunction{ nil };

    MTLVertexDescriptor* m_vertexDescriptor{ nil };

    std::unordered_map<uint32_t, id<MTLRenderPipelineState>> m_pipelines;

    // Keyed on the .frag basename rather than on the material handle, because several
    // registered shader names share one file and there is no reason to compile it twice.
    std::unordered_map<std::string, MaterialFunctions> m_moduleFunctions;

    // Materials already reported as untranslated, so the log says each one once.
    std::unordered_map<uint16_t, bool> m_reportedMaterials;
};

#endif // CRYSTALOTC_COCOA_WINDOW
