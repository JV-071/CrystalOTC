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

#include "uicompositionfixture.h"

#include <array>
#include <framework/graphics/drawpoolmanager.h>

void UICompositionFixture::drawSelf(const DrawPoolType drawPane)
{
    if (drawPane != DrawPoolType::FOREGROUND)
        return;

    UIWidget::drawSelf(drawPane);

    static constexpr std::array modes {
        CompositionMode::NORMAL,
        CompositionMode::MULTIPLY,
        CompositionMode::ADD,
        CompositionMode::REPLACE,
        CompositionMode::DESTINATION_BLENDING,
        CompositionMode::LIGHT
    };

    const Rect area = getPaddingRect();
    // Clear retained foreground contents explicitly. Non-standard blend probes such as
    // ADD must start from this fixture, not from a startup window cached in the pool.
    g_drawPool.setCompositionMode(CompositionMode::REPLACE, true);
    g_drawPool.addFilledRect(area, Color(2, 6, 23));

    const int gap = 12;
    const int cellWidth = (area.width() - gap * static_cast<int>(modes.size() - 1)) / static_cast<int>(modes.size());

    for (size_t index = 0; index < modes.size(); ++index) {
        const Rect cell(area.x() + static_cast<int>(index) * (cellWidth + gap), area.y(), cellWidth, area.height());
        const Rect left(cell.x(), cell.y(), cell.width() / 2, cell.height());
        const Rect right(left.right() + 1, cell.y(), cell.width() - left.width(), cell.height());
        g_drawPool.setCompositionMode(CompositionMode::REPLACE, true);
        g_drawPool.addFilledRect(left, Color(226, 232, 240));
        g_drawPool.setCompositionMode(CompositionMode::REPLACE, true);
        g_drawPool.addFilledRect(right, Color(71, 85, 105));

        Rect overlay = cell;
        overlay.expand(-18);
        g_drawPool.setCompositionMode(modes[index], true);
        g_drawPool.addFilledRect(overlay, Color(244, 63, 94, 190));
    }
}
