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

#include <memory>
#include <string>

namespace Rml { class RenderInterface; }

class RmlTargetTexture;
using RmlTargetTexturePtr = std::shared_ptr<RmlTargetTexture>;

// Executes RmlUi's render calls with real GPU handles, for one UIRmlWidget.
//
// RmlRenderer records what RmlUi asks for on the UI thread and replays it here on the
// graphics thread, so every method below runs on the graphics thread only. There is one
// implementation per way the client can draw (OpenGL / OpenGL ES today).
class RmlBackend
{
public:
    virtual ~RmlBackend() = default;

    virtual std::string name() const = 0;
    // Layers, filters and shaders (box-shadow, filter, gradients, mask-image): the "efeitos" theme.
    virtual bool supportsAdvancedEffects() const = 0;

    // The interface that runs RmlUi's calls. Handles passed to it are the ones it returned.
    virtual Rml::RenderInterface& renderInterface() = 0;

    // Around each batch of replayed commands: save and restore the GPU state the client caches.
    virtual void beginReplay() = 0;
    virtual void endReplay() = 0;

    // Around the commands of one RmlUi frame, composited into target.
    virtual void beginFrame(const RmlTargetTexturePtr& target) = 0;
    virtual void endFrame() = 0;
};

using RmlBackendPtr = std::unique_ptr<RmlBackend>;

// The executor for the way the client is drawing right now. Graphics thread.
// nullptr, with one "[rmlui]" log line, when there is none (no OpenGL context: pure-Vulkan mode)
// or when it cannot be set up on this GPU.
RmlBackendPtr createRmlBackend();

// The name the executor created by createRmlBackend() reports; "none" when there is no executor.
std::string rmlExpectedBackendName();
