-- Standalone test for the creature previews of the Prey window (modules/game_prey/prey.lua)
-- Run from the source tree root: luajit tests/lua/prey_preview_test.lua
--
-- A creature shown in a widget only cycles its walk frames while Creature:setStaticWalking has
-- a speed above zero. Speed 0 pins it to its first frame, which leaves every creature without
-- an idle animation of its own frozen.

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

loadFile("modules/game_prey/prey.lua")
assert(type(applyPreyCreaturePreview) == "function", "applyPreyCreaturePreview missing")

local function makePreview(creature)
    local widget = { calls = {} }

    for _, name in ipairs({ "setCenter", "setFixedCreatureSize", "setBaseScale", "setIgnoreDisplacementShift" }) do
        widget[name] = function(self, value)
            self.calls[name] = value
        end
    end

    function widget:getCreature()
        return creature
    end

    return widget
end

local function makeCreature()
    local creature = {}

    function creature:setStaticWalking(speed)
        self.walkSpeed = speed
    end

    return creature
end

-- the preview keeps its layout settings and starts the walk animation
local creature = makeCreature()
local widget = makePreview(creature)

applyPreyCreaturePreview(widget)

check("centered", widget.calls.setCenter, true)
check("fixed creature size", widget.calls.setFixedCreatureSize, true)
check("base scale", widget.calls.setBaseScale, true)
check("displacement shift ignored", widget.calls.setIgnoreDisplacementShift, true)
assert(type(creature.walkSpeed) == "number", "the preview must set a walk animation speed")
assert(creature.walkSpeed > 0, "the preview must animate: walk speed is " .. tostring(creature.walkSpeed))

-- a preview with no creature yet, or no widget at all, is left alone
applyPreyCreaturePreview(makePreview(nil))
applyPreyCreaturePreview(nil)

print("prey_preview_test: ok")
