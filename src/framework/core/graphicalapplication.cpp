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

#include "graphicalapplication.h"

#include "asyncdispatcher.h"
#include "clock.h"
#include "configmanager.h"
#include "eventdispatcher.h"
#include "garbagecollection.h"
#include "framework/graphics/drawpoolmanager.h"
#include "framework/graphics/graphics.h"
#include "framework/graphics/image.h"
#include "framework/graphics/particlemanager.h"
#include "framework/graphics/texture.h"
#include "framework/graphics/texturemanager.h"
#include "framework/input/mouse.h"
#include "framework/ui/uimanager.h"
#include <framework/util/stats.h>

#ifdef FRAMEWORK_SOUND
#include <framework/sound/soundmanager.h>
#endif

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#endif
#include <framework/html/htmlmanager.h>
#include <framework/platform/platformwindow.h>

#ifdef WIN32
// The Vulkan surface exists only for Win32 for now, so the frame loop comes into
// play only there - the remaining platforms compile exactly as before.
#include <framework/graphics/vulkan/vkcontext.h>
#include <framework/graphics/vulkan/vkfeeder.h>
#endif

GraphicalApplication g_app;

namespace
{
    // Opt-in loop timing ([debug] perfLog = 1 in config.ini) for hunting stutters on player machines.
    // Every thread owns its own instance, so nothing here is shared or locked. With the flag off the
    // loops never touch it.
    class LoopTimeLog
    {
    public:
        explicit LoopTimeLog(const char* name) : m_name(name) {}

        // Records one iteration (busy time, without the frame limiter sleep). Returns true when the
        // iteration is a hitch the caller should describe, at most MAX_HITCH_LINES per window.
        bool add(const ticks_t micros)
        {
            const auto ms = static_cast<size_t>(std::clamp<ticks_t>(micros / 1000, 0, BUCKETS - 1));
            ++m_histogram[ms];
            ++m_count;
            m_maxMicros = std::max(m_maxMicros, micros);

            if (micros < HITCH_MICROS)
                return false;

            ++m_hitches;
            return m_hitchLines++ < MAX_HITCH_LINES;
        }

        void reportIfDue(const ticks_t nowMillis)
        {
            if (m_windowStart == 0)
                m_windowStart = nowMillis;

            if (nowMillis - m_windowStart < WINDOW_MILLIS || m_count == 0)
                return;

            g_logger.info("[perf] {} loop, last {} s: {} iterations, p50 {} ms, p99 {} ms, max {:.1f} ms, hitches {}",
                          m_name, (nowMillis - m_windowStart) / 1000, m_count, percentile(50), percentile(99),
                          m_maxMicros / 1000.0, m_hitches);

            m_histogram.fill(0);
            m_count = 0;
            m_hitches = 0;
            m_hitchLines = 0;
            m_maxMicros = 0;
            m_windowStart = nowMillis;
        }

    private:
        static constexpr size_t BUCKETS = 256;
        static constexpr ticks_t HITCH_MICROS = 40 * 1000;
        static constexpr uint32_t MAX_HITCH_LINES = 10;
        static constexpr ticks_t WINDOW_MILLIS = 10 * 1000;

        // whole milliseconds, rounded down
        size_t percentile(const uint32_t pct) const
        {
            const uint64_t target = (static_cast<uint64_t>(m_count) * pct + 99) / 100;
            uint64_t seen = 0;
            for (size_t i = 0; i < BUCKETS; ++i) {
                seen += m_histogram[i];
                if (seen >= target)
                    return i;
            }
            return BUCKETS - 1;
        }

        const char* m_name;
        std::array<uint32_t, BUCKETS> m_histogram{};
        uint32_t m_count{ 0 };
        uint32_t m_hitches{ 0 };
        uint32_t m_hitchLines{ 0 };
        ticks_t m_maxMicros{ 0 };
        ticks_t m_windowStart{ 0 };
    };

    // time of the last GarbageCollection::poll, read by the map loop hitch line
    ticks_t s_lastGcMicros = 0;
}

void GraphicalApplication::init(std::vector<std::string>& args, ApplicationContext* context)
{
    Application::init(args, context);

    auto graphicalContext = static_cast<GraphicalApplicationContext*>(context);
    setDrawEvents(graphicalContext->getDrawEvents());

    // setup platform window
    g_window.init();
    g_window.hide();

    // set the window title color
    g_window.setTitleBarColor(Color::black);

    g_window.setOnResize([this](auto&& PH1) {
        if (!m_running) resize(PH1);
        else g_dispatcher.addEvent([&, PH1] { resize(PH1); });
    });

    g_window.setOnInputEvent([this](auto&& PH1) {
        if (!m_running) inputEvent(PH1);
        else g_dispatcher.addEvent([&, PH1] { inputEvent(PH1); });
    });

    g_window.setOnClose([this] { g_dispatcher.addEvent([this] { close(); }); });

    g_mouse.init();

    // initialize ui
    g_ui.init();

    // initialize graphics
    g_graphics.init();
    g_drawPool.init(graphicalContext->getSpriteSize());

    // fire first resize event
    resize(g_window.getSize());

#ifdef FRAMEWORK_SOUND
    // initialize sound
    g_sounds.init();
#endif

    m_mapProcessFrameCounter.init();
    m_graphicFrameCounter.init();
}

void GraphicalApplication::deinit()
{
    // hide the window because there is no render anymore
    g_window.hide();

    Application::deinit();
}

void GraphicalApplication::terminate()
{
    // destroy particles
    g_particles.terminate();

    // destroy any remaining widget
    g_html.terminate();
    g_ui.terminate();

    Application::terminate();
    m_terminated = false;

#ifdef FRAMEWORK_SOUND
    // terminate sound
    g_sounds.terminate();
#endif

    g_mouse.terminate();

    // terminate graphics
    g_drawPool.terminate();
    g_graphics.terminate();
    g_window.terminate();

    m_terminated = true;
}

#ifdef __EMSCRIPTEN__
void GraphicalApplication::mainLoop() {
    if (m_stopping) {
        emscripten_cancel_main_loop();
        MAIN_THREAD_EM_ASM({ window.location.reload(); });
        return;
    }
    mainPoll();

    if (!g_window.isVisible()) {
        stdext::millisleep(10);
        return;
    }

    const auto FPS = [this] {
        // The map thread emitted tiles up to 500 times per second (and without vsync/FPS limit - with
        // no ceiling at all), even though the screen shows 60-144 frames. With a static scene DrawPool::release
        // throws all that work away anyway because the hash didn't change - so idling burned a whole core.
        // A ceiling of 2x the render FPS leaves headroom for smoothness and cuts CPU usage severalfold.
        const uint16_t graphicsFps = m_graphicFrameCounter.getFps();
        m_mapProcessFrameCounter.setTargetFps(std::clamp<uint16_t>(graphicsFps * 2, 60u, 240u));
        return graphicsFps;
    };

    {
        AUTO_STAT(STATS_RENDER, "DrawPool");
        g_drawPool.draw();
    }

    if (m_graphicFrameCounter.update()) {
        g_dispatcher.addEvent([this, fps = FPS()] {
            g_lua.callGlobalField("g_app", "onFps", fps);
        });
    }
}
#endif

bool GraphicalApplication::canDrawMap() const {
    using enum DrawPoolType;

    if (!m_drawEvents->canDraw(MAP))
        return false;

    static constexpr std::array<DrawPoolType, 3> types{ MAP, LIGHT, FOREGROUND_MAP };

    for (DrawPoolType type : types) {
        if (g_drawPool.isDrawing(type))
            return false;
    }
    return true;
}

void GraphicalApplication::run()
{
    // run the first poll
    mainPoll();
    poll();

    // show window
    g_window.show();

    // run the second poll
    mainPoll();
    poll();

    g_lua.callGlobalField("g_app", "onRun");

#ifndef __EMSCRIPTEN__
    const auto FPS = [this] {
        // The map thread emitted tiles up to 500 times per second (and without vsync/FPS limit - with
        // no ceiling at all), even though the screen shows 60-144 frames. With a static scene DrawPool::release
        // throws all that work away anyway because the hash didn't change - so idling burned a whole core.
        // A ceiling of 2x the render FPS leaves headroom for smoothness and cuts CPU usage severalfold.
        const uint16_t graphicsFps = m_graphicFrameCounter.getFps();
        m_mapProcessFrameCounter.setTargetFps(std::clamp<uint16_t>(graphicsFps * 2, 60u, 240u));
        return graphicsFps;
    };
#endif
    // THREAD - POOL & MAP
    const auto& mapThread = g_asyncDispatcher.submit_task([this] {
        BS::multi_future<void> tasks;

        g_luaThreadId = g_eventThreadId = stdext::getThreadId();

        const bool perfLog = g_configs.getPublicConfig().debug.perfLog;
        LoopTimeLog loopLog("map");

        while (!m_stopping) {
            const ticks_t loopStart = perfLog ? stdext::micros() : 0;

            poll();

            if (!g_window.isVisible()) {
                stdext::millisleep(10);
                continue;
            }

            const ticks_t pollEnd = perfLog ? stdext::micros() : 0;
            ticks_t mapEnd = 0;
            bool uiRendered = false;

            const bool canDrawForeground = !g_drawPool.isDrawing(DrawPoolType::FOREGROUND) && m_drawEvents->canDraw(DrawPoolType::FOREGROUND);

            if (canDrawMap()) {
                uiRendered = canDrawForeground;

                if (canDrawForeground) {
                    tasks.emplace_back(g_asyncDispatcher.submit_task([] {
                        AUTO_STAT(STATS_RENDER, "DrawForegroundUI");
                        g_ui.render(DrawPoolType::FOREGROUND);
                    }));
                }

                {
                    AUTO_STAT(STATS_RENDER, "DrawPreload");
                    m_drawEvents->preLoad();
                }
                static constexpr std::array<DrawPoolType, 2> types{ DrawPoolType::LIGHT, DrawPoolType::FOREGROUND_MAP };
                for (const auto type : types) {
                    if (m_drawEvents->canDraw(type)) {
                        tasks.emplace_back(g_asyncDispatcher.submit_task([this, type] {
                            AUTO_STAT(STATS_RENDER, type == DrawPoolType::LIGHT ? "DrawLight" : "DrawForegroundMap");
                            m_drawEvents->draw(type);
                        }));
                    }
                }

                {
                    AUTO_STAT(STATS_RENDER, "DrawMap");
                    m_drawEvents->draw(DrawPoolType::MAP);
                }

                if (perfLog)
                    mapEnd = stdext::micros();

                tasks.wait();
                tasks.clear();
            } else if (canDrawForeground) {
                uiRendered = true;
                AUTO_STAT(STATS_RENDER, "DrawForegroundUI");
                g_ui.render(DrawPoolType::FOREGROUND);
            }

            if (perfLog) {
                const ticks_t loopEnd = stdext::micros();

                if (loopLog.add(loopEnd - loopStart)) {
                    // "map" covers preload and the map pool, "wait" is the time spent waiting
                    // for the UI, light and foreground map tasks after the map was done
                    g_logger.info("[hitch] map loop {:.1f} ms: poll {:.1f} ms (gc {:.1f} ms), map {:.1f} ms, wait {:.1f} ms, ui {}",
                                  (loopEnd - loopStart) / 1000.0, (pollEnd - loopStart) / 1000.0, s_lastGcMicros / 1000.0,
                                  mapEnd ? (mapEnd - pollEnd) / 1000.0 : 0.0,
                                  mapEnd ? (loopEnd - mapEnd) / 1000.0 : 0.0,
                                  uiRendered ? "yes" : "no");
                }

                loopLog.reportIfDue(stdext::millis());
            }

            m_mapProcessFrameCounter.update();
        }
    });

#ifdef __EMSCRIPTEN__
    m_running = true;
    emscripten_set_main_loop(([] { g_app.mainLoop(); }), 0, 1);
#else
    m_running = true;

    const bool perfLog = g_configs.getPublicConfig().debug.perfLog;
    LoopTimeLog renderLoopLog("render");

    while (!m_stopping) {
        const ticks_t loopStart = perfLog ? stdext::micros() : 0;

        mainPoll();

        if (!g_window.isVisible()) {
            stdext::millisleep(10);
            continue;
        }

        const ticks_t pollEnd = perfLog ? stdext::micros() : 0;

#ifdef WIN32
        // Stage 4: with a working Vulkan batch the draw queue is NOT executed by
        // OpenGL - the feeder translates it into batch triangles, and GL gets no work at all
        // this frame. When the batch doesn't work (missing .spv etc.), the old pair remains: GL draws,
        // Vulkan only clears the screen and shows the fallback scene - then at least it's visibly alive.
        auto& vkCtx = VkContext::instance();
        const bool vkGameFrame = vkCtx.isReady() && vkCtx.getBatch().isReady();
#endif
        {
            AUTO_STAT(STATS_RENDER, "DrawPool");
#ifdef WIN32
            if (vkGameFrame)
                VkDrawFeeder::instance().feedFrame(vkCtx.getBatch(), vkCtx.getExtent());
            else if (g_window.hasGLContext())
                g_drawPool.draw();
            else {
                // Vulkan died mid-session and a GL context was never created (pure VK
                // mode) - there is nothing to draw with. We consume the pool flags so the map thread
                // doesn't jam (canDrawMap waits for consumption), and leave a frozen image
                // instead of a crash on null-GL.
                VkDrawFeeder::instance().consumeAllPools();
            }
#else
            g_drawPool.draw();
#endif
        }

        const ticks_t drawEnd = perfLog ? stdext::micros() : 0;

        // update screen pixels
        {
            AUTO_STAT(STATS_RENDER, "SwapBuffers");

            // When the Vulkan context doesn't exist or dies along the way (drawFrame returns false
            // and shuts itself down), we immediately fall back to swapBuffers - and since the feeder
            // also stops being called then, the next frame goes entirely down the GL path.
            // Clear color: black under a game frame, navy under the fallback scene
            // (we can tell them apart with the naked eye).
#ifdef WIN32
            if (!vkCtx.isReady() || !vkCtx.drawFrame(vkGameFrame ? 0.0f : 0.05f,
                                                     vkGameFrame ? 0.0f : 0.10f,
                                                     vkGameFrame ? 0.0f : 0.25f)) {
                if (vkGameFrame) {
                    // The feeder consumed the pool flags and GL drew nothing this frame. Without
                    // forcing a repaint, the GL fallback would show framebuffers that nobody
                    // ever filled in Vulkan mode (black map until the hash changes).
                    for (int8_t i = -1; ++i < static_cast<int8_t>(DrawPoolType::LAST);)
                        g_drawPool.get(static_cast<DrawPoolType>(i))->repaint();
                }
                g_window.swapBuffers();
            }
#else
            g_window.swapBuffers();
#endif
        }

        if (perfLog) {
            const ticks_t loopEnd = stdext::micros();

            if (renderLoopLog.add(loopEnd - loopStart)) {
                g_logger.info("[hitch] render loop {:.1f} ms: poll {:.1f} ms, draw {:.1f} ms, present {:.1f} ms",
                              (loopEnd - loopStart) / 1000.0, (pollEnd - loopStart) / 1000.0,
                              (drawEnd - pollEnd) / 1000.0, (loopEnd - drawEnd) / 1000.0);
            }

            renderLoopLog.reportIfDue(stdext::millis());
        }

        if (m_graphicFrameCounter.update()) {
            g_dispatcher.addEvent([this, fps = FPS()] {
                g_lua.callGlobalField("g_app", "onFps", fps);
            });
        }
    }
#endif
    mapThread.wait();

    m_running = false;
    m_stopping = false;

    g_luaThreadId = g_eventThreadId = -1;
}

void GraphicalApplication::poll()
{
    if (g_configs.getPublicConfig().debug.perfLog) {
        const ticks_t gcStart = stdext::micros();
        GarbageCollection::poll();
        s_lastGcMicros = stdext::micros() - gcStart;
    } else
        GarbageCollection::poll();

    Application::poll();

#ifdef FRAMEWORK_SOUND
    g_sounds.poll();
#endif

    g_particles.poll();

    if (!g_window.isVisible()) {
        g_textDispatcher.poll();
    }
}
void GraphicalApplication::mainPoll()
{
    AUTO_STAT(STATS_MAIN, "MainPoll");
    {
        AUTO_STAT(STATS_MAIN, "ClockUpdate");
        g_clock.update();
    }
    {
        AUTO_STAT(STATS_MAIN, "DispatcherPoll");
        g_mainDispatcher.poll();
    }
    {
        // Batched deletion of GL textures collected by destructors from other threads.
        // Must be here: this is the only thread with an active OpenGL context, and the spot in the
        // frame is the same one where the individual deletion events used to execute.
        AUTO_STAT(STATS_MAIN, "TextureDeletion");
        Texture::flushDeletedTextures();
    }
    {
        AUTO_STAT(STATS_MAIN, "WindowPoll");
        g_window.poll();
    }
    {
        AUTO_STAT(STATS_MAIN, "TexturePoll");
        g_textures.poll();
    }
}

void GraphicalApplication::close()
{
    m_onInputEvent = true;
    Application::close();
    m_onInputEvent = false;
}

static constexpr bool USE_FRAMEBUFFER = false;
void GraphicalApplication::resize(const Size& size)
{
    const float scale = g_window.getDisplayDensity();
    g_graphics.resize(size);

    m_onInputEvent = true;
    g_ui.resize(size / scale);
    m_onInputEvent = false;

    g_mainDispatcher.addEvent([size, scale] {
        g_drawPool.get(DrawPoolType::FOREGROUND)->setFramebuffer(size / scale);
    });
}

void GraphicalApplication::inputEvent(const InputEvent& event)
{
    m_onInputEvent = true;
    g_ui.inputEvent(event);
    m_onInputEvent = false;
}

bool GraphicalApplication::isLoadingAsyncTexture() { return m_loadingAsyncTexture || (m_drawEvents && m_drawEvents->isLoadingAsyncTexture()); }
bool GraphicalApplication::isScaled() { return g_window.getDisplayDensity() != 1.f; }
void GraphicalApplication::setLoadingAsyncTexture(bool v) {
    if (m_drawEvents && m_drawEvents->isUsingProtobuf())
        v = true;
    else if (isEncrypted())
        v = false;

    m_loadingAsyncTexture = v;

    if (m_drawEvents)
        m_drawEvents->onLoadingAsyncTextureChanged(v);
}

void GraphicalApplication::doScreenshot(std::string file)
{
    if (file.empty()) {
        file = "screenshot.png";
    }

    g_mainDispatcher.addEvent([file] {
        auto resolution = g_graphics.getViewportSize();
        const int width = resolution.width();
        const int height = resolution.height();
        auto pixels = std::make_shared<std::vector<uint8_t>>(width * height * 4 * sizeof(GLubyte), 0);
        glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels->data());

        g_asyncDispatcher.detach_task([resolution, pixels, file] {
            try {
                Image image(resolution, 4, pixels->data());
                image.flipVertically();
                image.setOpacity(255);
                image.savePNG(file);
            } catch (stdext::exception& e) {
                g_logger.error(std::string("Can't do screenshot: ") + e.what());
            }
        });
    });
}

void GraphicalApplication::doMapScreenshot(std::string fileName)
{
    if (m_drawEvents) m_drawEvents->doMapScreenshot(fileName);
}

float GraphicalApplication::getHUDScale() const { return g_window.getDisplayDensity(); }
void GraphicalApplication::setHUDScale(const float v) {
    g_window.setDisplayDensity(v);
    resize(g_graphics.getViewportSize());
}
