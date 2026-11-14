-- chunkname: @/game_taskboard/game_taskboard.lua

TaskBoard = {}

local TAB_BOUNTY = "bounty"
local TAB_WEEKLY = "weekly"
local TAB_SHOP = "shop"
local CLIENT_EVENT_TYPE_BOUNTY_TASK = 11
local BOUNTY_SHORTCUT_HIGHLIGHT_ID = "taskBoardShortcutHighlight"
local bountyShortcutHighlightActive = false

local function getTaskBoardMainButton()
	if not modules.game_mainpanel or not modules.game_mainpanel.getButton then
		return nil
	end

	local button = modules.game_mainpanel.getButton("taskBoard")

	if not button or button:isDestroyed() then
		return nil
	end

	TaskBoard.mainButton = button

	return button
end

local function syncBountyShortcutHighlight()
	local button = getTaskBoardMainButton()

	if not button then
		return
	end

	local highlight = button:recursiveGetChildById(BOUNTY_SHORTCUT_HIGHLIGHT_ID)

	if not highlight then
		highlight = g_ui.createWidget("UIWidget", button)

		if not highlight then
			return
		end

		highlight:setId(BOUNTY_SHORTCUT_HIGHLIGHT_ID)
		highlight:setSize({
			width = 22,
			height = 22
		})
		highlight:setPhantom(true)
		highlight:setClipping(false)
		highlight:setImageSource("/images/animations/button-highlight-22x22")
		highlight:breakAnchors()
		highlight:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
		highlight:addAnchor(AnchorVerticalCenter, "parent", AnchorVerticalCenter)
	end

	highlight:setVisible(bountyShortcutHighlightActive)
end

function TaskBoard:setBountyShortcutHighlightVisible(show)
	bountyShortcutHighlightActive = show == true or show == 1

	syncBountyShortcutHighlight()
end

function TaskBoard:clearBountyShortcutHighlight()
	self:setBountyShortcutHighlightVisible(false)
end

local function onTaskBoardClientEvent(eventType)
	if eventType == CLIENT_EVENT_TYPE_BOUNTY_TASK then
		TaskBoard:setBountyShortcutHighlightVisible(true)
	end
end

local function onTaskBoardGameStart()
	scheduleEvent(syncBountyShortcutHighlight, 0)
end

function TaskBoard:is1533()
	return g_game.getClientVersion() >= 1533
end

-- Official 15.33 artwork is not shipped in git; the owner drops it under data/images/game/1533/taskboard/
-- (see UI-1533-ASSETS.md). Returns the image path when the file is there, nil otherwise, so every caller
-- keeps a fallback and the board works without the files.
local assetCache = {}

function TaskBoard:asset1533(name)
	local path = "/images/game/1533/taskboard/" .. name

	if assetCache[path] == nil then
		assetCache[path] = g_resources.fileExists(path .. ".png") and true or false
	end

	return assetCache[path] and path or nil
end

TaskBoard.resourceTypes = {
	soulSeals = 87,
	bountyPoints = 86,
	taskHunting = 50
}

function TaskBoard:formatNumberWithCommas(n)
	local s = tostring(n)
	local pos = string.len(s) % 3

	if pos == 0 then
		pos = 3
	end

	local t = s:sub(1, pos)

	for i = pos + 1, #s, 3 do
		t = t .. "," .. s:sub(i, i + 2)
	end

	return t
end

function TaskBoard:getResourceBalance(str)
	local t = self.resourceTypes[str]

	if not t then
		return 0
	end

	local player = g_game.getLocalPlayer()

	if not player then
		return 0
	end

	return player:getResourceBalance(t)
end

function TaskBoard:updateMenuSelection(tab)
	local bountyOn = tab == TAB_BOUNTY
	local weeklyOn = tab == TAB_WEEKLY
	local shopOn = tab == TAB_SHOP

	if self.menuBounty then
		self.menuBounty:setChecked(bountyOn)
		self.menuBounty:setOn(bountyOn)
	end

	if self.menuWeekly then
		self.menuWeekly:setChecked(weeklyOn)
		self.menuWeekly:setOn(weeklyOn)
	end

	if self.menuShop then
		self.menuShop:setChecked(shopOn)
		self.menuShop:setOn(shopOn)
	end
end

local function onTaskBoardGameEnd()
	TaskBoard:clearBountyShortcutHighlight()

	if TaskBoard.mainWindow then
		TaskBoard.mainWindow:setVisible(false)
	end

	if TaskBoard.mainButton then
		TaskBoard.mainButton:setOn(false)
	end
end

local function onTaskBoardResourceBalance()
	if not TaskBoard.BountyTaskPoints or not TaskBoard.TaskHuntingPoints or not TaskBoard.SoulSealsPoints then
		return
	end

	TaskBoard.BountyTaskPoints:getChildById("value"):setText(TaskBoard:formatNumberWithCommas(TaskBoard:getResourceBalance("bountyPoints")))
	TaskBoard.TaskHuntingPoints:getChildById("value"):setText(TaskBoard:formatNumberWithCommas(TaskBoard:getResourceBalance("taskHunting")))
	TaskBoard.SoulSealsPoints:getChildById("value"):setText(TaskBoard:formatNumberWithCommas(TaskBoard:getResourceBalance("soulSeals")))
end

local TAB_ORDER = {
	TAB_BOUNTY,
	TAB_WEEKLY,
	TAB_SHOP
}

function TaskBoard:showTab(tab)
	self.currentTab = tab

	self:updateMenuSelection(tab)

	-- the Preferred List belongs to the Bounty tab; do not leave it over another tab
	if tab ~= TAB_BOUNTY and self.preferredListPanel and self.preferredListPanel:isVisible() and self.BountyTask then
		self.BountyTask:closePreferredList()
	end

	if self.bountyTaskPanel then
		self.bountyTaskPanel:setVisible(tab == TAB_BOUNTY)
	end

	if self.weeklyPanel then
		self.weeklyPanel:setVisible(tab == TAB_WEEKLY)
	end

	if self.taskShopPanel then
		self.taskShopPanel:setVisible(tab == TAB_SHOP)
	end

	if self.WeeklyTask and self.WeeklyTask.updateOverlayVisibility then
		self.WeeklyTask:updateOverlayVisibility()
	end
end

function TaskBoard:showBountyTab()
	self:clearBountyShortcutHighlight()
	self:showTab(TAB_BOUNTY)
end

function TaskBoard:showWeeklyTab()
	self:showTab(TAB_WEEKLY)
end

function TaskBoard:showTaskShopTab()
	self:showTab(TAB_SHOP)
end

-- Tab / Shift+Tab walk through the three tabs like the official tab bar; off while the Preferred List
-- (with its search field) is open
function TaskBoard:cycleTab(step)
	if not self.mainWindow or not self.mainWindow:isVisible() then
		return
	end

	if self.preferredListPanel and self.preferredListPanel:isVisible() then
		return
	end

	local index = 1

	for i, tab in ipairs(TAB_ORDER) do
		if tab == self.currentTab then
			index = i
		end
	end

	index = (index - 1 + step) % #TAB_ORDER + 1

	local tab = TAB_ORDER[index]

	if tab == TAB_BOUNTY then
		self:showBountyTab()
	else
		self:showTab(tab)
	end
end

local function cycleTabForward()
	TaskBoard:cycleTab(1)
end

local function cycleTabBackward()
	TaskBoard:cycleTab(-1)
end

-- the bottom bar shows Bounty Points, Hunting Task Points and Soulseals; ask for exactly those
-- (0xED with the resource type) instead of an untyped request
local function requestTaskBoardBalances()
	if not g_game.sendResourceBalance then
		return
	end

	g_game.sendResourceBalance(TaskBoard.resourceTypes.bountyPoints)
	g_game.sendResourceBalance(TaskBoard.resourceTypes.taskHunting)
	g_game.sendResourceBalance(TaskBoard.resourceTypes.soulSeals)

	if TaskBoard:is1533() then
		g_game.sendResourceBalance(ResourceTypes.BOUNTY_REROLL_TOKENS)
	end
end

function init()
	connect(g_game, {
		onGameStart = onTaskBoardGameStart,
		onGameEnd = onTaskBoardGameEnd,
		onResourceBalance = onTaskBoardResourceBalance,
		onClientEvent = onTaskBoardClientEvent
	})
	g_ui.importStyle("menus/bounty_task")
	g_ui.importStyle("menus/weekly_task")
	g_ui.importStyle("menus/task_shop")

	TaskBoard.mainWindow = g_ui.displayUI("game_taskboard")

	TaskBoard.mainWindow:setId("taskboard")
	TaskBoard.mainWindow:setVisible(false)

	TaskBoard.menuBounty = TaskBoard.mainWindow:recursiveGetChildById("BountyTaskMenu")
	TaskBoard.menuWeekly = TaskBoard.mainWindow:recursiveGetChildById("WeeklyTaskMenu")
	TaskBoard.menuShop = TaskBoard.mainWindow:recursiveGetChildById("TaskShopMenu")
	TaskBoard.bountyTaskPanel = TaskBoard.mainWindow:recursiveGetChildById("bountyTaskPanel")
	TaskBoard.weeklyPanel = TaskBoard.mainWindow:recursiveGetChildById("weeklyPanel")
	TaskBoard.taskShopPanel = TaskBoard.mainWindow:recursiveGetChildById("taskShopPanel")
	TaskBoard.preferredListPanel = TaskBoard.mainWindow:recursiveGetChildById("preferredListPanel")
	TaskBoard.chainTransparent = TaskBoard.mainWindow:recursiveGetChildById("chainTransparent")
	TaskBoard.chainTransparentWeekly = TaskBoard.mainWindow:recursiveGetChildById("chainTransparentWeekly")
	TaskBoard.weeklyProgressPanel = TaskBoard.mainWindow:recursiveGetChildById("weeklyProgressPanel")

	if not TaskBoard.weeklyProgressPanel then
		print("[Warning] weeklyProgressPanel is nil! Check that the ID 'weeklyProgressPanel' is correct in weekly_task.otui and that the file is imported before displayUI.")
	end

	if not TaskBoard.chainTransparentWeekly then
		print("[Warning] chainTransparentWeekly is nil! Check that the ID 'chainTransparentWeekly' is correct in weekly_task.otui and that the file is imported before displayUI.")
	end

	TaskBoard.BountyTaskPoints = TaskBoard.mainWindow:recursiveGetChildById("bountyPointsPanel")
	TaskBoard.TaskHuntingPoints = TaskBoard.mainWindow:recursiveGetChildById("huntingPointsPanel")
	TaskBoard.SoulSealsPoints = TaskBoard.mainWindow:recursiveGetChildById("soulSealsPanel")

	TaskBoard:updateMenuSelection(TAB_BOUNTY)
	TaskBoard.currentTab = TAB_BOUNTY
	g_keyboard.bindKeyPress("Tab", cycleTabForward, TaskBoard.mainWindow)
	g_keyboard.bindKeyPress("Shift+Tab", cycleTabBackward, TaskBoard.mainWindow)
	TaskBoard.BountyTask:init()
	TaskBoard.TaskShop:init()
	TaskBoard.WeeklyTask:init()
	scheduleEvent(syncBountyShortcutHighlight, 0)
end

function terminate()
	disconnect(g_game, {
		onGameStart = onTaskBoardGameStart,
		onGameEnd = onTaskBoardGameEnd,
		onResourceBalance = onTaskBoardResourceBalance,
		onClientEvent = onTaskBoardClientEvent
	})
	TaskBoard:clearBountyShortcutHighlight()

	if TaskBoard.mainWindow then
		g_keyboard.unbindKeyPress("Tab", cycleTabForward, TaskBoard.mainWindow)
		g_keyboard.unbindKeyPress("Shift+Tab", cycleTabBackward, TaskBoard.mainWindow)
	end

	TaskBoard.BountyTask:terminate()
	TaskBoard.TaskShop:terminate()
	TaskBoard.WeeklyTask:terminate()
end

function TaskBoard:toggleWindow(mode)
	if not self.mainWindow:isVisible() then
		requestTaskBoardBalances()
		self.mainWindow:setVisible(true)
		self.mainWindow:focus()

		if mode == "bounty" then
			self:showBountyTab()
		elseif mode == "weekly" then
			self:showWeeklyTab()
		elseif mode == "shop" then
			self:showTaskShopTab()
		end

		g_game.sendOpenMenuTaskBoardAction(0)
		g_game.sendOpenMenuTaskBoardAction(1)
		g_game.sendOpenMenuTaskBoardAction(2)
		g_modalManager.show(self.mainWindow)
	else
		self.mainWindow:setVisible(false)

		if self.mainButton then
			self.mainButton:setOn(false)
		end

		g_modalManager.hide(self.mainWindow)
	end
end
