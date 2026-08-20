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

#ifndef COCOAWINDOW_H
#define COCOAWINDOW_H

#ifdef CRYSTALOTC_COCOA_WINDOW

#include "platformwindow.h"

// Every Objective-C object this window owns lives behind this handle, defined only inside
// cocoawindow.mm. platformwindow.cpp is compiled as C++ and includes this header to declare
// the global window instance, so no AppKit type may appear here.
struct CocoaWindowImpl;

/**
 * Native macOS platform window: AppKit for the window and input, CAMetalLayer for
 * presentation. See docs/metal-implementation-plan.md, Phase 1.
 *
 * Three properties of this class are load-bearing and easy to break:
 *
 * 1. **It owns no OpenGL context**, so hasGLContext() is false and the whole GL stack
 *    short-circuits the way it already does for the Windows Vulkan path
 *    (Graphics::init, Painter, Texture, Shader all check it). Presentation is a Metal
 *    clear-and-present until a real Metal backend lands in Phase 4.
 *
 * 2. **m_size is in backing pixels and m_displayDensity is the backing scale factor.**
 *    That is not a free choice: GraphicalApplication::resize feeds m_size straight to
 *    g_graphics (and thence to glViewport / Painter::setResolution) while laying the UI
 *    out at m_size / m_displayDensity. AndroidWindow uses the same convention with the
 *    system screen density. Note the codebase does not separate device pixel ratio from
 *    user HUD scale - g_app.setHUDScale writes this same variable - so a user changing
 *    HUD scale also changes the effective point-to-pixel mapping. Separating them is a
 *    framework change, not a window change.
 *
 * 3. **AppKit is main-thread-only, but this window is called from three threads.** Lua
 *    (and therefore every g_window.* binding) runs on the map thread, and the async pool
 *    reads cursors and mouse position. Every method that touches AppKit therefore defers
 *    through g_mainDispatcher, exactly as X11Window and WIN32Window do; that queue is
 *    drained by GraphicalApplication::mainPoll every frame and runs inline when the
 *    caller is already the main thread. terminate() is the sole exception - by then the
 *    dispatchers are shut down and addEvent silently no-ops, so it must work directly.
 */
class CocoaWindow : public PlatformWindow
{
public:
    CocoaWindow();
    // PlatformWindow declares no destructor, virtual or otherwise, so this cannot be an
    // override. The instance is a file-scope object in platformwindow.cpp and is never
    // deleted through a base pointer.
    ~CocoaWindow();

    void init() override;
    void terminate() override;

    void move(const Point& pos) override;
    void resize(const Size& size) override;
    void show() override;
    void hide() override;
    void maximize() override;
    void poll() override;
    void swapBuffers() override;

    // No GL context is ever created on this path; see the class comment.
    bool hasGLContext() const override { return false; }

    void showMouse() override;
    void hideMouse() override;
    void displayFatalError(std::string_view message) override;

    void setMouseCursor(int cursorId) override;
    void restoreMouseCursor() override;

    void setTitle(std::string_view title) override;
    void setMinimumSize(const Size& minimumSize) override;
    void setFullscreen(bool fullscreen) override;
    void setVerticalSync(bool enable) override;
    void setIcon(const std::string& iconFile) override;
    void setClipboardText(std::string_view text) override;

    Size getDisplaySize() override;
    std::string getClipboardText() override;
    std::string getPlatformType() override;

    // Drawable size in pixels. Equal to m_size today, but kept separate because the two
    // diverge for one frame whenever the backing scale changes, and Phase 4's MetalContext
    // must size its drawable from this rather than from the logical window size.
    Size getDrawableSize() const;

    // Called from the AppKit view and delegate objects. Public because Objective-C classes
    // cannot be C++ friends; not part of the PlatformWindow contract. The window-state ones
    // only latch, so the client callbacks fire at the tail of poll(): a live resize drag
    // coalesces into one m_onResize per frame and no client code re-enters from inside an
    // AppKit call.
    void onWindowResized();
    void onWindowMoved();
    void onWindowFocusChanged(bool focused);
    void onWindowCloseRequested();
    void onBackingPropertiesChanged();

    void handleKey(int virtualKeyCode, bool pressed);
    void handleFlagsChanged(unsigned long modifierFlags);
    void handleTextInput(const std::string& utf8Text);
    void handleMouseButton(int button, bool pressed);
    void handleMouseMove(double viewX, double viewY);
    void handleScroll(double deltaY);

protected:
    int internalLoadMouseCursor(const ImagePtr& image, const Point& hotSpot) override;

private:
    void internalCreateApplication();
    void internalCreateWindow();
    void internalPumpEvents();
    void internalApplyPendingGeometry();

    CocoaWindowImpl* m_impl{ nullptr };

    // Backing scale is mirrored here because m_displayDensity is user-writable through
    // g_app.setHUDScale; this is what the drawable is actually sized from.
    float m_backingScale{ 1.f };

    // Previous NSEvent modifier mask. PlatformWindow deliberately does not record modifier
    // keys in m_keyInfo - processKeyDown/processKeyUp return early for Ctrl/Shift/Meta/Alt
    // before setting the pressed state - so isKeyPressed() is always false for them and
    // cannot be used to detect a transition. This is the only usable previous state.
    unsigned long m_modifierFlags{ 0 };

    Size m_pendingSize;
    bool m_pendingResize{ false };
    bool m_closeRequested{ false };

    // Refreshed in poll(), because getClipboardText() is called from the map thread and
    // NSPasteboard must not be touched from there.
    std::string m_clipboardCache;

    friend struct CocoaWindowImpl;
};

#endif // CRYSTALOTC_COCOA_WINDOW

#endif
