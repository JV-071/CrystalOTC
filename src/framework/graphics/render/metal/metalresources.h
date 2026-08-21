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
 * MetalResources - the native side of the two handle spaces.
 *
 * A packet names a texture and a pass names a target, both by logical handle. `ResourceRegistry`
 * turns a handle back into the client object that describes it; this turns that description into
 * an `id<MTLTexture>`. It is the first half of the resource plane the design document sketched on
 * `IRenderBackend` and Phase 3 deliberately did not build, because until now no backend owned a
 * native object - GL's textures and framebuffers belong to `Texture` and `FrameBuffer`. These
 * belong here.
 *
 * TWO FORMATS, ON PURPOSE. Sampled textures are RGBA8, which is what `Image` already holds, so an
 * upload is a copy and never a swizzle. Render targets are BGRA8, matching the layer's drawable,
 * so one pipeline set covers every pass including the one that ends up on screen and the present
 * is a straight copy.
 *
 * ORIENTATION. GL stores a framebuffer's texture bottom-up and compensates when sampling it, with
 * the `upsideDown` half of the texture-matrix registry. Metal has no such asymmetry: render-target
 * row 0 is the top row, exactly like an uploaded image's row 0, so this backend derives every
 * texture matrix from the texture's size and never resolves a matrix id. That is not a shortcut -
 * resolving GL's id would apply GL's flip and turn every sampled target upside down.
 */
class MetalResources
{
public:
    struct Resolved
    {
        id<MTLTexture> texture{ nil };
        id<MTLSamplerState> sampler{ nil };
        Size size;

        [[nodiscard]] bool isValid() const { return texture != nil; }
    };

    void initialize(MetalContext* context);
    void shutdown();

    // Creates or resizes the target's texture. Transient targets are sized at the moment their
    // pass runs rather than up front, because one handle names a temporary SLOT at a nesting
    // depth and several passes reuse that slot at different sizes within one frame.
    id<MTLTexture> ensureTarget(RenderTargetHandle handle, const Size& size);
    [[nodiscard]] id<MTLTexture> findTarget(RenderTargetHandle handle) const;
    [[nodiscard]] Size targetSize(RenderTargetHandle handle) const;

    // Makes every texture the frame samples resident, and applies its dynamic uploads. Runs
    // before any pass so that encoding never has to stop to create a resource.
    void prepareFrame(const RenderFrame& frame, id<MTLCommandBuffer> commands);

    // Null texture means "not resident this frame": the packet is skipped, which is what the GL
    // path does when a texture has no name yet.
    [[nodiscard]] Resolved resolve(TextureHandle handle) const;

    // Drops cache entries whose client object has been destroyed. Handles are never reused, so a
    // dead entry is only wasted memory - but a session is long and sprites churn.
    void collectGarbage();

private:
    struct CachedTexture
    {
        id<MTLTexture> texture{ nil };
        id<MTLSamplerState> sampler{ nil };
        Size size;
        uint32_t revision{ 0 };
    };

    struct CachedTarget
    {
        id<MTLTexture> texture{ nil };
        Size size;
    };

    id<MTLSamplerState> samplerFor(bool smooth, bool repeat, bool mipmapped);

    // Resolves a handle to the Texture whose pixels are actually sampled. For an AnimatedTexture
    // that is the current frame - a separate Texture object with its own id, its own pixels and
    // its own cache entry - which is why the handle a packet carries can stay stable while what
    // it samples changes.
    static Texture* sampledTextureOf(TextureHandle handle);

    bool uploadTexture(Texture* texture, CachedTexture& out);
    void applyUpload(const TextureUpdate& update, id<MTLBlitCommandEncoder> blit);

    MetalContext* m_context{ nullptr };

    std::unordered_map<uint32_t, CachedTexture> m_textures;
    std::unordered_map<uint32_t, CachedTarget> m_targets;
    std::unordered_map<uint32_t, id<MTLSamplerState>> m_samplers;

    uint32_t m_framesSinceCollect{ 0 };
    bool m_loggedUnsupportedImage{ false };
};

#endif // CRYSTALOTC_COCOA_WINDOW
