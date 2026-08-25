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

/*
 * Shared internals of the Metal backend. Included FIRST by every .mm file here, because the
 * order of the two include worlds below is not free.
 *
 * The framework declares `Size`, `Point` and `Rect` as global type aliases, and so does Apple:
 * MacTypes.h, reached from any Apple umbrella header, defines all three as legacy QuickDraw
 * types at global scope. There is no include order that resolves the clash and the SDK offers
 * no opt-out, so Apple's spellings are renamed for the duration of the Apple imports - exactly
 * as cocoawindow.mm does, and for exactly the same reason. Nothing here uses the legacy types;
 * CGSize/CGRect/CGPoint and MTLSize/MTLRegion are distinct names and are untouched.
 *
 * These translation units are compiled WITH ARC (see src/CMakeLists.txt), unlike cocoawindow.mm.
 * That is deliberate: the backend holds Metal objects in C++ containers whose lifetime follows
 * the container's, and hand-written retain/release across a texture cache, a pipeline cache and
 * a per-frame retirement queue is the kind of bookkeeping ARC exists to remove. It also means
 * these files can never be folded into a unity blob with the non-ARC window, which the build
 * enforces rather than hopes for.
 */

#include <framework/graphics/render/renderframe.h>
#include <framework/graphics/render/renderhandles.h>
#include <framework/util/matrix.h>

#define GL_SILENCE_DEPRECATION

#define Size  CrystalOTCMacTypesSize
#define Point CrystalOTCMacTypesPoint
#define Rect  CrystalOTCMacTypesRect
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#undef Size
#undef Point
#undef Rect

namespace MetalABI
{
    // Frames the CPU may run ahead of the GPU. Three is the standard triple-buffered figure:
    // two lets the CPU stall behind a single long frame, four adds latency without adding
    // throughput. Every per-frame resource - the vertex ring, the retirement queue - is sized
    // by this.
    inline constexpr uint32_t MAX_FRAMES_IN_FLIGHT = 3;

    // Buffer and texture slots, shared between the MSL sources and the encoder. They are a
    // contract: MSL names them with [[buffer(n)]] attributes and nothing checks the two agree.
    inline constexpr uint32_t VERTEX_POSITION_BUFFER = 0;
    inline constexpr uint32_t VERTEX_TEXCOORD_BUFFER = 1;
    inline constexpr uint32_t VERTEX_UNIFORM_BUFFER = 2;
    inline constexpr uint32_t FRAGMENT_UNIFORM_BUFFER = 0;
    inline constexpr uint32_t FRAGMENT_MATERIAL_PARAMS_BUFFER = 1;
    inline constexpr uint32_t FRAGMENT_TEXTURE_SLOT = 0;
    inline constexpr uint32_t FRAGMENT_SAMPLER_SLOT = 0;

    /*
     * A 3x3 matrix laid out the way MSL expects one.
     *
     * The framework's Matrix3 stores nine floats row-major and the client uploads them to GL
     * with `glUniformMatrix3fv(..., transpose = GL_FALSE)`, which makes GL read each group of
     * three as a COLUMN - so the matrix GLSL evaluates is the transpose of the framework's, and
     * `M_glsl * v` is the framework's documented `[x y 1] * M` row-vector form. MSL's float3x3
     * is column-major too, so the same nine floats in the same order produce the same matrix
     * and the same product. The only difference is padding: an MSL float3x3 column occupies 16
     * bytes, not 12.
     */
    struct alignas(16) Mat3
    {
        float columns[3][4]{};

        Mat3() = default;

        explicit Mat3(const Matrix3& m)
        {
            const float* v = m.data();
            for (int c = 0; c < 3; ++c) {
                columns[c][0] = v[c * 3 + 0];
                columns[c][1] = v[c * 3 + 1];
                columns[c][2] = v[c * 3 + 2];
                columns[c][3] = 0.f;
            }
        }
    };

    static_assert(sizeof(Mat3) == 48);

    // Per-draw vertex-stage state. Projection and transform stay separate rather than being
    // pre-multiplied on the CPU because GLSL evaluates `u_ProjectionMatrix * u_TransformMatrix *
    // vec3(...)` per vertex, and the whole point of this backend is to be comparable to that one
    // - folding two multiplications into one changes the rounding, cheaply and for nothing.
    struct VertexUniforms
    {
        Mat3 projection;
        Mat3 transform;
        Mat3 textureMatrix;
    };

    // Per-draw fragment-stage state. `opacity` is separate from `color` because the fixed
    // fragment ABI applies it AFTER the material computes its pixel - `gl_FragColor.a *=
    // u_Opacity` - which is not the same as premultiplying it into the colour for any material
    // whose output does not simply scale with it (ReplaceColor is exactly such a material).
    struct alignas(16) FragmentUniforms
    {
        float color[4]{ 1.f, 1.f, 1.f, 1.f };
        float opacity{ 1.f };

        // 1.0 when this draw's u_Tex0 resolved to a RENDER TARGET, 0.0 when it resolved to an
        // ordinary texture. A translated module fragment reads it to run its arithmetic in GL's
        // coordinate space - GL samples a target through an upside-down texture matrix, so
        // `v_TexCoord.y` is `1 - t` there and `t` here - and to convert back at the u_Tex0
        // fetch. Zero for the built-ins, which only ever sample and cannot tell the difference.
        float tex0FlipY{ 0.f };
        float _pad[2]{};
    };

    static_assert(sizeof(FragmentUniforms) == 32);
}

#endif // CRYSTALOTC_COCOA_WINDOW
