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

#include "rmlbackend_gl.h"
#include "RmlUi_Renderer_GL3.h"
#include "rmlrenderer.h"

#include <framework/core/logger.h>
#include <framework/graphics/glutil.h>
#include <framework/graphics/graphics.h>

void RmlBackendGL::ClientState::save()
{
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo);
    glGetIntegerv(GL_CURRENT_PROGRAM, &program);
    glGetIntegerv(GL_ACTIVE_TEXTURE, &activeTexture);
    glActiveTexture(GL_TEXTURE0);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture);
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &arrayBuffer);
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vao);
}

void RmlBackendGL::ClientState::restore() const
{
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glUseProgram(program);
    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, arrayBuffer);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture);
    glActiveTexture(activeTexture);
}

RmlBackendPtr RmlBackendGL::create()
{
    // Creating the GL3 backend compiles its shader programs and ends with no program bound,
    // while the painter keeps believing its own program is current. Draws issued right after
    // would then fail silently - including the copy of pending textures (fonts) into the
    // texture atlas, which would stay blank for good.
    ClientState client;
    client.save();

    auto gl = std::make_unique<RenderInterface_GL3>();
    const bool valid = static_cast<bool>(*gl);
    if (!valid)
        gl.reset();

    client.restore();

    return valid ? RmlBackendPtr(new RmlBackendGL(std::move(gl))) : nullptr;
}

std::string RmlBackendGL::backendName()
{
#ifdef OPENGL_ES
    return "OpenGL ES 3";
#else
    return "OpenGL 3.3";
#endif
}

RmlBackendGL::RmlBackendGL(std::unique_ptr<RenderInterface_GL3> gl) : m_gl(std::move(gl)) {}

RmlBackendGL::~RmlBackendGL()
{
    if (!g_graphics.ok()) {
        // The GL context is already gone (client shutdown) and took its objects with it; the
        // GL3 backend's destructor would issue GL calls, so it is deliberately not run.
        (void)m_gl.release();
        return;
    }

    // Deleting the backend's objects (and, with the last backend, the shared shader programs)
    // must not disturb the client either.
    ClientState client;
    client.save();

    m_gl.reset();
    if (m_fbo)
        glDeleteFramebuffers(1, &m_fbo);

    client.restore();
}

Rml::RenderInterface& RmlBackendGL::renderInterface() { return *m_gl; }

void RmlBackendGL::beginReplay()
{
    m_clientState.save();
}

void RmlBackendGL::endReplay()
{
    m_clientState.restore();
}

void RmlBackendGL::beginFrame(const RmlTargetTexturePtr& target)
{
    auto* const raw = target.get();
    raw->realize();

    if (!m_fbo)
        glGenFramebuffers(1, &m_fbo);

    if (m_attachedTarget != raw) {
        glBindFramebuffer(GL_FRAMEBUFFER, m_fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, raw->getId(), 0);
        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
            g_logger.warning("[rmlui] widget framebuffer is incomplete");
        m_attachedTarget = raw;
        m_target = target;
    }

    m_gl->SetViewport(raw->getWidth(), raw->getHeight());
    m_gl->SetTargetFramebuffer(m_fbo);
    m_gl->BeginFrame();

    // BeginFrame() bound its first layer; clear our target (blending happens onto it at EndFrame).
    GLint layerFbo = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &layerFbo);
    glBindFramebuffer(GL_FRAMEBUFFER, m_fbo);
    glClear(GL_COLOR_BUFFER_BIT);
    glBindFramebuffer(GL_FRAMEBUFFER, layerFbo);
}

void RmlBackendGL::endFrame()
{
    m_gl->EndFrame();
}
