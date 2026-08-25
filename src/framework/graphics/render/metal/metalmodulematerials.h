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

// GENERATED FILE - DO NOT EDIT.
//
// Produced by tools/generate_metal_shaders.py from the .frag sources named below, through
// glslang and SPIRV-Cross. Regenerate with `tools/generate_metal_shaders.py --write`; the
// build re-runs the translation and fails if this file is stale, so editing it by hand only
// delays the contradiction.
//
// The line below records the tools that produced this file. SPIRV-Cross names its temporaries
// after SPIR-V ids, which glslang assigns, so two different glslang versions translate the same
// shader into byte-different but equivalent MSL. `--check` therefore compares byte-for-byte only
// when the local toolchain matches this line, and falls back to verifying that every material
// still translates and that the material set is unchanged when it does not - which is what CI
// does, since a distribution's glslang is rarely the one a developer has.
// toolchain: Glslang Version: 11:16.5.0 | spirv-cross Git commit:  Timestamp: 2026-07-06T12:43:32

#pragma once

#include <array>
#include <string_view>

// One MTLLibrary per material, compiled on first use rather than all at startup. Each carries
// both stages: SPIRV-Cross derives the fragment's [[stage_in]] struct from the same varying
// interface it derived the vertex's output from, so a generated pair agrees by construction
// where a generated fragment paired with the hand-written built-in vertex would only agree by
// inspection. A session that binds no module shader compiles none of them.
struct MetalModuleMaterial
{
    std::string_view key;           // the .frag basename, which is what a material resolves to
    std::string_view vertexEntry;
    std::string_view fragmentEntry;
    std::string_view source;
};

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/bloom.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_BLOOM = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_bloom_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_bloom_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_bloom_out crystalotc_vert_bloom(crystalotc_vert_bloom_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_bloom_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_bloom_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_bloom_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_bloom_out crystalotc_frag_bloom(crystalotc_frag_bloom_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_bloom_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 color = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37);
    for (int i = -4; i <= 4; i++)
    {
        for (int j = -4; j <= 4; j++)
        {
            float2 param_1 = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) + (float2(float(i), float(j)) * 0.0030000000260770320892333984375);
            color += (crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_1, _37) * 0.008000000379979610443115234375);
        }
    }
    out.crystalotc_FragColor = color;
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/cyclopedia.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_CYCLOPEDIA = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_cyclopedia_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_cyclopedia_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_cyclopedia_out crystalotc_vert_cyclopedia(crystalotc_vert_cyclopedia_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_cyclopedia_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_cyclopedia_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_cyclopedia_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_cyclopedia_out crystalotc_frag_cyclopedia(crystalotc_frag_cyclopedia_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_cyclopedia_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 col = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37);
    col.x = 0.0;
    col.y = 0.0;
    col.z = 0.0;
    out.crystalotc_FragColor = col;
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/fog.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_FOG = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_fog_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_fog_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_fog_out crystalotc_vert_fog(crystalotc_vert_fog_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_fog_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_fog_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_fog_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _48)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _48.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _48)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _48.u_Tex0FlipY)));
}

fragment crystalotc_frag_fog_out crystalotc_frag_fog(crystalotc_frag_fog_in in [[stage_in]], constant CrystalOTCDrawParams& _48 [[buffer(0)]], constant CrystalOTCMaterialParams& _78 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], texture2d<float> u_Tex1 [[texture(1)]], sampler u_Tex0Smplr [[sampler(0)]], sampler u_Tex1Smplr [[sampler(1)]])
{
    crystalotc_frag_fog_out out = {};
    float2 direction = float2(1.0, 0.300000011920928955078125);
    float speed = 0.0500000007450580596923828125;
    float pressure = 0.60000002384185791015625;
    float zoom = 0.5;
    float2 test = (crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _48) + float2(_78.u_WalkOffset.x, _78.u_WalkOffset.y)) + ((direction * _78.u_Time) * speed);
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _48);
    float3 bgcol = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _48).xyz;
    float3 fogcol = u_Tex1.sample(u_Tex1Smplr, test).xyz;
    float3 col = bgcol + (fogcol * pressure);
    out.crystalotc_FragColor = float4(col, 1.0);
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/forge.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_FORGE = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_forge_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_forge_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_forge_out crystalotc_vert_forge(crystalotc_vert_forge_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_forge_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



// Implementation of the GLSL mod() function, which is slightly different than Metal fmod()
template<typename Tx, typename Ty>
inline Tx mod(Tx x, Ty y)
{
    return x - y * floor(x / y);
}

struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_forge_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_forge_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_forge_out crystalotc_frag_forge(crystalotc_frag_forge_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], constant CrystalOTCMaterialParams& _72 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_forge_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 texColor = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37);
    float slow = sin(mod(_72.u_Time, 0.60000002384185791015625) * 3.141590118408203125);
    if (slow > 0.9900000095367431640625)
    {
        slow = 1.0;
    }
    float fast = sin(mod(_72.u_Time, 0.100000001490116119384765625) * 3.141590118408203125);
    if (fast > 0.9900000095367431640625)
    {
        fast = 1.0;
    }
    float intensity = fast::max(slow, fast);
    if (_72.u_Time > 5.0)
    {
        intensity = 1.0;
    }
    float3 flash = mix(texColor.xyz, float3(1.0), float3(intensity));
    out.crystalotc_FragColor = float4(flash, texColor.w);
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/grayscale.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_GRAYSCALE = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_grayscale_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_grayscale_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_grayscale_out crystalotc_vert_grayscale(crystalotc_vert_grayscale_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_grayscale_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_grayscale_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_grayscale_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _42)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _42.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _42)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _42.u_Tex0FlipY)));
}

static inline __attribute__((always_inline))
float4 grayscale(thread const float4& color)
{
    float gray = dot(color.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    return float4(gray, gray, gray, color.w);
}

fragment crystalotc_frag_grayscale_out crystalotc_frag_grayscale(crystalotc_frag_grayscale_in in [[stage_in]], constant CrystalOTCDrawParams& _42 [[buffer(0)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_grayscale_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _42);
    float4 param_1 = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _42);
    out.crystalotc_FragColor = grayscale(param_1) * _42.u_Color;
    out.crystalotc_FragColor.w *= _42.u_Opacity;
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/heat.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_HEAT = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_heat_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_heat_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_heat_out crystalotc_vert_heat(crystalotc_vert_heat_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_heat_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_heat_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_heat_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _41)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _41.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float col(thread const float2& coord, constant CrystalOTCMaterialParams& _94)
{
    float delta_theta = 0.89759790897369384765625;
    float col_1 = 0.0;
    float theta = 0.0;
    for (int i = 0; i < 5; i++)
    {
        float2 adjc = coord;
        theta = delta_theta * float(i);
        adjc.x += (((cos(theta) * _94.u_Time) * 0.0599999986588954925537109375) + (_94.u_Time * 0.02999999932944774627685546875));
        adjc.y -= (((sin(theta) * _94.u_Time) * 0.0599999986588954925537109375) - (_94.u_Time * 0.0199999995529651641845703125));
        col_1 += (cos(((adjc.x * cos(theta)) - (adjc.y * sin(theta))) * 3.0) * 30.0);
    }
    return cos(col_1);
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _41)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _41.u_Tex0FlipY)));
}

fragment crystalotc_frag_heat_out crystalotc_frag_heat(crystalotc_frag_heat_in in [[stage_in]], constant CrystalOTCDrawParams& _41 [[buffer(0)]], constant CrystalOTCMaterialParams& _94 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_heat_out out = {};
    float2 p = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _41);
    float2 c1 = p;
    float2 c2 = p;
    float2 param = c1;
    float cc1 = col(param, _94);
    c2.x += (_94.u_Resolution.x / 100.0);
    float2 param_1 = c2;
    float dx = (0.100000001490116119384765625 * (cc1 - col(param_1, _94))) / 100.0;
    c2.x = p.x;
    c2.y += (_94.u_Resolution.y / 100.0);
    float2 param_2 = c2;
    float dy = (0.100000001490116119384765625 * (cc1 - col(param_2, _94))) / 100.0;
    c1.x += dx;
    c1.y += dy;
    float alpha = 1.0 + ((dx * dy) * 1.2000000476837158203125);
    float2 param_3 = c1;
    out.crystalotc_FragColor = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_3, _41) * alpha;
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/hover_desaturate.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_HOVER_DESATURATE = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_hover_desaturate_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_hover_desaturate_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_hover_desaturate_out crystalotc_vert_hover_desaturate(crystalotc_vert_hover_desaturate_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_hover_desaturate_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_hover_desaturate_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_hover_desaturate_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_hover_desaturate_out crystalotc_frag_hover_desaturate(crystalotc_frag_hover_desaturate_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_hover_desaturate_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 color = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37) * _37.u_Color;
    float gray = dot(color.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 desaturated = mix(float3(gray), color.xyz, float3(0.5));
    out.crystalotc_FragColor = float4(desaturated, color.w);
    out.crystalotc_FragColor.w *= _37.u_Opacity;
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/noise.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_NOISE = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_noise_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_noise_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_noise_out crystalotc_vert_noise(crystalotc_vert_noise_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_noise_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_noise_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_noise_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _41)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _41.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float col(thread const float2& coord, constant CrystalOTCMaterialParams& _94)
{
    float delta_theta = 0.89759790897369384765625;
    float col_1 = 0.0;
    float theta = 0.0;
    for (int i = 0; i < 3; i++)
    {
        float2 adjc = coord;
        theta = delta_theta * float(i);
        adjc.x += (((cos(theta) * _94.u_Time) * 0.1599999964237213134765625) + (_94.u_Time * 0.12999999523162841796875));
        adjc.y -= (((sin(theta) * _94.u_Time) * 0.1599999964237213134765625) - (_94.u_Time * 0.119999997317790985107421875));
        col_1 += (cos(((adjc.x * cos(theta)) - (adjc.y * sin(theta))) * 100.0) * 100.0);
    }
    return cos(col_1);
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _41)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _41.u_Tex0FlipY)));
}

fragment crystalotc_frag_noise_out crystalotc_frag_noise(crystalotc_frag_noise_in in [[stage_in]], constant CrystalOTCDrawParams& _41 [[buffer(0)]], constant CrystalOTCMaterialParams& _94 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_noise_out out = {};
    float2 p = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _41);
    float2 c1 = p;
    float2 c2 = p;
    float2 param = c1;
    float cc1 = col(param, _94);
    c2.x += (_94.u_Resolution.x / 1000.0);
    float2 param_1 = c2;
    float dx = (1.0 * (cc1 - col(param_1, _94))) / 1000.0;
    c2.x = p.x;
    c2.y += (_94.u_Resolution.y / 1000.0);
    float2 param_2 = c2;
    float dy = (1.0 * (cc1 - col(param_2, _94))) / 1000.0;
    c1.x += dx;
    c1.y += dy;
    float alpha = 1.0 + ((dx * dy) * 10.19999980926513671875);
    float2 param_3 = c1;
    out.crystalotc_FragColor = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_3, _41) * alpha;
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/oldtv.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_OLDTV = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_oldtv_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_oldtv_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_oldtv_out crystalotc_vert_oldtv(crystalotc_vert_oldtv_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_oldtv_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_oldtv_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_oldtv_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_oldtv_out crystalotc_frag_oldtv(crystalotc_frag_oldtv_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], constant CrystalOTCMaterialParams& _75 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_oldtv_out out = {};
    float2 q = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float2 uv = float2(0.5) + ((q - float2(0.5)) * (0.89999997615814208984375 + (0.100000001490116119384765625 * sin(0.20000000298023223876953125 * _75.u_Time))));
    float2 param = float2(q.x, q.y);
    float3 oricol = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37).xyz;
    float3 col = oricol;
    col = fast::clamp((col * 0.5) + (((col * 0.5) * col) * 1.2000000476837158203125), float3(0.0), float3(1.0));
    col *= (0.5 + ((((8.0 * uv.x) * uv.y) * (1.0 - uv.x)) * (1.0 - uv.y)));
    col *= float3(0.800000011920928955078125, 1.0, 0.699999988079071044921875);
    col *= (0.89999997615814208984375 + (0.100000001490116119384765625 * sin((10.0 * _75.u_Time) + (uv.y * 1000.0))));
    col *= (0.9700000286102294921875 + (0.02999999932944774627685546875 * sin(110.0 * _75.u_Time)));
    out.crystalotc_FragColor = float4(col, 1.0);
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/outline.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_OUTLINE = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_outline_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_outline_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_outline_out crystalotc_vert_outline(crystalotc_vert_outline_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_outline_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_outline_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_outline_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_outline_out crystalotc_frag_outline(crystalotc_frag_outline_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], constant CrystalOTCMaterialParams& _134 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_outline_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 col = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37);
    if (col.w > 0.5)
    {
        out.crystalotc_FragColor = col;
    }
    else
    {
        float2 param_1 = float2(crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37).x + 0.015625, crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37).y);
        float2 param_2 = float2(crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37).x, crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37).y - 0.015625);
        float2 param_3 = float2(crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37).x - 0.015625, crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37).y);
        float2 param_4 = float2(crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37).x, crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37).y + 0.015625);
        float a = ((crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_1, _37).w + crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_2, _37).w) + crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_3, _37).w) + crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_4, _37).w;
        if ((col.w < 1.0) && (a > 0.0))
        {
            float x = (((cos(_134.u_Time * 9.56999969482421875) + 1.0) / 2.0) * 0.20000000298023223876953125) + 0.800000011920928955078125;
            out.crystalotc_FragColor = float4(x);
        }
        else
        {
            out.crystalotc_FragColor = col;
        }
    }
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/party.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_PARTY = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_party_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_party_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_party_out crystalotc_vert_party(crystalotc_vert_party_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_party_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_party_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_party_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_party_out crystalotc_frag_party(crystalotc_frag_party_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], constant CrystalOTCMaterialParams& _72 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_party_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 col = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37);
    float d = _72.u_Time * 2.0;
    col.x += ((1.0 + sin(d)) * 0.25);
    col.y += ((1.0 + sin(d * 2.0)) * 0.25);
    col.z += ((1.0 + sin(d * 4.0)) * 0.25);
    out.crystalotc_FragColor = col;
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/pulse.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_PULSE = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_pulse_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_pulse_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_pulse_out crystalotc_vert_pulse(crystalotc_vert_pulse_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_pulse_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_pulse_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_pulse_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_pulse_out crystalotc_frag_pulse(crystalotc_frag_pulse_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], constant CrystalOTCMaterialParams& _66 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_pulse_out out = {};
    float2 halfres = _66.u_Resolution / float2(2.0);
    float2 cPos = (crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) + float2(_66.u_WalkOffset.x, _66.u_WalkOffset.y)) * _66.u_Resolution;
    cPos.x -= ((((0.5 * halfres.x) * sin(_66.u_Time / 2.0)) + ((0.300000011920928955078125 * halfres.x) * cos(_66.u_Time))) + halfres.x);
    cPos.y -= ((((0.4000000059604644775390625 * halfres.y) * sin(_66.u_Time / 5.0)) + ((0.300000011920928955078125 * halfres.y) * cos(_66.u_Time))) + halfres.y);
    float cLength = length(cPos);
    float2 uv = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) + ((((cPos / float2(cLength)) * sin((cLength / 30.0) - (_66.u_Time * 10.0))) / float2(25.0)) * 0.1500000059604644775390625);
    float2 param = uv;
    float3 col = (crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37).xyz * 250.0) / float3(cLength);
    out.crystalotc_FragColor = float4(col, 1.0);
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/radialblur.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_RADIALBLUR = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_radialblur_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_radialblur_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_radialblur_out crystalotc_vert_radialblur(crystalotc_vert_radialblur_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_radialblur_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_radialblur_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_radialblur_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_radialblur_out crystalotc_frag_radialblur(crystalotc_frag_radialblur_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_radialblur_out out = {};
    float2 dir = float2(0.5) - crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float dist = sqrt((dir.x * dir.x) + (dir.y * dir.y));
    dir /= float2(dist);
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 color = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37);
    float4 sum = color;
    float2 param_1 = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) - ((dir * 0.07999999821186065673828125) * 1.0);
    sum += crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_1, _37);
    float2 param_2 = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) - ((dir * 0.0500000007450580596923828125) * 1.0);
    sum += crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_2, _37);
    float2 param_3 = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) - ((dir * 0.02999999932944774627685546875) * 1.0);
    sum += crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_3, _37);
    float2 param_4 = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) - ((dir * 0.0199999995529651641845703125) * 1.0);
    sum += crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_4, _37);
    float2 param_5 = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) - ((dir * 0.00999999977648258209228515625) * 1.0);
    sum += crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_5, _37);
    float2 param_6 = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) + ((dir * 0.00999999977648258209228515625) * 1.0);
    sum += crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_6, _37);
    float2 param_7 = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) + ((dir * 0.0199999995529651641845703125) * 1.0);
    sum += crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_7, _37);
    float2 param_8 = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) + ((dir * 0.02999999932944774627685546875) * 1.0);
    sum += crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_8, _37);
    float2 param_9 = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) + ((dir * 0.0500000007450580596923828125) * 1.0);
    sum += crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_9, _37);
    float2 param_10 = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37) + ((dir * 0.07999999821186065673828125) * 1.0);
    sum += crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param_10, _37);
    sum *= 0.0909090936183929443359375;
    float t = dist * 2.2000000476837158203125;
    t = fast::clamp(t, 0.0, 1.0);
    out.crystalotc_FragColor = mix(color, sum, float4(t));
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/rain.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_RAIN = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_rain_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_rain_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_rain_out crystalotc_vert_rain(crystalotc_vert_rain_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_rain_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



// Implementation of the GLSL mod() function, which is slightly different than Metal fmod()
template<typename Tx, typename Ty>
inline Tx mod(Tx x, Ty y)
{
    return x - y * floor(x / y);
}

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct crystalotc_frag_rain_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_rain_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _71)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _71.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _71)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _71.u_Tex0FlipY)));
}

static inline __attribute__((always_inline))
float4 crystalotc_fragCoord(thread float4& gl_FragCoord, constant CrystalOTCMaterialParams& _40)
{
    return float4(gl_FragCoord.x, _40.u_Resolution.y - gl_FragCoord.y, gl_FragCoord.z, gl_FragCoord.w);
}

static inline __attribute__((always_inline))
float rainLayer(thread float2& uv, thread const float& scale, thread const float& ttime)
{
    float w = smoothstep(1.0, 0.0, (-uv.y) * (scale / 5.0));
    if (w < 0.100000001490116119384765625)
    {
        return 0.0;
    }
    uv += float2((ttime * 0.5) / scale);
    uv.y += ((ttime * 2.5) / scale);
    uv.x += (sin(uv.y + (ttime * 0.100000001490116119384765625)) / scale);
    uv *= (1.2000000476837158203125 * scale);
    float2 s = floor(uv);
    float2 f = fract(uv);
    float2 p = float2(0.0);
    float k = 3.0;
    float d = 0.0;
    p = (float2(0.5) + (sin(fract(sin(((s + p) + float2(scale)) * float2x2(float2(7.0, 3.0), float2(6.0, 5.0))) * 5.0) * 11.0) * 0.3499999940395355224609375)) - f;
    d = length(p);
    k = fast::min(d, k);
    k = smoothstep(0.0, k, sin(f.x + f.y) * 0.00999999977648258209228515625);
    return k * w;
}

fragment crystalotc_frag_rain_out crystalotc_frag_rain(crystalotc_frag_rain_in in [[stage_in]], constant CrystalOTCDrawParams& _71 [[buffer(0)]], constant CrystalOTCMaterialParams& _40 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]], float4 gl_FragCoord [[position]])
{
    crystalotc_frag_rain_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _71);
    float4 Game = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _71);
    float2 uv = ((crystalotc_fragCoord(gl_FragCoord, _40).xy * 2.5) / float2(200.0)) + float2(_40.u_WalkOffset.x, _40.u_WalkOffset.y);
    float ttime = mod(_40.u_Time * 1.0, 1000.0);
    uv.x -= (uv.y * 0.89999997615814208984375);
    uv.y += 1.0;
    uv.y = dot(uv * 0.054999999701976776123046875, uv * 0.125);
    float rain = 0.0;
    float2 param_1 = uv;
    float param_2 = 2.0;
    float param_3 = ttime;
    float _255 = rainLayer(param_1, param_2, param_3);
    rain += _255;
    float2 param_4 = uv;
    float param_5 = 3.0;
    float param_6 = ttime;
    float _263 = rainLayer(param_4, param_5, param_6);
    rain += _263;
    float2 param_7 = uv;
    float param_8 = 4.0;
    float param_9 = ttime;
    float _272 = rainLayer(param_7, param_8, param_9);
    rain += _272;
    float opacity = 0.60000002384185791015625;
    out.crystalotc_FragColor = Game + float4(rain * opacity);
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/sepia.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_SEPIA = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_sepia_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_sepia_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_sepia_out crystalotc_vert_sepia(crystalotc_vert_sepia_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_sepia_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_sepia_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_sepia_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _42)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _42.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _42)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _42.u_Tex0FlipY)));
}

static inline __attribute__((always_inline))
float4 sepia(thread const float4& color)
{
    return float4(dot(color, float4(0.39300000667572021484375, 0.768999993801116943359375, 0.18899999558925628662109375, 0.0)), dot(color, float4(0.3490000069141387939453125, 0.68599998950958251953125, 0.16799999773502349853515625, 0.0)), dot(color, float4(0.272000014781951904296875, 0.533999979496002197265625, 0.13099999725818634033203125, 0.0)), 1.0);
}

fragment crystalotc_frag_sepia_out crystalotc_frag_sepia(crystalotc_frag_sepia_in in [[stage_in]], constant CrystalOTCDrawParams& _42 [[buffer(0)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_sepia_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _42);
    float4 param_1 = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _42);
    out.crystalotc_FragColor = sepia(param_1);
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/snow.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_SNOW = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_snow_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_snow_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_snow_out crystalotc_vert_snow(crystalotc_vert_snow_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_snow_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_snow_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_snow_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _48)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _48.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _48)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _48.u_Tex0FlipY)));
}

fragment crystalotc_frag_snow_out crystalotc_frag_snow(crystalotc_frag_snow_in in [[stage_in]], constant CrystalOTCDrawParams& _48 [[buffer(0)]], constant CrystalOTCMaterialParams& _86 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], texture2d<float> u_Tex1 [[texture(1)]], sampler u_Tex0Smplr [[sampler(0)]], sampler u_Tex1Smplr [[sampler(1)]])
{
    crystalotc_frag_snow_out out = {};
    float2 snowDirection = float2(0.5, 1.0);
    float snowSpeed = 0.07999999821186065673828125;
    float snowPressure = 0.4000000059604644775390625;
    float snowZoom = 0.100000001490116119384765625;
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _48);
    float3 Game = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _48).xyz;
    float2 SnowHandler = ((crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _48) + float2(_86.u_WalkOffset.x, _86.u_WalkOffset.y)) + ((snowDirection * _86.u_Time) * snowSpeed)) / float2(snowZoom);
    float3 Snow = u_Tex1.sample(u_Tex1Smplr, SnowHandler).xyz;
    float3 _output = Game + (Snow * snowPressure);
    out.crystalotc_FragColor = float4(_output, 1.0);
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_shaders/shaders/fragment/zomg.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_ZOMG = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_zomg_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_zomg_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_zomg_out crystalotc_vert_zomg(crystalotc_vert_zomg_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_zomg_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_zomg_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_zomg_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _40)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _40.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _40)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _40.u_Tex0FlipY)));
}

fragment crystalotc_frag_zomg_out crystalotc_frag_zomg(crystalotc_frag_zomg_in in [[stage_in]], constant CrystalOTCDrawParams& _40 [[buffer(0)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_zomg_out out = {};
    float2 tibiaDir = float2(1.0);
    float2 dir = float2(0.5) - crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _40);
    float dist = sqrt((dir.x * dir.x) + (dir.y * dir.y));
    float scale = 0.800000011920928955078125 + (dist * 0.5);
    float2 param = -((dir * scale) - float2(0.5));
    float4 color = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _40);
    out.crystalotc_FragColor = color;
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_exaltationforge/menu/shaders/blink_red.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_BLINK_RED = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_blink_red_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_blink_red_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_blink_red_out crystalotc_vert_blink_red(crystalotc_vert_blink_red_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_blink_red_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_blink_red_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_blink_red_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_blink_red_out crystalotc_frag_blink_red(crystalotc_frag_blink_red_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_blink_red_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 col = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37);
    if (col.w < 0.00999999977648258209228515625)
    {
        discard_fragment();
    }
    col.x = 0.63137257099151611328125;
    col.y = 0.066666670143604278564453125;
    col.z = 0.066666670143604278564453125;
    out.crystalotc_FragColor = col;
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_exaltationforge/menu/shaders/blink_white.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_BLINK_WHITE = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_blink_white_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_blink_white_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_blink_white_out crystalotc_vert_blink_white(crystalotc_vert_blink_white_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_blink_white_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_blink_white_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_blink_white_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_blink_white_out crystalotc_frag_blink_white(crystalotc_frag_blink_white_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_blink_white_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 col = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37);
    if (col.w < 0.00999999977648258209228515625)
    {
        discard_fragment();
    }
    col.x = 1.0;
    col.y = 1.0;
    col.z = 1.0;
    out.crystalotc_FragColor = col;
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_exaltationforge/menu/shaders/fade_in_white.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_FADE_IN_WHITE = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_fade_in_white_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_fade_in_white_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_fade_in_white_out crystalotc_vert_fade_in_white(crystalotc_vert_fade_in_white_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_fade_in_white_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_fade_in_white_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_fade_in_white_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_fade_in_white_out crystalotc_frag_fade_in_white(crystalotc_frag_fade_in_white_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], constant CrystalOTCMaterialParams& _83 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_fade_in_white_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 col = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37);
    if (col.w < 0.00999999977648258209228515625)
    {
        discard_fragment();
    }
    float duration = 0.800000011920928955078125;
    float t = fast::clamp(_83.u_Time / duration, 0.0, 1.0);
    float4 _93 = col;
    float3 _97 = mix(float3(1.0), _93.xyz, float3(t));
    col.x = _97.x;
    col.y = _97.y;
    col.z = _97.z;
    out.crystalotc_FragColor = col;
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_exaltationforge/menu/shaders/fade_out_red.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_FADE_OUT_RED = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_fade_out_red_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_fade_out_red_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_fade_out_red_out crystalotc_vert_fade_out_red(crystalotc_vert_fade_out_red_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_fade_out_red_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_fade_out_red_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_fade_out_red_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_fade_out_red_out crystalotc_frag_fade_out_red(crystalotc_frag_fade_out_red_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], constant CrystalOTCMaterialParams& _83 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_fade_out_red_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 col = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37);
    if (col.w < 0.00999999977648258209228515625)
    {
        discard_fragment();
    }
    float duration = 0.800000011920928955078125;
    float t = fast::clamp(_83.u_Time / duration, 0.0, 1.0);
    float fade = 1.0 - t;
    float a = col.w * fade;
    out.crystalotc_FragColor = float4(float3(0.63137257099151611328125, 0.066666670143604278564453125, 0.066666670143604278564453125) * a, a);
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_exaltationforge/menu/shaders/fade_out_white.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_FADE_OUT_WHITE = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_fade_out_white_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_fade_out_white_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_fade_out_white_out crystalotc_vert_fade_out_white(crystalotc_vert_fade_out_white_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_fade_out_white_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_fade_out_white_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_fade_out_white_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_fade_out_white_out crystalotc_frag_fade_out_white(crystalotc_frag_fade_out_white_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], constant CrystalOTCMaterialParams& _83 [[buffer(1)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_fade_out_white_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 col = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37);
    if (col.w < 0.00999999977648258209228515625)
    {
        discard_fragment();
    }
    float duration = 0.800000011920928955078125;
    float t = fast::clamp(_83.u_Time / duration, 0.0, 1.0);
    float fade = 1.0 - t;
    float a = col.w * fade;
    out.crystalotc_FragColor = float4(a);
    return out;
}
)MSL";

// ---------------------------------------------------------------------------
// modules/game_exaltationforge/menu/shaders/silhouette.frag
// ---------------------------------------------------------------------------
inline constexpr std::string_view METAL_MODULE_MSL_SILHOUETTE = R"MSL(
#include <metal_stdlib>

using namespace metal;

struct CrystalOTCVertexParams
{
    float3x3 u_ProjectionMatrix;
    float3x3 u_TransformMatrix;
    float3x3 u_TextureMatrix;
};

struct crystalotc_vert_silhouette_out
{
    float2 v_TexCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

struct crystalotc_vert_silhouette_in
{
    float2 a_Vertex [[attribute(0)]];
    float2 a_TexCoord [[attribute(1)]];
};

vertex crystalotc_vert_silhouette_out crystalotc_vert_silhouette(crystalotc_vert_silhouette_in in [[stage_in]], constant CrystalOTCVertexParams& _20 [[buffer(2)]])
{
    crystalotc_vert_silhouette_out out = {};
    out.gl_Position = float4(((_20.u_ProjectionMatrix * _20.u_TransformMatrix) * float3(in.a_Vertex, 1.0)).xy, 0.0, 1.0);
    out.v_TexCoord = (_20.u_TextureMatrix * float3(in.a_TexCoord, 1.0)).xy;
    return out;
}

#pragma clang diagnostic ignored "-Wmissing-prototypes"



struct CrystalOTCDrawParams
{
    float4 u_Color;
    float u_Opacity;
    float u_Tex0FlipY;
};

struct CrystalOTCMaterialParams
{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    float2 u_Resolution;
    float2 u_WalkOffset;
    float2 u_MapCenterCoord;
    float2 u_MapGlobalCoord;
    float2 u_TextOffset;
    float2 u_TextCenter;
};

struct crystalotc_frag_silhouette_out
{
    float4 crystalotc_FragColor [[color(0)]];
};

struct crystalotc_frag_silhouette_in
{
    float2 crystalotc_v_TexCoordIn [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 crystalotc_texCoordGL(thread float2& crystalotc_v_TexCoordIn, constant CrystalOTCDrawParams& _37)
{
    return float2(crystalotc_v_TexCoordIn.x, mix(crystalotc_v_TexCoordIn.y, 1.0 - crystalotc_v_TexCoordIn.y, _37.u_Tex0FlipY));
}

static inline __attribute__((always_inline))
float4 crystalotc_sampleTex0(texture2d<float> s, sampler sSmplr, thread const float2& c, constant CrystalOTCDrawParams& _37)
{
    return s.sample(sSmplr, float2(c.x, mix(c.y, 1.0 - c.y, _37.u_Tex0FlipY)));
}

fragment crystalotc_frag_silhouette_out crystalotc_frag_silhouette(crystalotc_frag_silhouette_in in [[stage_in]], constant CrystalOTCDrawParams& _37 [[buffer(0)]], texture2d<float> u_Tex0 [[texture(0)]], sampler u_Tex0Smplr [[sampler(0)]])
{
    crystalotc_frag_silhouette_out out = {};
    float2 param = crystalotc_texCoordGL(in.crystalotc_v_TexCoordIn, _37);
    float4 col = crystalotc_sampleTex0(u_Tex0, u_Tex0Smplr, param, _37);
    if (col.w < 0.00999999977648258209228515625)
    {
        discard_fragment();
    }
    out.crystalotc_FragColor = float4(0.0, 0.0, 0.0, col.w);
    return out;
}
)MSL";

inline constexpr std::array METAL_MODULE_MATERIALS = std::to_array<MetalModuleMaterial>({
    { "bloom", "crystalotc_vert_bloom", "crystalotc_frag_bloom", METAL_MODULE_MSL_BLOOM },
    { "cyclopedia", "crystalotc_vert_cyclopedia", "crystalotc_frag_cyclopedia", METAL_MODULE_MSL_CYCLOPEDIA },
    { "fog", "crystalotc_vert_fog", "crystalotc_frag_fog", METAL_MODULE_MSL_FOG },
    { "forge", "crystalotc_vert_forge", "crystalotc_frag_forge", METAL_MODULE_MSL_FORGE },
    { "grayscale", "crystalotc_vert_grayscale", "crystalotc_frag_grayscale", METAL_MODULE_MSL_GRAYSCALE },
    { "heat", "crystalotc_vert_heat", "crystalotc_frag_heat", METAL_MODULE_MSL_HEAT },
    { "hover_desaturate", "crystalotc_vert_hover_desaturate", "crystalotc_frag_hover_desaturate", METAL_MODULE_MSL_HOVER_DESATURATE },
    { "noise", "crystalotc_vert_noise", "crystalotc_frag_noise", METAL_MODULE_MSL_NOISE },
    { "oldtv", "crystalotc_vert_oldtv", "crystalotc_frag_oldtv", METAL_MODULE_MSL_OLDTV },
    { "outline", "crystalotc_vert_outline", "crystalotc_frag_outline", METAL_MODULE_MSL_OUTLINE },
    { "party", "crystalotc_vert_party", "crystalotc_frag_party", METAL_MODULE_MSL_PARTY },
    { "pulse", "crystalotc_vert_pulse", "crystalotc_frag_pulse", METAL_MODULE_MSL_PULSE },
    { "radialblur", "crystalotc_vert_radialblur", "crystalotc_frag_radialblur", METAL_MODULE_MSL_RADIALBLUR },
    { "rain", "crystalotc_vert_rain", "crystalotc_frag_rain", METAL_MODULE_MSL_RAIN },
    { "sepia", "crystalotc_vert_sepia", "crystalotc_frag_sepia", METAL_MODULE_MSL_SEPIA },
    { "snow", "crystalotc_vert_snow", "crystalotc_frag_snow", METAL_MODULE_MSL_SNOW },
    { "zomg", "crystalotc_vert_zomg", "crystalotc_frag_zomg", METAL_MODULE_MSL_ZOMG },
    { "blink_red", "crystalotc_vert_blink_red", "crystalotc_frag_blink_red", METAL_MODULE_MSL_BLINK_RED },
    { "blink_white", "crystalotc_vert_blink_white", "crystalotc_frag_blink_white", METAL_MODULE_MSL_BLINK_WHITE },
    { "fade_in_white", "crystalotc_vert_fade_in_white", "crystalotc_frag_fade_in_white", METAL_MODULE_MSL_FADE_IN_WHITE },
    { "fade_out_red", "crystalotc_vert_fade_out_red", "crystalotc_frag_fade_out_red", METAL_MODULE_MSL_FADE_OUT_RED },
    { "fade_out_white", "crystalotc_vert_fade_out_white", "crystalotc_frag_fade_out_white", METAL_MODULE_MSL_FADE_OUT_WHITE },
    { "silhouette", "crystalotc_vert_silhouette", "crystalotc_frag_silhouette", METAL_MODULE_MSL_SILHOUETTE },
});
