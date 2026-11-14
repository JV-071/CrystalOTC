-- chunkname: @/game_taskboard/menus/weekly_task.lua

TaskBoard.WeeklyTask = {}

local WeeklyTask = TaskBoard.WeeklyTask

WeeklyTask.mainWindow = nil
WeeklyTask.isWeeklyTaskActive = false

function WeeklyTask:updateOverlayVisibility()
	local canShowOverlay = self.isWeeklyTaskActive and TaskBoard.mainWindow and TaskBoard.mainWindow:isVisible() and TaskBoard.weeklyPanel and TaskBoard.weeklyPanel:isVisible() and TaskBoard.chainTransparentWeekly and TaskBoard.weeklyProgressPanel

	if canShowOverlay then
		TaskBoard.chainTransparentWeekly:show()
		TaskBoard.weeklyProgressPanel:show()
		TaskBoard.weeklyProgressPanel:raise()
		TaskBoard.weeklyProgressPanel:focus()

		return
	end

	if TaskBoard.weeklyProgressPanel then
		TaskBoard.weeklyProgressPanel:hide()
	end

	if TaskBoard.chainTransparentWeekly then
		TaskBoard.chainTransparentWeekly:hide()
	end
end

local function capitalizeWords(str)
	return (str or ""):gsub("(%a)([%w_']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end)
end

local function getKillSlotsList()
	local weeklyPanel = TaskBoard.weeklyPanel

	if not weeklyPanel then
		return nil
	end

	local killTasks = weeklyPanel:recursiveGetChildById("killTasks")

	if not killTasks then
		return nil
	end

	return killTasks:recursiveGetChildById("killSlotsList")
end

local function getDeliverySlotsList()
	local weeklyPanel = TaskBoard.weeklyPanel

	if not weeklyPanel then
		return nil
	end

	local deliveryTasks = weeklyPanel:recursiveGetChildById("deliveryTasks")

	if not deliveryTasks then
		return nil
	end

	return deliveryTasks:recursiveGetChildById("deliverySlotsList")
end

local function setKillSlotCreature(panel, raceData, isAnyCreature)
	local outfitIcon = panel:getChildById("outfitIcon")

	if not outfitIcon then
		return
	end

	local anyCreatureIcon = outfitIcon:getChildById("anyCreatureIcon")

	if raceData and raceData.outfit and raceData.raceId ~= 0 then
		if anyCreatureIcon then
			anyCreatureIcon:hide()
		end

		outfitIcon:setOutfit(raceData.outfit)
		outfitIcon:setFixedCreatureSize(true)
		outfitIcon:setVisible(true)

		local c = outfitIcon:getCreature()

		if c then
			c:setStaticWalking(1000)
		end
	elseif isAnyCreature then
		-- Keep the dark /images/ui/item slot frame (from the .otui) and show the arbitrary
		-- icon as a child over it, so "Any Creature" matches the other slots instead of
		-- replacing the frame with a lighter standalone icon.
		outfitIcon:setVisible(true)

		if anyCreatureIcon then
			anyCreatureIcon:show()
		end
	else
		outfitIcon:setVisible(false)

		if anyCreatureIcon then
			anyCreatureIcon:hide()
		end
	end
end

local function setSlotDone(panel, done, countIds)
	for _, id in ipairs(countIds) do
		local label = panel:getChildById(id)

		if label then
			label:setVisible(not done)
		end
	end

	-- the plain "of" label between the counts has no id
	for _, child in ipairs(panel:getChildren()) do
		if child:getText() == "of" then
			child:setVisible(not done)
		end
	end

	local doneIcon = panel:getChildById("doneIcon")

	if doneIcon then
		doneIcon:setVisible(done)
	end
end

local function confirmDelivery(entry, itemName)
	local count = entry.totalItems or 0
	local taskId = entry.taskId or 0
	local box

	local function close()
		if box then
			box:destroy()
			box = nil
		end
	end

	box = displayGeneralBox(tr("Confirm"), tr("Do you really want to deliver %sx %s?", TaskBoard:formatNumberWithCommas(count), itemName), {
		{
			text = tr("Yes"),
			callback = function()
				close()
				g_game.sendDeliveryTask(taskId)
			end
		},
		{
			text = tr("No"),
			callback = close
		},
		anchor = AnchorHorizontalCenter
	}, function()
		close()
		g_game.sendDeliveryTask(taskId)
	end, close)
end

-- clicking the delivery item offers the Cyclopedia entry (the board is modal, so it closes first)
local function onDeliveryItemClicked(itemId)
	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	local modCyc = modules.game_cyclopedia
	local cycApi = modCyc and modCyc.Cyclopedia

	if not thingType or not thingType.isCyclopediaItem or not thingType:isCyclopediaItem() or not cycApi or not cycApi.openItemInCyclopedia then
		return
	end

	local menu = g_ui.createWidget("PopupMenu")

	menu:setGameMenu(true)
	menu:addOption(tr("Cyclopedia"), function()
		if TaskBoard.mainWindow and TaskBoard.mainWindow:isVisible() then
			TaskBoard:toggleWindow()
		end

		if modCyc.show then
			modCyc.show("items")
		end

		cycApi.openItemInCyclopedia(itemId)
	end)
	menu:display(g_window.getMousePosition())
end

local function fillKillSlot(panel, name, current, target, raceData, isAnyCreature)
	if not panel then
		return
	end

	local displayName = capitalizeWords(name or "")

	if #displayName > 17 then
		displayName = displayName:sub(1, 17) .. "..."
	end

	panel:setText(displayName)
	setKillSlotCreature(panel, raceData, isAnyCreature)

	local done = (target or 0) > 0 and (current or 0) >= target
	local currentLabel = panel:getChildById("killAnyMonstersLabel")

	if currentLabel then
		currentLabel:setText(TaskBoard:formatNumberWithCommas(current or 0))
		currentLabel:setColor("#d33c3c")
	end

	local totalLabel = panel:getChildById("totalKillAnyMonstersLabel")

	if totalLabel then
		totalLabel:setText(TaskBoard:formatNumberWithCommas(target or 0))
	end

	-- like the official board: a finished task shows only a check mark
	setSlotDone(panel, done, { "killAnyMonstersLabel", "totalKillAnyMonstersLabel" })
end

local function fillDeliverySlot(panel, entry)
	if not panel or not entry then
		return
	end

	local thingType = g_things.getThingType(entry.taskItemId, 0)
	local fullName = ""

	if thingType then
		fullName = thingType:getName() or ""

		local itemName = capitalizeWords(fullName)

		if #itemName > 17 then
			itemName = itemName:sub(1, 17) .. "..."
		end

		panel:setText(itemName)
	end

	local itemIcon = panel:getChildById("itemIcon")

	if itemIcon then
		itemIcon:setItemId(entry.taskItemId or 0)
		itemIcon:setTooltip(capitalizeWords(fullName))

		local itemId = entry.taskItemId or 0

		function itemIcon.onMouseRelease(widget, mousePos, mouseButton)
			if mouseButton == MouseLeftButton or mouseButton == MouseRightButton then
				onDeliveryItemClicked(itemId)

				return true
			end

			return false
		end
	end

	local delivered = (entry.completed or 0) ~= 0
	local currentLabel = panel:getChildById("currentDeliveryLabel")

	if currentLabel then
		currentLabel:setText(TaskBoard:formatNumberWithCommas(entry.count or 0))

		if entry.count >= entry.totalItems then
			currentLabel:setColor("#44ad25")
		else
			currentLabel:setColor("#d33c3c")
		end
	end

	setSlotDone(panel, delivered, { "currentDeliveryLabel", "totalDeliveryLabel" })

	local totalLabel = panel:getChildById("totalDeliveryLabel")

	if totalLabel then
		totalLabel:setText(TaskBoard:formatNumberWithCommas(entry.totalItems or 0))
	end

	local deliverButton = panel:getChildById("deliverButton")

	if deliverButton then
		-- the server only accepts a delivery of the full amount (inventory, stash and depot together)
		local hasItems = (entry.count or 0) >= (entry.totalItems or 0) and (entry.totalItems or 0) > 0

		deliverButton:setVisible(not delivered)
		deliverButton:setEnabled(hasItems and not delivered)

		function deliverButton.onClick()
			confirmDelivery(entry, fullName)
		end
	end
end

local WEEKLY_KILL_TRACKER_MAX_SLOTS = 9
local WEEKLY_ANY_CREATURE_ICON = "/modules/game_taskboard/images/icon-arbitrarymonster"
local WEEKLY_CREATURETRACK_NO_CREATURE_IMG = "/images/game/prey/prey-noprey-small"
local WEEKLY_TRACKER_TOOLTIP_FOOTER = "Click in this window to open the Task Board dialog."

local function buildWeeklyTrackerActiveTooltip(creatureName, killed, total)
	local header = string.format("Creature: %s\nAmount: %s / %s", creatureName, TaskBoard:formatNumberWithCommas(killed), TaskBoard:formatNumberWithCommas(total))

	return header .. "\n\n" .. tr(WEEKLY_TRACKER_TOOLTIP_FOOTER)
end

local function refreshBountyKillTrackerIfAvailable()
	local bounty = modules.game_taskboard and modules.game_taskboard.TaskBoard and modules.game_taskboard.TaskBoard.BountyTask

	if bounty and bounty.refreshKillTracker then
		bounty.refreshKillTracker()
	end
end

local function getWeeklyTrackerSlot(slotIndex)
	local prey = modules.game_prey

	if not prey or not prey.preyTracker or prey.preyTracker:isDestroyed() then
		return nil
	end

	local contents = prey.preyTracker.contentsPanel

	if not contents then
		return nil
	end

	return contents:getChildById("wslot" .. slotIndex)
end

local function setWeeklyKillTrackerUnused(slotIndex)
	local slot = getWeeklyTrackerSlot(slotIndex)

	if not slot then
		return
	end

	slot:setVisible(false)

	local creature = slot:getChildById("creature")
	local noCreature = slot:getChildById("noCreature")
	local nameLabel = slot:getChildById("creatureName")
	local timeBar = slot:getChildById("time")

	if creature then
		creature:setVisible(false)
	end

	if noCreature then
		noCreature:setImageSource(WEEKLY_CREATURETRACK_NO_CREATURE_IMG)
		noCreature:setVisible(true)
	end

	if nameLabel then
		nameLabel:setText(tr("Inactive"))
	end

	if timeBar then
		timeBar:setPercent(0)
	end

	slot:setTooltip("")
end

local function setWeeklyTrackerSelected(slotIndex, raceId, monstersKilled, totalKills, isAnyCreature)
	local slot = getWeeklyTrackerSlot(slotIndex)

	if not slot then
		return
	end

	slot:setVisible(true)

	local creature = slot:getChildById("creature")
	local noCreature = slot:getChildById("noCreature")
	local nameLabel = slot:getChildById("creatureName")
	local timeBar = slot:getChildById("time")
	local creatureName = "?"

	if isAnyCreature then
		creatureName = tr("Any Creature")

		if creature then
			creature:setVisible(false)
		end

		if noCreature then
			noCreature:setImageSource(WEEKLY_ANY_CREATURE_ICON)
			noCreature:setImageSize({
				width = 18,
				height = 14
			})
			noCreature:setCenter(true)
			noCreature:setVisible(true)
		end
	else
		local rid = tonumber(raceId) or 0
		local raceData = g_things.getRaceData(rid)

		creatureName = (raceData and raceData.raceId ~= 0 and raceData.name and raceData.name ~= "") and raceData.name or (rid > 0 and string.format("Creature (%d)", rid) or "?")

		if creature then
			if raceData and raceData.outfit then
				creature:setOutfit(raceData.outfit)
				creature:getCreature():setStaticWalking(1000)
				creature:setVisible(true)
			else
				creature:setVisible(false)
			end
		end

		if noCreature then
			noCreature:setImageSource(WEEKLY_CREATURETRACK_NO_CREATURE_IMG)
			noCreature:setVisible(false)
		end
	end

	if nameLabel then
		if isAnyCreature then
			nameLabel:setText(capitalizeWords(creatureName))
		else
			nameLabel:setText(modules.game_prey.formatKillTrackerCreatureName(creatureName))
		end
	end

	local killed = tonumber(monstersKilled) or 0
	local total = tonumber(totalKills) or 0

	if timeBar then
		local percent = 0

		if total > 0 then
			percent = math.min(100, math.floor(killed / total * 100))
		end

		timeBar:setPercent(percent)
	end

	slot:setTooltip(buildWeeklyTrackerActiveTooltip(capitalizeWords(creatureName), killed, total))
end

local function layoutWeeklyKillTrackerSlots(usedCount)
	for i = 1, WEEKLY_KILL_TRACKER_MAX_SLOTS do
		if usedCount < i then
			setWeeklyKillTrackerUnused(i)
		end
	end
end

local function buildKillSlots(weeklyTasks)
	local killSlotsList = getKillSlotsList()

	if not killSlotsList then
		return
	end

	local killEntries = weeklyTasks.killEntries or {}

	if #killEntries == 0 then
		killSlotsList:updateLayout()
		layoutWeeklyKillTrackerSlots(0)

		if modules.game_prey and modules.game_prey.updateTrackerHeight then
			modules.game_prey.updateTrackerHeight()
		end

		refreshBountyKillTrackerIfAvailable()

		return
	end

	killSlotsList:destroyChildren()

	local ok, anyPanel = pcall(g_ui.createWidget, "KillSlots", killSlotsList)

	if not ok then
		print("[WeeklyTask] error creating KillSlots (Any Creature):", tostring(anyPanel))

		return
	end

	fillKillSlot(anyPanel, "Any Creature", weeklyTasks.killedsAnyMonsters, weeklyTasks.killsAnyMonsters, nil, true)
	setWeeklyTrackerSelected(1, nil, weeklyTasks.killedsAnyMonsters, weeklyTasks.killsAnyMonsters, true)

	local unlockKillButton = killSlotsList:getParent():getChildById("unlockKillButton")

	if unlockKillButton then
		if #killEntries > 5 then
			unlockKillButton:setVisible(false)
		else
			unlockKillButton:setVisible(true)
		end
	end

	local maxSpeciesSlots = WEEKLY_KILL_TRACKER_MAX_SLOTS - 1

	for slotIndex, entry in ipairs(killEntries) do
		local ok2, panel = pcall(g_ui.createWidget, "KillSlots", killSlotsList)

		if not ok2 then
			print("[WeeklyTask] error creating KillSlots:", tostring(panel))

			break
		end

		local rid = tonumber(entry.raceId) or 0
		local raceData = g_things.getRaceData(rid)
		local raceName = (raceData and raceData.raceId ~= 0 and raceData.name and raceData.name ~= "") and raceData.name or (rid > 0 and string.format("Creature (%d)", rid) or "?")

		fillKillSlot(panel, raceName, entry.totalMonsterKilleds, entry.totalKills, raceData, false)

		if slotIndex <= maxSpeciesSlots then
			setWeeklyTrackerSelected(slotIndex + 1, rid, entry.totalMonsterKilleds, entry.totalKills, false)
		end
	end

	local usedTrackerSlots = math.min(1 + #killEntries, WEEKLY_KILL_TRACKER_MAX_SLOTS)

	layoutWeeklyKillTrackerSlots(usedTrackerSlots)
	killSlotsList:updateLayout()

	if modules.game_prey and modules.game_prey.updateTrackerHeight then
		modules.game_prey.updateTrackerHeight()
	end

	refreshBountyKillTrackerIfAvailable()
end

local function buildDeliverySlots(weeklyTasks)
	local deliverySlotsList = getDeliverySlotsList()

	if not deliverySlotsList then
		return
	end

	deliverySlotsList:destroyChildren()

	local unlockDeliveryButton = deliverySlotsList:getParent():getChildById("unlockDeliveryButton")

	if unlockDeliveryButton then
		if #weeklyTasks.deliveryEntries > 6 then
			unlockDeliveryButton:setVisible(false)
		else
			unlockDeliveryButton:setVisible(true)
		end
	end

	if weeklyTasks.deliveryEntries then
		for _, entry in ipairs(weeklyTasks.deliveryEntries) do
			local ok, panel = pcall(g_ui.createWidget, "DeliverySlots", deliverySlotsList)

			if not ok then
				print("[WeeklyTask] error creating DeliverySlots:", tostring(panel))

				break
			end

			fillDeliverySlot(panel, entry)
		end
	end

	deliverySlotsList:updateLayout()
end

local PROGRESS_BAR_INNER_WIDTH = 577
local PROGRESS_BAR_TOTAL_TASKS = 18
local PROGRESS_BAR_FILL_IMAGE = "/images/bars/progressbar-green-large"
local STORE_WEEKLY_OFFER_NAME = "Permanent Weekly Task Expansion"

local function openWeeklyTaskStoreOffer()
	local store = modules and modules.game_store

	if not store or not store.openWeeklyTaskExpansion then
		return
	end

	if TaskBoard and TaskBoard.mainWindow and TaskBoard.mainWindow:isVisible() then
		TaskBoard:toggleWindow()
	end

	store.openWeeklyTaskExpansion()
end

local function wireUnlockButton(button)
	if not button then
		return
	end

	button:setTooltip(tr("Open Store: %s", STORE_WEEKLY_OFFER_NAME))

	function button.onClick()
		openWeeklyTaskStoreOffer()
	end
end

-- level gates of the weekly difficulties (IOWeeklyTasks::getUnlockedDifficulty: 30 / 150 / 300)
local DIFFICULTY_REQUIRED_LEVEL = {
	[0] = 0,
	30,
	150,
	300
}
local DIFFICULTY_BUTTON_TOOLTIPS = {
	[0] = tr("Beginner tasks include easy creatures."),
	tr("Adept tasks include easy and medium creatures. (Requires level %d)", DIFFICULTY_REQUIRED_LEVEL[1]),
	tr("Expert tasks include medium and hard creatures. (Requires level %d)", DIFFICULTY_REQUIRED_LEVEL[2]),
	tr("Master tasks include hard and challenging creatures. (Requires level %d)", DIFFICULTY_REQUIRED_LEVEL[3])
}

local function wireDifficultyButton(button, difficulty)
	if not button then
		return
	end

	button:setTooltip(DIFFICULTY_BUTTON_TOOLTIPS[difficulty])

	function button.onClick()
		g_game.sendSelectDifficultyWeeklyTasks(difficulty)
	end
end

local function buildBarProgress(weeklyTasks)
	if not TaskBoard.weeklyPanel then
		return
	end

	local progressBar = TaskBoard.weeklyPanel:recursiveGetChildById("progressBar")

	if not progressBar then
		return
	end

	local totalKills = weeklyTasks.kill or 0
	local totalDeliveries = weeklyTasks.delivery or 0
	local total = math.max(0, math.min(totalKills + totalDeliveries, PROGRESS_BAR_TOTAL_TASKS))
	local fillWidth = math.floor(total / PROGRESS_BAR_TOTAL_TASKS * PROGRESS_BAR_INNER_WIDTH + 0.5)
	local fill = progressBar:getChildById("progressFill")

	if not fill then
		fill = g_ui.createWidget("UIWidget", progressBar)

		fill:setId("progressFill")
		fill:setPhantom(true)
		fill:setImageSource(PROGRESS_BAR_FILL_IMAGE)
		fill:setImageRepeated(true)
		fill:addAnchor(AnchorTop, "parent", AnchorTop)
		fill:addAnchor(AnchorLeft, "parent", AnchorLeft)
		fill:addAnchor(AnchorBottom, "parent", AnchorBottom)
		fill:setMarginTop(1)
		fill:setMarginBottom(1)
		fill:setMarginLeft(1)
	end

	fill:setVisible(fillWidth > 0)
	fill:setWidth(fillWidth)
	progressBar:setTooltip(tr("Weekly Progress: %d / %d tasks", total, PROGRESS_BAR_TOTAL_TASKS))
end

-- Hunting Task Points per finished task and the multiplier by finished tasks, as the server computes them
-- (IOWeeklyTasks::getHTPPerKillTask / getHTPMultiplier); kill tasks pay by difficulty, delivery tasks 75
local HTP_PER_KILL_TASK = {
	[0] = 25,
	50,
	100,
	110
}
local HTP_PER_DELIVERY_TASK = 75

local function getHuntingTaskPointsMultiplier(completed)
	if completed >= 17 then
		return 8
	elseif completed >= 13 then
		return 5
	elseif completed >= 9 then
		return 3
	elseif completed >= 5 then
		return 2
	end

	return 1
end

local function buildHuntingPointsTooltip(weeklyTasks)
	local kills = weeklyTasks.kill or 0
	local deliveries = weeklyTasks.delivery or 0
	local perKill = HTP_PER_KILL_TASK[weeklyTasks.difficulty or 0] or HTP_PER_KILL_TASK[0]
	local multiplier = getHuntingTaskPointsMultiplier(kills + deliveries)
	local total = weeklyTasks.totalPoints or (kills * perKill + deliveries * HTP_PER_DELIVERY_TASK) * multiplier

	return table.concat({
		tr("Hunting Task Points:"),
		"",
		string.format("   %2d * %3d   (from Kill Tasks)", kills, perKill),
		string.format("+ %2d * %3d   (from Delivery Tasks)", deliveries, HTP_PER_DELIVERY_TASK),
		"----------------------------------",
		string.format("*      %d       (from completing Tasks)", multiplier),
		string.format("=      %s       Hunting Task Points", TaskBoard:formatNumberWithCommas(total))
	}, "\n")
end

local function buildXpInfo(weeklyTasks)
	local label = TaskBoard.weeklyPanel and TaskBoard.weeklyPanel:recursiveGetChildById("xpInfoLabel")

	if not label then
		return
	end

	local killXp = weeklyTasks.killTaskXp or 0
	local deliveryXp = weeklyTasks.deliveryTaskXp or 0

	if killXp == 0 and deliveryXp == 0 then
		label:setText("")
	elseif killXp == deliveryXp then
		label:setText(tr("Each task rewards you with %s XP.", TaskBoard:formatNumberWithCommas(killXp)))
	else
		label:setText(tr("Each kill task will reward you with %s XP and each delivery task will reward you with %s XP.", TaskBoard:formatNumberWithCommas(killXp), TaskBoard:formatNumberWithCommas(deliveryXp)))
	end
end

local function buildRewards(weeklyTasks)
	local huntingPoints = weeklyTasks.totalPoints or 0
	local soulSealsPoints = weeklyTasks.totalTasksCompleted or 0

	local help = TaskBoard.weeklyPanel and TaskBoard.weeklyPanel:recursiveGetChildById("huntingPointsHelp")

	if help then
		help:setTooltip(buildHuntingPointsTooltip(weeklyTasks))
	end

	if TaskBoard.weeklyPanel then
		local huntingPointsLabel = TaskBoard.weeklyPanel:recursiveGetChildById("huntingPointsLabel")

		if huntingPointsLabel then
			huntingPointsLabel:setText(huntingPoints)
		end

		local soulSealsPointsLabel = TaskBoard.weeklyPanel:recursiveGetChildById("soulSealsPointsLabel")

		if soulSealsPointsLabel then
			soulSealsPointsLabel:setText(soulSealsPoints)
		end
	end

	local timeStamp = weeklyTasks.mondayTime or 0
	local daysRemainingLabel = TaskBoard.weeklyPanel and TaskBoard.weeklyPanel:recursiveGetChildById("daysRemaining")

	if daysRemainingLabel and timeStamp > 0 then
		local diffSeconds = math.max(0, timeStamp - os.time())
		local daysRemaining = math.floor(diffSeconds / 86400)

		-- official: "N day(s) remaining", and "N hour(s) remaining" in red on the last day
		if daysRemaining >= 1 then
			daysRemainingLabel:setText(tr("%d day(s) remaining", daysRemaining))
			daysRemainingLabel:setColor("#c0c0c0")
		else
			daysRemainingLabel:setText(tr("%d hour(s) remaining", math.ceil(diffSeconds / 3600)))
			daysRemainingLabel:setColor("#d33c3c")
		end
	end
end

-- results of the finished week, shown above the difficulty choice
local function buildResults(weeklyTasks)
	local panel = TaskBoard.weeklyProgressPanel

	if not panel then
		return
	end

	local killCount = #(weeklyTasks.killEntries or {})

	if (weeklyTasks.killsAnyMonsters or 0) > 0 then
		killCount = killCount + 1
	end

	local deliveryCount = #(weeklyTasks.deliveryEntries or {})
	local show = weeklyTasks.weeklyTaskActive == 1 and (killCount > 0 or deliveryCount > 0)
	local killLabel = panel:getChildById("resultKillLabel")
	local deliveryLabel = panel:getChildById("resultDeliveryLabel")
	local rewardRow = panel:getChildById("resultRewardRow")

	killLabel:setVisible(show)
	deliveryLabel:setVisible(show)
	rewardRow:setVisible(show)

	if not show then
		return
	end

	killLabel:setText(tr("You have completed %d / %d kill tasks.", weeklyTasks.kill or 0, killCount))
	deliveryLabel:setText(tr("You have completed %d / %d delivery tasks.", weeklyTasks.delivery or 0, deliveryCount))

	local prefix = rewardRow:getChildById("resultRewardPrefix")
	local middle = rewardRow:getChildById("resultRewardMiddle")

	prefix:setText(tr("Total earned: %s", TaskBoard:formatNumberWithCommas(weeklyTasks.totalPoints or 0)))
	middle:setText(tr("and %s", TaskBoard:formatNumberWithCommas(weeklyTasks.totalTasksCompleted or 0)))
	rewardRow:setWidth(prefix:getTextSize().width + 2 + 11 + 3 + middle:getTextSize().width + 2 + 9)
end

function WeeklyTask:allowDifficultyWeeklyTasks(unlockedDifficulties)
	local panel = TaskBoard.weeklyProgressPanel

	if not panel then
		return
	end

	local unlocked = tonumber(unlockedDifficulties) or 0

	if unlocked < 0 then
		unlocked = 0
	elseif unlocked > 3 then
		unlocked = 3
	end

	local buttons = {
		{
			tier = 0,
			id = "beginnerButton"
		},
		{
			tier = 1,
			id = "adeptButton"
		},
		{
			tier = 2,
			id = "expertButton"
		},
		{
			tier = 3,
			id = "masterButton"
		}
	}

	for _, entry in ipairs(buttons) do
		local btn = panel:recursiveGetChildById(entry.id)

		if btn and btn.setEnabled then
			btn:setEnabled(unlocked >= entry.tier)
		end
	end

	if type(g_ui.updateHoveredWidget) == "function" then
		g_ui.updateHoveredWidget(true)
	end
end

function onWeeklyTasks(weeklyTasks)
	if type(weeklyTasks) ~= "table" then
		return
	end

	buildKillSlots(weeklyTasks)
	buildDeliverySlots(weeklyTasks)
	buildBarProgress(weeklyTasks)
	buildRewards(weeklyTasks)
	buildXpInfo(weeklyTasks)
	buildResults(weeklyTasks)

	WeeklyTask.isWeeklyTaskActive = weeklyTasks.weeklyTaskActive == 1

	WeeklyTask:updateOverlayVisibility()
	WeeklyTask:allowDifficultyWeeklyTasks(weeklyTasks.unlockedDifficulties)
end

-- ADAPTER for our engine: onWeeklyTaskData passes THREE separate structures
-- (header, monsters, items) and uses different field names than the module. We assemble them into
-- the single table that onWeeklyTasks expects.
function onEngineWeeklyTaskData(header, monsters, items)
	header = header or {}

	local killEntries = {}
	local killsAnyMonsters = 0
	local killedsAnyMonsters = 0

	for _, m in ipairs(monsters or {}) do
		if m.raceId == 0 then
			-- the engine prepends a synthetic "any monsters" entry with raceId = 0
			killsAnyMonsters = m.total
			killedsAnyMonsters = m.current
		else
			killEntries[#killEntries + 1] = {
				raceId = m.raceId,
				totalMonsterKilleds = m.current,
				totalKills = m.total,
				state = m.state
			}
		end
	end

	local deliveryEntries = {}

	for _, it in ipairs(items or {}) do
		deliveryEntries[#deliveryEntries + 1] = {
			taskId = it.slotIndex,
			taskItemId = it.itemId,
			count = it.current,
			totalItems = it.total,
			completed = it.claimed,
			state = it.state
		}
	end

	onWeeklyTasks({
		killEntries = killEntries,
		deliveryEntries = deliveryEntries,
		killsAnyMonsters = killsAnyMonsters,
		killedsAnyMonsters = killedsAnyMonsters,
		kill = header.completedKillTasks,
		delivery = header.completedDeliveryTasks,
		totalPoints = header.pointsEarned,
		totalTasksCompleted = header.soulsealsEarned,
		mondayTime = header.resetTimestamp,
		weeklyTaskActive = header.weeklyProgressFinished,
		-- engine difficulty is 1-4 (0 = no tasks yet), the module counts 0-3
		difficulty = math.max(0, (header.difficulty or 1) - 1),
		killTaskXp = header.maxExperience or 0,
		deliveryTaskXp = header.maxDeliveryExperience or 0,
		-- the engine reports 1-4, the module counts 0-3
		unlockedDifficulties = math.max(0, (header.unlockedDifficulty or 1) - 1)
	})
end

function WeeklyTask:init()
	connect(g_game, {
		onWeeklyTasks = onWeeklyTasks,
		onWeeklyTaskData = onEngineWeeklyTaskData
	})

	if TaskBoard.weeklyPanel then
		wireUnlockButton(TaskBoard.weeklyPanel:recursiveGetChildById("unlockKillButton"))
		wireUnlockButton(TaskBoard.weeklyPanel:recursiveGetChildById("unlockDeliveryButton"))
	end

	if TaskBoard.weeklyProgressPanel then
		wireDifficultyButton(TaskBoard.weeklyProgressPanel:recursiveGetChildById("beginnerButton"), 0)
		wireDifficultyButton(TaskBoard.weeklyProgressPanel:recursiveGetChildById("adeptButton"), 1)
		wireDifficultyButton(TaskBoard.weeklyProgressPanel:recursiveGetChildById("expertButton"), 2)
		wireDifficultyButton(TaskBoard.weeklyProgressPanel:recursiveGetChildById("masterButton"), 3)
	end
end

function WeeklyTask:terminate()
	disconnect(g_game, {
		onWeeklyTasks = onWeeklyTasks,
		onWeeklyTaskData = onEngineWeeklyTaskData
	})
end
