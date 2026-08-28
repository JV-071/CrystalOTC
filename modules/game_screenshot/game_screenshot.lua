-- chunkname: @/game_screenshot/game_screenshot.lua

local CLIENT_EVENT_TYPE_SIMPLE = 1
local CLIENT_EVENT_TYPE_ACHIEVEMENT = 2
local CLIENT_EVENT_TYPE_LEVEL = 4
local CLIENT_EVENT_TYPE_SKILL = 5
local CLIENT_EVENT_TYPE_BESTIARY = 6
local CLIENT_EVENT_BOSSDEFEATED = 1
local CLIENT_EVENT_DEATHPVE = 2
local CLIENT_EVENT_DEATHPVP = 3
local CLIENT_EVENT_PLAYERKILLASSIST = 4
local CLIENT_EVENT_PLAYERKILL = 5
local CLIENT_EVENT_PLAYERATTACKING = 6
local CLIENT_EVENT_TREASUREFOUND = 7
local CLIENT_EVENT_GIFTOFLIFE = 8
local AutoScreenshotEvents = {
	{
		enableDefault = true,
		label = "Level Up",
		optionKey = "levelUp"
	},
	{
		enableDefault = true,
		label = "Skill Up",
		optionKey = "skillUp"
	},
	{
		enableDefault = true,
		label = "Achievement",
		optionKey = "achievement"
	},
	{
		enableDefault = false,
		label = "Bestiary Entry Unlocked",
		optionKey = "bestiaryUnlocked"
	},
	{
		enableDefault = false,
		label = "Bestiary Entry Completed",
		optionKey = "bestiaryCompleted"
	},
	{
		enableDefault = false,
		label = "Treasure Found",
		optionKey = "treasureFound"
	},
	{
		enableDefault = false,
		label = "Valuable Loot",
		optionKey = "valuableLoot"
	},
	{
		enableDefault = false,
		label = "Boss Defeated",
		optionKey = "bossDefeated"
	},
	{
		enableDefault = true,
		label = "Death PvE",
		optionKey = "deathPvE"
	},
	{
		enableDefault = false,
		label = "Death PvP",
		optionKey = "deathPvP"
	},
	{
		enableDefault = false,
		label = "Player Kill",
		optionKey = "playerKill"
	},
	{
		enableDefault = false,
		label = "Player Kill Assist",
		optionKey = "playerKillAssist"
	},
	{
		enableDefault = false,
		label = "Player Attacking",
		optionKey = "playerAttacking"
	},
	{
		enableDefault = false,
		label = "Highest Damage Dealt",
		optionKey = "highestDamage"
	},
	{
		enableDefault = false,
		label = "Highest Healing Done",
		optionKey = "highestHealing"
	},
	{
		enableDefault = false,
		label = "Low Health",
		optionKey = "lowHealth"
	},
	{
		enableDefault = true,
		label = "Gift of Life Triggered",
		optionKey = "giftOfLife"
	}
}
local SIMPLE_EVENT_SCREENSHOTS = {
	[CLIENT_EVENT_BOSSDEFEATED] = {
		"bossDefeated",
		"BossDefeated"
	},
	[CLIENT_EVENT_DEATHPVE] = {
		"deathPvE",
		"DeathPvE"
	},
	[CLIENT_EVENT_DEATHPVP] = {
		"deathPvP",
		"DeathPvP"
	},
	[CLIENT_EVENT_PLAYERKILLASSIST] = {
		"playerKillAssist",
		"PlayerKillAssist"
	},
	[CLIENT_EVENT_PLAYERKILL] = {
		"playerKill",
		"PlayerKill"
	},
	[CLIENT_EVENT_PLAYERATTACKING] = {
		"playerAttacking",
		"PlayerAttacking"
	},
	[CLIENT_EVENT_TREASUREFOUND] = {
		"treasureFound",
		"TreasureFound"
	},
	[CLIENT_EVENT_GIFTOFLIFE] = {
		"giftOfLife",
		"GiftOfLifeTriggered"
	}
}
local autoScreenshotDir = "/auto_screenshots"

-- "Keep Backlog of the Screenshots of the Last 5 Seconds": while the option is on we keep a
-- rolling ring of one-per-second captures, and a real capture promotes the whole ring next
-- to itself. Writing a frame every second is why the official tooltip warns about stutter.
local BACKLOG_SLOTS = 5
local BACKLOG_INTERVAL_MS = 1000
local backlogDir = autoScreenshotDir .. "/backlog"
local backlogSlot = 0
local backlogEvent

screenshotController = Controller:new()

local function ensureScreenshotDir()
	if not g_resources.directoryExists(autoScreenshotDir) then
		g_resources.makeDir(autoScreenshotDir)
	end
end

-- The on-disk path of the screenshot folder, for the "saved to location" message and for
-- g_platform.openDir. It used to rewrite every separator to a backslash, which only ever
-- produced a valid path on Windows.
local function getScreenshotDirPath()
	ensureScreenshotDir()

	local writeDir = g_resources.getWriteDir():gsub("[/\\]+$", "")

	if g_app.getOs() == "windows" then
		return writeDir:gsub("/", "\\") .. "\\auto_screenshots"
	end

	return writeDir .. autoScreenshotDir
end

local function showScreenshotSavedMessage(eventName)
	if not eventName or not modules.game_textmessage or not modules.game_textmessage.displayStatusMessage then
		return
	end

	modules.game_textmessage.displayStatusMessage(tr("Screenshot for event %s has been saved to location '%s'.", eventName, getScreenshotDirPath()))
end

local function getScreenshotOption(key)
	if modules.client_options and modules.client_options.getOption then
		local value = modules.client_options.getOption(key)

		if value ~= nil then
			return value
		end
	end

	return false
end

local function ensureBacklogDir()
	if not g_resources.directoryExists(backlogDir) then
		g_resources.makeDir(backlogDir)
	end
end

-- One capture, honouring "Only Capture Game Window" for both the real shots and the ring.
local function capture(path)
	if getScreenshotOption("onlyCaptureGameWindow") then
		g_app.doMapScreenshot(path)
	else
		g_app.doScreenshot(path)
	end
end

local function backlogSlotPath(slot)
	return backlogDir .. "/slot" .. slot .. ".png"
end

local function copyFile(from, to)
	if not g_resources.fileExists(from) then
		return false
	end

	-- readFileContents throws when the file is missing, and a ring slot can still be empty
	-- while its encode is in flight, so both the throw and the empty read are expected.
	local ok, contents = pcall(g_resources.readFileContents, from)

	if not ok or not contents or contents == "" then
		return false
	end

	local wrote, result = pcall(g_resources.writeFileContents, to, contents)

	return wrote and result ~= false
end

-- Saves the ring alongside a capture, oldest first. backlogSlot points at the slot written
-- most recently, so walking forward from it yields chronological order.
local function saveBacklogBeside(baseName)
	if not getScreenshotOption("keepBacklog") then
		return
	end

	local base = baseName:gsub("%.png$", "")

	for age = BACKLOG_SLOTS - 1, 0, -1 do
		local slot = (backlogSlot - age - 1) % BACKLOG_SLOTS + 1

		copyFile(backlogSlotPath(slot), string.format("%s_backlog-%ds.png", base, age + 1))
	end
end

local function stopBacklog()
	if backlogEvent then
		removeEvent(backlogEvent)

		backlogEvent = nil
	end
end

local function tickBacklog()
	backlogEvent = nil

	if not g_game.isOnline() or not getScreenshotOption("keepBacklog") then
		return
	end

	ensureBacklogDir()

	backlogSlot = backlogSlot % BACKLOG_SLOTS + 1

	capture(backlogSlotPath(backlogSlot))

	backlogEvent = scheduleEvent(tickBacklog, BACKLOG_INTERVAL_MS)
end

-- Called on game start and whenever the option changes, so ticking follows the checkbox
-- without waiting for a relog.
function syncBacklogCapture()
	stopBacklog()

	if g_game.isOnline() and getScreenshotOption("keepBacklog") then
		backlogSlot = 0
		backlogEvent = scheduleEvent(tickBacklog, BACKLOG_INTERVAL_MS)
	end
end

local function triggerAutoScreenshot(optionKey, labelSuffix)
	if not getScreenshotOption("enableAutoScreenshots") then
		return
	end

	if not getScreenshotOption(optionKey) then
		return
	end

	local player = g_game.getLocalPlayer()

	if not player then
		return
	end

	local name = player:getName() or "player"
	local level = player:getLevel() or 1
	local screenshotName = name .. level .. "_" .. labelSuffix:gsub("%s+", "") .. "_" .. os.date("%Y%m%d%H%M%S") .. ".png"

	takeScreenshot(autoScreenshotDir .. "/" .. screenshotName, labelSuffix)
end

local function onClientEvent(eventType, ...)
	if eventType == CLIENT_EVENT_TYPE_SIMPLE then
		local simpleType = select(1, ...)
		local entry = SIMPLE_EVENT_SCREENSHOTS[simpleType]

		if entry then
			triggerAutoScreenshot(entry[1], entry[2])
		end

		return
	end

	if eventType == CLIENT_EVENT_TYPE_ACHIEVEMENT then
		triggerAutoScreenshot("achievement", "Achievement")

		return
	end

	if eventType == CLIENT_EVENT_TYPE_LEVEL then
		triggerAutoScreenshot("levelUp", "LevelUp")

		return
	end

	if eventType == CLIENT_EVENT_TYPE_SKILL then
		triggerAutoScreenshot("skillUp", "SkillUp")

		return
	end

	if eventType == CLIENT_EVENT_TYPE_BESTIARY then
		local progressLevel = select(2, ...) or 0

		if progressLevel == 0 then
			triggerAutoScreenshot("bestiaryUnlocked", "BestiaryEntryUnlocked")
		elseif progressLevel >= 3 then
			triggerAutoScreenshot("bestiaryCompleted", "BestiaryEntryCompleted")
		end
	end
end

function screenshotController:onInit()
	-- The official client offers a manual screenshot hotkey; the backlog option's own
	-- description refers to it. No default binding, so it does not collide with anything
	-- an existing profile already uses.
	Keybind.new("Misc", "Take Screenshot", "", "")
	Keybind.bind("Misc", "Take Screenshot", {
		{
			type = KEY_DOWN,
			callback = function()
				takeManualScreenshot()
			end
		}
	})
end

function screenshotController:onTerminate()
	stopBacklog()
	Keybind.delete("Misc", "Take Screenshot")

	AutoScreenshotEvents = {}
end

function screenshotController:onGameStart()
	if g_game.getClientVersion() < 1180 then
		return
	end

	ensureScreenshotDir()
	screenshotController:registerEvents(g_game, {
		onClientEvent = onClientEvent
	})
	syncBacklogCapture()
end

function screenshotController:onGameEnd()
	stopBacklog()
end

-- Kept for callers outside the options window; the Reset button on the Screenshots page now
-- goes through client_options, which owns the defaults and no longer needs them duplicated
-- here.
function resetValues()
	if modules.client_options and modules.client_options.resetPageToDefaults then
		modules.client_options.resetPageToDefaults("miscScreenshots")
	end
end

function takeScreenshot(name, eventName)
	if not g_game.isOnline() then
		return
	end

	ensureScreenshotDir()
	screenshotController:scheduleEvent(function()
		capture(name)
		saveBacklogBeside(name)
		showScreenshotSavedMessage(eventName)
	end, 50, "screenshotScheduleEvent")
end

-- The manual screenshot the backlog tooltip refers to ("taken either automatically for a
-- selected event or manually using a hotkey").
function takeManualScreenshot()
	if not g_game.isOnline() then
		return
	end

	local player = g_game.getLocalPlayer()
	local name = player and player:getName() or "player"
	local level = player and player:getLevel() or 1

	takeScreenshot(autoScreenshotDir .. "/" .. name .. level .. "_Manual_" .. os.date("%Y%m%d%H%M%S") .. ".png", "Manual")
end

function OpenFolder()
	g_platform.openDir(getScreenshotDirPath())
end
