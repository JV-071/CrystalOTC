-- Standalone test for the gem list refresh after a reveal in modules/game_wheel/classes/gematelier.lua
-- Run from the source tree root: luajit tests/lua/gem_atelier_reveal_test.lua
--
-- Revealing a gem makes the server send 0xC5 (index of the new gem) followed by the refreshed
-- wheel data, which rebuilds the list through GemAtelier.showGems(). The list shows 15 gems
-- per page; the new gem must end up on screen and selected.

local function loadFile(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local src = f:read("*a")
    f:close()
    if src:sub(1, 3) == "\239\187\191" then
        src = src:sub(4)
    end
    local chunk = assert(loadstring(src, "@" .. path))
    return chunk()
end

local function check(label, got, want)
    assert(got == want, string.format("%s: expected %s, got %s", label, tostring(want), tostring(got)))
end

-- minimal stand-ins for the widgets showGems touches
local gemList = { children = {}, focused = nil }

function gemList:destroyChildren() self.children = {} self.focused = nil end
function gemList:getChildren() return self.children end
function gemList:getFirstChild() return self.children[1] end
function gemList:focusChild(widget) self.focused = widget end

local function plainWidget()
    return { setVisible = function() end }
end

local clickedPanel = { clickedContent = plainWidget(), cleanContent = plainWidget() }

gemAtelierWindow = {
    recursiveGetChildById = function(_, id)
        if id == "gemContent" then
            return gemList
        elseif id == "clickedPanel" then
            return clickedPanel
        end
    end
}

g_ui = {
    createWidget = function(_, parent)
        local widget = {}
        parent.children[#parent.children + 1] = widget
        return widget
    end
}

local gems = {}
for index = 0, 39 do
    gems[#gems + 1] = { gemID = index, locked = 0, gemDomain = index % 4, gemType = 0, lesserBonus = 0 }
end

WheelOfDestiny = { atelierGems = gems, vocationId = 1 }

loadFile("modules/game_wheel/classes/gematelier.lua")
assert(type(GemAtelier) == "table" and type(GemAtelier.showGems) == "function", "GemAtelier.showGems missing")
assert(type(GemAtelier.onGemRevealed) == "function", "GemAtelier.onGemRevealed missing")

-- the parts of the atelier that need the real UI are not under test
GemAtelier.setupVesselPanel = function() end
GemAtelier.showGemRevelation = function() end
GemAtelier.configurePages = function() end
GemAtelier.onSelectGem = function() end
GemAtelier.setupGemWidget = function(widget, data)
    widget.gemID = data.gemID
    return true
end

local function shownIds()
    local ids = {}
    for _, widget in ipairs(gemList.children) do
        ids[#ids + 1] = widget.gemID
    end
    return ids
end

-- 1. Plain refresh: first page, first gem selected.
GemAtelier.showGems()
check("1: page size", #gemList.children, 15)
check("1: first gem on page", shownIds()[1], 0)
check("1: default selection", gemList.focused and gemList.focused.gemID, 0)

-- 2. Gem 22 was just revealed: the list opens page 2 (gems 15..29) and selects it.
GemAtelier.onGemRevealed(22)
GemAtelier.showGems()
check("2: first gem on page", shownIds()[1], 15)
check("2: last gem on page", shownIds()[15], 29)
check("2: revealed gem selected", gemList.focused and gemList.focused.gemID, 22)

-- 3. The reveal is consumed: the next refresh keeps the page and no longer forces gem 22.
GemAtelier.showGems()
check("3: page kept", shownIds()[1], 15)
check("3: default selection again", gemList.focused and gemList.focused.gemID, 15)

-- 4. Index 0 is a valid gem: from page 2 the list goes back to page 1 and selects it.
GemAtelier.onGemRevealed(0)
GemAtelier.showGems()
check("4: back on first page", shownIds()[1], 0)
check("4: gem 0 selected", gemList.focused and gemList.focused.gemID, 0)

-- 5. A reveal on the last, partial page (gems 30..39).
GemAtelier.onGemRevealed(39)
GemAtelier.showGems()
check("5: partial page size", #gemList.children, 10)
check("5: last gem selected", gemList.focused and gemList.focused.gemID, 39)

-- 6. An index that is not in the list changes nothing.
GemAtelier.onGemRevealed(999)
GemAtelier.showGems()
check("6: page kept", shownIds()[1], 30)
check("6: default selection", gemList.focused and gemList.focused.gemID, 30)

print("gem_atelier_reveal_test: ok")
