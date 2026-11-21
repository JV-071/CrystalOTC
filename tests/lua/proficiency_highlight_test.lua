-- Standalone test for the unused-perk highlight in mods/game_proficiency/proficiency.lua
-- Run from the source tree root: luajit tests/lua/proficiency_highlight_test.lua
--
-- Two packets feed the highlight:
--   0x5C (onProficiencyNotification): item id, experience, server flag. No perk list.
--   0xC4 (onWeaponProficiency):       item id, experience, the assigned perks.
-- Until 0xC4 arrives the assigned perks are unknown, and "unknown" must not read as
-- "every unlocked lane is free".

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

local ITEM = 3271
local OTHER_ITEM = 3272
local LEVEL_EXP = { 100, 200, 300 } -- three perk lanes

local function makeThingType(id)
    return {
        getId = function() return id end,
        getProficiencyId = function() return 7 end,
        getMarketData = function() return { category = 20 } end,
    }
end

local thingTypes = { [ITEM] = makeThingType(ITEM), [OTHER_ITEM] = makeThingType(OTHER_ITEM) }

local function makeHand(id)
    return {
        getId = function() return id end,
        getProficiencyId = function() return 7 end,
        getThingType = function() return thingTypes[id] end,
    }
end

local handItem
local requests = {}
local highlights = {}

g_game = {
    sendWeaponProficiencyAction = function(action, itemId)
        requests[#requests + 1] = { action = action, itemId = itemId }
    end
}
g_ui = { getRootWidget = function() return nil end }
modules = {
    game_inventory = {
        getWeaponProficiencyHandItem = function() return handItem end
    },
    game_interface = {
        StatsBar = {
            onUpdateProficiencyData = function(itemCache, hasHighlight, thingType)
                highlights[#highlights + 1] = { itemId = thingType:getId(), on = hasHighlight }
            end
        }
    }
}

loadFile("mods/game_proficiency/const.lua")
loadFile("mods/game_proficiency/proficiency.lua")
assert(type(onProficiencyNotification) == "function", "onProficiencyNotification missing")
assert(type(onWeaponProficiency) == "function", "onWeaponProficiency missing")

-- the highlight logic only needs the lane count and the level thresholds
ProficiencyData = {
    getPerkLaneCount = function() return #LEVEL_EXP end,
    getCurrentLevelByExp = function(_, _, exp)
        local level = 0
        for i, need in ipairs(LEVEL_EXP) do
            if exp >= need then
                level = i
            end
        end
        return level
    end,
    getLevelPercent = function(_, exp, lane)
        return exp >= LEVEL_EXP[lane] and 100 or 0
    end,
    getServerClientId = function(_, entry) return entry.id end,
}

local function reset()
    WeaponProficiency.cacheList = {}
    requests = {}
    highlights = {}
    handItem = nil
end

local function lastHighlight()
    return highlights[#highlights]
end

-- 1. Experience update for the equipped weapon, perks not known yet: the handler must ask the
--    server for them (item info = action 0) and must not light the highlight on its own.
reset()
handItem = makeHand(ITEM)
onProficiencyNotification(ITEM, 150, false, thingTypes[ITEM])
check("1: info requested once", #requests, 1)
check("1: info request action", requests[1].action, 0)
check("1: info request item", requests[1].itemId, ITEM)
assert(lastHighlight(), "1: StatsBar must be updated")
check("1: no highlight while perks are unknown", lastHighlight().on, false)
check("1: hasUnusedPerk while perks are unknown", WeaponProficiency:hasUnusedPerk(ITEM, thingTypes[ITEM]), false)

-- 2. More kills before the answer arrives: still no highlight, no second request.
onProficiencyNotification(ITEM, 180, false, thingTypes[ITEM])
check("2: info not requested again", #requests, 1)
check("2: still no highlight", lastHighlight().on, false)

-- 3. The answer says lane 1 is already assigned: no highlight.
onWeaponProficiency(ITEM, 180, { [0] = 2 }, 20, {})
check("3: lane assigned, no highlight", lastHighlight().on, false)

-- 4. Later kills never ask again, and reaching level 2 with lane 2 free lights the highlight.
onProficiencyNotification(ITEM, 190, false, thingTypes[ITEM])
check("4: no request once perks are known", #requests, 1)
check("4: level 1 fully assigned", lastHighlight().on, false)
onProficiencyNotification(ITEM, 250, false, thingTypes[ITEM])
check("4: no request on level up", #requests, 1)
check("4: lane 2 is free", lastHighlight().on, true)

-- 5. An answer with no perks and level 1 reached is a real free lane.
reset()
handItem = makeHand(ITEM)
onWeaponProficiency(ITEM, 150, {}, 20, {})
check("5: known empty perks light the highlight", lastHighlight().on, true)

-- 6. The server flag is the fallback while perks are unknown.
reset()
handItem = makeHand(ITEM)
onProficiencyNotification(ITEM, 150, true, thingTypes[ITEM])
check("6: server flag honoured while perks are unknown", lastHighlight().on, true)
onWeaponProficiency(ITEM, 150, { [0] = 1 }, 20, {})
check("6: real perks win over the server flag", lastHighlight().on, false)

-- 7. The update arrives before the hand slot does (login, weapon swap): nothing is requested
--    for a weapon that is not in hand, and the later hand sync asks exactly once.
reset()
handItem = makeHand(OTHER_ITEM)
onProficiencyNotification(ITEM, 150, false, thingTypes[ITEM])
check("7: nothing requested for a weapon that is not in hand", #requests, 0)
handItem = makeHand(ITEM)
check("7: no highlight from an unknown perk list", WeaponProficiency:hasUnusedPerk(ITEM, thingTypes[ITEM]), false)
check("7: hand sync requests the perks", WeaponProficiency:requestPerksIfUnknown(ITEM), true)
check("7: request sent", #requests, 1)
check("7: request action", requests[1].action, 0)
check("7: second sync does not ask again", WeaponProficiency:requestPerksIfUnknown(ITEM), false)
check("7: still one request", #requests, 1)

-- 8. No experience means no server entry to answer with: do not ask, and ask once it exists.
reset()
handItem = makeHand(ITEM)
onProficiencyNotification(ITEM, 0, false, thingTypes[ITEM])
check("8: nothing requested without experience", #requests, 0)
onProficiencyNotification(ITEM, 120, false, thingTypes[ITEM])
check("8: requested once experience exists", #requests, 1)

-- 9. Unknown weapons are ignored by the hand sync.
reset()
check("9: no cache entry, no request", WeaponProficiency:requestPerksIfUnknown(ITEM), false)
check("9: nothing sent", #requests, 0)

print("proficiency_highlight_test: ok")
