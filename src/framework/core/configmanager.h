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

#include "config.h"

struct GraphicsConfig
{
    uint16_t maxAtlasSize = 8192;
    int16_t  mapAtlasSize = 0;
    int16_t foregroundAtlasSize = 2048;

    // Render backend: "gl" (default, current path), "vulkan" (the Windows feeder) or "metal"
    // (macOS, and only with renderPath = "frame"). With "vulkan" and a failed initialization the
    // client falls back to "gl"; with "metal" it falls back to "gl" too, which on a window that
    // never created a GL context means it falls back to drawing nothing and says so.
    //
    // Leaving this at "gl" does NOT force OpenGL on the frame path: it is the default value and
    // the Vulkan feeder's "not vulkan", so it carries no intent. The frame path resolves its
    // backend by capability unless this says "metal" outright, or --render-backend= /
    // CRYSTALOTC_RENDER_BACKEND does.
    std::string renderBackend = "gl";

    // Which renderer executes a frame: "legacy" (default) or "frame".
    //
    // Orthogonal to renderBackend, which picks the GRAPHICS API. This picks how the frame
    // reaches it: "legacy" replays DrawPool objects onto Painter, "frame" compiles them into an
    // explicit RenderFrame and hands that to a backend. Both are OpenGL today, and they are
    // meant to be pixel-identical - which is the whole reason both exist at once.
    //
    // Overridden, in order, by --render-path=<value> and CRYSTALOTC_RENDER_PATH.
    std::string renderPath = "legacy";
};

struct FontConfig
{
    std::string widget;
    std::string staticText;
    std::string animatedText;
    std::string creatureText;
    std::string itemCount;
};

struct DebugConfig
{
    // Periodic memory/renderer diagnostics ([gc], [mem], [boot], [vulkan] frame stats).
    // Off by default - enable in config.ini ([debug] memoryLog = 1) when hunting RAM issues.
    bool memoryLog = false;
};

struct PublicConfig
{
    GraphicsConfig graphics;
    FontConfig font;
    DebugConfig debug;
};

// @bindsingleton g_configs
class ConfigManager
{
public:
    void init();
    void terminate();

    ConfigPtr getSettings();
    ConfigPtr get(const std::string& file);

    ConfigPtr create(const std::string& file);
    ConfigPtr loadSettings(const std::string& file);
    ConfigPtr load(const std::string& file);

    bool unload(const std::string& file);

    // Saves the render backend choice to config.ini so it survives a restart.
    // The engine reads this value at STARTUP, so the change only takes effect after relaunching.
    // Called from the graphics options in the client (modules/client_options).
    void setRenderBackend(const std::string& backend);

    // The actual backend from config.ini (loaded at startup) - the graphics options synchronize
    // the engine list with it, so after a manual config.ini edit it doesn't show a stale choice.
    std::string getRenderBackend() { return m_publicConfig.graphics.renderBackend; }
    void remove(const ConfigPtr& config);

    void saveSettings();

    const PublicConfig& getPublicConfig() const { return m_publicConfig; }
    void loadPublicConfig(const std::string& file);

protected:
    ConfigPtr m_settings;

private:
    std::list<ConfigPtr> m_configs;
    PublicConfig m_publicConfig;
};

extern ConfigManager g_configs;
