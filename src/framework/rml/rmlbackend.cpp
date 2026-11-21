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

#include "rmlbackend.h"
#include "rmlbackend_gl.h"

#include <framework/core/logger.h>
#include <framework/platform/platformwindow.h>

RmlBackendPtr createRmlBackend()
{
    // Without an OpenGL context the client is drawing with its Vulkan renderer. RmlUi has no
    // executor for it yet and must never create a GL context of its own to get one.
    if (!g_window.hasGLContext()) {
        g_logger.warning("[rmlui] no executor for the active render backend");
        return nullptr;
    }

    auto backend = RmlBackendGL::create();
    if (!backend)
        g_logger.error("[rmlui] could not create the {} renderer; RmlUi widgets will stay empty", RmlBackendGL::backendName());
    return backend;
}

std::string rmlExpectedBackendName()
{
    return g_window.hasGLContext() ? RmlBackendGL::backendName() : "none";
}
