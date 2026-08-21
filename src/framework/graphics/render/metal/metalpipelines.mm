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

#ifdef CRYSTALOTC_COCOA_WINDOW

#include "metalpipelines.h"

#include "metalmodulematerials.h"
#include <framework/graphics/render/materialregistry.h>
#include "metalshaders.h"

#include <framework/core/logger.h>

namespace
{
    struct BlendFactors
    {
        MTLBlendFactor srcRGB;
        MTLBlendFactor dstRGB;
        MTLBlendFactor srcAlpha;
        MTLBlendFactor dstAlpha;
    };

    /*
     * The surveyed GL blend table, copied by formula.
     *
     * Two translations are worth stating because they look like changes and are not. GL's
     * glBlendFunc sets one factor pair for all four channels, and a *_COLOR factor applied to the
     * alpha channel uses that colour's ALPHA component - so `GL_DST_COLOR` as an alpha factor is
     * arithmetically `MTLBlendFactorDestinationAlpha`, and spelling it that way is what keeps
     * Metal's validation layer from rejecting a colour factor in an alpha slot. Nothing about the
     * result changes.
     *
     * And `AddWeird` is not additive. `CompositionMode::ADD` is (1-srcColor, 1-srcColor), which
     * every particle effect in the game is tuned against; implementing the name instead of the
     * formula is the single most likely way to break this backend invisibly.
     */
    constexpr BlendFactors blendFactorsOf(const BlendMode mode)
    {
        switch (mode) {
            case BlendMode::Normal: // rgb: srcA, 1-srcA | alpha: ONE, ONE - alpha ACCUMULATES
                return { MTLBlendFactorSourceAlpha, MTLBlendFactorOneMinusSourceAlpha,
                         MTLBlendFactorOne, MTLBlendFactorOne };
            case BlendMode::Multiply: // DST_COLOR, 1-SRC_ALPHA
                return { MTLBlendFactorDestinationColor, MTLBlendFactorOneMinusSourceAlpha,
                         MTLBlendFactorDestinationAlpha, MTLBlendFactorOneMinusSourceAlpha };
            case BlendMode::AddWeird: // 1-SRC_COLOR, 1-SRC_COLOR
                return { MTLBlendFactorOneMinusSourceColor, MTLBlendFactorOneMinusSourceColor,
                         MTLBlendFactorOneMinusSourceAlpha, MTLBlendFactorOneMinusSourceAlpha };
            case BlendMode::Replace: // ONE, ZERO
                return { MTLBlendFactorOne, MTLBlendFactorZero,
                         MTLBlendFactorOne, MTLBlendFactorZero };
            case BlendMode::DestBlend: // 1-DST_ALPHA, DST_ALPHA
                return { MTLBlendFactorOneMinusDestinationAlpha, MTLBlendFactorDestinationAlpha,
                         MTLBlendFactorOneMinusDestinationAlpha, MTLBlendFactorDestinationAlpha };
            case BlendMode::LightModulate: // ZERO, SRC_COLOR
                return { MTLBlendFactorZero, MTLBlendFactorSourceColor,
                         MTLBlendFactorZero, MTLBlendFactorSourceAlpha };
        }
        return { MTLBlendFactorSourceAlpha, MTLBlendFactorOneMinusSourceAlpha,
                 MTLBlendFactorOne, MTLBlendFactorOne };
    }

    // Every pass in this renderer writes a BGRA8 attachment: the offscreen backbuffer matches the
    // layer's drawable so the present is a straight copy, and every other target matches it so
    // that one pipeline set serves them all.
    constexpr MTLPixelFormat ATTACHMENT_FORMAT = MTLPixelFormatBGRA8Unorm;
}

bool MetalPipelineCache::initialize(MetalContext* context)
{
    m_context = context;

    NSError* error = nil;
    NSString* source = [NSString stringWithUTF8String:METAL_BUILTIN_SHADER_SOURCE.data()];

    MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
    // The GL fragment stage is `gl_FragColor.a *= u_Opacity` over a texture fetch, with no
    // reassociation that would change a pixel. Fast math would let the compiler reassociate it;
    // there is no measurable win here and the whole point of this backend is comparability.
    options.fastMathEnabled = NO;

    m_library = [m_context->device() newLibraryWithSource:source options:options error:&error];
    if (!m_library) {
        g_logger.warning("[metal] built-in shader compilation failed: {}",
                         error ? [[error localizedDescription] UTF8String] : "unknown error");
        return false;
    }

    [m_library setLabel:@"CrystalOTC built-ins"];

    m_vertexFunction = [m_library newFunctionWithName:@"crystalotc_vertex"];
    m_texturedFunction = [m_library newFunctionWithName:@"crystalotc_textured"];
    m_solidFunction = [m_library newFunctionWithName:@"crystalotc_solid"];
    m_replaceColorFunction = [m_library newFunctionWithName:@"crystalotc_replace_color"];

    if (!m_vertexFunction || !m_texturedFunction || !m_solidFunction || !m_replaceColorFunction) {
        g_logger.warning("[metal] a built-in shader function is missing from the compiled library");
        shutdown();
        return false;
    }

    // Positions and texture coordinates stay in two separate float2 streams, because that is the
    // shape the compiled vertex arena has and the shape the fixed vertex stage takes. Interleaving
    // them would mean rewriting every arena on the way to the GPU for no benefit.
    m_vertexDescriptor = [[MTLVertexDescriptor alloc] init];
    m_vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
    m_vertexDescriptor.attributes[0].offset = 0;
    m_vertexDescriptor.attributes[0].bufferIndex = MetalABI::VERTEX_POSITION_BUFFER;
    m_vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
    m_vertexDescriptor.attributes[1].offset = 0;
    m_vertexDescriptor.attributes[1].bufferIndex = MetalABI::VERTEX_TEXCOORD_BUFFER;
    m_vertexDescriptor.layouts[MetalABI::VERTEX_POSITION_BUFFER].stride = sizeof(float) * 2;
    m_vertexDescriptor.layouts[MetalABI::VERTEX_POSITION_BUFFER].stepFunction = MTLVertexStepFunctionPerVertex;
    m_vertexDescriptor.layouts[MetalABI::VERTEX_TEXCOORD_BUFFER].stride = sizeof(float) * 2;
    m_vertexDescriptor.layouts[MetalABI::VERTEX_TEXCOORD_BUFFER].stepFunction = MTLVertexStepFunctionPerVertex;

    return true;
}

void MetalPipelineCache::shutdown()
{
    m_pipelines.clear();
    m_moduleFunctions.clear();
    m_reportedMaterials.clear();
    m_vertexDescriptor = nil;
    m_replaceColorFunction = nil;
    m_solidFunction = nil;
    m_texturedFunction = nil;
    m_vertexFunction = nil;
    m_library = nil;
    m_context = nullptr;
}

MetalPipelineCache::MaterialFunctions MetalPipelineCache::moduleFunctions(const std::string& sourceKey)
{
    if (const auto it = m_moduleFunctions.find(sourceKey); it != m_moduleFunctions.end())
        return it->second;

    MaterialFunctions functions;

    const MetalModuleMaterial* material = nullptr;
    for (const auto& candidate : METAL_MODULE_MATERIALS) {
        if (candidate.key == sourceKey) {
            material = &candidate;
            break;
        }
    }

    if (!material) {
        m_moduleFunctions.emplace(sourceKey, functions);
        return functions;
    }

    NSError* error = nil;
    NSString* source = [[NSString alloc] initWithBytes:material->source.data()
                                                length:material->source.size()
                                              encoding:NSUTF8StringEncoding];

    MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
    // Same reasoning as the built-ins: the point of this backend is comparability with GL, and
    // reassociation is exactly what would cost it. Several of these shaders accumulate a sum
    // over a loop - bloom takes 81 taps - where reassociation is visible rather than theoretical.
    options.fastMathEnabled = NO;

    id<MTLLibrary> library = [m_context->device() newLibraryWithSource:source options:options error:&error];
    if (!library) {
        g_logger.warning("[metal] module material '{}' failed to compile: {}", sourceKey,
                         error ? [[error localizedDescription] UTF8String] : "unknown error");
        m_moduleFunctions.emplace(sourceKey, functions);
        return functions;
    }

    [library setLabel:[NSString stringWithUTF8String:sourceKey.c_str()]];

    functions.vertex = [library newFunctionWithName:
        [NSString stringWithUTF8String:std::string{ material->vertexEntry }.c_str()]];
    functions.fragment = [library newFunctionWithName:
        [NSString stringWithUTF8String:std::string{ material->fragmentEntry }.c_str()]];

    if (!functions.vertex || !functions.fragment) {
        g_logger.warning("[metal] module material '{}' compiled but is missing an entry point",
                         sourceKey);
        functions = {};
    }

    m_moduleFunctions.emplace(sourceKey, functions);
    return functions;
}

MetalPipelineCache::MaterialFunctions MetalPipelineCache::functionsFor(const uint16_t material,
                                                                      const bool textured)
{
    const MaterialFunctions builtin{
        m_vertexFunction,
        textured ? m_texturedFunction : m_solidFunction
    };

    if (material >= static_cast<uint16_t>(BuiltinMaterial::FirstModule)) {
        // Every translated module fragment samples u_Tex0, so one bound to untextured geometry
        // would read a texture argument nothing filled. GL would have run the same fragment
        // against whatever happened to be bound to unit 0, which is not behaviour worth
        // reproducing; the built-in draws the geometry instead.
        if (!textured)
            return builtin;

        if (const auto* desc = MaterialRegistry::instance().resolve(MaterialHandle{ material });
            desc && !desc->sourceKey.empty()) {
            if (const auto functions = moduleFunctions(desc->sourceKey); functions.fragment)
                return functions;
        }

        if (m_reportedMaterials.try_emplace(material, true).second) {
            const auto* desc = MaterialRegistry::instance().resolve(MaterialHandle{ material });
            g_logger.info("[metal] no translated MSL for material {} ('{}'); drawing it unshaded",
                          material, desc ? desc->name : std::string{ "unregistered" });
        }
        return builtin;
    }

    switch (static_cast<BuiltinMaterial>(material)) {
        case BuiltinMaterial::SolidColor:
            return { m_vertexFunction, m_solidFunction };
        case BuiltinMaterial::ReplaceColor:
            // A replace-colour draw still samples: the alpha it tests comes from the texture.
            return { m_vertexFunction, textured ? m_replaceColorFunction : m_solidFunction };
        case BuiltinMaterial::Textured:
        default:
            return builtin;
    }
}

id<MTLRenderPipelineState> MetalPipelineCache::get(const MetalPipelineKey& key)
{
    const uint32_t packed = key.pack();
    if (const auto it = m_pipelines.find(packed); it != m_pipelines.end())
        return it->second;

    const auto functions = functionsFor(key.material, key.textured);

    MTLRenderPipelineDescriptor* desc = [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction = functions.vertex;
    desc.fragmentFunction = functions.fragment;
    desc.vertexDescriptor = m_vertexDescriptor;
    desc.label = [NSString stringWithFormat:@"CrystalOTC material %u blend %u%s%s%s",
                  key.material, static_cast<unsigned>(key.blend),
                  key.blendEnabled ? "" : " (blend off)",
                  key.alphaWrite ? "" : " (no alpha)",
                  key.textured ? "" : " (untextured)"];

    auto* attachment = desc.colorAttachments[0];
    attachment.pixelFormat = ATTACHMENT_FORMAT;
    attachment.blendingEnabled = key.blendEnabled ? YES : NO;

    if (key.blendEnabled) {
        const auto factors = blendFactorsOf(key.blend);
        attachment.sourceRGBBlendFactor = factors.srcRGB;
        attachment.destinationRGBBlendFactor = factors.dstRGB;
        attachment.sourceAlphaBlendFactor = factors.srcAlpha;
        attachment.destinationAlphaBlendFactor = factors.dstAlpha;
        // Every blend equation in this client is ADD. The enum carries four more and no code path
        // anywhere selects one, which is why the packet does not carry the field at all.
        attachment.rgbBlendOperation = MTLBlendOperationAdd;
        attachment.alphaBlendOperation = MTLBlendOperationAdd;
    }

    // glColorMask(1, 1, 1, alphaWriting), which is off for exactly one thing: draws into the MAP
    // target, whose pixels replace rather than blend when it is composited.
    attachment.writeMask = key.alphaWrite
        ? MTLColorWriteMaskAll
        : (MTLColorWriteMaskRed | MTLColorWriteMaskGreen | MTLColorWriteMaskBlue);

    NSError* error = nil;
    id<MTLRenderPipelineState> pipeline = [m_context->device() newRenderPipelineStateWithDescriptor:desc
                                                                                              error:&error];
    if (!pipeline) {
        g_logger.warning("[metal] pipeline creation failed for material {}: {}", key.material,
                         error ? [[error localizedDescription] UTF8String] : "unknown error");
    }

    m_pipelines[packed] = pipeline;
    return pipeline;
}

#endif // CRYSTALOTC_COCOA_WINDOW
