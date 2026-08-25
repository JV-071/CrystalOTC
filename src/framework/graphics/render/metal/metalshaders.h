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

#include <string_view>

/*
 * The built-in materials, in Metal Shading Language.
 *
 * These are hand-written translations of `shader/shadersources.h`, and the resemblance is the
 * specification: one fixed vertex stage shared by everything, and a fragment stage that is a
 * `calculatePixel()` variant with `alpha *= opacity` applied afterwards. GL's fourth built-in,
 * the line program, has no counterpart here on purpose - UIGraph's lines are triangulated into
 * ordinary solid-colour quads at record time, so nothing can emit a line material and creating
 * a pipeline for one would be creating a pipeline nothing can select.
 *
 * COMPILED AT RUNTIME, from this string, rather than from a .metallib built by CMake. That is a
 * Phase 4 decision with a Phase 6 expiry: the shader toolchain that phase brings - .frag through
 * glslang and SPIRV-Cross into a build-time .metallib - is where the module materials arrive,
 * and standing one up now for three functions would be building the toolchain early rather than
 * building the renderer. Four functions of MSL cost single-digit milliseconds at startup.
 */
inline constexpr std::string_view METAL_BUILTIN_SHADER_SOURCE = R"MSL(
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float3x3 projection;
    float3x3 transform;
    float3x3 textureMatrix;
};

struct FragmentUniforms {
    float4 color;
    float opacity;
    // Read only by the translated module fragments; declared here so both halves of the ABI
    // describe the same buffer. See MetalABI::FragmentUniforms.
    float tex0FlipY;
};

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// The fixed vertex stage. Two things differ from the GLSL it mirrors, both deliberate.
//
// Texture coordinates arrive in TEXELS and are normalised here by the texture matrix, exactly as
// `u_TextureMatrix` does - the producer writes raw pixel rects and always has.
//
// The GLSL writes `vec4(projection * transform * vec3(xy, 1.0), 1.0)`, so its clip-space z is
// whatever the matrices' third row produces - which is 1.0 for every 2D affine transform this
// client builds, sitting exactly on GL's far plane. Metal's clip volume is 0 <= z <= w rather
// than -w <= z <= w, and there is no depth buffer anywhere in this renderer, so z is pinned to
// the near plane instead: inside the volume by construction, whatever a transform does.
vertex VertexOut crystalotc_vertex(VertexIn in [[stage_in]],
                                   constant Uniforms& u [[buffer(2)]])
{
    VertexOut out;
    float3 p = u.projection * u.transform * float3(in.position, 1.0);
    out.position = float4(p.xy, 0.0, 1.0);
    out.texCoord = (u.textureMatrix * float3(in.texCoord, 1.0)).xy;
    return out;
}

fragment float4 crystalotc_textured(VertexOut in [[stage_in]],
                                    constant FragmentUniforms& f [[buffer(0)]],
                                    texture2d<float> tex [[texture(0)]],
                                    sampler smp [[sampler(0)]])
{
    float4 c = tex.sample(smp, in.texCoord) * f.color;
    c.a *= f.opacity;
    return c;
}

fragment float4 crystalotc_solid(VertexOut in [[stage_in]],
                                 constant FragmentUniforms& f [[buffer(0)]])
{
    float4 c = f.color;
    c.a *= f.opacity;
    return c;
}

// `a > 0.01 ? colour : transparent`, the mask/tint program every marked creature and every
// highlighted item binds. The threshold is copied, not rounded: it is a behavioural constant.
fragment float4 crystalotc_replace_color(VertexOut in [[stage_in]],
                                         constant FragmentUniforms& f [[buffer(0)]],
                                         texture2d<float> tex [[texture(0)]],
                                         sampler smp [[sampler(0)]])
{
    float4 c = tex.sample(smp, in.texCoord).a > 0.01 ? f.color : float4(0.0, 0.0, 0.0, 0.0);
    c.a *= f.opacity;
    return c;
}
)MSL";
