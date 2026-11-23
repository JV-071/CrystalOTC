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

#include <cstdint>

class RenderInterface_GL3;

// OpenGL executor: RmlUi's own GL3 backend (RmlUi_Renderer_GL3) compositing each frame into
// the widget's texture through a framebuffer object. The same code serves desktop OpenGL 3.3
// and, in OPENGL_ES builds, OpenGL ES 3 on ANGLE.
class RmlBackendGL final : public RmlBackend
{
public:
    // nullptr when the GL3 backend cannot be set up on the current context (e.g. its shaders
    // do not compile). Needs a current OpenGL context.
    static RmlBackendPtr create();
    static std::string backendName();

    ~RmlBackendGL() override;

    std::string name() const override { return backendName(); }
    bool supportsAdvancedEffects() const override { return true; }
    Rml::RenderInterface& renderInterface() override;

    void beginReplay() override;
    void endReplay() override;
    void beginFrame(const RmlTargetTexturePtr& target) override;
    void endFrame() override;

private:
    explicit RmlBackendGL(std::unique_ptr<RenderInterface_GL3> gl);

    std::unique_ptr<RenderInterface_GL3> m_gl;
    uint32_t m_fbo{ 0 };
    RmlTargetTexture* m_attachedTarget{ nullptr };
    // Keeps the attached texture alive, so a new target can never reuse its address while the
    // framebuffer still points at the old one.
    RmlTargetTexturePtr m_target;

    // The GL state the client's painter caches or relies on (bound framebuffer, shader program,
    // texture, array buffer and vertex array). RmlUi's backend changes all of it - not only while
    // drawing, also when it is created (it compiles its shaders and leaves no program bound) and
    // destroyed - so every entry point of this class restores what it found.
    struct ClientState
    {
        int fbo{ 0 };
        int program{ 0 };
        int activeTexture{ 0 };
        int texture{ 0 };
        int arrayBuffer{ 0 };
        int vao{ 0 };

        void save();
        void restore() const;
    };

    ClientState m_clientState; // captured by beginReplay(), restored by endReplay()
};
