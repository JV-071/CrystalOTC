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

#include "metalresources.h"

#include <framework/core/logger.h>
#include <framework/graphics/animatedtexture.h>
#include <framework/graphics/framebuffer.h>
#include <framework/graphics/image.h>
#include <framework/graphics/render/resourceregistry.h>
#include <framework/graphics/texture.h>

#include <vector>

namespace
{
    constexpr MTLPixelFormat SAMPLED_FORMAT = MTLPixelFormatRGBA8Unorm;
    constexpr MTLPixelFormat TARGET_FORMAT = MTLPixelFormatBGRA8Unorm;

    // Cache entries outlive the objects that named them - a handle is never reused, so a dead
    // entry is inert rather than dangerous. Sweeping every few seconds keeps a long session from
    // accumulating them without paying for a scan per frame.
    constexpr uint32_t COLLECT_INTERVAL_FRAMES = 600;

    uint32_t mipLevelsFor(const Size& size)
    {
        uint32_t levels = 1;
        int extent = std::max(size.width(), size.height());
        while (extent > 1) {
            extent >>= 1;
            ++levels;
        }
        return levels;
    }
}

void MetalResources::initialize(MetalContext* context)
{
    m_context = context;
}

void MetalResources::shutdown()
{
    m_textures.clear();
    m_targets.clear();
    m_samplers.clear();
    m_context = nullptr;
}

id<MTLSamplerState> MetalResources::samplerFor(const bool smooth, const bool repeat, const bool mipmapped)
{
    // The client uses exactly four filter/wrap combinations, doubled by whether the texture
    // carries a mip chain - GL selects LINEAR_MIPMAP_LINEAR only when one exists, and stating
    // "not mipmapped" is how that distinction survives into a sampler object.
    const uint32_t key = (smooth ? 1u : 0u) | (repeat ? 2u : 0u) | (mipmapped ? 4u : 0u);

    if (const auto it = m_samplers.find(key); it != m_samplers.end())
        return it->second;

    MTLSamplerDescriptor* desc = [[MTLSamplerDescriptor alloc] init];
    desc.minFilter = smooth ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;
    desc.magFilter = smooth ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;
    desc.mipFilter = mipmapped
        ? (smooth ? MTLSamplerMipFilterLinear : MTLSamplerMipFilterNearest)
        : MTLSamplerMipFilterNotMipmapped;
    desc.sAddressMode = repeat ? MTLSamplerAddressModeRepeat : MTLSamplerAddressModeClampToEdge;
    desc.tAddressMode = desc.sAddressMode;
    desc.label = [NSString stringWithFormat:@"CrystalOTC sampler %s%s%s",
                  smooth ? "linear" : "nearest", repeat ? "+repeat" : "+clamp",
                  mipmapped ? "+mips" : ""];

    id<MTLSamplerState> sampler = [m_context->device() newSamplerStateWithDescriptor:desc];
    m_samplers[key] = sampler;
    return sampler;
}

Texture* MetalResources::sampledTextureOf(const TextureHandle handle)
{
    auto* texture = ResourceRegistry::instance().resolveTexture(handle);
    if (!texture)
        return nullptr;

    if (texture->isAnimatedTexture()) {
        // One AnimatedTexture is a stack of ordinary Textures with one cursor. The packet names
        // the stack; what gets sampled is whichever frame the cursor is on, and that frame owns
        // its own pixels and its own cache entry.
        const auto& frame = static_cast<AnimatedTexture*>(texture)->getCurrentFrame();
        return frame ? frame.get() : nullptr;
    }

    return texture;
}

bool MetalResources::uploadTexture(Texture* texture, CachedTexture& out)
{
    const Size size = texture->getSize();
    if (!size.isValid())
        return false;

    const auto& image = texture->getPendingImage();

    if (image && image->getBpp() != 4) {
        // Every Image this client builds is RGBA8 - the PNG loader forces it, and Image itself
        // asserts four channels in five of its own mutators - so this is a guard against a future
        // producer rather than a case that exists. Refusing is better than uploading a texture
        // whose rows are the wrong length, which would read as scrambled diagonal garbage.
        if (!m_loggedUnsupportedImage) {
            m_loggedUnsupportedImage = true;
            g_logger.warning("[metal] texture with {} channels is not supported; drawing without it",
                             image->getBpp());
        }
        return false;
    }

    const bool wantsMips = texture->hasMipmaps() && image != nullptr;

    if (!out.texture || out.size != size) {
        MTLTextureDescriptor* desc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:SAMPLED_FORMAT
                                                               width:static_cast<NSUInteger>(size.width())
                                                              height:static_cast<NSUInteger>(size.height())
                                                           mipmapped:wantsMips];
        desc.usage = MTLTextureUsageShaderRead;
        // Shared storage: this build targets Apple Silicon only (CMAKE_OSX_ARCHITECTURES=arm64),
        // where CPU and GPU address the same memory, so an upload is a memcpy and a private copy
        // would buy a staging blit and nothing else.
        desc.storageMode = MTLStorageModeShared;
        if (wantsMips)
            desc.mipmapLevelCount = mipLevelsFor(size);

        out.texture = [m_context->device() newTextureWithDescriptor:desc];
        if (!out.texture)
            return false;

        [out.texture setLabel:[NSString stringWithFormat:@"CrystalOTC texture %u", texture->getUniqueId()]];
        out.size = size;
    }

    if (image) {
        const MTLRegion region = MTLRegionMake2D(0, 0,
                                                 static_cast<NSUInteger>(size.width()),
                                                 static_cast<NSUInteger>(size.height()));
        [out.texture replaceRegion:region
                       mipmapLevel:0
                         withBytes:image->getPixelData()
                       bytesPerRow:static_cast<NSUInteger>(size.width()) * 4];

        // The non-GL twin of what create() does after uploadPixels. Without it `m_id` stays zero
        // forever, the garbage collector keeps treating this texture as one that never reached the
        // GPU, and create() reloads the file from disk on every frame it is drawn.
        texture->markUploaded();
    }

    out.revision = texture->getContentRevision();
    out.sampler = samplerFor(texture->isSmooth(), texture->hasRepeat(), wantsMips);
    return true;
}

id<MTLTexture> MetalResources::ensureTarget(const RenderTargetHandle handle, const Size& size)
{
    if (!m_context || !size.isValid())
        return nil;

    auto& target = m_targets[handle.id];
    if (target.texture && target.size == size)
        return target.texture;

    MTLTextureDescriptor* desc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:TARGET_FORMAT
                                                           width:static_cast<NSUInteger>(size.width())
                                                          height:static_cast<NSUInteger>(size.height())
                                                       mipmapped:NO];
    desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    // Private: nothing writes these from the CPU. A readback copies out through a blit encoder,
    // which is the one path that needs to see them and the one that can.
    desc.storageMode = MTLStorageModePrivate;

    target.texture = [m_context->device() newTextureWithDescriptor:desc];
    target.size = target.texture ? size : Size();
    target.undefined = true;

    if (target.texture) {
        [target.texture setLabel:[NSString stringWithFormat:@"CrystalOTC target %u (%dx%d)",
                                  handle.id, size.width(), size.height()]];
    }

    return target.texture;
}

bool MetalResources::takeUndefined(const RenderTargetHandle handle)
{
    const auto it = m_targets.find(handle.id);
    if (it == m_targets.end() || !it->second.undefined)
        return false;

    it->second.undefined = false;
    return true;
}

id<MTLTexture> MetalResources::findTarget(const RenderTargetHandle handle) const
{
    const auto it = m_targets.find(handle.id);
    return it == m_targets.end() ? nil : it->second.texture;
}

Size MetalResources::targetSize(const RenderTargetHandle handle) const
{
    const auto it = m_targets.find(handle.id);
    return it == m_targets.end() ? Size() : it->second.size;
}

void MetalResources::applyUpload(const TextureUpdate& update, id<MTLBlitCommandEncoder> blit)
{
    auto* texture = sampledTextureOf(update.texture);
    if (!texture || texture->getSize() != update.size)
        return;

    auto& cached = m_textures[texture->getUniqueId()];
    if (!cached.texture && !uploadTexture(texture, cached))
        return;
    if (!cached.texture || cached.size != update.size)
        return;

    const size_t bytes = update.pixels.size();
    if (bytes < static_cast<size_t>(update.size.area()) * 4)
        return;

    // Staged through the frame's own buffer and copied by the GPU, rather than written straight
    // into the texture. The two are not equivalent: this texture is re-uploaded every time its
    // content changes and may still be sampled by a frame that has not finished, and a CPU write
    // has nothing ordering it against that read. A blit inside this frame's command buffer does.
    const auto slice = m_context->allocate(update.pixels.data(), bytes, 256);
    if (!slice.isValid() || !blit)
        return;

    [blit copyFromBuffer:slice.buffer
            sourceOffset:slice.offset
       sourceBytesPerRow:static_cast<NSUInteger>(update.size.width()) * 4
     sourceBytesPerImage:bytes
              sourceSize:MTLSizeMake(static_cast<NSUInteger>(update.size.width()),
                                     static_cast<NSUInteger>(update.size.height()), 1)
               toTexture:cached.texture
        destinationSlice:0
        destinationLevel:0
       destinationOrigin:MTLOriginMake(0, 0, 0)];
}

void MetalResources::prepareFrame(const RenderFrame& frame, id<MTLCommandBuffer> commands)
{
    if (!m_context)
        return;

    std::vector<id<MTLTexture>> needMipmaps;

    const auto residency = [&](const TextureHandle handle) {
        if (!handle.isValid() || RenderHandles::isRenderTargetTexture(handle))
            return;

        auto* texture = sampledTextureOf(handle);
        if (!texture)
            return;

        auto& cached = m_textures[texture->getUniqueId()];
        const bool isNew = cached.texture == nil;
        const bool stale = !isNew && cached.revision != texture->getContentRevision()
                           && texture->getPendingImage() != nullptr;

        if (!isNew && !stale)
            return;

        if (uploadTexture(texture, cached) && texture->hasMipmaps() && cached.texture)
            needMipmaps.push_back(cached.texture);
    };

    for (const auto& upload : frame.uploads)
        residency(upload.texture);

    for (const auto& pass : frame.passes) {
        for (const auto& packet : pass.packets) {
            residency(packet.texture);
            for (const auto& extra : packet.extraTex)
                residency(extra);
        }
    }

    if (frame.uploads.empty() && needMipmaps.empty())
        return;

    id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
    [blit setLabel:@"CrystalOTC uploads"];

    for (const auto& upload : frame.uploads)
        applyUpload(upload, blit);

    for (id<MTLTexture> texture : needMipmaps)
        [blit generateMipmapsForTexture:texture];

    [blit endEncoding];
}

MetalResources::Resolved MetalResources::resolve(const TextureHandle handle) const
{
    if (!handle.isValid())
        return {};

    if (RenderHandles::isRenderTargetTexture(handle)) {
        const RenderTargetHandle target{ handle.id };
        const auto it = m_targets.find(target.id);
        if (it == m_targets.end() || !it->second.texture)
            return {};

        // Filtering follows the FrameBuffer the client still owns, so the policy stays where it
        // already lives: pool targets are smooth by FrameBuffer's default, lazily created
        // temporary ones are explicitly not.
        bool smooth = true;
        if (const auto* fb = ResourceRegistry::instance().resolveTarget(target)) {
            if (const auto& texture = fb->getTexture())
                smooth = texture->isSmooth();
        }

        Resolved resolved;
        resolved.texture = it->second.texture;
        resolved.size = it->second.size;
        resolved.sampler = const_cast<MetalResources*>(this)->samplerFor(smooth, false, false);
        return resolved;
    }

    auto* texture = sampledTextureOf(handle);
    if (!texture)
        return {};

    const auto it = m_textures.find(texture->getUniqueId());
    if (it == m_textures.end() || !it->second.texture)
        return {};

    return { it->second.texture, it->second.sampler, it->second.size };
}

void MetalResources::collectGarbage()
{
    if (++m_framesSinceCollect < COLLECT_INTERVAL_FRAMES)
        return;

    m_framesSinceCollect = 0;

    auto& registry = ResourceRegistry::instance();
    for (auto it = m_textures.begin(); it != m_textures.end();) {
        if (registry.resolveTexture(TextureHandle{ it->first }))
            ++it;
        else
            it = m_textures.erase(it);
    }
}

#endif // CRYSTALOTC_COCOA_WINDOW
