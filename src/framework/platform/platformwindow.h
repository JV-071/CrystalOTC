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

#include <framework/core/inputevent.h>
#include <framework/core/timer.h>
#include <framework/global.h>
#include <framework/graphics/declarations.h>

 // Forward declaration
class Color;

// ---------------------------------------------------------------------------------------
// The presentation surface a GPU backend draws onto.
//
// `getNativeWindowHandle()` below already exists for Vulkan, but it is a bare `void*` whose
// meaning is "an HWND, on the one platform that has one" - the exact thing the architecture
// document says the generic window interface must stop claiming. This is the typed form: the
// tag says what the pointers are, and a backend that does not recognise the tag refuses to
// initialise rather than casting hopefully.
//
// It is deliberately not an owning handle. The layer belongs to the view, which AppKit
// resizes with the window; the backend borrows it for the lifetime of the window.
// ---------------------------------------------------------------------------------------
enum class NativeSurfaceType : uint8_t
{
    None = 0,
    CocoaMetalLayer, // layer = CAMetalLayer*, device = id<MTLDevice>
};

struct NativeSurface
{
    NativeSurfaceType type{ NativeSurfaceType::None };
    void* layer{ nullptr };
    void* device{ nullptr };

    [[nodiscard]] bool isValid() const { return type != NativeSurfaceType::None && layer != nullptr; }
};

//@bindsingleton g_window
class PlatformWindow
{
    enum
    {
        KEY_PRESS_REPEAT_INTERVAL = 30,
    };

    struct KeyInfo
    {
        ticks_t firstTicks = 0;
        ticks_t lastTicks = 0;
        bool state = false;
        uint8_t delay = KEY_PRESS_REPEAT_INTERVAL;
    };

    using OnResizeCallback = std::function<void(const Size&)>;
    using OnInputEventCallback = std::function<void(const InputEvent&)>;

public:
    virtual void init() = 0;
    virtual void terminate() = 0;

    // Native window handle for the Vulkan renderer (Win32 surface). None by default -
    // platforms without support simply return no handle and Vulkan stays disabled.
    virtual void* getNativeWindowHandle() const { return nullptr; }

    // The typed presentation surface, for a backend that presents its own frames. Invalid by
    // default: a platform that does not offer one simply cannot host such a backend.
    [[nodiscard]] virtual NativeSurface getNativeSurface() const { return {}; }

    // PRESENTATION OWNERSHIP, settled here rather than left implicit.
    //
    // The render loop calls swapBuffers() unconditionally after drawing, which is right when
    // the window is what presents - GL's buffer swap, and the Cocoa window's own
    // acquire-clear-present. A backend that acquires the drawable itself must present it
    // itself, because a drawable can only be presented by the command buffer that rendered
    // into it; two presents per frame would show the backend's work and then immediately
    // overwrite it. So such a backend claims presentation at initialize() and releases it at
    // shutdown(), and the window stands down for as long as the claim stands.
    virtual void setPresentationOwned(bool /*owned*/) {}

    virtual void move(const Point& pos) = 0;
    virtual void resize(const Size& size) = 0;
    virtual void show() = 0;
    virtual void hide() = 0;
    virtual void maximize() = 0;
    virtual void poll() = 0;
    virtual void swapBuffers() = 0;

    // Vulkan mode starts without an OpenGL context (a loaded GL driver alone is 100+ MB
    // of process memory). hasGLContext() tells whether GL exists; ensureGLContext() creates
    // it on the fly when the Vulkan init fails and we must fall back to the GL path.
    virtual bool hasGLContext() const { return true; }
    virtual void ensureGLContext() {}
    virtual void showMouse() = 0;
    virtual void hideMouse() = 0;
    virtual void displayFatalError(const std::string_view /*message*/) {}

    virtual int loadMouseCursor(const std::string& file, const Point& hotSpot);
    virtual void setMouseCursor(int cursorId) = 0;
    virtual void restoreMouseCursor() = 0;
    virtual void setSystemCursor(const std::string& cursorName) {}

    virtual void setTitle(std::string_view title) = 0;
    virtual void setMinimumSize(const Size& minimumSize) = 0;
    virtual void setFullscreen(bool fullscreen) = 0;
    virtual void setVerticalSync(bool enable) = 0;
    virtual void setIcon(const std::string& iconFile) = 0;
    virtual void setClipboardText(std::string_view text) = 0;

    // This method is intentionally left empty because title bar color customization
    // is only supported on Windows 10/11 via the DWM API. On other platforms,
    // or when not implemented in the derived class, this method does nothing.
    // Derived classes should override this method to provide platform-specific behavior.
    virtual void setTitleBarColor(const Color& /*color*/) {}

    // Convenience methods for setting title bar color
    // Usage examples:
    //   g_window.setTitleBarColor(255, 0, 0);           // Red (RGB 0-255)
    //   g_window.setTitleBarColor(1.0f, 0.0f, 0.0f);    // Red (float 0.0-1.0)
    //   g_window.setTitleBarColorRGB(0, 128, 255);       // Blue
    //   g_window.setTitleBarColor(Color::darkBlue);      // Using predefined color
    void setTitleBarColor(int r, int g, int b);
    void setTitleBarColor(float r, float g, float b);
    void setTitleBarColorRGB(uint8_t r, uint8_t g, uint8_t b);

    // Wide-gamut presentation. macOS colour-matches our rendered frames from sRGB into the
    // display's space; on a Display P3 panel that is a real gamut compression, and since the
    // artwork is authored and tagged sRGB it is also the correct thing to do. The official
    // client does no colour matching at all, so the same bytes land on a P3 panel unconverted
    // and read as roughly 13% more saturated. Enabling this drops our colour match to reproduce
    // that look. Only CocoaWindow implements it - every other platform already presents frames
    // unmanaged, so there is nothing to turn off and both methods stay at their defaults.
    virtual void setVividColors(bool /*enable*/) {}
    virtual bool isVividColorsSupported() { return false; }

    virtual Size getDisplaySize() = 0;
    virtual std::string getClipboardText() = 0;
    virtual std::string getPlatformType() = 0;

    int getDisplayWidth() { return getDisplaySize().width(); }
    int getDisplayHeight() { return getDisplaySize().height(); }
    // The EFFECTIVE logical-to-device scale: the product of the two independent inputs below.
    // Everything that converts between UI units and pixels wants this one.
    float getDisplayDensity() { return m_displayDensity; }

    // How many device pixels the display puts behind one point. Owned by the platform layer,
    // which reads it from the window server; the user never sets it.
    float getDevicePixelRatio() const { return m_devicePixelRatio; }
    void setDevicePixelRatio(const float v) { updateScales(v, m_hudScale); }

    // How much larger than default the user wants the interface. Owned by the user; the platform
    // never sets it.
    //
    // These were ONE variable until 2026-08-25, and the conflation was not harmless. Setting a
    // HUD scale overwrote the display's pixel ratio, so on a display with a ratio of 2 asking for
    // HUD scale 1 laid the whole interface out at device resolution - every widget half the size
    // it should be - while asking for 2 changed nothing at all, because the value was already 2.
    // In the other direction, moving the window to a display with a different backing scale
    // silently discarded whatever the user had chosen.
    float getHUDScale() const { return m_hudScale; }
    void setHUDScale(const float v) { updateScales(m_devicePixelRatio, v); }

    Size getUnmaximizedSize() { return m_unmaximizedSize; }
    Size getSize() { return m_size; }
    Size getMinimumSize() { return m_minimumSize; }
    int getWidth() { return m_size.width(); }
    int getHeight() { return m_size.height(); }
    Point getUnmaximizedPos() { return m_unmaximizedPos; }
    Point getPosition() { return m_position; }
    int getX() { return m_position.x; }
    int getY() { return m_position.y; }
    Point getMousePosition() { return m_inputEvent.mousePos; }
    int getKeyboardModifiers() { return m_inputEvent.keyboardModifiers; }

    // Bounds-checked because this is bound straight into Lua, and const.lua declares key
    // codes up to 167 (KeyNumpadDivide) while m_keyInfo only has Fw::KeyLast entries.
    bool isKeyPressed(const Fw::Key keyCode) { return keyCode < Fw::KeyLast && m_keyInfo[keyCode].state; }
    bool isMouseButtonPressed(const Fw::MouseButton mouseButton)
    { if (mouseButton == Fw::MouseNoButton) return m_mouseButtonStates != 0; return (m_mouseButtonStates & (1u << mouseButton)) == (1u << mouseButton); }
    bool isVisible() { return m_visible; }
    bool isMaximized() { return m_maximized; }
    bool isFullscreen() { return m_fullscreen; }
    bool hasFocus() { return m_focused; }

    bool vsyncEnabled() const { return m_vsync; }

    void setOnClose(const std::function<void()>& onClose) { m_onClose = onClose; }
    void setOnResize(const OnResizeCallback& onResize) { m_onResize = onResize; }
    void setOnInputEvent(const OnInputEventCallback& onInputEvent) { m_onInputEvent = onInputEvent; }

    void addKeyListener(std::function<void(const InputEvent&)> listener) { m_keyListeners.push_back(listener); }

    void setKeyDelay(const Fw::Key key, const uint8_t delay) { if (key < Fw::KeyLast) m_keyInfo[key].delay = delay; }

protected:

    virtual int internalLoadMouseCursor(const ImagePtr& image, const Point& hotSpot) = 0;

    virtual void onDisplayDensityChanged(float /*newDensity*/) {}

    void updateUnmaximizedCoords();

    void processKeyDown(Fw::Key keyCode);
    void processKeyUp(Fw::Key keyCode);
    void releaseAllKeys();
    void fireKeysPress();

    stdext::map<int, Fw::Key> m_keyMap;
    std::array<KeyInfo, Fw::KeyLast> m_keyInfo = {};
    Timer m_keyPressTimer;

    Size m_size;
    Size m_minimumSize;
    Point m_position;
    Size m_unmaximizedSize;
    Point m_unmaximizedPos;
    InputEvent m_inputEvent;

    uint32_t m_mouseButtonStates{ 0 };

    bool m_created{ false };
    bool m_visible{ false };
    bool m_focused{ false };
    bool m_fullscreen{ false };
    bool m_maximized{ false };
    bool m_vsync{ false };
    // m_displayDensity is the cached product of the two below, kept as a member rather than
    // computed so that platform code reading it directly on a hot path stays cheap.
    float m_displayDensity{ DEFAULT_DISPLAY_DENSITY };
    float m_devicePixelRatio{ DEFAULT_DISPLAY_DENSITY };
    float m_hudScale{ 1.f };

    void updateScales(const float ratio, const float hud)
    {
        const float safeRatio = ratio > 0.f ? ratio : 1.f;
        const float safeHud = hud > 0.f ? hud : 1.f;
        const float effective = safeRatio * safeHud;

        m_devicePixelRatio = safeRatio;
        m_hudScale = safeHud;

        if (m_displayDensity == effective)
            return;

        m_displayDensity = effective;
        onDisplayDensityChanged(effective);
    }

    std::function<void()> m_onClose;
    OnResizeCallback m_onResize;
    OnInputEventCallback m_onInputEvent;

    std::vector<std::function<void(const InputEvent&)>> m_keyListeners;
};

extern PlatformWindow& g_window;
