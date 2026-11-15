-- chunkname: @/game_taskboard/menus/bounty_task.lua

TaskBoard.BountyTask = {}

local BountyTask = TaskBoard.BountyTask

CLAIMED_DAILY_TASK_STATE = false

local BACKDROP_BY_STARS = {
	[0] = "/modules/game_taskboard/images/backdrop_tasksystem_normal_task",
	"/modules/game_taskboard/images/backdrop_tasksystem_silver_task",
	"/modules/game_taskboard/images/backdrop_tasksystem_gold_task"
}

local function capitalizeWords(str)
	return (str or ""):gsub("(%a)([%w_']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end)
end

-- grade: 0 normal, 1 silver, 2 gold, 3 platinum (15.33)
local GRADE_PLATINUM = 3
-- the official client caps stored reroll tokens at 10 ("You can store up to 10 Reroll Tokens at a time")
local MAX_REROLL_TOKENS = 10

local DIFFICULTY_HELP_1530 = "Select one of three Bounty tasks to complete and earn a reward.\n\nTasks are grouped by difficulty:\n\n  Beginner tasks include easy creatures.\n  Adept tasks include easy and medium creatures.\n  Expert tasks include medium and hard creatures.\n  Master tasks include hard and challenging creatures.\n\nYou can change the difficulty at any time, but it only takes effect\n when selecting your next task.\n\nUse the Preferred List to customise which tasks can appear when\n you roll.\n\nTasks can be re-rolled using Reroll Tokens. One token can be\n claimed for free each day. You can store up to 10 Reroll Tokens at\n a time.\n\nThere is a chance for Silver and Gold tasks to appear, which grant\n greater rewards."
local DIFFICULTY_HELP_1533 = "Select one of three Bounty tasks to complete and earn a reward.\n\nTasks are grouped by difficulty:\n\n  Beginner tasks include easy creatures.\n  Adept tasks include easy and medium creatures.\n  Expert tasks include medium and hard creatures.\n  Master tasks include hard and challenging creatures.\n\nWhen Elite is enabled, all new tasks roll as Elite tasks, where\n monsters deal 100% more damage and take 50% less. In return,\n rewards include 100% more XP and additional dust based on\n difficulty. Dust is only awarded to Premium accounts.\n\nYou can change the difficulty and Elite setting at any time, but\n changes only apply to your next task.\n\nUse the Preferred List to customise which tasks can appear when\n you roll.\n\nTasks can be re-rolled using Reroll Tokens. One token can be\n claimed for free each day from the Daily Reward Wall. You can store\n up to 10 Reroll Tokens at a time.\n\nThere is a chance for Silver and Gold tasks to appear, which grant\n greater rewards. Whenever you don't choose a monster, its chance for\n these improved tasks increases and even a chance for Platinum\n tasks is added."
local DIFFICULTY_LABEL_TOOLTIP = "Beginner tasks include easy creatures.\nAdept tasks include easy and medium creatures.\nExpert tasks include medium and hard creatures.\nMaster tasks include hard and challenging creatures."
local ELITE_TOOLTIP = "When Elite is enabled, all new tasks roll as Elite tasks, where\nmonsters deal 100% more damage and take 50% less.\nIn return, rewards include 100% more XP and additional dust\nbased on difficulty. Dust is only awarded to Premium accounts."

local function applyStarsBackdrop(starsWidget, data)
	if not starsWidget then
		return
	end

	local grade = tonumber(data and data.grade) or tonumber(data and data.stars) or 0
	local stars = math.min(tonumber(data and data.stars) or grade, 2)
	local tierIcon = starsWidget:getChildById("tierIcon")
	local platinumIcon = grade >= GRADE_PLATINUM and TaskBoard:asset1533("icon-bounty-task-platinum") or nil

	if tierIcon then
		tierIcon:setVisible(platinumIcon ~= nil)
	end

	if platinumIcon then
		-- like the 15.33 board: plain backdrop with the tier icon drawn on top of it
		starsWidget:setClipping(false)
		starsWidget:setImageSource(BACKDROP_BY_STARS[0])
		tierIcon:setImageSource(platinumIcon)
		tierIcon:setTooltip(tr("Platinum Task"))

		return
	end

	if stars > 0 then
		starsWidget:setSize(tosize("279 44"))
	end

	starsWidget:setImageSource(BACKDROP_BY_STARS[stars] or BACKDROP_BY_STARS[0])
	-- without the Platinum artwork a Platinum task keeps the Gold backdrop; say what it is
	starsWidget:setTooltip(grade >= GRADE_PLATINUM and tr("Platinum Task") or "")
end

local function applyEliteMarker(starsWidget, isElite)
	if not starsWidget then
		return
	end

	local icon = starsWidget:getChildById("eliteIcon")
	local text = starsWidget:getChildById("eliteText")
	local image = isElite and TaskBoard:asset1533("icon-difficulty") or nil

	if icon then
		icon:setVisible(image ~= nil)

		if image then
			icon:setImageSource(image)
			icon:setTooltip(tr("Elite"))
		end
	end

	if text then
		text:setVisible(isElite and image == nil)
	end
end

local BOUNTY_TRACKER_TOOLTIP_FOOTER = "Click in this window to open the Task Board dialog."
local BOUNTY_TRACKER_TOOLTIP_INACTIVE = "Inactive Task.\n\nClick in this window to open Task Board dialog. Select a monster to start a new task."
local lastBountyTrackerData

local function buildBountyTrackerActiveTooltip(creatureName, killed, total)
	local header = string.format("Creature: %s\nAmount: %s / %s", capitalizeWords(creatureName), TaskBoard:formatNumberWithCommas(killed), TaskBoard:formatNumberWithCommas(total))

	return header .. "\n\n" .. tr(BOUNTY_TRACKER_TOOLTIP_FOOTER)
end

local function getBountyTrackerSlot()
	local prey = modules.game_prey

	if not prey or not prey.preyTracker or prey.preyTracker:isDestroyed() then
		return nil
	end

	local contents = prey.preyTracker.contentsPanel

	if not contents then
		return nil
	end

	return contents:getChildById("bslot1")
end

local function setBountyTrackerTooltip(slot, text)
	if not slot then
		return
	end

	slot:setTooltip(text)
end

local function setBountyTrackerInactive()
	local slot = getBountyTrackerSlot()

	if not slot then
		return
	end

	local creature = slot:getChildById("creature")
	local noCreature = slot:getChildById("noCreature")
	local nameLabel = slot:getChildById("creatureName")
	local timeBar = slot:getChildById("time")

	if creature then
		creature:setVisible(false)
	end

	if noCreature then
		noCreature:setVisible(true)
	end

	if nameLabel then
		nameLabel:setText(tr("Inactive"))
	end

	if timeBar then
		timeBar:setPercent(0)
	end

	setBountyTrackerTooltip(slot, tr(BOUNTY_TRACKER_TOOLTIP_INACTIVE))
end

local function setBountyTrackerSelected(data)
	local slot = getBountyTrackerSlot()

	if not slot or not data then
		return
	end

	local creature = slot:getChildById("creature")
	local noCreature = slot:getChildById("noCreature")
	local nameLabel = slot:getChildById("creatureName")
	local timeBar = slot:getChildById("time")
	local raceId = tonumber(data.raceId) or 0
	local raceData = g_things.getRaceData(raceId)
	local creatureName = (raceData and raceData.raceId ~= 0 and raceData.name and raceData.name ~= "") and raceData.name or (raceId > 0 and string.format("Creature (%d)", raceId) or "?")

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
		noCreature:setVisible(false)
	end

	if nameLabel then
		nameLabel:setText(modules.game_prey.formatKillTrackerCreatureName(creatureName))
	end

	local killed = tonumber(data.monstersKilled) or 0
	local total = tonumber(data.totalKills) or 0

	if timeBar then
		local percent = 0

		if total > 0 then
			percent = math.min(100, math.floor(killed / total * 100))
		end

		timeBar:setPercent(percent)
	end

	local tooltip = buildBountyTrackerActiveTooltip(creatureName, killed, total)

	setBountyTrackerTooltip(slot, tooltip)
	scheduleEvent(function()
		local trackerSlot = getBountyTrackerSlot()

		if trackerSlot then
			setBountyTrackerTooltip(trackerSlot, tooltip)
		end
	end, 0)
end

local function updateBountyKillTracker(slots)
	if type(slots) == "table" and #slots == 1 then
		lastBountyTrackerData = slots[1]

		setBountyTrackerSelected(slots[1])
	else
		lastBountyTrackerData = nil

		setBountyTrackerInactive()
	end

	if modules.game_prey and modules.game_prey.updateTrackerHeight then
		modules.game_prey.updateTrackerHeight()
	end
end

function BountyTask.requestTrackerData()
	if not g_game.isOnline() then
		return
	end

	if g_game.sendOpenMenuTaskBoardAction then
		g_game.sendOpenMenuTaskBoardAction(0)
	end
end

local function refreshBountyKillTrackerFromCache()
	if lastBountyTrackerData then
		setBountyTrackerSelected(lastBountyTrackerData)
	else
		setBountyTrackerInactive()
	end
end

function BountyTask.refreshKillTracker()
	refreshBountyKillTrackerFromCache()
end

function BountyTask:fillSlotPanel(panel, data, selected)
	if not panel or not data then
		return
	end

	panel.bountySlotData = data

	local starsBox = panel:getChildById("stars")

	applyStarsBackdrop(starsBox, data)
	applyEliteMarker(starsBox, data.isElite == true)

	local creature = panel:recursiveGetChildById("slotCreature")
	local raceId = tonumber(data.raceId) or 0
	local creatureName = raceId > 0 and string.format("Creature (%d)", raceId) or "?"
	local raceData = g_things.getRaceData(raceId)

	if raceData and raceData.raceId ~= 0 and raceData.name and raceData.name ~= "" then
		creatureName = raceData.name

		if creature and raceData.outfit then
			creature:setOutfit(raceData.outfit)
			creature:setCenter(true)
			creature:setFixedCreatureSize(true)
			creature:setBaseScale(true)
			creature:setIgnoreDisplacementShift(true)
			creature:setVisible(true)

			local c = creature:getCreature()

			if c then
				c:setStaticWalking(1000)
			end
		end
	elseif creature then
		creature:setVisible(false)

		local c = creature:getCreature()

		if c then
			c:setStaticWalking(0)
		end
	end

	local nameLabel = starsBox and starsBox:getChildById("creatureName")
	local cur = panel:getChildById("killsCurrentValue")
	local tgt = panel:getChildById("killsTargetValue")
	local expL = panel:getChildById("experienceLabel")
	local bpL = panel:getChildById("bountyPointsLabel")

	nameLabel:setText(capitalizeWords(creatureName))
	cur:setText(TaskBoard:formatNumberWithCommas(data.monstersKilled or 0))
	tgt:setText(TaskBoard:formatNumberWithCommas(data.totalKills or 0))
	expL:setText(TaskBoard:formatNumberWithCommas(data.experiencePoints or 0))
	bpL:setText(TaskBoard:formatNumberWithCommas(data.bountyPoints or 0))

	-- 15.33 Elite tasks also reward dust: " and N <dust icon>"
	local dust = tonumber(data.dustReward) or 0
	local dustL = panel:getChildById("dustLabel")
	local dustIcon = panel:getChildById("dustIcon")

	if dustL and dustIcon then
		dustL:setText(tr(" and %s", TaskBoard:formatNumberWithCommas(dust)))
		dustL:setVisible(dust > 0)
		dustIcon:setVisible(dust > 0)
	end

	local limitL = panel:getChildById("rerollLimitLabel")

	if limitL then
		limitL:setVisible(TaskBoard:is1533() and BountyTask.rerollTokens ~= nil and BountyTask.rerollTokens >= MAX_REROLL_TOKENS)
	end

	local btn = panel:getChildById("selectTaskButton")

	if selected then
		btn:setText(tr("Claim Reward"))

		if data.monstersKilled < data.totalKills then
			btn:setEnabled(false)
			btn:setTooltip(tr("Finish the task to claim the reward."))
		else
			btn:setEnabled(true)
		end
	end

	function btn.onClick()
		if selected then
			g_game.sendClaimReward()
		else
			BountyTask:onSelectSlot(panel)
		end
	end

	local container = panel:getParent()

	if not container then
		return
	end

	local children = container:getChildren()

	if selected then
		children[1]:setMarginLeft(325)
	else
		for i = 2, #children do
			local child = children[i]

			child:addAnchor(AnchorLeft, "prev", AnchorRight)
			child:addAnchor(AnchorTop, "parent", AnchorTop)
			child:setMarginLeft(11)
		end
	end
end

function BountyTask:onSelectSlot(panel)
	local data = panel and panel.bountySlotData

	if not data then
		return
	end

	g_game.sendSelectTask(data.taskId)
end

function BountyTask:selectDifficulty(difficulty)
	local difficulties = {
		[0] = 0, [1] = 1, [2] = 2, [3] = 3,
		Beginner = 0, Adept = 1, Expert = 2, Master = 3,
		beginner = 0, adept = 1, expert = 2, master = 3
	}

	local d = difficulties[difficulty]
	if d == nil and type(difficulty) == "string" then
		d = difficulties[difficulty:lower()]
		if d == nil then
			if difficulty == tr("Beginner") then d = 0
			elseif difficulty == tr("Adept") then d = 1
			elseif difficulty == tr("Expert") then d = 2
			elseif difficulty == tr("Master") then d = 3
			end
		end
	end

	self.currentDifficulty = d or 0

	-- 15.33 sends the Elite setting with the difficulty; take it from the checkbox so a click that the
	-- server has not confirmed yet is not undone
	local elite
	local rerollBox = TaskBoard:is1533() and TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollTasks")
	local eliteCheck = rerollBox and rerollBox:getChildById("eliteCheck")

	if eliteCheck then
		elite = eliteCheck:isChecked()
	end

	g_game.sendSelectTaskDifficulty(d or 0, elite)
end

local bountyCreatureCache, selectedBountyRow, selectedBountyRace, listBuildEvent
local BOUNTY_COLOR_EVEN = "#484848"
local BOUNTY_COLOR_ODD = "#414141"
local BOUNTY_COLOR_SELECTED = "#585858"
local BOUNTY_BATCH_SIZE = 10

local function reindexListColors(list)
	if not list then
		return
	end

	local children = list:getChildren()
	local idx = 0

	for _, row in ipairs(children) do
		local base = idx % 2 == 0 and BOUNTY_COLOR_EVEN or BOUNTY_COLOR_ODD

		row.bountyBaseColor = base

		if row ~= selectedBountyRow then
			row:setBackgroundColor(base)
		end

		idx = idx + 1
	end
end

local function getBountyList()
	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return nil
	end

	local leftPanel = preferredListPanel:getChildById("leftPanel")

	if not leftPanel then
		return nil
	end

	return leftPanel:getChildById("list")
end

local function buildBountyCreatureCache()
	local allRaces = g_things.getMonsterList()
	local filtered = {}

	-- The module filtered on `race.hasBountyTask` - a field from the ported client's own build, which
	-- our staticdata.proto does not have at all (Creature carries only raceId/name/outfit, plus the
	-- boss flag from the boss bank). The condition was therefore always false and the list came out EMPTY.
	-- The server validates raceId only via getMonsterTypeByRaceId, so filtering out bosses is enough.
	for _, race in ipairs(allRaces) do
		if race.raceId and race.raceId > 0 and not race.boss and race.name and race.name ~= "" then
			filtered[#filtered + 1] = race
		end
	end

	table.sort(filtered, function(a, b)
		return a.name:lower() < b.name:lower()
	end)

	bountyCreatureCache = filtered
end

local function getBountyCreaturesSorted()
	if not bountyCreatureCache then
		buildBountyCreatureCache()
	end

	return bountyCreatureCache
end

local function selectBountyRow(row, race)
	if selectedBountyRow and selectedBountyRow ~= row then
		selectedBountyRow:setBackgroundColor(selectedBountyRow.bountyBaseColor or BOUNTY_COLOR_EVEN)
	end

	selectedBountyRow = row
	selectedBountyRace = race

	if row then
		row:setBackgroundColor(BOUNTY_COLOR_SELECTED)
	end
end

local function applyBountyCreaturePreview(creatureWidget, outfit, animate)
	if not creatureWidget or not outfit then
		return
	end

	creatureWidget:setOutfit(outfit)

	if animate then
		local c = creatureWidget:getCreature()

		if c then
			c:setStaticWalking(1000)
		end
	end
end

local function setSlotCreature(slotWidget, race)
	if not slotWidget or not race then
		return
	end

	local creature = slotWidget:getChildById("slotCreature")

	if creature and race.outfit then
		applyBountyCreaturePreview(creature, race.outfit, true)
		creature:setVisible(true)
	end

	slotWidget.assignedRaceId = race.raceId
end

local function cancelListBuild()
	if listBuildEvent then
		removeEvent(listBuildEvent)

		listBuildEvent = nil
	end
end

local function createBountyRow(list, race, rowIndex)
	local row = g_ui.createWidget("BountyCreatureRow", list)

	if not row then
		return
	end

	local base = rowIndex % 2 == 0 and BOUNTY_COLOR_EVEN or BOUNTY_COLOR_ODD

	row.bountyBaseColor = base
	row.bountyRace = race

	row:setBackgroundColor(base)

	local sprite = row:getChildById("creatureSprite")

	if sprite and race.outfit then
		applyBountyCreaturePreview(sprite, race.outfit, false)
	end

	local nameLabel = row:getChildById("creatureName")

	if nameLabel then
		nameLabel:setText(capitalizeWords(race.name))
	end

	function row.onClick()
		selectBountyRow(row, race)
	end
end

local function populateBountyCreatureList(filterText, excludeRaceIds)
	cancelListBuild()

	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return
	end

	local leftPanel = preferredListPanel:getChildById("leftPanel")

	if not leftPanel then
		return
	end

	local list = leftPanel:getChildById("list")

	if not list then
		return
	end

	selectedBountyRow = nil
	selectedBountyRace = nil

	list:destroyChildren()

	local creatures = getBountyCreaturesSorted()
	local lowerFilter = filterText and filterText:lower() or ""
	local excludeSet = {}

	for _, id in ipairs(excludeRaceIds or {}) do
		excludeSet[id] = true
	end

	local toCreate = {}

	for _, race in ipairs(creatures) do
		if not excludeSet[race.raceId] and (lowerFilter == "" or race.name:lower():find(lowerFilter, 1, true)) then
			toCreate[#toCreate + 1] = race
		end
	end

	local idx = 1
	local total = #toCreate

	local function createNextBatch()
		listBuildEvent = nil

		if not list or list:isDestroyed() then
			return
		end

		local layout = list:getLayout()

		if layout then
			layout:disableUpdates()
		end

		local endIdx = math.min(idx + BOUNTY_BATCH_SIZE - 1, total)

		for i = idx, endIdx do
			createBountyRow(list, toCreate[i], i - 1)
		end

		idx = endIdx + 1

		if layout then
			layout:enableUpdates()
			layout:update()
		end

		if idx <= total then
			listBuildEvent = addEvent(createNextBatch)
		end
	end

	createNextBatch()
end

local function getExcludedRaceIds()
	local ids = {}
	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return ids
	end

	local rightPanel = preferredListPanel:getChildById("rightPanel")

	if not rightPanel then
		return ids
	end

	local slotsList = rightPanel:getChildById("slotsList")

	if not slotsList then
		return ids
	end

	for _, row in ipairs(slotsList:getChildren()) do
		local prefSlot = row:getChildById("preferredSlot")

		if prefSlot and prefSlot.assignedRaceId then
			ids[#ids + 1] = prefSlot.assignedRaceId
		end

		local unwSlot = row:getChildById("unwantedSlot")

		if unwSlot and unwSlot.assignedRaceId then
			ids[#ids + 1] = unwSlot.assignedRaceId
		end
	end

	return ids
end

function BountyTask:filterPreferredList(text)
	populateBountyCreatureList(text, getExcludedRaceIds())
end

function BountyTask:clearPreferredSearch()
	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return
	end

	local leftPanel = preferredListPanel:getChildById("leftPanel")

	if not leftPanel then
		return
	end

	local search = leftPanel:getChildById("search")

	if search then
		search:setText("")
	end

	populateBountyCreatureList("", getExcludedRaceIds())
end

function BountyTask:showPreferredList()
	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return
	end

	bountyCreatureCache = nil
	selectedBountyRow = nil
	selectedBountyRace = nil

	populateBountyCreatureList("", {})

	local chainTransparent = TaskBoard.chainTransparent

	if chainTransparent then
		chainTransparent:show()
	end

	preferredListPanel:show()
	preferredListPanel:raise()
	preferredListPanel:focus()
end

function BountyTask:closePreferredList()
	cancelListBuild()

	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return
	end

	preferredListPanel:hide()

	local chainTransparent = TaskBoard.chainTransparent

	if chainTransparent then
		chainTransparent:hide()
	end
end

local PREFERRED_CLEAR_COST = 10
local PREFERRED_UNLOCK_COSTS = {
	300,
	600,
	900,
	1200
}

local function clearSlotWidget(slotWidget)
	if not slotWidget then
		return
	end

	local creature = slotWidget:getChildById("slotCreature")

	if creature then
		creature:setVisible(false)

		local c = creature:getCreature()

		if c then
			c:setStaticWalking(0)
		end
	end

	slotWidget.assignedRaceId = nil
end

local function wireSlotClearButton(row, slotWidget, btn, costPanel, slotIndex, isUnwanted)
	btn:setText(tr("Clear"))

	if costPanel then
		costPanel:show()
	end

	function btn.onClick()
		if isUnwanted then
			g_game.sendPreferredListClearUnwanted(slotIndex)
		else
			g_game.sendPreferredListClearPreferred(slotIndex)
		end

		clearSlotWidget(slotWidget)
		btn:setText(tr("Assign"))

		if costPanel then
			costPanel:hide()
		end

		function btn.onClick()
			if isUnwanted then
				BountyTask:assignToRow(row, slotIndex, true)
			else
				BountyTask:assignToRow(row, slotIndex, false)
			end
		end

		populateBountyCreatureList("", getExcludedRaceIds())
	end
end

local function wireSlotAssignButton(row, btn, slotIndex, isUnwanted)
	function btn.onClick()
		if isUnwanted then
			BountyTask:assignToRow(row, slotIndex, true)
		else
			BountyTask:assignToRow(row, slotIndex, false)
		end
	end
end

function BountyTask:assignToRow(row, slotIndex, isUnwanted)
	if not selectedBountyRace then
		return
	end

	local slotId = isUnwanted and "unwantedSlot" or "preferredSlot"
	local btnId = isUnwanted and "unwantedButton" or "preferredButton"
	local costId = isUnwanted and "unwantedCostPanel" or "preferredCostPanel"
	local slotWidget = row:getChildById(slotId)
	local btn = row:getChildById(btnId)
	local costPanel = row:getChildById(costId)

	setSlotCreature(slotWidget, selectedBountyRace)

	if isUnwanted then
		g_game.sendPreferredListUnwanted(slotIndex, selectedBountyRace.raceId)
	else
		g_game.sendPreferredListPreferred(slotIndex, selectedBountyRace.raceId)
	end

	if selectedBountyRow then
		selectedBountyRow:destroy()

		selectedBountyRow = nil
	end

	selectedBountyRace = nil

	reindexListColors(getBountyList())
	wireSlotClearButton(row, slotWidget, btn, costPanel, slotIndex, isUnwanted)
end

function BountyTask:AssignCreatureSlot()
	return
end

function BountyTask:UnwantedCreatureSlot()
	return
end

local function buildPreferredSlotRow(container, slotIndex, data)
	local row = g_ui.createWidget("PreferredSlotRow", container)

	if not row then
		return
	end

	local prefSlot = row:getChildById("preferredSlot")
	local prefBtn = row:getChildById("preferredButton")
	local prefCost = row:getChildById("preferredCostPanel")
	local unwSlot = row:getChildById("unwantedSlot")
	local unwBtn = row:getChildById("unwantedButton")
	local unwCost = row:getChildById("unwantedCostPanel")

	if data.preferred and data.preferred ~= 0 then
		local raceData = g_things.getRaceData(data.preferred)

		if raceData and raceData.raceId ~= 0 then
			setSlotCreature(prefSlot, raceData)
			wireSlotClearButton(row, prefSlot, prefBtn, prefCost, slotIndex, false)
		end
	else
		wireSlotAssignButton(row, prefBtn, slotIndex, false)
	end

	if data.unwanted and data.unwanted ~= 0 then
		local raceData = g_things.getRaceData(data.unwanted)

		if raceData and raceData.raceId ~= 0 then
			setSlotCreature(unwSlot, raceData)
			wireSlotClearButton(row, unwSlot, unwBtn, unwCost, slotIndex, true)
		end
	else
		wireSlotAssignButton(row, unwBtn, slotIndex, true)
	end
end

local function buildPreferredLockedRow(container, slotIndex)
	local row = g_ui.createWidget("PreferredLockedRow", container)

	if not row then
		return
	end

	local costLabel = row:recursiveGetChildById("unlockCostValue")
	local unlockCost = PREFERRED_UNLOCK_COSTS[slotIndex] or slotIndex * 300

	if costLabel then
		costLabel:setText(TaskBoard:formatNumberWithCommas(unlockCost))
	end

	local btn = row:getChildById("unlockButton")

	if btn then
		function btn.onClick()
			-- our engine requires the slot number (bountyPreferredAction BUY_SLOT ignores slot == 0),
			-- while the module had it only in the closure and never passed it anywhere
			g_game.sendPreferredListUnlockSlots(slotIndex)
		end
	end
end

local function updatePreferredList(preferredListData)
	local preferredListPanel = TaskBoard.preferredListPanel

	if not preferredListPanel then
		return
	end

	local rightPanel = preferredListPanel:getChildById("rightPanel")

	if not rightPanel then
		return
	end

	local slotsList = rightPanel:getChildById("slotsList")

	if not slotsList then
		return
	end

	slotsList:destroyChildren()

	if type(preferredListData) ~= "table" then
		return
	end

	local lockedIndex = 1

	for i, data in ipairs(preferredListData) do
		local isUnlocked = data.unlocked or i == 1

		if isUnlocked then
			buildPreferredSlotRow(slotsList, i - 1, data)
		else
			buildPreferredLockedRow(slotsList, lockedIndex)

			lockedIndex = lockedIndex + 1
		end
	end

	populateBountyCreatureList("", getExcludedRaceIds())
end

function BountyTask:rerollTasks()
	local rerollTokens = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollPanel")
	local rerollButton = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollButton")
	local valueLabel = rerollTokens and rerollTokens:getChildById("value")
	local tokens = valueLabel and tonumber(valueLabel:getText()) or 0

	if tokens == 1 and rerollButton then
		rerollButton:setEnabled(false)
		rerollButton:setTooltip(tr("You have no rerolls left."))
	end

	g_game.sendRerollTasks()
end

function BountyTask:claimDaily()
	if not CLAIMED_DAILY_TASK_STATE then
		return
	end

	local rerollBox = TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollTasks")
	local claimButton = rerollBox:getChildById("claimButton")

	claimButton:setEnabled(false)
	claimButton:setImageClip("0 40 108 20")
	claimButton:setTooltip(tr("Already claimed today."))

	CLAIMED_DAILY_TASK_STATE = false

	g_game.sendClaimDaily()
end

function BountyTask:updateTalisman(talismanId)
	g_game.sendUpgradeTalisman(talismanId)
end

local function bountyDifficultyOptionText(index)
	local i = tonumber(index) or 0
	local names = {
		tr("Beginner"),
		tr("Adept"),
		tr("Expert"),
		tr("Master")
	}

	return names[i + 1] or names[1]
end

local function getTalismanBonus(talismanId, level)
	local percent = 2.5

	level = tonumber(level) or 0
	talismanId = tonumber(talismanId) or 0

	if talismanId <= 2 then
		local lvl1 = math.min(level, 15)

		percent = percent + lvl1 * 0.5

		if level > 15 then
			local lvl2 = math.min(level - 15, 40)

			percent = percent + lvl2 * 0.25
		end

		if level > 55 then
			percent = percent + (level - 55) * 0.1
		end

		return math.min(percent, 50)
	end

	percent = 5

	if talismanId == 3 then
		local lvl1 = math.min(level, 15)

		percent = percent + lvl1 * 1

		if level > 15 then
			local lvl2 = math.min(level - 15, 40)

			percent = percent + lvl2 * 0.5
		end

		if level > 55 then
			percent = percent + (level - 55) * 0.2
		end

		return math.min(percent, 100)
	end

	return 0
end

local function applyBountyTalismanRow(talismanId, data, labelWidget, upgradeButton, bountyPointsPanel)
	if not data then
		return
	end

	local level = tonumber(data.talismaLevel) or 0
	local price = tonumber(data.upgradePrice) or 0
	local can = data.canUpgrade == true

	if labelWidget then
		labelWidget:setText(string.format("%.1f", getTalismanBonus(talismanId, level)))
	end

	if bountyPointsPanel then
		local v = bountyPointsPanel:getChildById("value")

		if v then
			v:setText(TaskBoard:formatNumberWithCommas(price))
		end
	end

	if upgradeButton then
		upgradeButton:setEnabled(can)

		if can then
			local nextTier = getTalismanBonus(talismanId, level + 1)

			upgradeButton:setText(tr("Upgrade to %.1f %%", nextTier))
		else
			local nextTier = getTalismanBonus(talismanId, level + 1)

			upgradeButton:setText(tr("Upgrade to %.1f %%", nextTier))
			upgradeButton:setTooltip(tr("You do not have enough Bounty Points."))
		end
	end
end

-- 15.33 lays the setup bar out like the official RowLayout: help, separator, then the difficulty, Elite
-- and Preferred List controls centred between the two separators, and the reroll controls on the right.
local SETUP_1533 = {
	helpMarginLeft = 25,
	labelToCombo = 11,
	comboToIcon = 25,
	iconToCheck = 6,
	checkToPreferred = 17,
	separatorToReroll = 24,
	rerollToTokens = 15,
	rightEdge = 10,
	tokensToLimitIcon = 5
}

local function anchorWidget(widget, horizontalEdge, target, targetEdge, margin)
	if not widget then
		return
	end

	widget:breakAnchors()
	widget:addAnchor(AnchorTop, "parent", AnchorTop)
	widget:addAnchor(horizontalEdge, target, targetEdge)
	widget:setMarginLeft(horizontalEdge == AnchorLeft and margin or 0)
	widget:setMarginRight(horizontalEdge == AnchorRight and margin or 0)
end

-- explicit visibility, the board window may still be hidden; fitsText: the widget resizes to its text, which may not have happened yet right after setText
local function widgetWidth(widget, fitsText)
	if not widget or not widget:isExplicitlyVisible() then
		return 0
	end

	local width = widget:getWidth()

	if fitsText then
		width = math.max(width, widget:getTextSize().width)
	end

	return width
end

-- the reroll limit warning takes room at the right edge, so the token box moves left while it is shown
local function layoutRerollRightEdge(rerollBox)
	if not rerollBox or not TaskBoard:is1533() then
		return
	end

	local tokens = rerollBox:getChildById("rerollPanel")
	local limitIcon = rerollBox:getChildById("rerollLimitIcon")

	if not tokens then
		return
	end

	local margin = SETUP_1533.rightEdge

	if limitIcon and limitIcon:isExplicitlyVisible() then
		margin = margin + limitIcon:getWidth() + SETUP_1533.tokensToLimitIcon
	end

	tokens:setMarginRight(margin)
end

local function updateRerollLimit(rerollTokens)
	BountyTask.rerollTokens = tonumber(rerollTokens) or 0

	-- 15.33 only; the 15.30 board never showed the limit warning
	local limitReached = TaskBoard:is1533() and BountyTask.rerollTokens >= MAX_REROLL_TOKENS
	local panel = TaskBoard.bountyTaskPanel

	if not panel then
		return
	end

	local limitIcon = panel:recursiveGetChildById("rerollLimitIcon")

	if limitIcon then
		limitIcon:setVisible(limitReached)
		layoutRerollRightEdge(limitIcon:getParent())
	end

	local container = panel:recursiveGetChildById("dailyTasks")

	if container then
		for _, slot in ipairs(container:getChildren()) do
			local label = slot:getChildById("rerollLimitLabel")

			if label then
				label:setVisible(limitReached)
			end
		end
	end
end

local function applyRerollTokens(rerollTokensValue, rerollButton, rerollTokens)
	if rerollTokensValue then
		rerollTokensValue:setText(rerollTokens and tostring(rerollTokens) or "0")
	end

	updateRerollLimit(rerollTokens)

	if not rerollButton then
		return
	end

	if not rerollTokens or tonumber(rerollTokens) == 0 then
		rerollButton:setEnabled(false)
		rerollButton:setImageClip("0 40 108 20")
		rerollButton:setTooltip(tr("You have no rerolls left."))
	else
		rerollButton:setEnabled(true)
		rerollButton:setImageClip("0 0 108 20")
	end
end

-- 15.33 keeps the reroll tokens in resource 0x58, which the server can send on its own
-- (for example after the daily reward token), so refresh the board without waiting for 0x5B
local function onBountyResourceBalance(resourceType, value)
	if resourceType ~= ResourceTypes.BOUNTY_REROLL_TOKENS or g_game.getClientVersion() < 1533 then
		return
	end

	local rerollBox = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollTasks")
	if not rerollBox then
		return
	end

	local rerollTokensLabel = rerollBox:getChildById("rerollPanel")
	applyRerollTokens(rerollTokensLabel and rerollTokensLabel:getChildById("value"),
		rerollBox:getChildById("rerollButton"), math.min(tonumber(value) or 0, 255))
end

-- 15.33 removed the "Claim Daily" reroll token button (the token comes from the Daily Reward Wall now)
-- and added the Elite setting next to the difficulty; one panel serves both, laid out per version.
local updatingEliteCheck = false

local function layoutSetupBar1533(rerollBox, iconImage)
	local c = SETUP_1533
	local help = rerollBox:getChildById("difficultyHelp")
	local label = rerollBox:getChildById("difficultyLabel")
	local combo = rerollBox:getChildById("showFilterDifficulty")
	local eliteIcon = rerollBox:getChildById("eliteIcon")
	local eliteCheck = rerollBox:getChildById("eliteCheck")
	local preferred = rerollBox:getChildById("preferredListButton")
	local separator = rerollBox:getChildById("rerollSeparator")
	local group = rerollBox:getChildById("centerGroup")

	if help then
		help:setMarginLeft(c.helpMarginLeft)
	end

	-- right edge, built from the border inwards
	anchorWidget(rerollBox:getChildById("rerollLimitIcon"), AnchorRight, "parent", AnchorRight, c.rightEdge)
	anchorWidget(rerollBox:getChildById("rerollPanel"), AnchorRight, "parent", AnchorRight, c.rightEdge)
	anchorWidget(rerollBox:getChildById("rerollButton"), AnchorRight, "rerollPanel", AnchorLeft, c.rerollToTokens)

	if separator then
		separator:breakAnchors()
		separator:addAnchor(AnchorTop, "parent", AnchorTop)
		separator:addAnchor(AnchorBottom, "parent", AnchorBottom)
		separator:addAnchor(AnchorRight, "rerollButton", AnchorLeft)
		separator:setMarginLeft(0)
		separator:setMarginRight(c.separatorToReroll)
	end

	-- centre group: label, combobox, Elite icon, Elite checkbox, Preferred List; centerGroup gets the
	-- width of the whole row and is centred between the separators, the label starts at its left edge
	anchorWidget(label, AnchorLeft, "centerGroup", AnchorLeft, 0)
	anchorWidget(combo, AnchorLeft, "difficultyLabel", AnchorRight, c.labelToCombo)

	local groupWidth = widgetWidth(label, true) + c.labelToCombo + widgetWidth(combo)

	if iconImage then
		anchorWidget(eliteIcon, AnchorLeft, "showFilterDifficulty", AnchorRight, c.comboToIcon)
		anchorWidget(eliteCheck, AnchorLeft, "eliteIcon", AnchorRight, c.iconToCheck)
		groupWidth = groupWidth + c.comboToIcon + widgetWidth(eliteIcon) + c.iconToCheck
	else
		anchorWidget(eliteCheck, AnchorLeft, "showFilterDifficulty", AnchorRight, c.comboToIcon)
		groupWidth = groupWidth + c.comboToIcon
	end

	anchorWidget(preferred, AnchorLeft, "eliteCheck", AnchorRight, c.checkToPreferred)
	groupWidth = groupWidth + widgetWidth(eliteCheck) + c.checkToPreferred + widgetWidth(preferred)

	if group then
		group:setWidth(math.max(1, groupWidth))
	end

	layoutRerollRightEdge(rerollBox)
end

-- the 15.30 bar as declared in bounty_task.otui, restored when the client switches back from 15.33
local function layoutSetupBar1530(rerollBox)
	local help = rerollBox:getChildById("difficultyHelp")
	local separator = rerollBox:getChildById("rerollSeparator")

	if help then
		help:setMarginLeft(20)
	end

	anchorWidget(rerollBox:getChildById("difficultyLabel"), AnchorLeft, "setupSeparator", AnchorRight, 26)
	anchorWidget(rerollBox:getChildById("showFilterDifficulty"), AnchorLeft, "difficultyLabel", AnchorRight, 23)
	anchorWidget(rerollBox:getChildById("preferredListButton"), AnchorLeft, "showFilterDifficulty", AnchorRight, 26)

	if separator then
		separator:breakAnchors()
		separator:addAnchor(AnchorTop, "parent", AnchorTop)
		separator:addAnchor(AnchorBottom, "parent", AnchorBottom)
		separator:addAnchor(AnchorLeft, "preferredListButton", AnchorRight)
		separator:setMarginLeft(26)
		separator:setMarginRight(0)
	end

	anchorWidget(rerollBox:getChildById("rerollButton"), AnchorLeft, "rerollSeparator", AnchorRight, 26)
	anchorWidget(rerollBox:getChildById("rerollPanel"), AnchorLeft, "rerollButton", AnchorRight, 16)
	anchorWidget(rerollBox:getChildById("rerollLimitIcon"), AnchorLeft, "rerollPanel", AnchorRight, 6)
end

function BountyTask:applyVersionLayout()
	local rerollBox = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollTasks")

	if not rerollBox then
		return
	end

	local is1533 = TaskBoard:is1533()
	local eliteIcon = rerollBox:getChildById("eliteIcon")
	local eliteCheck = rerollBox:getChildById("eliteCheck")
	local claimButton = rerollBox:getChildById("claimButton")
	local difficultyLabel = rerollBox:getChildById("difficultyLabel")
	local difficultyHelp = rerollBox:getChildById("difficultyHelp")
	local limitIcon = rerollBox:getChildById("rerollLimitIcon")
	local iconImage = is1533 and TaskBoard:asset1533("icon-difficulty") or nil

	if eliteIcon then
		eliteIcon:setVisible(iconImage ~= nil)

		if iconImage then
			eliteIcon:setImageSource(iconImage)
			eliteIcon:setTooltip(ELITE_TOOLTIP)
		end
	end

	if eliteCheck then
		eliteCheck:setVisible(is1533)
		eliteCheck:setTooltip(ELITE_TOOLTIP)
	end

	if claimButton then
		claimButton:setVisible(not is1533)
	end

	if limitIcon and not is1533 then
		limitIcon:setVisible(false)
	end

	if difficultyLabel then
		difficultyLabel:setText(is1533 and tr("Task Difficulty") or tr("Task Difficulty:"))
		difficultyLabel:setTooltip(is1533 and DIFFICULTY_LABEL_TOOLTIP or "")
	end

	if difficultyHelp then
		difficultyHelp:setTooltip(is1533 and DIFFICULTY_HELP_1533 or DIFFICULTY_HELP_1530)
	end

	if is1533 then
		layoutSetupBar1533(rerollBox, iconImage)
	else
		layoutSetupBar1530(rerollBox)
	end

	rerollBox:updateLayout()
end

local function setEliteChecked(enabled)
	local rerollBox = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollTasks")

	if not rerollBox then
		return
	end

	local eliteCheck = rerollBox:getChildById("eliteCheck")
	local eliteIcon = rerollBox:getChildById("eliteIcon")

	if eliteCheck and eliteCheck:isChecked() ~= enabled then
		updatingEliteCheck = true
		eliteCheck:setChecked(enabled)
		updatingEliteCheck = false
	end

	if eliteIcon then
		eliteIcon:setOpacity(enabled and 1.0 or 0.4)
	end
end

function BountyTask:onEliteToggled(checked)
	if updatingEliteCheck or not TaskBoard:is1533() then
		return
	end

	local rerollBox = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollTasks")
	local eliteIcon = rerollBox and rerollBox:getChildById("eliteIcon")

	if eliteIcon then
		eliteIcon:setOpacity(checked and 1.0 or 0.4)
	end

	-- 0x5F action 2 carries both settings; they apply to the next tasks only
	g_game.sendSelectTaskDifficulty(self.currentDifficulty or 0, checked)
end

function onBountyTasksDaily(slots, rerollTokens, claimUnlocked, difficultyBountyTask, talismanData, preferredListData, eliteEnabled)
	updateBountyKillTracker(slots)
	BountyTask.rerollTokens = tonumber(rerollTokens) or 0
	BountyTask.currentDifficulty = tonumber(difficultyBountyTask) or 0

	local container = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("dailyTasks")

	if not container then
		return
	end

	container:destroyChildren()

	if #slots == 1 then
		local panel = g_ui.createWidget("BountyTaskSlotPanel", container)

		if panel then
			BountyTask:fillSlotPanel(panel, slots[1], true)
		end
	else
		for _, slotData in ipairs(slots) do
			local panel = g_ui.createWidget("BountyTaskSlotPanel", container)

			if panel then
				BountyTask:fillSlotPanel(panel, slotData)
			end
		end
	end

	container:updateLayout()

	local bountyPanel = container:getParent()

	if bountyPanel then
		bountyPanel:updateLayout()
	end

	local rerollBox = TaskBoard.bountyTaskPanel:recursiveGetChildById("rerollTasks")
	local filterDifficulty = rerollBox:getChildById("showFilterDifficulty")
	local rerollButton = rerollBox:getChildById("rerollButton")
	local rerollTokensLabel = rerollBox:getChildById("rerollPanel")
	local rerollTokensValue = rerollTokensLabel and rerollTokensLabel:getChildById("value")
	local claimButton = rerollBox:getChildById("claimButton")

	filterDifficulty:setCurrentOption(bountyDifficultyOptionText(difficultyBountyTask), true)
	applyRerollTokens(rerollTokensValue, rerollButton, rerollTokens)

	if TaskBoard:is1533() then
		setEliteChecked(eliteEnabled == true)
	elseif tonumber(claimUnlocked) == 0 then
		claimButton:setEnabled(true)
		claimButton:setImageClip("0 0 108 20")

		CLAIMED_DAILY_TASK_STATE = true
	elseif tonumber(claimUnlocked) == 1 then
		claimButton:setEnabled(false)
		claimButton:setImageClip("0 40 108 20")
		claimButton:setTooltip(tr("Already claimed today."))

		CLAIMED_DAILY_TASK_STATE = false
	elseif tonumber(claimUnlocked) == 2 then
		claimButton:setEnabled(false)
		claimButton:setImageClip("0 40 108 20")
		claimButton:setTooltip(tr("Limit reached."))

		CLAIMED_DAILY_TASK_STATE = false
	end

	local talismanPanel = TaskBoard.bountyTaskPanel and TaskBoard.bountyTaskPanel:recursiveGetChildById("bountyTalismans")

	if talismanPanel and type(talismanData) == "table" and #talismanData >= 4 then
		local damageTalisman = talismanPanel:recursiveGetChildById("damageAgainst")
		local damageButton = talismanPanel:getChildById("damageButton")
		local bountyDamagePanel = talismanPanel:getChildById("bountyPointsDamagePanel")

		applyBountyTalismanRow(0, talismanData[1], damageTalisman, damageButton, bountyDamagePanel)

		local lifeLeechTalisman = talismanPanel:recursiveGetChildById("LifeLeechAgainst")
		local lifeLeechButton = talismanPanel:getChildById("lifeLeechButton")
		local bountyLifeLeechPanel = talismanPanel:getChildById("bountyPointsLifeLeechPanel")

		applyBountyTalismanRow(1, talismanData[2], lifeLeechTalisman, lifeLeechButton, bountyLifeLeechPanel)

		local moreLootTalisman = talismanPanel:recursiveGetChildById("MoreLootAgainst")
		local moreLootButton = talismanPanel:getChildById("moreLootButton")
		local bountyMoreLootPanel = talismanPanel:getChildById("bountyPointsMoreLootPanel")

		applyBountyTalismanRow(2, talismanData[3], moreLootTalisman, moreLootButton, bountyMoreLootPanel)

		local bestiaryTalisman = talismanPanel:recursiveGetChildById("BestiaryAgainst")
		local bestiaryButton = talismanPanel:getChildById("bestiaryButton")
		local bountyBestiaryPanel = talismanPanel:getChildById("bountyPointsBestiaryPanel")

		applyBountyTalismanRow(3, talismanData[4], bestiaryTalisman, bestiaryButton, bountyBestiaryPanel)
	end

	if type(preferredListData) == "table" then
		updatePreferredList(preferredListData)
	end
end

local function onGameStartBounty()
	bountyCreatureCache = nil

	BountyTask:applyVersionLayout()

	scheduleEvent(buildBountyCreatureCache, 500)
	scheduleEvent(function()
		BountyTask.requestTrackerData()
	end, 500)
end

local function onGameEndBounty()
	cancelListBuild()

	bountyCreatureCache = nil
	selectedBountyRow = nil
	selectedBountyRace = nil
	lastBountyTrackerData = nil

	setBountyTrackerInactive()
end

-- ADAPTER for our engine.
-- The engine splits bounty data into TWO events always arriving in pairs and always in this order:
-- onBountyTaskData (header + monsters + talismans), followed immediately by onBountyPreferredData
-- (preference list slots). The module expects everything at once in onBountyTasksDaily, so
-- we stash the first packet in a cache and only call the handler on the second one.
local pendingBountyData = nil

local BOUNTY_ENGINE_STARS = { [0] = 0, [1] = 1, [2] = 2 }

function onEngineBountyTaskData(header, monsters, talismans)
	local slots = {}

	for _, m in ipairs(monsters or {}) do
		slots[#slots + 1] = {
			taskId = m.taskIndex,
			raceId = m.raceId,
			monstersKilled = m.currentKills,
			totalKills = m.totalKills,
			experiencePoints = m.rewardXp,
			bountyPoints = m.rewardPoints,
			rerollPoints = m.rewardReroll,
			stars = BOUNTY_ENGINE_STARS[m.rarity] or 0,
			-- 15.33: raw grade (3 = Platinum), Elite flag and dust reward
			grade = m.grade or m.rarity or 0,
			isElite = m.isElite == 1,
			dustReward = m.rewardDust or 0,
			isActive = m.isActive == 1,
			isCompleted = m.isCompleted == 1
		}
	end

	local talismanData = {}

	for _, t in ipairs(talismans or {}) do
		talismanData[#talismanData + 1] = {
			talismaLevel = t.currentValue,
			upgradePrice = t.upgradeCost,
			-- the module expects a boolean, the engine gives 0/1
			canUpgrade = t.isActiveUpgrade == 1
		}
	end

	pendingBountyData = {
		slots = slots,
		talismanData = talismanData,
		-- the engine reports difficulty on a 1-4 scale, the module counts 0-3
		difficulty = math.max(0, (header and header.difficulty or 1) - 1),
		rerollTokens = header and header.rerollPoints or 0,
		-- engine: claimDaily == 1 means "can be claimed"; module: 0 means "unlocked"
		claimUnlocked = (header and header.claimDaily == 1) and 0 or 1,
		-- 15.33: Elite enabled for new tasks
		eliteEnabled = header ~= nil and header.elite == 1
	}
end

function onEngineBountyPreferredData(preferredSlots, _, allRaceIds)
	local data = pendingBountyData or {
		slots = {},
		talismanData = {},
		difficulty = 0,
		rerollTokens = 0,
		claimUnlocked = 1
	}

	pendingBountyData = nil

	local preferredListData = {}

	for _, s in ipairs(preferredSlots or {}) do
		preferredListData[#preferredListData + 1] = {
			slot = s.slot,
			-- the engine sends locked (1 = locked), the module reads unlocked
			unlocked = s.locked == 0,
			preferred = s.preferred,
			unwanted = s.unwanted,
			price = s.price
		}
	end

	BountyTask.engineRaceIds = allRaceIds or {}

	onBountyTasksDaily(data.slots, data.rerollTokens, data.claimUnlocked, data.difficulty,
		data.talismanData, preferredListData, data.eliteEnabled)
end

function BountyTask:init()
	connect(g_game, {
		onBountyTasksDaily = onBountyTasksDaily,
		onBountyTaskData = onEngineBountyTaskData,
		onBountyPreferredData = onEngineBountyPreferredData,
		onResourceBalance = onBountyResourceBalance,
		onGameStart = onGameStartBounty,
		onGameEnd = onGameEndBounty
	})
	BountyTask:applyVersionLayout()
	scheduleEvent(refreshBountyKillTrackerFromCache, 0)
end

function BountyTask:terminate()
	disconnect(g_game, {
		onBountyTasksDaily = onBountyTasksDaily,
		onBountyTaskData = onEngineBountyTaskData,
		onBountyPreferredData = onEngineBountyPreferredData,
		onResourceBalance = onBountyResourceBalance,
		onGameStart = onGameStartBounty,
		onGameEnd = onGameEndBounty
	})
end
