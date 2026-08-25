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

#include "framework/graphics/coordsbuffer.h"
#include "framework/luaengine/luaobject.h"
#include "staticdata.h"
#include <framework/graphics/declarations.h>

class LightView final : public LuaObject
{
public:
    LightView(const Size& size);
    ~LightView() override { m_texture = nullptr; }

    void resize(const Size& size, uint16_t tileSize);
    void draw(const Rect& dest, const Rect& src);

    void addLightSource(const Point& pos, const Light& light, float brightness = 1.f);
    void resetShade(const Point& pos);
    void markIndoor(const Point& pos, bool indoor);

    void setGlobalLight(const Light& light)
    {
        m_globalLightIntensity = light.intensity;
        m_globalLightColor = Color::from8bit(light.color, light.intensity / static_cast<float>(UINT8_MAX));
        updateDarkness();
    }

    // The light a roofed tile gets instead of the open-air one - the "Clouds & Indoor Effect".
    // MapView hands over a finished colour rather than a Light so the policy stays in one place;
    // `intensity` comes along only so the darkness test can read it. With the option off MapView
    // produces exactly m_globalLightColor, so the branch in updatePixels is then a no-op.
    void setIndoorLight(const Color& color, const uint8_t intensity)
    {
        m_indoorLightIntensity = intensity;
        m_indoorLightColor = color;
        updateDarkness();
    }

    bool isDark() const { return m_isDark; }
    bool isEnabled() const;
    void setEnabled(const bool v);
    void clear() {
        m_lightData.lights.clear();
        m_lightData.tiles.assign(m_mapSize.area(), {});
        m_lightData.indoor.assign(m_mapSize.area(), 0);
        m_indoorHash = 0;
    }

private:
    struct TileLight : Light
    {
        Point pos;
        float brightness{ 1.f };

        TileLight(const Point& pos, const uint8_t intensity, const uint8_t color, const float brightness) : Light(intensity, color), pos(pos), brightness(brightness) {}
    };

    struct LightData
    {
        std::vector<size_t> tiles;
        std::vector<TileLight> lights;

        // One flag per tile of the light grid: is this tile under a roof. Parallel to `tiles`
        // rather than part of it because the two are written by different passes.
        std::vector<uint8_t> indoor;
    };

    void updateCoords(const Rect& dest, const Rect& src);
    void updatePixels();

    // Dark when EITHER light is dark. A shaded interior has to be drawn even while the open
    // air outside sits at full daylight - and that is exactly the case that would otherwise
    // keep the whole pass off, since the server's LIGHT_LEVEL_DAY is this same 250.
    void updateDarkness() { m_isDark = m_globalLightIntensity < 250 || m_indoorLightIntensity < 250; }

    bool m_isDark{ false };

    Size m_mapSize;
    uint16_t m_tileSize{ 32 };
    Color m_globalLightColor{ Color::white };
    Color m_indoorLightColor{ Color::white };
    uint8_t m_globalLightIntensity{ UINT8_MAX };
    uint8_t m_indoorLightIntensity{ UINT8_MAX };
    size_t m_indoorHash{ 0 };

    DrawPool* m_pool{ nullptr };

    Rect m_dest, m_src;
    CoordsBuffer m_coords;
    TexturePtr m_texture;
    LightData m_lightData;
    std::array<std::vector<uint8_t>, 2> m_pixels;
};
