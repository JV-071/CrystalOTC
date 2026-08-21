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

#include "../irenderbackend.h"

#include <memory>

/*
 * MetalBackend - the second consumer of a RenderFrame, and the first one that owns anything.
 *
 * GLBackend was the control experiment: it proved the frame model describes the client's real
 * behaviour by making the reference renderer run on it and comparing the pixels. This one is the
 * point of the exercise. It shares no code with the OpenGL path, holds no Painter, and reaches
 * nothing below the boundary except the frame it is handed.
 *
 * THREE DECISIONS ARE WORTH KNOWING BEFORE READING THE IMPLEMENTATION.
 *
 * It PRESENTS. Phase 1 left presentation ownership contested between CocoaWindow::swapBuffers and
 * IRenderBackend::render; this settles it in favour of the backend, because a drawable may only be
 * presented by the command buffer that rendered into it, and because acquiring one as late as
 * possible is the whole reason the acquisition is separate from the encoding. The window stands
 * down for as long as this backend lives (PlatformWindow::setPresentationOwned).
 *
 * It renders into its OWN offscreen backbuffer and blits that into the drawable. The extra
 * full-screen copy buys two things worth more than it costs: a drawable can never be read after it
 * is presented, so a screenshot taken between frames - which is exactly how every renderer
 * baseline is captured - has something to read; and a frame that finds no drawable available
 * loses only its presentation rather than its work.
 *
 * It draws BUILT-IN MATERIALS ONLY. The 27 registered module programs are GLSL, and translating
 * them is the Phase 6 toolchain's job; until then they draw as ordinary textured geometry, which
 * is the fallback the design document specifies and which reads on screen as a missing effect
 * rather than as a missing object.
 */
class MetalBackend final : public IRenderBackend
{
public:
    MetalBackend();
    ~MetalBackend() override;

    bool initialize() override;
    void shutdown() override;
    void resize(const Size& drawableSize) override;
    bool render(const RenderFrame& frame) override;
    bool readPixels(const ReadbackRequest& request, ReadbackResult& out) override;

    [[nodiscard]] const char* name() const override { return "metal"; }

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

#endif // CRYSTALOTC_COCOA_WINDOW
