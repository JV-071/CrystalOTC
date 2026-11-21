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

#include "rmlbackend.h"

#include <framework/graphics/texture.h>

#include <RmlUi/Core/RenderInterface.h>
#include <RmlUi/Core/Variant.h>

#include <functional>
#include <mutex>
#include <unordered_map>
#include <vector>

// Texture that receives the composited RmlUi frame of one UIRmlWidget.
// It is created on the UI thread (so the draw pool can reference it while recording) and
// gets its GPU storage from the backend on the graphics thread, right before the first frame
// is replayed. Until then it only knows its size: nothing the graphics thread owns (GPU
// objects, the texture matrix table) is touched by the constructor.
class RmlTargetTexture final : public Texture
{
public:
    explicit RmlTargetTexture(const Size& size);

    // OpenGL storage; called by the OpenGL backend only.
    void realize();
};

// What RmlRenderer needs from the outside. RmlManager provides the real ones; tests provide fakes.
struct RmlRendererHooks
{
    // Graphics thread, on the first replay that has commands. nullptr = no executor available.
    std::function<RmlBackendPtr()> createBackend;
    // UI thread. Resolves an RmlUi image source (file or virtual item/effect/outfit image).
    std::function<ImagePtr(const std::string& source)> loadImage;
    // Graphics thread, once: the backend that was created, or nullptr when there is none.
    std::function<void(const RmlBackend* backend)> onBackendResult;
};

// Rml::RenderInterface used by one Rml::Context.
//
// The UI is updated and rendered by the client's UI thread, but the GPU lives on the graphics
// thread. Every call made by RmlUi is therefore recorded with proxy handles (returned
// immediately to RmlUi) and replayed later on the graphics thread through an RmlBackend, which
// maps each proxy handle to the real GPU object.
class RmlRenderer final : public Rml::RenderInterface
{
public:
    explicit RmlRenderer(RmlRendererHooks hooks);
    ~RmlRenderer() override;

    // UI thread
    void beginFrame(const RmlTargetTexturePtr& target);
    // Returns the serial of the frame the target is going to show. The serial only changes when
    // the frame was queued: a frame that draws exactly what the previous one drew into the same
    // target (and has nothing else to tell the backend) is dropped, so a caller can render as
    // often as it likes and learn from the serial whether the document actually changed.
    uint64_t endFrame();
    void retire(); // stop recording; the GPU objects are freed on the graphics thread

    // graphics thread
    void replay();
    void releaseBackend(); // after retire(): run the pending releases, then destroy the backend
    bool backendFailed() const { return m_backendFailed; }
    bool hasAdvancedEffects() const { return m_advancedEffects; }
    // Frames executed by all renderers since the client started (diagnostics, any thread).
    static uint64_t replayedFrameCount();

    Rml::CompiledGeometryHandle CompileGeometry(Rml::Span<const Rml::Vertex> vertices, Rml::Span<const int> indices) override;
    void RenderGeometry(Rml::CompiledGeometryHandle geometry, Rml::Vector2f translation, Rml::TextureHandle texture) override;
    void ReleaseGeometry(Rml::CompiledGeometryHandle geometry) override;

    Rml::TextureHandle LoadTexture(Rml::Vector2i& textureDimensions, const Rml::String& source) override;
    Rml::TextureHandle GenerateTexture(Rml::Span<const Rml::byte> source, Rml::Vector2i sourceDimensions) override;
    void ReleaseTexture(Rml::TextureHandle texture) override;

    void EnableScissorRegion(bool enable) override;
    void SetScissorRegion(Rml::Rectanglei region) override;

    void EnableClipMask(bool enable) override;
    void RenderToClipMask(Rml::ClipMaskOperation operation, Rml::CompiledGeometryHandle geometry, Rml::Vector2f translation) override;

    void SetTransform(const Rml::Matrix4f* transform) override;

    Rml::LayerHandle PushLayer() override;
    void CompositeLayers(Rml::LayerHandle source, Rml::LayerHandle destination, Rml::BlendMode blendMode,
                         Rml::Span<const Rml::CompiledFilterHandle> filters) override;
    void PopLayer() override;

    Rml::TextureHandle SaveLayerAsTexture() override;
    Rml::CompiledFilterHandle SaveLayerAsMaskImage() override;

    Rml::CompiledFilterHandle CompileFilter(const Rml::String& name, const Rml::Dictionary& parameters) override;
    void ReleaseFilter(Rml::CompiledFilterHandle filter) override;

    Rml::CompiledShaderHandle CompileShader(const Rml::String& name, const Rml::Dictionary& parameters) override;
    void RenderShader(Rml::CompiledShaderHandle shader, Rml::CompiledGeometryHandle geometry, Rml::Vector2f translation,
                      Rml::TextureHandle texture) override;
    void ReleaseShader(Rml::CompiledShaderHandle shader) override;

private:
    enum class Op : uint8_t
    {
        BeginFrame, EndFrame,
        CompileGeometry, RenderGeometry, ReleaseGeometry,
        GenerateTexture, ReleaseTexture,
        EnableScissor, SetScissor,
        EnableClipMask, RenderToClipMask,
        SetTransform, ResetTransform,
        PushLayer, CompositeLayers, PopLayer,
        SaveLayerAsTexture, SaveLayerAsMaskImage,
        CompileFilter, ReleaseFilter,
        CompileShader, RenderShader, ReleaseShader
    };

    struct Command
    {
        Op op;
        uintptr_t a{ 0 };
        uintptr_t b{ 0 };
        uintptr_t c{ 0 };
        bool flag{ false };
        int mode{ 0 };
        Rml::Vector2f translation;
        Rml::Vector2i dimensions;
        Rml::Rectanglei rect;
        Rml::Matrix4f matrix;
        std::vector<Rml::Vertex> vertices;
        std::vector<int> indices;
        std::vector<Rml::byte> bytes;
        std::vector<uintptr_t> handles;
        Rml::String name;
        Rml::Dictionary parameters;
        RmlTargetTexturePtr target;
    };

    // Queues a finished command. Commands recorded outside of a frame are visible to the
    // graphics thread from this point on, so they must be complete when passed in.
    void commit(Command&& cmd);
    void commit(Op op, uintptr_t a = 0);
    uintptr_t newHandle() { return ++m_lastHandle; }
    uintptr_t resolve(uintptr_t proxy) const;
    uintptr_t take(uintptr_t proxy); // resolve() for a proxy that is being released
    uint64_t frameSignature(bool& mustReplay) const;
    void execute(Command& cmd);

    RmlRendererHooks m_hooks;

    // UI thread
    uintptr_t m_lastHandle{ 0 };
    bool m_inFrame{ false };
    bool m_retired{ false };
    std::vector<Command> m_frame;
    uint64_t m_frameSerial{ 0 };
    uint64_t m_lastSignature{ 0 }; // of the last frame queued; 0 = none yet
    RmlTargetTexturePtr m_lastTarget;

    std::mutex m_queueMutex;
    std::vector<Command> m_queue;

    // graphics thread
    RmlBackendPtr m_backend;
    bool m_backendFailed{ false };
    bool m_advancedEffects{ false };
    std::unordered_map<uintptr_t, uintptr_t> m_handles;
    std::vector<uintptr_t> m_frameLayers; // layer handles are only valid inside one frame
};

using RmlRendererPtr = std::shared_ptr<RmlRenderer>;
