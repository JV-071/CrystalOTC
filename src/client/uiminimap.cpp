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

#include "luavaluecasts_client.h"
#include "uiminimap.h"

#include "minimap.h"
#include "satellitemap.h"
#include "uimapanchorlayout.h"
#include "framework/otml/otmlnode.h"
#include "framework/ui/uilayout.h"
#include "framework/core/eventdispatcher.h"
#include "framework/core/clock.h"
#include <cmath>

void UIMinimap::drawSelf(const DrawPoolType drawPane)
{
    UIWidget::drawSelf(drawPane);
    if (drawPane != DrawPoolType::FOREGROUND)
        return;

    if (!m_layout)
        m_layout = std::make_shared<UIMapAnchorLayout>(static_self_cast<UIWidget>());

    if (m_satelliteMode && g_satelliteMap.hasChunksForView(m_cameraPosition.z))
        g_satelliteMap.draw(getPaddingRect(), m_cameraPosition, m_scale, m_floorSeparatorOpacity);
    else
        g_minimap.draw(getPaddingRect(), m_cameraPosition, m_scale, m_color);
}

// Duration and curve are carried over verbatim from the Lua version this replaces.
static constexpr ticks_t SCALE_ANIM_DURATION = 300;

// The Cyclopedia hangs an O(labels^2) relayout off onSmoothZoomScaleChange, and there are hundreds
// of labels. Firing it on every animation frame was most of the cost of zooming; a handful of times
// across the ease, plus once when it settles, looks the same and is a fraction of the work.
static constexpr ticks_t SCALE_NOTIFY_INTERVAL = 60;

bool UIMinimap::smoothZoomBy(const int8_t step, const Point& anchor)
{
    if (step == 0)
        return false;

    // Start from whatever is on screen right now, mid-animation included, so a second wheel notch
    // eases on from where the first had reached instead of snapping back to its start.
    const auto startScale = m_scale;

    // Remember the world position under the cursor so it can be held there while the scale changes.
    // This is what the Lua beginSmoothZoom/endSmoothZoom pair was meant to do: the mouse position
    // was threaded through every call site, but neither method was ever defined anywhere in the
    // repo, so the calls hit nil and the minimap always zoomed on the camera centre instead.
    const auto hasAnchor = anchor.x >= 0 && anchor.y >= 0 && getPaddingRect().contains(anchor);
    const auto anchorPosition = hasAnchor ? getTilePosition(anchor) : Position();

    if (!setZoom(static_cast<int8_t>(m_zoom + step)))
        return false;

    m_scaleFrom = startScale;
    m_scaleTo = m_scale;
    m_scale = startScale;
    m_scaleAnchor = hasAnchor && anchorPosition.isValid() ? anchor : Point(-1, -1);
    m_scaleAnchorPosition = anchorPosition;
    m_scaleAnimStart = g_clock.millis();
    m_scaleAnimNotified = 0;
    m_scaleAnimating = true;

    if (!m_scaleAnimEvent) {
        m_scaleAnimEvent = g_dispatcher.cycleEvent([self = static_self_cast<UIMinimap>()] {
            self->tickScaleAnimation();
        }, 16);
    }

    return true;
}

// Runs on the event thread, which is also the Lua thread - drawSelf is not a safe place for this,
// because the foreground pane is recorded on an async worker.
void UIMinimap::tickScaleAnimation()
{
    if (isDestroyed()) {
        stopScaleAnimation();
        return;
    }

    if (!m_scaleAnimating)
        return;

    const auto now = g_clock.millis();
    const auto elapsed = now - m_scaleAnimStart;
    const auto finished = elapsed >= SCALE_ANIM_DURATION;

    if (finished) {
        m_scale = m_scaleTo;
    } else {
        // smootherstep, interpolated geometrically because scale is a power of two per zoom step
        const auto t = static_cast<float>(elapsed) / static_cast<float>(SCALE_ANIM_DURATION);
        const auto eased = t * t * t * (t * (t * 6.f - 15.f) + 10.f);
        m_scale = m_scaleFrom * std::pow(m_scaleTo / m_scaleFrom, eased);
    }

    // Put the anchored world position back under the cursor. The mapping is linear in the camera
    // with unit slope in tile space, so correcting by the drift is exact rather than an
    // approximation, and it re-converges every tick as the scale eases.
    if (m_scaleAnchor.x >= 0 && m_scaleAnchorPosition.isValid()) {
        if (const auto& current = getTilePosition(m_scaleAnchor); current.isValid()) {
            m_cameraPosition.x += m_scaleAnchorPosition.x - current.x;
            m_cameraPosition.y += m_scaleAnchorPosition.y - current.y;
        }
    }

    if (finished || now - m_scaleAnimNotified >= SCALE_NOTIFY_INTERVAL) {
        m_scaleAnimNotified = now;
        callLuaField("onSmoothZoomScaleChange", m_scale);
    }

    if (finished)
        stopScaleAnimation();
}

void UIMinimap::stopScaleAnimation()
{
    m_scaleAnimating = false;
    m_scaleAnchor = { -1, -1 };

    if (m_scaleAnimEvent) {
        m_scaleAnimEvent->cancel();
        m_scaleAnimEvent = nullptr;
    }
}

bool UIMinimap::setZoom(const int8_t zoom)
{
    if (zoom == m_zoom)
        return true;

    if (zoom < m_minZoom || zoom > m_maxZoom)
        return false;

    const int oldZoom = m_zoom;
    m_zoom = zoom;

    m_scale = 1.f;

    if (m_zoom < 0)
        m_scale /= 1 << std::abs(zoom);
    else if (m_zoom > 0)
        m_scale *= 1 << std::abs(zoom);

    if (m_layout)
        m_layout->update();

    onZoomChange(zoom, oldZoom);
    return true;
}

void UIMinimap::setCameraPosition(const Position& pos)
{
    if (m_cameraPosition == pos)
        return;

    const Position oldPos = m_cameraPosition;
    m_cameraPosition = pos;

    if (m_layout)
        m_layout->update();

    onCameraPositionChange(pos, oldPos);
}

bool UIMinimap::floorUp()
{
    Position pos = m_cameraPosition;
    if (!pos.up())
        return false;

    setCameraPosition(pos);
    return true;
}

bool UIMinimap::floorDown()
{
    Position pos = m_cameraPosition;
    if (!pos.down())
        return false;
    setCameraPosition(pos);
    return true;
}

Point UIMinimap::getTilePoint(const Position& pos)
{
    return g_minimap.getTilePoint(pos, getPaddingRect(), m_cameraPosition, m_scale);
}

Rect UIMinimap::getTileRect(const Position& pos)
{
    return g_minimap.getTileRect(pos, getPaddingRect(), m_cameraPosition, m_scale);
}

Position UIMinimap::getTilePosition(const Point& mousePos)
{
    return g_minimap.getTilePosition(mousePos, getPaddingRect(), m_cameraPosition, m_scale);
}

void UIMinimap::anchorPosition(const UIWidgetPtr& anchoredWidget, const Fw::AnchorEdge anchoredEdge, const Position& hookedPosition, const Fw::AnchorEdge hookedEdge)
{
    if (!m_layout)
        return;

    const auto& layout = m_layout->static_self_cast<UIMapAnchorLayout>();
    assert(layout);
    layout->addPositionAnchor(anchoredWidget, anchoredEdge, hookedPosition, hookedEdge);
}

void UIMinimap::fillPosition(const UIWidgetPtr& anchoredWidget, const Position& hookedPosition)
{
    if (!m_layout)
        return;

    const auto& layout = m_layout->static_self_cast<UIMapAnchorLayout>();
    assert(layout);
    layout->fillPosition(anchoredWidget, hookedPosition);
}

void UIMinimap::centerInPosition(const UIWidgetPtr& anchoredWidget, const Position& hookedPosition)
{
    if (!m_layout)
        return;

    const auto& layout = m_layout->static_self_cast<UIMapAnchorLayout>();
    assert(layout);
    layout->centerInPosition(anchoredWidget, hookedPosition);
}

void UIMinimap::onZoomChange(const int zoom, const int oldZoom) { callLuaField("onZoomChange", zoom, oldZoom); }

void UIMinimap::onCameraPositionChange(const Position& position, const Position& oldPosition) { callLuaField("onCameraPositionChange", position, oldPosition); }

void UIMinimap::onStyleApply(const std::string_view styleName, const OTMLNodePtr& styleNode)
{
    UIWidget::onStyleApply(styleName, styleNode);
    for (const auto& node : styleNode->children()) {
        if (node->tag() == "zoom")
            setZoom(node->value<int>());
        else if (node->tag() == "max-zoom")
            setMaxZoom(node->value<int>());
        else if (node->tag() == "min-zoom")
            setMinZoom(node->value<int>());
    }
}