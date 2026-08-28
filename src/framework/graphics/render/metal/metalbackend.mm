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

#include "metalbackend.h"

#include "metalcontext.h"
#include "metalpipelines.h"
#include "metalresources.h"

#include <framework/core/logger.h>
#include <framework/util/profiler.h>
#include <framework/platform/platformwindow.h>

#include <cstring>
#include <unordered_map>

namespace
{
    /*
     * The projection, copied from Painter::getTransformMatrix rather than called through it.
     *
     * Painter is the OpenGL renderer's state machine and this backend deliberately touches none of
     * it, but the matrix itself is not GL - it is the client's pixel-space-to-clip-space contract,
     * top-left origin, y down. Metal's clip space has the same handedness as GL's in x and y, so
     * the same nine numbers are correct here; only the depth range differs, and nothing in this
     * renderer has a depth.
     */
    Matrix3 projectionFor(const Size& resolution)
    {
        return { 2.0f / resolution.width(),  0.0f,                       0.0f,
                 0.0f,                      -2.0f / resolution.height(), 0.0f,
                -1.0f,                       1.0f,                       1.0f };
    }

    // Pixel coordinates to normalised ones, which is what `u_TextureMatrix` does for GL. GL's
    // registry also carries an upside-down variant for framebuffer-backed textures; Metal needs no
    // such variant, because its render targets are stored top-left exactly like an uploaded image.
    Matrix3 textureMatrixFor(const Size& size)
    {
        if (!size.isValid())
            return DEFAULT_MATRIX3;

        return { 1.0f / size.width(), 0.0f,                 0.0f,
                 0.0f,                1.0f / size.height(), 0.0f,
                 0.0f,                0.0f,                 1.0f };
    }

    MTLClearColor clearColorOf(const Color& color)
    {
        return MTLClearColorMake(color.rF(), color.gF(), color.bF(), color.aF());
    }
}

struct MetalBackend::Impl
{
    MetalContext context;
    MetalResources resources;
    MetalPipelineCache pipelines;

    // Where each arena's two vertex streams landed in this frame's transient buffer. Several
    // passes share one arena - every pass a pool compiled points at that pool's - so the copy is
    // made once per arena and not once per pass.
    struct ArenaSlices
    {
        MetalContext::BufferSlice positions;
        MetalContext::BufferSlice texCoords;
    };

    std::unordered_map<const VertexArena*, ArenaSlices> arenas;

    // What is currently bound on the encoder being filled.
    //
    // Metal keeps every one of these across draws within one encoder, so re-stating them per
    // packet is work the API already did. Consecutive packets very often differ only in vertex
    // range - a pool batches by state, so a run of packets sharing a texture and colour is the
    // normal case - and setRenderPipelineState in particular is the expensive one to repeat.
    //
    // Scoped to a single encoder ON PURPOSE, and constructed fresh in encodePass: a new encoder
    // inherits nothing, so a tracker that outlived one would claim things were bound that are
    // not. That is the failure mode this struct has to avoid, and the reason it is a local
    // rather than a member.
    struct EncoderState
    {
        id<MTLRenderPipelineState> pipeline{ nil };
        id<MTLTexture> texture{ nil };
        id<MTLSamplerState> sampler{ nil };

        MetalABI::VertexUniforms vertexUniforms{};
        MetalABI::FragmentUniforms fragmentUniforms{};
        MaterialParams params{};
        MTLScissorRect scissor{};

        bool hasVertexUniforms{ false };
        bool hasFragmentUniforms{ false };
        bool hasParams{ false };
        bool hasScissor{ false };
    };

    bool initialized{ false };
    bool loggedDrawableMismatch{ false };

    void encodePass(id<MTLCommandBuffer> commands, const RenderPass& pass, id<MTLTexture> screen);
    void encodePacket(id<MTLRenderCommandEncoder> encoder, const DrawPacket& packet,
                      const Matrix3& projection, const Size& targetSize, EncoderState& state);
    void present(id<MTLCommandBuffer> commands, id<MTLTexture> screen);
};

MetalBackend::MetalBackend() : m_impl(std::make_unique<Impl>()) {}

MetalBackend::~MetalBackend()
{
    if (m_impl && m_impl->initialized)
        shutdown();
}

bool MetalBackend::initialize()
{
    if (m_impl->initialized)
        return true;

    // A GL context and this backend are mutually exclusive by construction, not by policy: the
    // window creates one or the other. Refusing here rather than half-initialising is what
    // IRenderBackend::initialize promises its caller.
    if (!m_impl->context.initialize(g_window.getNativeSurface()))
        return false;

    if (!m_impl->pipelines.initialize(&m_impl->context)) {
        m_impl->context.shutdown();
        return false;
    }

    m_impl->resources.initialize(&m_impl->context);

    // From here the window must stop presenting, or its clear colour would replace every frame
    // this backend draws.
    g_window.setPresentationOwned(true);

    m_impl->initialized = true;
    return true;
}

void MetalBackend::shutdown()
{
    if (!m_impl->initialized)
        return;

    g_window.setPresentationOwned(false);

    m_impl->arenas.clear();
    m_impl->resources.shutdown();
    m_impl->pipelines.shutdown();
    m_impl->context.shutdown();
    m_impl->initialized = false;
}

void MetalBackend::resize(const Size& drawableSize)
{
    // Nothing to do here. The layer is resized by the window, which owns it, and every render
    // target - the offscreen backbuffer included - is created or resized at the moment the pass
    // that writes it runs, from the size that pass states.
    (void)drawableSize;
}

void MetalBackend::Impl::encodePacket(id<MTLRenderCommandEncoder> encoder, const DrawPacket& packet,
                                      const Matrix3& projection, const Size& targetSize,
                                      EncoderState& state)
{
    if (packet.vertexCount == 0)
        return;

    // An enabled but empty scissor is how the compiler states "this clip rect misses its target,
    // so draw nothing". Metal would reject a zero-sized rect outright, and the draw has no pixels
    // either way, so it is dropped here rather than encoded.
    if (packet.scissorEnabled && (packet.scissor.width() <= 0 || packet.scissor.height() <= 0))
        return;

    MetalResources::Resolved texture;
    if (packet.textured) {
        texture = resources.resolve(packet.texture);

        // Textured geometry with nothing to sample draws NOTHING, rather than drawing untextured.
        // That is load-bearing rather than defensive: it is how a texture that has not become
        // resident yet misses a frame instead of appearing as a solid rectangle of its tint
        // colour. Painter::drawArrays makes the same early return for the same reason.
        if (!texture.isValid())
            return;
    }

    const bool textured = packet.textured && texture.isValid();

    id<MTLRenderPipelineState> pipeline = pipelines.get({ packet.material.id, packet.blend,
                                                          packet.blendEnabled, packet.alphaWrite,
                                                          textured });
    if (!pipeline)
        return;

    // The vertex buffers are the pass's, bound once by encodePass - one encoder draws from one
    // arena, so there is nothing per-packet to rebind.
    if (state.pipeline != pipeline) {
        state.pipeline = pipeline;
        [encoder setRenderPipelineState:pipeline];
    }

    MetalABI::VertexUniforms vertexUniforms;
    vertexUniforms.projection = MetalABI::Mat3(projection);
    vertexUniforms.transform = MetalABI::Mat3(packet.transform);
    vertexUniforms.textureMatrix = MetalABI::Mat3(textured ? textureMatrixFor(texture.size) : DEFAULT_MATRIX3);
    if (!state.hasVertexUniforms
        || std::memcmp(&state.vertexUniforms, &vertexUniforms, sizeof(vertexUniforms)) != 0) {
        state.vertexUniforms = vertexUniforms;
        state.hasVertexUniforms = true;
        [encoder setVertexBytes:&vertexUniforms length:sizeof(vertexUniforms)
                        atIndex:MetalABI::VERTEX_UNIFORM_BUFFER];
    }

    MetalABI::FragmentUniforms fragmentUniforms;
    fragmentUniforms.color[0] = packet.color.rF();
    fragmentUniforms.color[1] = packet.color.gF();
    fragmentUniforms.color[2] = packet.color.bF();
    fragmentUniforms.color[3] = packet.color.aF();
    fragmentUniforms.opacity = packet.opacity;
    fragmentUniforms.tex0FlipY = (textured && texture.isRenderTarget) ? 1.f : 0.f;
    if (!state.hasFragmentUniforms
        || std::memcmp(&state.fragmentUniforms, &fragmentUniforms, sizeof(fragmentUniforms)) != 0) {
        state.fragmentUniforms = fragmentUniforms;
        state.hasFragmentUniforms = true;
        [encoder setFragmentBytes:&fragmentUniforms length:sizeof(fragmentUniforms)
                          atIndex:MetalABI::FRAGMENT_UNIFORM_BUFFER];
    }

    // The frozen parameter block. Bound unconditionally rather than only for materials that read
    // it: a translated module fragment declares it or does not, and Metal ignores a buffer bound
    // to a slot the function never names, so branching here would only mean the binding could be
    // wrong. A built-in never reads it. Packets with no block of their own get the frame's
    // defaults - FrameAssembler supplies one per pass - so there is no null case to handle.
    static constexpr MaterialParams DEFAULT_MATERIAL_PARAMS{};
    const MaterialParams& params = packet.params ? *packet.params : DEFAULT_MATERIAL_PARAMS;
    // Compared by VALUE rather than by the packet's pointer: the assembler hands out pointers
    // into a vector it refills every frame, so pointer identity says nothing useful about
    // whether the eighty bytes behind it still match what is bound.
    if (!state.hasParams || std::memcmp(&state.params, &params, sizeof(params)) != 0) {
        state.params = params;
        state.hasParams = true;
        [encoder setFragmentBytes:&params length:sizeof(params)
                          atIndex:MetalABI::FRAGMENT_MATERIAL_PARAMS_BUFFER];
    }

    if (textured) {
        if (state.texture != texture.texture) {
            state.texture = texture.texture;
            [encoder setFragmentTexture:texture.texture atIndex:MetalABI::FRAGMENT_TEXTURE_SLOT];
        }
        if (state.sampler != texture.sampler) {
            state.sampler = texture.sampler;
            [encoder setFragmentSamplerState:texture.sampler atIndex:MetalABI::FRAGMENT_SAMPLER_SLOT];
        }

        // u_Tex1..3. Only Fog and Snow use them, and only through a map shader - but without
        // them those two sample an unbound texture argument, which Metal treats as an error
        // rather than as black. GL reaches the same textures from inside Painter::drawArrays,
        // off the bound program; here they travel in the packet because there is no program to
        // read them off.
        for (size_t unit = 0; unit < std::size(packet.extraTex); ++unit) {
            if (!packet.extraTex[unit].isValid())
                continue;

            const auto extra = resources.resolve(packet.extraTex[unit]);
            if (!extra.isValid())
                continue;

            [encoder setFragmentTexture:extra.texture
                                atIndex:MetalABI::FRAGMENT_TEXTURE_SLOT + unit + 1];
            [encoder setFragmentSamplerState:extra.sampler
                                     atIndex:MetalABI::FRAGMENT_SAMPLER_SLOT + unit + 1];
        }
    }

    // Metal keeps the scissor across draws in one encoder, so "no clipping" has to be stated as
    // the whole target rather than left unset.
    MTLScissorRect scissor{ 0, 0,
                            static_cast<NSUInteger>(targetSize.width()),
                            static_cast<NSUInteger>(targetSize.height()) };
    if (packet.scissorEnabled) {
        // The compiler already clamped to the pass viewport. Clamping again to the texture that
        // actually exists costs nothing and covers the one frame after a resize where the two can
        // disagree - Metal treats an out-of-bounds scissor as an error, not as a suggestion.
        const int left = std::clamp(packet.scissor.left(), 0, targetSize.width());
        const int top = std::clamp(packet.scissor.top(), 0, targetSize.height());
        const int width = std::clamp(packet.scissor.width(), 0, targetSize.width() - left);
        const int height = std::clamp(packet.scissor.height(), 0, targetSize.height() - top);
        if (width <= 0 || height <= 0)
            return;

        scissor = { static_cast<NSUInteger>(left), static_cast<NSUInteger>(top),
                    static_cast<NSUInteger>(width), static_cast<NSUInteger>(height) };
    }
    if (!state.hasScissor
        || state.scissor.x != scissor.x || state.scissor.y != scissor.y
        || state.scissor.width != scissor.width || state.scissor.height != scissor.height) {
        state.scissor = scissor;
        state.hasScissor = true;
        [encoder setScissorRect:scissor];
    }

    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:packet.vertexOffset
                vertexCount:packet.vertexCount];
}

void MetalBackend::Impl::encodePass(id<MTLCommandBuffer> commands, const RenderPass& pass,
                                    id<MTLTexture> screen)
{
    const Size size = pass.viewport.size();
    if (!size.isValid())
        return;

    id<MTLTexture> target = pass.target.isBackbuffer()
        ? screen
        // Sized HERE, not up front. A transient target handle names a temporary SLOT at a nesting
        // depth, and several widgets bind depth 0 in one frame at different sizes; sizing them
        // ahead of the frame collapses them onto whichever came last, and the earlier blits then
        // sample a texture smaller than their source rect. GL avoids this by resizing inside the
        // bind callback, which is the same moment.
        : resources.ensureTarget(pass.target, size);

    if (!target)
        return;

    MTLRenderPassDescriptor* desc = [MTLRenderPassDescriptor renderPassDescriptor];
    desc.colorAttachments[0].texture = target;
    desc.colorAttachments[0].storeAction = MTLStoreActionStore;

    // Keep is not a nicety: a pool whose content hash is unchanged is re-composited without being
    // re-rendered, and every pass after the first into the same target continues it. The one
    // exception is a target nobody has written yet - a freshly allocated private texture holds
    // undefined memory, and loading that is not the same as loading what the last frame left.
    const bool undefinedContents = resources.takeUndefined(pass.target);

    if (pass.load == LoadAction::Clear || undefinedContents) {
        desc.colorAttachments[0].loadAction = MTLLoadActionClear;
        desc.colorAttachments[0].clearColor = pass.load == LoadAction::Clear
            ? clearColorOf(pass.clearColor)
            : MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    } else {
        desc.colorAttachments[0].loadAction = MTLLoadActionLoad;
    }

    id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:desc];
    if (!encoder)
        return;

    [encoder setLabel:[NSString stringWithUTF8String:pass.label.empty() ? "pass" : pass.label.c_str()]];
    [encoder setViewport:(MTLViewport){ 0.0, 0.0,
                                        static_cast<double>(size.width()),
                                        static_cast<double>(size.height()),
                                        0.0, 1.0 }];

    const Matrix3 projection = projectionFor(pass.projectionSize());
    const Size targetSize(static_cast<int>([target width]), static_cast<int>([target height]));

    // One encoder draws from one arena, so this is bound here rather than per packet - it used to
    // be a hash lookup and two setVertexBuffer calls for every draw in the pass.
    //
    // A missing or empty arena skips the DRAWS, not the pass: the encoder is still opened and
    // ended, because a pass whose load action is Clear owes its target that clear whether or not
    // anything draws into it afterwards.
    const auto arena = arenas.find(pass.arena);
    if (arena != arenas.end() && arena->second.positions.isValid()) {
        [encoder setVertexBuffer:arena->second.positions.buffer
                          offset:arena->second.positions.offset
                         atIndex:MetalABI::VERTEX_POSITION_BUFFER];
        [encoder setVertexBuffer:arena->second.texCoords.buffer
                          offset:arena->second.texCoords.offset
                         atIndex:MetalABI::VERTEX_TEXCOORD_BUFFER];

        EncoderState state;
        for (const auto& packet : pass.packets)
            encodePacket(encoder, packet, projection, targetSize, state);
    }

    [encoder endEncoding];
}

void MetalBackend::Impl::present(id<MTLCommandBuffer> commands, id<MTLTexture> screen)
{
    @autoreleasepool {
        id<CAMetalDrawable> drawable = [context.layer() nextDrawable];
        if (!drawable)
            return; // window-server starvation or a zero-sized window: the frame is drawn, just not shown

        id<MTLTexture> surface = drawable.texture;
        if ([surface width] != [screen width] || [surface height] != [screen height]) {
            // One frame of a live resize, where the layer has already been resized and the frame
            // in hand was built for the old size. Presenting a drawable nothing wrote would show
            // undefined memory, so the previous frame stays up instead - which is exactly what a
            // skipped present means.
            if (!loggedDrawableMismatch) {
                loggedDrawableMismatch = true;
                g_logger.info("[metal] drawable {}x{} does not match the frame's {}x{}; "
                              "skipping presentation until they agree",
                              static_cast<int>([surface width]), static_cast<int>([surface height]),
                              static_cast<int>([screen width]), static_cast<int>([screen height]));
            }
            return;
        }

        id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
        [blit setLabel:@"CrystalOTC present"];
        [blit copyFromTexture:screen toTexture:surface];
        [blit endEncoding];

        [commands presentDrawable:drawable];
    }
}

bool MetalBackend::render(const RenderFrame& frame)
{
    if (!m_impl->initialized)
        return false;

    // A minimised or zero-sized window has nothing to draw and nothing to present. Reporting
    // success is right: the frame was handled, and reporting failure would send the caller looking
    // for a legacy path that does not exist on this window.
    if (!frame.drawableSize.isValid())
        return true;

    @autoreleasepool {
        id<MTLCommandBuffer> commands = m_impl->context.beginFrame();
        if (!commands)
            return false;

        // Uploads and residency first, in their own blit pass, so that encoding a draw never has
        // to stop to create a resource.
        m_impl->resources.prepareFrame(frame, commands);

        id<MTLTexture> screen = m_impl->resources.ensureTarget(
            RenderTargetHandle{ RenderTargetHandle::BACKBUFFER }, frame.drawableSize);
        if (!screen) {
            m_impl->context.endFrame(commands);
            return false;
        }

        // Every arena the frame references, copied into this frame's transient buffer once.
        m_impl->arenas.clear();
        for (const auto& pass : frame.passes) {
            if (!pass.arena || m_impl->arenas.count(pass.arena))
                continue;

            const size_t bytes = pass.arena->arrayBytes();
            if (bytes == 0)
                continue;

            Impl::ArenaSlices slices;
            slices.positions = m_impl->context.allocate(pass.arena->positions(), bytes);
            slices.texCoords = m_impl->context.allocate(pass.arena->texCoords(), bytes);
            m_impl->arenas.emplace(pass.arena, slices);
        }

        {
            PROFILE_ZONE(BackendEncode);
            for (const auto& pass : frame.passes)
                m_impl->encodePass(commands, pass, screen);
        }

        {
            // Isolated because this is where the frame WAITS: nextDrawable blocks until the
            // display releases one, so lumping it in with encoding makes CPU cost and vsync idle
            // indistinguishable - which is exactly the confusion this profiler exists to end.
            PROFILE_ZONE(GpuPresent);
            m_impl->present(commands, screen);
        }
        m_impl->context.endFrame(commands);
    }

    m_impl->resources.collectGarbage();
    return true;
}

bool MetalBackend::readPixels(const ReadbackRequest& request, ReadbackResult& out)
{
    out.ok = false;

    if (!m_impl->initialized)
        return false;

    // The backbuffer is an ordinary target here, which is the point of rendering into one: a
    // presented drawable can never be read, and every renderer baseline is a screenshot taken
    // between frames.
    id<MTLTexture> source = m_impl->resources.findTarget(request.source);
    if (!source)
        return false;

    const Size targetSize(static_cast<int>([source width]), static_cast<int>([source height]));

    Rect region = request.region.isValid() ? request.region : Rect(0, 0, targetSize);
    region = region.intersection(Rect(0, 0, targetSize));
    if (!region.isValid())
        return false;

    const auto width = static_cast<NSUInteger>(region.width());
    const auto height = static_cast<NSUInteger>(region.height());

    // A blit's destination rows have an alignment requirement; 256 is the safe figure across every
    // Apple GPU family, so the buffer is padded and unpacked row by row below.
    const NSUInteger bytesPerRow = ((width * 4) + 255) & ~static_cast<NSUInteger>(255);

    @autoreleasepool {
        id<MTLBuffer> staging = [m_impl->context.device() newBufferWithLength:bytesPerRow * height
                                                                      options:MTLResourceStorageModeShared];
        if (!staging)
            return false;

        id<MTLCommandBuffer> commands = m_impl->context.utilityCommandBuffer(@"CrystalOTC readback");
        if (!commands)
            return false;

        id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
        [blit copyFromTexture:source
                  sourceSlice:0
                  sourceLevel:0
                 sourceOrigin:MTLOriginMake(static_cast<NSUInteger>(region.left()),
                                            static_cast<NSUInteger>(region.top()), 0)
                   sourceSize:MTLSizeMake(width, height, 1)
                     toBuffer:staging
            destinationOffset:0
       destinationBytesPerRow:bytesPerRow
     destinationBytesPerImage:bytesPerRow * height];
        [blit endEncoding];

        [commands commit];
        [commands waitUntilCompleted];

        if (commands.error) {
            g_logger.warning("[metal] readback failed: {}",
                             [[commands.error localizedDescription] UTF8String]);
            return false;
        }

        out.size = Size(static_cast<int>(width), static_cast<int>(height));
        out.pixels.resize(static_cast<size_t>(width) * height * 4);

        // Render targets are BGRA8 because that is what the drawable is; the readback contract is
        // RGBA8 and top-left. Metal textures are already top-left, so the row order is kept and
        // only the two colour channels are swapped - the GL path flips instead, and swaps nothing.
        const auto* src = static_cast<const uint8_t*>([staging contents]);
        for (NSUInteger y = 0; y < height; ++y) {
            const uint8_t* row = src + y * bytesPerRow;
            uint8_t* dst = out.pixels.data() + static_cast<size_t>(y) * width * 4;
            for (NSUInteger x = 0; x < width; ++x) {
                dst[x * 4 + 0] = row[x * 4 + 2];
                dst[x * 4 + 1] = row[x * 4 + 1];
                dst[x * 4 + 2] = row[x * 4 + 0];
                dst[x * 4 + 3] = row[x * 4 + 3];
            }
        }
    }

    out.ok = true;
    return true;
}

#endif // CRYSTALOTC_COCOA_WINDOW
