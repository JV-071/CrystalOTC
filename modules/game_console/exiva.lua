-- Exiva Options: who may use Exiva on this character (0xCA in both directions).
-- The server sends the full whitelists on login and only the confirmed
-- additions and removals after every change, so the lists are kept here.

local exivaWindow = nil
local exivaRadioGroup = nil
local exivaOptions = nil

local function newExivaOptions()
	return {
		allowAll = false,
		allowGuild = false,
		allowParty = false,
		allowVips = false,
		allowCharacterWhitelist = false,
		allowGuildWhitelist = false,
		characters = {},
		guilds = {}
	}
end

exivaOptions = newExivaOptions()

local function findEntry(list, name)
	local lowered = name:lower()

	for index, entry in ipairs(list) do
		if entry:lower() == lowered then
			return index
		end
	end

	return nil
end

local function applyEntries(list, added, removed)
	for _, name in ipairs(removed or {}) do
		local index = findEntry(list, name)

		if index then
			table.remove(list, index)
		end
	end

	for _, name in ipairs(added or {}) do
		if name ~= "" and not findEntry(list, name) then
			table.insert(list, name)
		end
	end
end

local function parseLines(text)
	local result = {}

	for line in (text or ""):gmatch("[^\r\n]+") do
		local name = line:trim()

		if name ~= "" and not findEntry(result, name) then
			table.insert(result, name)
		end
	end

	return result
end

local function diffEntries(current, wanted)
	local added = {}
	local removed = {}

	for _, name in ipairs(wanted) do
		if not findEntry(current, name) then
			table.insert(added, name)
		end
	end

	for _, name in ipairs(current) do
		if not findEntry(wanted, name) then
			table.insert(removed, name)
		end
	end

	return added, removed
end

local function isExivaWindowOpen()
	return exivaWindow and not exivaWindow:isDestroyed()
end

local function getWhitelistEdit(id)
	local panel = exivaWindow:recursiveGetChildById(id)

	return panel and panel:getChildById("textEdit")
end

local function updateExivaEnabledState()
	if not isExivaWindowOpen() then
		return
	end

	local allowAll = exivaWindow:recursiveGetChildById("allowEveryoneRadio"):isChecked()
	local groupsPanel = exivaWindow:recursiveGetChildById("groupsPanel")

	for _, child in ipairs(groupsPanel:getChildren()) do
		child:setEnabled(not allowAll)
	end

	local characterEnabled = not allowAll and exivaWindow:recursiveGetChildById("allowCharacterWhitelist"):isChecked()
	local guildEnabled = not allowAll and exivaWindow:recursiveGetChildById("allowGuildWhitelist"):isChecked()

	getWhitelistEdit("characterWhitelist"):setEnabled(characterEnabled)
	getWhitelistEdit("guildWhitelist"):setEnabled(guildEnabled)
end

local function setWhitelistText(id, list)
	local edit = getWhitelistEdit(id)

	if not edit then
		return
	end

	local text = table.concat(list, "\n")

	edit:setText(text)
	edit:setCursorPos(#text)
end

local function fillExivaWindow()
	if not isExivaWindowOpen() then
		return
	end

	local radio = exivaOptions.allowAll and "allowEveryoneRadio" or "allowSelectedRadio"

	exivaRadioGroup:selectWidget(exivaWindow:recursiveGetChildById(radio), true)
	exivaWindow:recursiveGetChildById("allowGuild"):setChecked(exivaOptions.allowGuild)
	exivaWindow:recursiveGetChildById("allowParty"):setChecked(exivaOptions.allowParty)
	exivaWindow:recursiveGetChildById("allowVips"):setChecked(exivaOptions.allowVips)
	exivaWindow:recursiveGetChildById("allowCharacterWhitelist"):setChecked(exivaOptions.allowCharacterWhitelist)
	exivaWindow:recursiveGetChildById("allowGuildWhitelist"):setChecked(exivaOptions.allowGuildWhitelist)
	setWhitelistText("characterWhitelist", exivaOptions.characters)
	setWhitelistText("guildWhitelist", exivaOptions.guilds)
	updateExivaEnabledState()
end

function onReceiveExivaOptions(allowAll, allowGuild, allowParty, allowVips, allowCharacterWhitelist, allowGuildWhitelist, addedCharacters, removedCharacters, addedGuilds, removedGuilds)
	exivaOptions.allowAll = allowAll and true or false
	exivaOptions.allowGuild = allowGuild and true or false
	exivaOptions.allowParty = allowParty and true or false
	exivaOptions.allowVips = allowVips and true or false
	exivaOptions.allowCharacterWhitelist = allowCharacterWhitelist and true or false
	exivaOptions.allowGuildWhitelist = allowGuildWhitelist and true or false

	applyEntries(exivaOptions.characters, addedCharacters, removedCharacters)
	applyEntries(exivaOptions.guilds, addedGuilds, removedGuilds)
	fillExivaWindow()
end

function onExivaOptionToggled()
	updateExivaEnabledState()
end

function closeExivaOptions()
	if exivaRadioGroup then
		exivaRadioGroup:destroy()

		exivaRadioGroup = nil
	end

	if isExivaWindowOpen() then
		exivaWindow:destroy()
	end

	exivaWindow = nil
end

function applyExivaOptions()
	if not isExivaWindowOpen() or not g_game.canExivaOptions() then
		return
	end

	local characters = parseLines(getWhitelistEdit("characterWhitelist"):getText())
	local guilds = parseLines(getWhitelistEdit("guildWhitelist"):getText())
	local addedCharacters, removedCharacters = diffEntries(exivaOptions.characters, characters)
	local addedGuilds, removedGuilds = diffEntries(exivaOptions.guilds, guilds)

	g_game.sendExivaOptions(exivaWindow:recursiveGetChildById("allowEveryoneRadio"):isChecked(), exivaWindow:recursiveGetChildById("allowGuild"):isChecked(), exivaWindow:recursiveGetChildById("allowParty"):isChecked(), exivaWindow:recursiveGetChildById("allowVips"):isChecked(), exivaWindow:recursiveGetChildById("allowCharacterWhitelist"):isChecked(), exivaWindow:recursiveGetChildById("allowGuildWhitelist"):isChecked(), addedCharacters, removedCharacters, addedGuilds, removedGuilds)
end

function onExivaOptionsOk()
	applyExivaOptions()
	closeExivaOptions()
end

function openExivaOptions()
	if not g_game.isOnline() or not g_game.canExivaOptions() then
		return
	end

	if isExivaWindowOpen() then
		exivaWindow:raise()
		exivaWindow:focus()

		return
	end

	exivaWindow = g_ui.displayUI("exiva")

	if not exivaWindow then
		return
	end

	exivaRadioGroup = UIRadioGroup.create()

	exivaRadioGroup:addWidget(exivaWindow:recursiveGetChildById("allowEveryoneRadio"))
	exivaRadioGroup:addWidget(exivaWindow:recursiveGetChildById("allowSelectedRadio"))

	exivaRadioGroup.onSelectionChange = function()
		updateExivaEnabledState()
	end

	fillExivaWindow()
	exivaWindow:raise()
	exivaWindow:focus()
end

function updateExivaButton()
	if not consolePanel then
		return
	end

	local button = consolePanel:recursiveGetChildById("exivaButton")

	if not button then
		return
	end

	if g_game.canExivaOptions() then
		button:setEnabled(true)
		button:setTooltip(tr("Exiva Options"))
	else
		button:setEnabled(false)
		button:setTooltip(tr("Exiva Options are only available on Optional PvP game worlds"))
	end
end

function onExivaGameStart()
	updateExivaButton()
end

function onExivaGameEnd()
	closeExivaOptions()

	exivaOptions = newExivaOptions()

	updateExivaButton()
end

function initExivaOptions()
	connect(g_game, {
		onReceiveExivaOptions = onReceiveExivaOptions,
		onGameStart = onExivaGameStart,
		onGameEnd = onExivaGameEnd
	})

	updateExivaButton()
end

function terminateExivaOptions()
	disconnect(g_game, {
		onReceiveExivaOptions = onReceiveExivaOptions,
		onGameStart = onExivaGameStart,
		onGameEnd = onExivaGameEnd
	})

	closeExivaOptions()
end
