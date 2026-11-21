-- Standalone test for modules/game_analysers/menus/BossCooldown.lua
-- Run from the source tree root: luajit tests/lua/boss_cooldown_test.lua
-- The engine hands g_game.onBossCooldown a list of { bossRaceId = ..., cooldownTime = ... }
-- tables (push_luavalue(BossCooldownData) in src/client/luavaluecasts_client.cpp).

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

local raceNames = { [1001] = "Grand Master Oberon", [1002] = "Scarlett Etzel" }

tr = function(text) return text end
g_things = {
    getRaceData = function(raceId)
        return { raceId = raceId, name = raceNames[raceId] or "" }
    end
}

loadFile("modules/game_analysers/menus/BossCooldown.lua")
assert(type(BossCooldown) == "table" and type(BossCooldown.setupCooldown) == "function", "BossCooldown.setupCooldown missing")

local function check(label, got, want)
    assert(got == want, string.format("%s: expected %s, got %s", label, tostring(want), tostring(got)))
end

local function entryOf(raceId)
    for _, entry in ipairs(BossCooldown.entries) do
        if entry.bossId == raceId then
            return entry
        end
    end
end

local now = os.time()

-- the shape the engine really sends: named fields
BossCooldown:setupCooldown({
    { bossRaceId = 1001, cooldownTime = now + 3600 },
    { bossRaceId = 1002, cooldownTime = 0 },
})
check("named rows: entry count", #BossCooldown.entries, 2)

local oberon = assert(entryOf(1001), "named rows: boss 1001 missing")
check("named rows: name", oberon.name, "Grand Master Oberon")
check("named rows: absolute timestamp kept", oberon.untilTs, now + 3600)

local name, untilTs = BossCooldown:hasCooldown(1001)
check("hasCooldown name", name, "Grand Master Oberon")
check("hasCooldown until", untilTs, now + 3600)
assert(BossCooldown:getCooldown(1001) ~= "", "getCooldown must report a running cooldown for boss 1001")

local scarlett = assert(entryOf(1002), "named rows: boss 1002 missing")
assert(scarlett.untilTs <= os.time(), "a zero cooldown must not be in the future")
check("no cooldown text", BossCooldown:getCooldown(1002), "")

-- positional rows keep working (older engine builds pushed { raceId, cooldown })
BossCooldown:setupCooldown({ { 1001, now + 60 } })
check("positional rows: entry count", #BossCooldown.entries, 1)
check("positional rows: until", BossCooldown.entries[1].untilTs, now + 60)

-- rows without a race id are dropped, a non-table payload clears the list
BossCooldown:setupCooldown({ { cooldownTime = now + 60 }, "junk", { bossRaceId = 1002, cooldownTime = now + 60 } })
check("invalid rows dropped", #BossCooldown.entries, 1)
check("valid row kept", BossCooldown.entries[1].bossId, 1002)

BossCooldown:setupCooldown(nil)
check("nil payload clears", #BossCooldown.entries, 0)

print("boss_cooldown_test: ok")
