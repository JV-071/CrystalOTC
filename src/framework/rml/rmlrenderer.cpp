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

#include "rmlrenderer.h"

#include <framework/graphics/image.h>

#include <algorithm>
#include <atomic>
#include <iterator>

namespace
{
    std::atomic<uint64_t> g_replayedFrames{ 0 };

    // FNV-1a over the fields of a recorded frame
    struct FrameHash
    {
        uint64_t value{ 14695981039346656037ull };

        void bytes(const void* data, const size_t size)
        {
            const auto* byte = static_cast<const unsigned char*>(data);
            for (size_t i = 0; i < size; ++i)
                value = (value ^ byte[i]) * 1099511628211ull;
        }
        void add(const uint64_t number) { bytes(&number, sizeof(number)); }
        void add(const float number) { bytes(&number, sizeof(number)); }
        void add(const Rml::Vector2f& vector) { add(vector.x); add(vector.y); }
    };

    // marks a handle numbered by its position inside the frame; real proxies never get this high
    constexpr uint64_t kFrameLocal = 1ull << 63;
}

RmlTargetTexture::RmlTargetTexture(const Size& size)
{
    // Not setupSize(): it validates the size against the GPU limit, which is only known once a
    // graphics context exists. A widget never exceeds the window, and the storage itself is
    // created later by the backend, on the graphics thread.
    m_size = size;
    // GL framebuffer orientation, like FrameBuffer textures. Only the flag: the matrix that goes
    // with it lives in a table owned by the graphics thread and is looked up in realize().
    setProp(Prop::upsideDown, true);
}

void RmlTargetTexture::realize()
{
    if (m_id)
        return;

    setupTranformMatrix();
    createTexture();
    bind();
    setupPixels(0, m_size, nullptr, 4);
    setupWrap();
    setupFilters();
}

RmlRenderer::RmlRenderer(RmlRendererHooks hooks) : m_hooks(std::move(hooks)) {}
RmlRenderer::~RmlRenderer() = default;

void RmlRenderer::commit(Command&& cmd)
{
    if (m_inFrame) {
        m_frame.emplace_back(std::move(cmd));
        return;
    }

    // Outside of a frame (e.g. resources created or released during Context::Update). The
    // graphics thread may swap the queue away at any moment, so the command goes in complete:
    // nothing may be written to it once it is queued.
    std::scoped_lock lock(m_queueMutex);
    m_queue.emplace_back(std::move(cmd));
}

void RmlRenderer::commit(const Op op, const uintptr_t a)
{
    Command cmd{ op };
    cmd.a = a;
    commit(std::move(cmd));
}

void RmlRenderer::beginFrame(const RmlTargetTexturePtr& target)
{
    m_frame.clear();
    m_inFrame = !m_retired;
    if (m_inFrame) {
        Command cmd{ Op::BeginFrame };
        cmd.target = target;
        commit(std::move(cmd));
    }
}

uint64_t RmlRenderer::replayedFrameCount() { return g_replayedFrames.load(std::memory_order_relaxed); }

uint64_t RmlRenderer::endFrame()
{
    if (!m_inFrame)
        return m_frameSerial;

    commit(Op::EndFrame);
    m_inFrame = false;

    const auto target = m_frame.front().target;
    bool mustReplay = false;
    const uint64_t signature = frameSignature(mustReplay);
    if (!mustReplay && signature == m_lastSignature && target == m_lastTarget) {
        m_frame.clear(); // the target already shows exactly this
        return m_frameSerial;
    }

    m_lastSignature = signature;
    m_lastTarget = target;

    std::scoped_lock lock(m_queueMutex);
    std::move(m_frame.begin(), m_frame.end(), std::back_inserter(m_queue));
    m_frame.clear();
    return ++m_frameSerial;
}

// Identifies what a frame draws: the drawing commands and the state around them, in order.
//
// mustReplay tells that the frame also creates or releases something RmlUi keeps a handle to
// (geometry, textures, filters, shaders). Such a frame has to reach the backend whatever it
// draws, but those commands are not part of the signature: the usual case is a frame that
// builds the geometry of what changed, followed by frames that draw the very same thing with
// the geometry that now exists - and those must compare equal to it.
//
// Handles that are born and die inside the frame (layers, mask images) get a new value on every
// frame, so they enter the signature by order of creation instead.
uint64_t RmlRenderer::frameSignature(bool& mustReplay) const
{
    std::vector<uintptr_t> local;
    std::vector<uintptr_t> openMasks;
    const auto canonical = [&local](const uintptr_t handle) -> uint64_t {
        const auto it = std::ranges::find(local, handle);
        return it != local.end() ? kFrameLocal | static_cast<uint64_t>(it - local.begin()) : handle;
    };

    FrameHash hash;
    for (const auto& cmd : m_frame) {
        const uint64_t before = hash.value; // restored for a command that is not a drawing
        hash.add(static_cast<uint64_t>(cmd.op));

        switch (cmd.op) {
            case Op::BeginFrame:
            case Op::EndFrame:
            case Op::PopLayer:
            case Op::ResetTransform:
                break;
            case Op::RenderGeometry:
                hash.add(static_cast<uint64_t>(cmd.a));
                hash.add(static_cast<uint64_t>(cmd.c));
                hash.add(cmd.translation);
                break;
            case Op::EnableScissor:
            case Op::EnableClipMask:
                hash.add(static_cast<uint64_t>(cmd.flag));
                break;
            case Op::SetScissor:
                for (const int edge : { cmd.rect.Left(), cmd.rect.Top(), cmd.rect.Right(), cmd.rect.Bottom() })
                    hash.add(static_cast<uint64_t>(static_cast<int64_t>(edge)));
                break;
            case Op::RenderToClipMask:
                hash.add(static_cast<uint64_t>(cmd.mode));
                hash.add(static_cast<uint64_t>(cmd.a));
                hash.add(cmd.translation);
                break;
            case Op::SetTransform:
                hash.bytes(cmd.matrix.data(), sizeof(float) * 16);
                break;
            case Op::PushLayer:
                local.emplace_back(cmd.a);
                break;
            case Op::CompositeLayers:
                hash.add(canonical(cmd.a));
                hash.add(canonical(cmd.b));
                hash.add(static_cast<uint64_t>(cmd.mode));
                hash.add(static_cast<uint64_t>(cmd.handles.size()));
                for (const auto filter : cmd.handles)
                    hash.add(canonical(filter));
                break;
            case Op::SaveLayerAsMaskImage:
                local.emplace_back(cmd.a);
                openMasks.emplace_back(cmd.a);
                break;
            case Op::ReleaseFilter:
                if (std::erase(openMasks, cmd.a) != 0) {
                    hash.add(canonical(cmd.a));
                } else {
                    mustReplay = true; // a filter from an earlier frame goes away
                    hash.value = before;
                }
                break;
            case Op::RenderShader:
                hash.add(static_cast<uint64_t>(cmd.a));
                hash.add(static_cast<uint64_t>(cmd.b));
                hash.add(static_cast<uint64_t>(cmd.c));
                hash.add(cmd.translation);
                break;
            default:
                mustReplay = true; // creates or releases something that outlives the frame
                hash.value = before;
                break;
        }
    }

    if (!openMasks.empty())
        mustReplay = true; // a mask image that RmlUi will release in a later frame

    return hash.value != 0 ? hash.value : 1;
}

void RmlRenderer::retire()
{
    endFrame();
    m_retired = true;
    m_lastTarget = nullptr;
    m_lastSignature = 0;
}

Rml::CompiledGeometryHandle RmlRenderer::CompileGeometry(const Rml::Span<const Rml::Vertex> vertices, const Rml::Span<const int> indices)
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    Command cmd{ Op::CompileGeometry };
    cmd.a = handle;
    cmd.vertices.assign(vertices.begin(), vertices.end());
    cmd.indices.assign(indices.begin(), indices.end());
    commit(std::move(cmd));
    return handle;
}

void RmlRenderer::RenderGeometry(const Rml::CompiledGeometryHandle geometry, const Rml::Vector2f translation, const Rml::TextureHandle texture)
{
    if (m_retired) return;
    Command cmd{ Op::RenderGeometry };
    cmd.a = geometry;
    cmd.c = texture;
    cmd.translation = translation;
    commit(std::move(cmd));
}

void RmlRenderer::ReleaseGeometry(const Rml::CompiledGeometryHandle geometry)
{
    if (!geometry) return;
    commit(Op::ReleaseGeometry, geometry);
}

Rml::TextureHandle RmlRenderer::LoadTexture(Rml::Vector2i& textureDimensions, const Rml::String& source)
{
    if (m_retired || !m_hooks.loadImage) return 0;

    const auto image = m_hooks.loadImage(source);
    if (!image || image->getSize().area() <= 0)
        return 0;

    const auto& size = image->getSize();
    const int bpp = image->getBpp();
    const auto& pixels = image->getPixels();
    const size_t count = static_cast<size_t>(size.area());

    std::vector<Rml::byte> rgba(count * 4);
    for (size_t i = 0; i < count; ++i) {
        const uint8_t r = pixels[i * bpp + 0];
        const uint8_t g = pixels[i * bpp + 1];
        const uint8_t b = pixels[i * bpp + 2];
        const uint8_t a = bpp == 4 ? pixels[i * bpp + 3] : 255;
        // RmlUi 6 expects premultiplied alpha
        rgba[i * 4 + 0] = static_cast<Rml::byte>(r * a / 255);
        rgba[i * 4 + 1] = static_cast<Rml::byte>(g * a / 255);
        rgba[i * 4 + 2] = static_cast<Rml::byte>(b * a / 255);
        rgba[i * 4 + 3] = a;
    }

    textureDimensions = { size.width(), size.height() };

    const auto handle = newHandle();
    Command cmd{ Op::GenerateTexture };
    cmd.a = handle;
    cmd.dimensions = textureDimensions;
    cmd.bytes = std::move(rgba);
    commit(std::move(cmd));
    return handle;
}

Rml::TextureHandle RmlRenderer::GenerateTexture(const Rml::Span<const Rml::byte> source, const Rml::Vector2i sourceDimensions)
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    Command cmd{ Op::GenerateTexture };
    cmd.a = handle;
    cmd.dimensions = sourceDimensions;
    cmd.bytes.assign(source.begin(), source.end());
    commit(std::move(cmd));
    return handle;
}

void RmlRenderer::ReleaseTexture(const Rml::TextureHandle texture)
{
    if (!texture) return;
    commit(Op::ReleaseTexture, texture);
}

void RmlRenderer::EnableScissorRegion(const bool enable)
{
    if (m_retired) return;
    Command cmd{ Op::EnableScissor };
    cmd.flag = enable;
    commit(std::move(cmd));
}

void RmlRenderer::SetScissorRegion(const Rml::Rectanglei region)
{
    if (m_retired) return;
    Command cmd{ Op::SetScissor };
    cmd.rect = region;
    commit(std::move(cmd));
}

void RmlRenderer::EnableClipMask(const bool enable)
{
    if (m_retired) return;
    Command cmd{ Op::EnableClipMask };
    cmd.flag = enable;
    commit(std::move(cmd));
}

void RmlRenderer::RenderToClipMask(const Rml::ClipMaskOperation operation, const Rml::CompiledGeometryHandle geometry, const Rml::Vector2f translation)
{
    if (m_retired) return;
    Command cmd{ Op::RenderToClipMask };
    cmd.mode = static_cast<int>(operation);
    cmd.a = geometry;
    cmd.translation = translation;
    commit(std::move(cmd));
}

void RmlRenderer::SetTransform(const Rml::Matrix4f* transform)
{
    if (m_retired) return;
    if (!transform) {
        commit(Op::ResetTransform);
        return;
    }

    Command cmd{ Op::SetTransform };
    cmd.matrix = *transform;
    commit(std::move(cmd));
}

Rml::LayerHandle RmlRenderer::PushLayer()
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    commit(Op::PushLayer, handle);
    return handle;
}

void RmlRenderer::CompositeLayers(const Rml::LayerHandle source, const Rml::LayerHandle destination, const Rml::BlendMode blendMode,
                                  const Rml::Span<const Rml::CompiledFilterHandle> filters)
{
    if (m_retired) return;
    Command cmd{ Op::CompositeLayers };
    cmd.a = source;
    cmd.b = destination;
    cmd.mode = static_cast<int>(blendMode);
    cmd.handles.assign(filters.begin(), filters.end());
    commit(std::move(cmd));
}

void RmlRenderer::PopLayer()
{
    if (m_retired) return;
    commit(Op::PopLayer);
}

Rml::TextureHandle RmlRenderer::SaveLayerAsTexture()
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    commit(Op::SaveLayerAsTexture, handle);
    return handle;
}

Rml::CompiledFilterHandle RmlRenderer::SaveLayerAsMaskImage()
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    commit(Op::SaveLayerAsMaskImage, handle);
    return handle;
}

Rml::CompiledFilterHandle RmlRenderer::CompileFilter(const Rml::String& name, const Rml::Dictionary& parameters)
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    Command cmd{ Op::CompileFilter };
    cmd.a = handle;
    cmd.name = name;
    cmd.parameters = parameters;
    commit(std::move(cmd));
    return handle;
}

void RmlRenderer::ReleaseFilter(const Rml::CompiledFilterHandle filter)
{
    if (!filter) return;
    commit(Op::ReleaseFilter, filter);
}

Rml::CompiledShaderHandle RmlRenderer::CompileShader(const Rml::String& name, const Rml::Dictionary& parameters)
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    Command cmd{ Op::CompileShader };
    cmd.a = handle;
    cmd.name = name;
    cmd.parameters = parameters;
    commit(std::move(cmd));
    return handle;
}

void RmlRenderer::RenderShader(const Rml::CompiledShaderHandle shader, const Rml::CompiledGeometryHandle geometry, const Rml::Vector2f translation,
                               const Rml::TextureHandle texture)
{
    if (m_retired) return;
    Command cmd{ Op::RenderShader };
    cmd.a = shader;
    cmd.b = geometry;
    cmd.c = texture;
    cmd.translation = translation;
    commit(std::move(cmd));
}

void RmlRenderer::ReleaseShader(const Rml::CompiledShaderHandle shader)
{
    if (!shader) return;
    commit(Op::ReleaseShader, shader);
}

uintptr_t RmlRenderer::resolve(const uintptr_t proxy) const
{
    if (proxy == 0)
        return 0;
    const auto it = m_handles.find(proxy);
    return it != m_handles.end() ? it->second : 0;
}

uintptr_t RmlRenderer::take(const uintptr_t proxy)
{
    const auto it = m_handles.find(proxy);
    if (it == m_handles.end())
        return 0;

    const auto handle = it->second; // 0 when the backend refused to create it
    m_handles.erase(it);
    return handle;
}

void RmlRenderer::replay()
{
    std::vector<Command> commands;
    {
        std::scoped_lock lock(m_queueMutex);
        commands.swap(m_queue);
    }

    // Without an executor the commands are dropped here, so the queue never grows.
    if (commands.empty() || m_backendFailed)
        return;

    if (!m_backend) {
        if (m_hooks.createBackend)
            m_backend = m_hooks.createBackend();
        if (m_hooks.onBackendResult)
            m_hooks.onBackendResult(m_backend.get());
        if (!m_backend) {
            m_backendFailed = true;
            return;
        }
        m_advancedEffects = m_backend->supportsAdvancedEffects();
    }

    m_backend->beginReplay();
    for (auto& cmd : commands)
        execute(cmd);
    m_backend->endReplay();
}

void RmlRenderer::execute(Command& cmd)
{
    auto& gpu = m_backend->renderInterface();

    switch (cmd.op) {
        case Op::BeginFrame:
            m_backend->beginFrame(cmd.target);
            g_replayedFrames.fetch_add(1, std::memory_order_relaxed);
            break;
        case Op::EndFrame:
            m_backend->endFrame();
            for (const auto layer : m_frameLayers)
                m_handles.erase(layer);
            m_frameLayers.clear();
            break;
        case Op::CompileGeometry:
            m_handles[cmd.a] = gpu.CompileGeometry(cmd.vertices, cmd.indices);
            break;
        case Op::RenderGeometry:
            if (const auto geometry = resolve(cmd.a))
                gpu.RenderGeometry(geometry, cmd.translation, resolve(cmd.c));
            break;
        case Op::ReleaseGeometry:
            if (const auto geometry = take(cmd.a))
                gpu.ReleaseGeometry(geometry);
            break;
        case Op::GenerateTexture:
            m_handles[cmd.a] = gpu.GenerateTexture(cmd.bytes, cmd.dimensions);
            break;
        case Op::ReleaseTexture:
            if (const auto texture = take(cmd.a))
                gpu.ReleaseTexture(texture);
            break;
        case Op::EnableScissor:
            gpu.EnableScissorRegion(cmd.flag);
            break;
        case Op::SetScissor:
            gpu.SetScissorRegion(cmd.rect);
            break;
        case Op::EnableClipMask:
            gpu.EnableClipMask(cmd.flag);
            break;
        case Op::RenderToClipMask:
            if (const auto geometry = resolve(cmd.a))
                gpu.RenderToClipMask(static_cast<Rml::ClipMaskOperation>(cmd.mode), geometry, cmd.translation);
            break;
        case Op::SetTransform:
            gpu.SetTransform(&cmd.matrix);
            break;
        case Op::ResetTransform:
            gpu.SetTransform(nullptr);
            break;
        case Op::PushLayer:
            m_handles[cmd.a] = gpu.PushLayer();
            m_frameLayers.emplace_back(cmd.a);
            break;
        case Op::CompositeLayers: {
            std::vector<Rml::CompiledFilterHandle> filters;
            filters.reserve(cmd.handles.size());
            for (const auto proxy : cmd.handles) {
                // a filter the backend refused (unknown name) is left out, not passed as null
                if (const auto filter = resolve(proxy))
                    filters.emplace_back(filter);
            }
            gpu.CompositeLayers(resolve(cmd.a), resolve(cmd.b), static_cast<Rml::BlendMode>(cmd.mode), filters);
            break;
        }
        case Op::PopLayer:
            gpu.PopLayer();
            break;
        case Op::SaveLayerAsTexture:
            m_handles[cmd.a] = gpu.SaveLayerAsTexture();
            break;
        case Op::SaveLayerAsMaskImage:
            m_handles[cmd.a] = gpu.SaveLayerAsMaskImage();
            break;
        case Op::CompileFilter:
            m_handles[cmd.a] = gpu.CompileFilter(cmd.name, cmd.parameters);
            break;
        case Op::ReleaseFilter:
            if (const auto filter = take(cmd.a))
                gpu.ReleaseFilter(filter);
            break;
        case Op::CompileShader:
            m_handles[cmd.a] = gpu.CompileShader(cmd.name, cmd.parameters);
            break;
        case Op::RenderShader: {
            // RmlUi only holds proxies, so it goes on drawing with a shader the backend refused
            // (decorator: shader("unknown")) or with geometry that was never created.
            const auto shader = resolve(cmd.a);
            const auto geometry = resolve(cmd.b);
            if (shader && geometry)
                gpu.RenderShader(shader, geometry, cmd.translation, resolve(cmd.c));
            break;
        }
        case Op::ReleaseShader:
            if (const auto shader = take(cmd.a))
                gpu.ReleaseShader(shader);
            break;
    }
}

void RmlRenderer::releaseBackend()
{
    // graphics thread, after retire(): apply the final releases recorded by RmlUi, then drop the
    // backend together with every GPU object it still holds.
    replay();
    m_backendFailed = true;

    m_handles.clear();
    m_frameLayers.clear();
    m_backend.reset();
}
