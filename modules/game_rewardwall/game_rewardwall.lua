-- chunkname: @/game_rewardwall/game_rewardwall.lua

rewardWallController = Controller:new()

local ServerPackets = {
	CloseRewardWall = 227,
	OpenRewardWall = 226,
	DailyRewardCollectionState = 222,
	ShowDialog = 237,
	DailyRewardHistory = 229,
	DailyRewardBasic = 228
}
local ClientPackets = {
	JokerResource = 21,
	OpenRewardWall = 216,
	CollectionResource = 20,
	SelectReward = 218,
	OpenRewardHistory = 217
}
local ButtonRewardWall, windowsPickWindow, generalBox
local bonuses = {}
local actualUsed = {}
local bonusShrine = 0
local DAILY_REWARD_CYCLE = 86400
local dailyRewardSlotTimerEvent, dailyRewardSlotTimerData, restingAreaTimerEvent, restingAreaTimerData
local claimPending = false
local claimCloseResetEvent
local COLORS = {
	BASE_1 = "#484848",
	BASE_2 = "#414141"
}
local ZONE = {
	RESTING_AREA_ZONE = 1,
	LAST_ZONE = -99,
	NUMERIC_ICON_ID = 30,
	ICON_ID = "condition_Rewards"
}
local bundleType = {
	FIXED = 0,
	XPBOOST = 3,
	PREY = 2,
	ITEMS = 1
}

-- 15.33 reward entry kinds (0xE4): 1 item, 2 prey wildcards, 3 XP boost, 4 cosmetic tokens, 5 reroll tokens
local RewardEntryKind = {
	ITEM = 1,
	PREY_WILDCARDS = 2,
	XP_BOOST = 3,
	COSMETIC_TOKENS = 4,
	REROLL_TOKENS = 5
}

-- optional official artwork, added by the owner outside git (see UI-1533-ASSETS.md)
local REWARD_ICON_COSMETIC_1533 = "/images/game/1533/rewardwall/icon-reward-cosmetic"
local COSMETIC_TOKEN_ICON_1533 = "/images/game/1533/store/icon-cosmetic-token"
local streakBonuses = {}
local lastRewardStreak = 0

local function is1533()
	return g_game.getClientVersion() >= 1533
end

-- the window asks for the same optional images on every open and every reward list,
-- remember the answer instead of searching the resource paths again
local imageExistsCache = {}

local function imageExists(path)
	local exists = imageExistsCache[path]

	if exists == nil then
		exists = g_resources.fileExists(path .. ".png")
		imageExistsCache[path] = exists
	end

	return exists
end

-- official 15.33 graphics copied by the owner into data/images/1533/ (git ignored, see
-- install_ui_graphics.py); the names are the original ones from the client resources
local OFFICIAL_1533_ROOT = "/images/1533/images/"

local function official1533(name, fallback)
	local path = OFFICIAL_1533_ROOT .. name

	if imageExists(path) then
		return path
	end

	return fallback
end

local UI_CLASSIC = "game_rewardwall"
local UI_1533 = "game_rewardwall_1533"

-- the 15.33 window (game_rewardwall_1533.otui) has no resting area bonus icons
local function usesNewLayout()
	local ui = rewardWallController.ui

	return ui ~= nil and ui.restingAreaPanel ~= nil and ui.restingAreaPanel.bonusIcons == nil
end

local TEXT_1533 = {
	premiumActive = "Great! You benefit from the maximum number of rewards thanks to your Premium status.",
	premiumMissing = "With a Premium account, you would receive even more rewards.",
	noStreakBonus = "You currently have no Reward Streak Bonus.",
	streakBonus = "Your reward streak currently grants you a %d%% chance to gain double weapon proficiency XP.",
	streakHelp = "Claim your daily reward once between two regular server saves to keep your streak rising. Your streak grants a chance of up to %d%% to gain double weapon proficiency XP.",
	hurry = "Hurry! Claim your daily reward at latest in %s (before the next regular server save) to raise your reward streak by one.",
	claimed = "Congratulations! You claimed your daily reward in time. Come back after the next regular server save for more rewards.",
	jokers = "Daily Reward Jokers help you to keep your reward streak. If there is a day on which you're unable to claim your daily reward, you can use a joker to continue your streak. The more jokers you have, the more days you can cover.\nEvery character will receive a Daily Reward Joker on the first day of each month.\nTo be on the safe side, remember to collect your reward on a daily basis."
}
local STATUS = {
	LOCKED = 3,
	ACTIVE = 2,
	COLLECTED = 1
}
local OPEN_WINDOWS = {
	SHRINE = 1,
	BUTTON_WIDGET = 0
}
local DailyRewardStatus = {
	DAILY_REWARD_COLLECTED = 0,
	DAILY_REWARD_NOTAVAILABLE = 2,
	DAILY_REWARD_NOTCOLLECTED = 1
}
local CONST_WINDOWS_BOX = {
	ALREADY = 1,
	NO_IRA = 4,
	RELEASE = 2
}
local BOX_CONFIGS = {
	[CONST_WINDOWS_BOX.ALREADY] = {
		title = "Warning",
		content = "Sorry, you have already taken your daily reward or you are unable to collect it"
	},
	[CONST_WINDOWS_BOX.NO_IRA] = {
		title = "Warning: No Sufficient Instant Reward Access",
		content = "Remember! you can always collect your daily reward for free by visiting a reward shrine!\nyou do not have an Instant Reward Access.\nVisit the store to buy more!"
	}
}

local function destroyWindows(windows)
	if type(windows) == "table" then
		for _, window in pairs(windows) do
			if window and not window:isDestroyed() then
				g_modalManager.hide(window)
				window:destroy()
			end
		end
	elseif windows and not windows:isDestroyed() then
		g_modalManager.hide(windows)
		windows:destroy()
	end

	return nil
end

local function getClaimUsedToken()
	if bonusShrine == OPEN_WINDOWS.SHRINE then
		return 0
	end

	return 1
end

local function claimInstantDailyReward()
	g_game.requestGetRewardDaily(getClaimUsedToken(), actualUsed)

	generalBox, windowsPickWindow = destroyWindows({
		generalBox,
		windowsPickWindow
	})
end

local function premiumStatusWindwos(isPremium)
	if usesNewLayout() then
		local premiumStatus = rewardWallController.ui.premiumStatus

		premiumStatus.premiumMessage:setText(isPremium and TEXT_1533.premiumActive or TEXT_1533.premiumMissing)
		premiumStatus.premiumButton:setOn(not isPremium)
		rewardWallController.ui.infoPanel.free:setColor(isPremium and "#909090" or "#FFFFFF")
		rewardWallController.ui.infoPanel.premium:setColor(isPremium and "#FFFFFF" or "#909090")

		return
	end

	rewardWallController.ui.premiumStatus.premiumMessage:setText(isPremium and "Great! You benefit from the best possible rewards and bonuses due to your premium status." or "With a Premium account, you would benefit from even better rewards and bonuses.")
	rewardWallController.ui.premiumStatus.premiumButton:setOn(not isPremium)
	rewardWallController.ui.premiumStatus.premiumMessage:setMarginTop(-5)
	rewardWallController.ui.infoPanel.free:setColor(isPremium and "#909090" or "#FFFFFF")
	rewardWallController.ui.infoPanel.premium:setColor(isPremium and "#FFFFFF" or "#909090")
end

local function updateRestingAreaBonusIcons(dayStreakLevel)
	local bonusIcons = rewardWallController.ui and rewardWallController.ui.restingAreaPanel and rewardWallController.ui.restingAreaPanel.bonusIcons

	if not bonusIcons then
		return
	end

	dayStreakLevel = dayStreakLevel or 0

	for i = 1, 6 do
		local widget = bonusIcons:getChildById("bonusIcon" .. i)

		if not widget then
			break
		end

		local requiredStreak = i + 1
		local locked = dayStreakLevel < requiredStreak
		local dither = widget.ditherpattern or widget:getChildById("ditherpattern")

		if dither then
			dither:setVisible(locked)
		end

		local banner = widget.dayBanner or widget:getChildById("dayBanner")

		if banner then
			banner:setVisible(locked)
		end

		local bannerText = widget.dayBannerText or widget:getChildById("dayBannerText")

		if bannerText then
			bannerText:setVisible(locked)

			if locked then
				bannerText:setText(tostring(requiredStreak))
			end
		end
	end
end

local function convert_timestamp(timestamp)
	return os.date("%Y-%m-%d, %H:%M:%S", timestamp)
end

local function formatRewardTimeLeft(timeLeft)
	if not timeLeft or timeLeft == 0 then
		return ""
	end

	if timeLeft == 90001 then
		return "< 1 min"
	end

	return os.date("%H:%M", timeLeft)
end

local function resolveRemainingSeconds(nextRewardTime, elapsedSinceStart)
	if not nextRewardTime or nextRewardTime == 0 then
		return 0
	end

	if nextRewardTime == 90001 then
		return 59
	end

	if nextRewardTime > 1000000000 then
		return math.max(0, nextRewardTime - os.time())
	end

	elapsedSinceStart = elapsedSinceStart or 0

	return math.max(0, nextRewardTime - elapsedSinceStart)
end

local function formatCountdownHHMM(seconds)
	if seconds == 90001 then
		return "< 1 min"
	end

	if not seconds or seconds <= 0 then
		return "00:00"
	end

	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)

	return string.format("%02d:%02d", hours, minutes)
end

local function getDailyRewardProgressPercent(remainingSeconds, useRemaining)
	if not remainingSeconds or remainingSeconds <= 0 then
		return useRemaining and 0 or 100
	end

	remainingSeconds = math.min(remainingSeconds, DAILY_REWARD_CYCLE)

	if useRemaining then
		return math.min(100, math.max(0, remainingSeconds / DAILY_REWARD_CYCLE * 100))
	end

	local elapsed = DAILY_REWARD_CYCLE - remainingSeconds

	return math.min(100, math.max(0, elapsed / DAILY_REWARD_CYCLE * 100))
end

local function stopDailyRewardSlotTimer()
	if dailyRewardSlotTimerEvent then
		removeEvent(dailyRewardSlotTimerEvent)

		dailyRewardSlotTimerEvent = nil
	end

	dailyRewardSlotTimerData = nil
end

local function stopRestingAreaTimer()
	if restingAreaTimerEvent then
		removeEvent(restingAreaTimerEvent)

		restingAreaTimerEvent = nil
	end

	restingAreaTimerData = nil
end

local function getDailyRewardProgressBar(overlay)
	if not overlay then
		return nil
	end

	if overlay.content and overlay.content.progress then
		return overlay.content.progress
	end

	return overlay:recursiveGetChildById("progress")
end

local function updateTimerOverlayUI(timerData)
	if not timerData then
		return false
	end

	local overlay = timerData.overlay

	if not overlay or overlay:isDestroyed() then
		return false
	end

	local nextRewardTime = timerData.nextRewardTime
	local elapsed = os.time() - timerData.startTime
	local useRemaining = timerData.useRemainingProgress == true
	local text, percent

	if nextRewardTime == 0 then
		text = "00:00"
		percent = useRemaining and 0 or 100
	elseif nextRewardTime == 90001 then
		text = "< 1 min"
		percent = getDailyRewardProgressPercent(59, useRemaining)
	else
		local remaining = resolveRemainingSeconds(nextRewardTime, elapsed)

		text = formatCountdownHHMM(remaining)
		percent = getDailyRewardProgressPercent(remaining, useRemaining)
	end

	if overlay.text then
		overlay.text:setText(text)
	end

	local progressBar = getDailyRewardProgressBar(overlay)

	if progressBar then
		progressBar:setPercent(percent)
	end

	return true
end

local function updateDailyRewardSlotTimerUI()
	if not dailyRewardSlotTimerData then
		return
	end

	if not updateTimerOverlayUI(dailyRewardSlotTimerData) then
		stopDailyRewardSlotTimer()
	end
end

local function updateRestingAreaTimerUI()
	if not restingAreaTimerData then
		return
	end

	if not updateTimerOverlayUI(restingAreaTimerData) then
		stopRestingAreaTimer()
	end
end

local function startDailyRewardSlotTimer(overlay, nextRewardTime)
	stopDailyRewardSlotTimer()

	if not overlay then
		return
	end

	dailyRewardSlotTimerData = {
		useRemainingProgress = true,
		overlay = overlay,
		nextRewardTime = nextRewardTime or 0,
		startTime = os.time()
	}

	updateDailyRewardSlotTimerUI()

	dailyRewardSlotTimerEvent = cycleEvent(updateDailyRewardSlotTimerUI, 1000)
end

local function startRestingAreaTimer(overlay, nextRewardTime)
	stopRestingAreaTimer()

	if not overlay then
		return
	end

	restingAreaTimerData = {
		useRemainingProgress = true,
		overlay = overlay,
		nextRewardTime = nextRewardTime or 0,
		startTime = os.time()
	}

	updateRestingAreaTimerUI()

	restingAreaTimerEvent = cycleEvent(updateRestingAreaTimerUI, 1000)
end

local function getBonusStrings(bonuses)
	local result = {}

	for _, bonus in ipairs(bonuses) do
		table.insert(result, bonus.name)
	end

	return table.concat(result, ", ")
end

local function visibleHistory(bool)
	-- the footer stays, every other part of the window makes room for the history
	for _, widget in ipairs(rewardWallController.ui:getChildren()) do
		local id = widget:getId()

		if id == "historyPanel" then
			widget:setVisible(bool)
		elseif id ~= "footerPanel" then
			widget:setVisible(not bool)
		end
	end
end

local REWARD_CONTAINER_ACTIVE = "/game_rewardwall/images/container-bonus-active"
local REWARD_CONTAINER_INACTIVE = "/game_rewardwall/images/container-bonus-inactive"
local REWARD_GOLD_CLIPS = {
	CHECK_BOTTOM = "0 40 66 20",
	LOCKED = "0 0 66 20",
	CHECK_TOP = "0 20 66 20",
	EMPTY = "0 60 66 20"
}
local REWARD_ARROW_CLIPS = {
	CURRENT_LEFT = "5 0 5 7",
	DEFAULT = "0 0 5 7"
}
local REWARD_BUTTON_MODE = {
	LOCKED = 3,
	WAITING = 2,
	COLLECTABLE = 1,
	COLLECTED = 4
}
local pendingRewardButton
local TILE_BUTTON_UP = "/images/ui/button-grey-up"
local TILE_BUTTON_DOWN = "/images/ui/button-grey-down"

-- 15.33 tile: parchment backdrop in a sunken frame, the claimable day is a raised button and
-- every day except the current one is dithered (RewardWallDialog.qml)
local function setOfficialTileVisual(button, pressed)
	local mode = button.rewardVisualMode
	local collectable = mode == REWARD_BUTTON_MODE.COLLECTABLE

	if collectable then
		button:setImageSource(pressed and TILE_BUTTON_DOWN or TILE_BUTTON_UP)
		button:setImageBorder(3)
	else
		button:setImageSource(button.officialFrame)
		button:setImageBorder(1)
	end

	button:setImageClip("0 0 0 0")

	local shift = pressed and 1 or 0

	button.rewardIcon:setMarginTop(13 + shift)
	button.rewardIcon:setMarginLeft(13 + shift)
	button.countText:setMarginBottom(14 - shift)
	-- the raised button text is 2px wider to the left until it is pressed
	button.countText:setMarginLeft(collectable and not pressed and -2 or 0)
	button.premiumBanner:setMarginTop(1 + shift)
	button.premiumBanner:setMarginLeft(1 + shift)
	button.ditherpattern:setVisible(mode == REWARD_BUTTON_MODE.COLLECTED or mode == REWARD_BUTTON_MODE.LOCKED)
end

local function setRewardDayButtonState(button, mode)
	if not button then
		return
	end

	button.rewardVisualMode = mode

	if button.officialArt then
		setOfficialTileVisual(button, false)

		return
	end

	local dither = button.ditherpattern

	if mode == REWARD_BUTTON_MODE.COLLECTABLE then
		button:setImageSource(REWARD_CONTAINER_ACTIVE)
		button:setImageClip("0 0 66 66")

		if dither then
			dither:setVisible(false)
		end
	elseif mode == REWARD_BUTTON_MODE.WAITING then
		button:setImageSource(REWARD_CONTAINER_INACTIVE)
		button:setImageClip("0 0 66 66")

		if dither then
			dither:setVisible(false)
		end
	else
		button:setImageSource(REWARD_CONTAINER_INACTIVE)
		button:setImageClip("0 0 66 66")

		if dither then
			dither:setVisible(true)
		end
	end
end

local function restoreRewardButtonVisual(button)
	if not button or button.rewardVisualMode ~= REWARD_BUTTON_MODE.COLLECTABLE then
		return
	end

	if button.officialArt then
		setOfficialTileVisual(button, false)

		return
	end

	button:setImageSource(REWARD_CONTAINER_ACTIVE)
	button:setImageClip("0 0 66 66")
end

local function wireRewardButtonClick(button)
	if not button or button.rewardClickWired then
		return
	end

	button.rewardClickWired = true
	button.onClick = nil

	function button.onMousePress(widget, mousePos, mouseButton)
		if mouseButton ~= MouseLeftButton then
			return false
		end

		if widget.rewardVisualMode ~= REWARD_BUTTON_MODE.COLLECTABLE or claimPending then
			return true
		end

		pendingRewardButton = widget

		if widget.officialArt then
			setOfficialTileVisual(widget, true)
		else
			widget:setImageClip("66 0 66 66")
		end

		return true
	end

	function button.onMouseRelease(widget, mousePos, mouseButton)
		if mouseButton ~= MouseLeftButton then
			return false
		end

		local wasPending = pendingRewardButton == widget

		pendingRewardButton = nil

		restoreRewardButtonVisual(widget)

		if widget.rewardVisualMode ~= REWARD_BUTTON_MODE.COLLECTABLE then
			return true
		end

		if not wasPending or claimPending then
			return true
		end

		if not widget:containsPoint(mousePos) then
			return true
		end

		onClickPickReward(widget)

		return true
	end
end

local function beginClaim()
	if claimPending then
		return false
	end

	claimPending = true

	return true
end

local function setRewardGoldSlotState(slot)
	if not slot then
		return
	end

	slot:setOn(false)
end

local function setupRewardGoldOverlay(slot, styleName)
	if not slot then
		return nil
	end

	-- every open refreshes all seven slots, keep the overlay when the day kept its state
	local current = slot.rewardOverlay

	if current and slot.rewardOverlayStyle == styleName and not current:isDestroyed() then
		return current
	end

	slot:destroyChildren()

	local overlay = g_ui.createWidget(styleName, slot)

	overlay:setPhantom(true)

	slot.rewardOverlay = overlay
	slot.rewardOverlayStyle = styleName

	return overlay
end

local function updateRewardGoldCollectableOverlay(overlay)
	if not overlay then
		return
	end

	local balance = 0
	local player = g_game.getLocalPlayer()

	if player then
		balance = player:getResourceBalance(ResourceTypes.DAILYREWARD_STREAK) or 0
	end

	if overlay.balance then
		overlay.balance:setText(tostring(balance))
	end
end

local function setupClaimButton(button, slot, rewardButton)
	if not button then
		return
	end

	button:setPhantom(false)

	function button.onClick()
		if rewardButton.rewardVisualMode == REWARD_BUTTON_MODE.COLLECTABLE and not claimPending then
			onClickPickReward(rewardButton)
		end
	end

	-- the slot holds the hover text, the button on top of it would swallow the hover
	function button.onHoverChange(widget, hovered)
		if slot.onHoverChange then
			slot:onHoverChange(hovered)
		end
	end
end

local function updateLoopArrow(dayStreakDay)
	local arrowLoop = rewardWallController.ui.dailyRewardsPanel.arrowLoop

	if not arrowLoop or not usesNewLayout() then
		return
	end

	-- RewardWallDialog.qml: active once a cycle is complete and the first day is next again
	local active = lastRewardStreak ~= 0 and dayStreakDay == 0
	local name = active and "icon-rewardarrow-loop-active" or "icon-rewardarrow-loop-inactive"

	arrowLoop:setImageSource(official1533("dailyreward/" .. name, "/game_rewardwall/images/" .. name))
end

local function getRestingAreaTimeLeftFrame(widget)
	if not widget then
		return nil
	end

	return widget.frame or widget:getChildById("frame")
end

local function updateRestingAreaTimeLeft(notCollected, timeLeft)
	local timeLeftWidget = rewardWallController.ui.restingAreaPanel.restingAreaInfo.timeLeft

	if not timeLeftWidget then
		return
	end

	local frame = getRestingAreaTimeLeftFrame(timeLeftWidget)

	if notCollected then
		if frame then
			frame:setImageClip(REWARD_GOLD_CLIPS.EMPTY)
		end

		if timeLeftWidget.content then
			timeLeftWidget.content:setVisible(true)
		end

		if timeLeftWidget.text then
			timeLeftWidget.text:setVisible(true)
		end

		startRestingAreaTimer(timeLeftWidget, timeLeft)
	else
		stopRestingAreaTimer()

		if frame then
			frame:setImageClip(REWARD_GOLD_CLIPS.CHECK_TOP)
		end

		if timeLeftWidget.content then
			timeLeftWidget.content:setVisible(false)
		end

		if timeLeftWidget.text then
			timeLeftWidget.text:setVisible(false)
			timeLeftWidget.text:setText("")
		end
	end
end

-- the info icon next to the timer explains the streak state (rewardStreakStateInfoText)
local lastTimerHelpState

local function updateTimerHelp(canClaim, timeLeft)
	local ui = rewardWallController.ui

	if not usesNewLayout() or not ui.restingAreaPanel.restingAreaInfo.timeLeftHelp then
		return
	end

	if canClaim ~= nil then
		lastTimerHelpState = {
			canClaim = canClaim,
			timeLeft = timeLeft,
			startTime = os.time()
		}
	end

	local state = lastTimerHelpState or {}
	local text

	if state.canClaim then
		local remaining = resolveRemainingSeconds(state.timeLeft, os.time() - (state.startTime or os.time()))

		text = string.format(TEXT_1533.hurry, formatCountdownHHMM(remaining))
	else
		text = TEXT_1533.claimed
	end

	ui.restingAreaPanel.restingAreaInfo.timeLeftHelp:setTooltip(text)
end

local function initRewardGoldSlots()
	local panel = rewardWallController.ui and rewardWallController.ui.dailyRewardsPanel

	if not panel then
		return
	end

	for i = 1, 7 do
		local rewardWidget = panel:getChildById("reward" .. i)

		if rewardWidget then
			setRewardGoldSlotState(rewardWidget:getChildById("rewardGold" .. i))
		end
	end
end

local function updateDailyRewards(dayStreakDay, wasDailyRewardTaken, nextRewardTime, canGetReward, timeLeft)
	stopDailyRewardSlotTimer()
	stopRestingAreaTimer()

	if not dayStreakDay or dayStreakDay < 0 or dayStreakDay > 6 then
		dayStreakDay = 0
	end

	if not wasDailyRewardTaken or wasDailyRewardTaken < 0 then
		wasDailyRewardTaken = 0
	end

	local canClaim = canGetReward == 2
	local currentIndex = dayStreakDay + 1
	local dailyRewardsPanel = rewardWallController.ui.dailyRewardsPanel

	for i = 1, 6 do
		local rewardArrow = dailyRewardsPanel:getChildById("arrow" .. i)

		if rewardArrow then
			local active = i < currentIndex

			if rewardArrow.officialActive then
				rewardArrow:setImageSource(active and rewardArrow.officialActive or rewardArrow.officialInactive)
				rewardArrow:setImageClip("0 0 0 0")
			elseif active then
				rewardArrow:setImageClip(REWARD_ARROW_CLIPS.CURRENT_LEFT)
			else
				rewardArrow:setImageClip(REWARD_ARROW_CLIPS.DEFAULT)
			end
		end
	end

	updateLoopArrow(dayStreakDay)

	for i = 1, 7 do
		local rewardWidget = dailyRewardsPanel:getChildById("reward" .. i)

		if not rewardWidget then
			break
		end

		local rewardButton = rewardWidget:getChildById("rewardButton" .. i)
		local goldSlot = rewardWidget:getChildById("rewardGold" .. i)

		wireRewardButtonClick(rewardButton)

		if i < currentIndex then
			setupRewardGoldOverlay(goldSlot, "RewardGoldCollected")
			setRewardGoldSlotState(goldSlot)
			setRewardDayButtonState(rewardButton, REWARD_BUTTON_MODE.COLLECTED)

			goldSlot.status = STATUS.COLLECTED
		elseif i == currentIndex then
			setRewardGoldSlotState(goldSlot)

			if canClaim and usesNewLayout() then
				-- 15.33 shows a Claim button under the claimable day
				local overlay = setupRewardGoldOverlay(goldSlot, "RewardGoldClaim")

				setupClaimButton(overlay, goldSlot, rewardButton)
				setRewardDayButtonState(rewardButton, REWARD_BUTTON_MODE.COLLECTABLE)
			elseif canClaim then
				local overlay = setupRewardGoldOverlay(goldSlot, "RewardGoldCollectable")

				updateRewardGoldCollectableOverlay(overlay)
				setRewardDayButtonState(rewardButton, REWARD_BUTTON_MODE.COLLECTABLE)
			else
				local overlay = setupRewardGoldOverlay(goldSlot, "RewardGoldContent")

				startDailyRewardSlotTimer(overlay, nextRewardTime)
				setRewardDayButtonState(rewardButton, REWARD_BUTTON_MODE.WAITING)
			end

			goldSlot.status = STATUS.ACTIVE
		else
			setupRewardGoldOverlay(goldSlot, "RewardGoldLocked")
			setRewardGoldSlotState(goldSlot)
			setRewardDayButtonState(rewardButton, REWARD_BUTTON_MODE.LOCKED)

			goldSlot.status = STATUS.LOCKED
		end
	end

	updateRestingAreaTimeLeft(canClaim, timeLeft)
	updateTimerHelp(canClaim, timeLeft)
end

local function getDayStreakIcon(dayStreakLevel)
	local IconConsecutiveDays = {
		[24] = "icon-rewardstreak-default",
		[49] = "icon-rewardstreak-bronze",
		[99] = "icon-rewardstreak-silver",
		[100] = "icon-rewardstreak-gold"
	}

	if dayStreakLevel <= 24 then
		return IconConsecutiveDays[24]
	elseif dayStreakLevel <= 49 then
		return IconConsecutiveDays[49]
	elseif dayStreakLevel <= 99 then
		return IconConsecutiveDays[99]
	else
		return IconConsecutiveDays[100]
	end
end

local function getBonusDescription(bonusName, streakCount, activeBonuses)
	local isPremium = g_game.getLocalPlayer():isPremium()

	return string.format("Allow [color=#909090]%s[/color]%s\nThis bonus is active because you are [color=%s]Premium[/color] and reached a reward streak of at least [color=#44AD25]%d[/color].%s", bonusName, isPremium and "" or "[color=#ff0000](Locked)[/color]", isPremium and "#44AD25" or "#ff0000", streakCount, isPremium and ("\n\nActive bonuses: [color=#909090]%s[/color]."):format(activeBonuses) or "")
end

local function pluralText(count, singular, plural)
	return count == 1 and singular or plural
end

local function formatRewardEntry(entry)
	local count = tonumber(entry.count) or 0
	local kind = entry.bundleType

	if kind == RewardEntryKind.ITEM then
		return string.format("%dx %s", count, entry.name or "")
	elseif kind == RewardEntryKind.PREY_WILDCARDS then
		return string.format("%d %s", count, pluralText(count, "Prey Wildcard", "Prey Wildcards"))
	elseif kind == RewardEntryKind.XP_BOOST then
		-- the parser keeps the minutes in itemId and the percent in value
		return string.format("%d minutes XP Boost %d%%", tonumber(entry.itemId) or 0, tonumber(entry.value) or 0)
	elseif kind == RewardEntryKind.COSMETIC_TOKENS then
		return string.format("%d %s", count, pluralText(count, "Cosmetic Token", "Cosmetic Tokens"))
	elseif kind == RewardEntryKind.REROLL_TOKENS then
		return string.format("%d %s", count, pluralText(count, "Reroll Token", "Reroll Tokens"))
	end

	return entry.name or ""
end

local function formatRewardEntries(day)
	local lines = {}

	for _, entry in ipairs(day and day.bundleItems or {}) do
		table.insert(lines, formatRewardEntry(entry))
	end

	if #lines == 0 then
		return tr("No reward")
	end

	return table.concat(lines, "\n")
end

local function getRewardIcon1533(day)
	local first = day and day.bundleItems and day.bundleItems[1]
	local kind = first and first.bundleType

	if kind == RewardEntryKind.XP_BOOST then
		return "game_rewardwall/images/icon-reward-xpboost"
	elseif kind == RewardEntryKind.COSMETIC_TOKENS and imageExists(REWARD_ICON_COSMETIC_1533) then
		return REWARD_ICON_COSMETIC_1533
	end

	return "game_rewardwall/images/icon-reward-fixeditems"
end

-- RewardWallDialog.qml dailyRewardIcon: one 30x30 icon per kind of the first entry
local OFFICIAL_REWARD_ICONS = {
	[RewardEntryKind.ITEM] = "dailyreward/icon-reward-temple-teleport",
	[RewardEntryKind.PREY_WILDCARDS] = "dailyreward/icon-reward-wildcard",
	[RewardEntryKind.XP_BOOST] = "dailyreward/icon-reward-xp-boost",
	[RewardEntryKind.COSMETIC_TOKENS] = "dailyreward/icon-reward-cosmetic"
}

-- dailyRewardNumbersText: the amount of the first entry, the percent for an XP boost
local function getRewardNumbersText(day)
	local first = day and day.bundleItems and day.bundleItems[1]

	if not first then
		return ""
	end

	if first.bundleType == RewardEntryKind.XP_BOOST then
		return string.format("%d%%", tonumber(first.value) or 0)
	end

	return string.format("x%d", tonumber(first.count) or 0)
end

local function fillOfficialTile(button, day, premium)
	local first = day and day.bundleItems and day.bundleItems[1]
	local iconName = first and OFFICIAL_REWARD_ICONS[first.bundleType]
	local iconPath = iconName and official1533(iconName)

	button:setIcon("")

	if iconPath then
		button.rewardIcon:setImageSource(iconPath)
		button.rewardIcon:setVisible(true)
	else
		-- no official icon for this kind (reroll tokens): show the repo artwork scaled down
		local fallback = getRewardIcon1533(day)

		button.rewardIcon:setImageSource(fallback:sub(1, 1) == "/" and fallback or "/" .. fallback)
		button.rewardIcon:setVisible(first ~= nil)
	end

	button.countText:setText(getRewardNumbersText(day))
	button.countText:setVisible(true)
	button.premiumBanner:setVisible(premium and button.premiumBanner:getImageSource() ~= "")
end

local function checkRewards(data)
	local premium = g_game.getLocalPlayer():isPremium()
	local rewardType = premium and data.premiumRewards or data.freeRewards
	local altType = premium and data.freeRewards or data.premiumRewards

	for index = 1, #rewardType do
		local reward = rewardType[index]
		local altReward = altType[index]
		local rewardWidget = rewardWallController.ui.dailyRewardsPanel:getChildById("reward" .. index)

		if not rewardWidget then
			break
		end

		local rewardButton = rewardWidget:getChildById("rewardButton" .. index)

		if not rewardButton then
			break
		end

		rewardButton.rewardEntries = nil

		local hasSelectableItems = reward.selectableItems and next(reward.selectableItems) ~= nil
		local iconWidget = rewardButton
		-- 15.33 days can have an empty reward list (and new token kinds 4 and 5)
		local firstBundle = reward.bundleItems and reward.bundleItems[1]
		local altFirstBundle = altReward and altReward.bundleItems and altReward.bundleItems[1]

		if is1533() then
			-- 15.33 has no pick items rewards: every day is a fixed list that is claimed with one click
			if rewardButton.officialArt then
				fillOfficialTile(rewardButton, reward, premium)
			else
				iconWidget:setIcon(getRewardIcon1533(reward))
			end

			rewardButton.bundleType = bundleType.FIXED
			rewardButton.rewardEntries = {
				free = data.freeRewards and data.freeRewards[index],
				premium = data.premiumRewards and data.premiumRewards[index]
			}
		elseif hasSelectableItems then
			iconWidget:setIcon("game_rewardwall/images/icon-reward-pickitems")

			rewardButton.bundleType = bundleType.ITEMS
			rewardButton.rewardItem = reward.selectableItems
			rewardButton.itemsToSelect = {
				reward.itemsToSelect or 0,
				altReward and altReward.itemsToSelect or 0
			}
		elseif firstBundle and firstBundle.bundleType == bundleType.XPBOOST then
			iconWidget:setIcon("game_rewardwall/images/icon-reward-xpboost")

			rewardButton.bundleType = bundleType.XPBOOST
			rewardButton.itemsToSelect = {
				firstBundle.itemId or 0,
				altFirstBundle and altFirstBundle.itemId or 0
			}
		else
			iconWidget:setIcon("game_rewardwall/images/icon-reward-fixeditems")

			rewardButton.bundleType = bundleType.PREY
			rewardButton.itemsToSelect = {
				firstBundle and firstBundle.count or 0,
				altFirstBundle and altFirstBundle.count or 0
			}
			rewardButton.itemName = firstBundle and firstBundle.name or "Prey Wildcard"
		end
	end
end

local function onDailyRewardCollectionState(state)
	if not rewardWallController.ui:isVisible() then
		return
	end

	local text = {
		[DailyRewardStatus.DAILY_REWARD_COLLECTED] = "you did not claim your daily reward in time. too bad, you do not have enough Daily Reward Jokers.",
		[DailyRewardStatus.DAILY_REWARD_NOTCOLLECTED] = "You did not claim your daily reward in time. If you don't claim your reward now, your [color=#D33C3C]streak will be reset.[/color]",
		[DailyRewardStatus.DAILY_REWARD_NOTAVAILABLE] = "idk"
	}

	if usesNewLayout() then
		-- the server sends this after every open and only tells whether today's reward was
		-- taken, not that a claim was missed, so the official window would show no warning
		return
	end

	rewardWallController.ui.restingAreaPanel.streakWarning:parseColoredText(text[state], "#c0c0c0")
end

local function onRestingAreaState(zone, state, message)
	-- 15.33 no longer sends a text, so the icon would get an empty tooltip
	if not message or message == "" then
		message = tr("You are within a resting area.")
	end

	updatePlayerRestingAreaState(zone, state, message)

	if ZONE.LAST_ZONE == zone then
		return
	end

	ZONE.LAST_ZONE = zone

	local gameInterface = modules.game_interface

	if zone == ZONE.RESTING_AREA_ZONE then
		gameInterface.processIcon(ZONE.NUMERIC_ICON_ID, function(icon)
			icon:setTooltip(message)
		end, true)
	else
		gameInterface.processIcon(ZONE.ICON_ID, function(icon)
			icon:destroy()
		end)
	end
end

local function getStreakBonusPercent(streak)
	local count = #streakBonuses

	if not streak or streak <= 0 or count == 0 then
		return 0
	end

	-- the server sends one entry per streak length, the last entry covers every longer streak
	return tonumber(streakBonuses[math.min(streak, count)]) or 0
end

local function updateStreakBonusText()
	local ui = rewardWallController.ui

	if not ui or not is1533() then
		return
	end

	local panel = ui.restingAreaPanel.streakBonusPanel
	local percent = getStreakBonusPercent(lastRewardStreak)

	if not usesNewLayout() then
		panel.streakBonusText:setText(string.format(TEXT_1533.streakBonus, percent))

		return
	end

	panel.streakBonusText:setText(percent > 0 and string.format(TEXT_1533.streakBonus, percent) or TEXT_1533.noStreakBonus)

	local maxPercent = 0

	for _, value in ipairs(streakBonuses) do
		maxPercent = math.max(maxPercent, tonumber(value) or 0)
	end

	panel.streakBonusHelp:setTooltip(string.format(TEXT_1533.streakHelp, maxPercent > 0 and maxPercent or 7))
end

local function setFooterBalance(widget, value)
	if widget and widget.text then
		widget.text:setText(tostring(value or 0))
	end
end

local function updateTokenBalances()
	local ui = rewardWallController.ui
	local player = g_game.getLocalPlayer()

	if not ui or not player or not is1533() then
		return
	end

	setFooterBalance(ui.footerPanel.footerCosmetic, player:getResourceBalance(ResourceTypes.COSMETIC_TOKENS) or 0)
	setFooterBalance(ui.footerPanel.footerReroll, player:getResourceBalance(ResourceTypes.BOUNTY_REROLL_TOKENS) or 0)
end

local function onRewardWallResourceBalance(resourceType, value)
	if not rewardWallController.ui then
		return
	end

	if resourceType == ResourceTypes.COSMETIC_TOKENS or resourceType == ResourceTypes.BOUNTY_REROLL_TOKENS then
		updateTokenBalances()
	elseif resourceType == ResourceTypes.DAILYREWARD_STREAK then
		setFooterBalance(rewardWallController.ui.footerPanel.footerGold2, value)
	end
end

local STREAK_HELP_TEXT_1533 = "Claim a daily reward every day to raise your reward streak by 1. If you miss a day, Daily Reward Jokers are used to keep the streak; without enough jokers it is reset.\n\nThe longer your reward streak, the higher your chance to gain double weapon proficiency XP."

-- 15.33 replaced the resting area bonus icons with the reward streak bonus and shows the token balances in the footer
local function applyVersionLayout()
	local ui = rewardWallController.ui

	if not ui then
		return
	end

	if usesNewLayout() then
		-- game_rewardwall_1533.otui already has the 15.33 parts in place
		ui.restingAreaPanel.restingAreaInfo.jokerHelp:setTooltip(TEXT_1533.jokers)

		return
	end

	local newLayout = is1533()
	local resting = ui.restingAreaPanel
	local footer = ui.footerPanel

	resting.bonusIcons:setVisible(not newLayout)
	resting.streakBonusPanel:setVisible(newLayout)
	resting.streakBonusPanel.streakBonusHelp:setTooltip(STREAK_HELP_TEXT_1533)
	footer.footerCosmetic:setVisible(newLayout)
	footer.footerReroll:setVisible(newLayout)
	footer.footerGold1:removeAnchor(AnchorLeft)

	if newLayout then
		footer.footerGold1:addAnchor(AnchorLeft, "footerReroll", AnchorRight)
		footer.footerGold1:setMarginLeft(6)

		if imageExists(COSMETIC_TOKEN_ICON_1533) then
			footer.footerCosmetic.gold:setImageSource(COSMETIC_TOKEN_ICON_1533)
		end
	else
		footer.footerGold1:addAnchor(AnchorLeft, "parent", AnchorLeft)
		footer.footerGold1:setMarginLeft(0)
	end
end

local function onDailyReward(data)
	if not data then
		return
	end

	bonuses = data.bonuses or {}
	streakBonuses = data.streakBonuses or {}

	checkRewards(data)
	updateStreakBonusText()
end

local function onServerError(code, error)
	claimPending = false
	generalBox = destroyWindows(generalBox)

	local function cancelCallback()
		generalBox = destroyWindows(generalBox)

		rewardWallController.ui:show()
		g_modalManager.show(rewardWallController.ui)
	end

	local standardButtons = {
		{
			text = "ok",
			callback = cancelCallback
		}
	}

	generalBox = displayGeneralBox3(rewardWallController.ui:getText(), error, standardButtons)
end

local function connectOnServerError()
	connect(g_game, {
		onServerError = onServerError
	})
end

local function disconnectOnServerError()
	disconnect(g_game, {
		onServerError = onServerError
	})
end

local function onCloseRewardWall()
	if claimPending then
		hide(false)

		if claimCloseResetEvent then
			removeEvent(claimCloseResetEvent)
		end

		claimCloseResetEvent = scheduleEvent(function()
			claimCloseResetEvent = nil

			if claimPending then
				claimPending = false
			end
		end, 2000)

		return
	end

	hide(true)
end

local function onOpenRewardWall(bonusShrines, nextRewardTime, dayStreakDay, wasDailyRewardTaken, errorMessage, tokens, timeLeft, dayStreakLevel, canGetReward)
	if claimCloseResetEvent then
		removeEvent(claimCloseResetEvent)

		claimCloseResetEvent = nil
	end

	claimPending = false
	pendingRewardButton = nil
	bonusShrine = bonusShrines

	lastRewardStreak = dayStreakLevel or 0

	applyVersionLayout()
	updateDailyRewards(dayStreakDay, wasDailyRewardTaken, nextRewardTime, canGetReward, timeLeft)
	premiumStatusWindwos(g_game.getLocalPlayer():isPremium())
	rewardWallController.ui:show()
	g_modalManager.show(rewardWallController.ui)
	connectOnServerError()
	rewardWallController.ui.restingAreaPanel.restingAreaInfo.rewardStreakIcon:setText(dayStreakLevel)
	updateRestingAreaBonusIcons(dayStreakLevel)

	if tokens and tokens > 999999 then
		tokens = 0
	end

	rewardWallController.ui.restingAreaPanel.restingAreaInfo.restingAreaGold.text:setText(tokens or 0)
	rewardWallController.ui.footerPanel.footerGold1.text:setText(tokens or 0)
	local streakIcon = getDayStreakIcon(dayStreakLevel)

	rewardWallController.ui.restingAreaPanel.restingAreaInfo.rewardStreakIcon:setImageSource(usesNewLayout() and official1533("dailyreward/" .. streakIcon, "/game_rewardwall/images/" .. streakIcon) or "/game_rewardwall/images/" .. streakIcon)
	rewardWallController.ui.footerPanel.footerGold2.text:setText(g_game.getLocalPlayer():getResourceBalance(ResourceTypes.DAILYREWARD_STREAK))
	updateStreakBonusText()
	updateTokenBalances()

	if is1533() then
		-- the balances are not pushed on login, ask for the current values
		g_game.sendResourceBalance(ResourceTypes.COSMETIC_TOKENS)
		g_game.sendResourceBalance(ResourceTypes.BOUNTY_REROLL_TOKENS)
	end
end

local function historyDescriptionMarginTop(descriptionLabel, text)
	descriptionLabel:setText(text)
	descriptionLabel:setTextWrap(false)

	local wraps = descriptionLabel:getTextSize().width > descriptionLabel:getWidth()

	descriptionLabel:setTextWrap(true)

	return wraps and -3 or -16
end

local function onRewardHistory(rewardHistory)
	local transferHistory = rewardWallController.ui.historyPanel.historyList.List

	transferHistory:destroyChildren()

	local headerRow = g_ui.createWidget("historyData2", transferHistory)

	headerRow:setBackgroundColor("#363636")
	headerRow.date:setText("Date")
	headerRow.Balance:setText("Streak")
	headerRow.Description:setText("Event")

	for i, data in ipairs(rewardHistory) do
		local row = g_ui.createWidget("historyData2", transferHistory)

		row:setHeight(30)
		row.date:setText(convert_timestamp(data[1]))
		row.date:setMarginTop(-16)
		row.Balance:setText(data[4])
		row.Balance:setMarginTop(-12)
		row.Balance:setTextOffset("-6 -2")
		row.Description:setMarginTop(historyDescriptionMarginTop(row.Description, data[3]))
		row:setBackgroundColor(i % 2 == 0 and "#ffffff12" or "#00000012")
	end
end

function show()
	if not rewardWallController.ui then
		return
	end

	if not rewardWallController.ui:isVisible() then
		g_game.sendOpenRewardWall()
	end

	rewardWallController.ui:show()
	g_modalManager.show(rewardWallController.ui)
	connectOnServerError()
	premiumStatusWindwos(g_game.getLocalPlayer():isPremium())
end

function hide(bool)
	if not rewardWallController.ui then
		return
	end

	stopDailyRewardSlotTimer()
	stopRestingAreaTimer()
	g_modalManager.hide(rewardWallController.ui)
	rewardWallController.ui:hide()

	if bool then
		disconnectOnServerError()
	end
end

function toggle()
	if not rewardWallController.ui then
		return
	end

	if rewardWallController.ui:isVisible() then
		if ButtonRewardWall then
			ButtonRewardWall:setOn(false)
		end

		return hide(true)
	end

	show()
end

local INFO_PANEL_COLOR = "#c0c0c0"

local function clearInfoPanel()
	if not rewardWallController.ui or not rewardWallController.ui.infoPanel then
		return
	end

	local infoPanel = rewardWallController.ui.infoPanel

	infoPanel.statusText:setText("")
	infoPanel.statusText:setVisible(true)
	infoPanel.free:setText("")
	infoPanel.free:setVisible(false)
	infoPanel.premium:setText("")
	infoPanel.premium:setVisible(false)
end

local function showInfoPanelDescription(text, colored)
	if not rewardWallController.ui or not rewardWallController.ui.infoPanel then
		return
	end

	local infoPanel = rewardWallController.ui.infoPanel

	infoPanel.free:setVisible(false)
	infoPanel.premium:setVisible(false)
	infoPanel.statusText:setVisible(true)
	infoPanel.statusText:raise()

	text = text or ""

	if colored then
		infoPanel.statusText:parseColoredText(text, INFO_PANEL_COLOR)
	else
		infoPanel.statusText:setText(text)
		infoPanel.statusText:setColor(INFO_PANEL_COLOR)
	end
end

local function showInfoPanelRewardSplit(freeText, premiumText)
	if not rewardWallController.ui or not rewardWallController.ui.infoPanel then
		return
	end

	local infoPanel = rewardWallController.ui.infoPanel

	infoPanel.statusText:setText("")
	infoPanel.statusText:setVisible(false)
	infoPanel.statusText:lower()
	infoPanel.free:setVisible(true)
	infoPanel.premium:setVisible(true)
	infoPanel.free:raise()
	infoPanel.premium:raise()
	infoPanel.free:setText(freeText or "")
	infoPanel.premium:setText(premiumText or "")
end

local function wireHover(widget, handler)
	if not widget then
		return
	end

	function widget:onHoverChange(hovered)
		handler({
			target = self,
			value = hovered
		})
	end
end

local function setupRewardWallHovers()
	local ui = rewardWallController.ui

	if not ui then
		return
	end

	local restingInfo = ui.restingAreaPanel.restingAreaInfo

	wireHover(restingInfo.rewardStreakIcon, function(e)
		rewardWallController:onhoverStatusPlayer(e)
	end)
	wireHover(restingInfo.timeLeft, function(e)
		rewardWallController:onhoverStatusPlayer(e)
	end)
	wireHover(restingInfo.restingAreaGold, function(e)
		rewardWallController:onhoverStatusPlayer(e)
	end)

	local bonusIcons = ui.restingAreaPanel.bonusIcons

	for i = 1, 6 do
		wireHover(bonusIcons and bonusIcons:getChildById("bonusIcon" .. i), function(e)
			rewardWallController:onhoverBonus(e)
		end)
	end

	for i = 1, 7 do
		local rewardPanel = ui.dailyRewardsPanel:getChildById("reward" .. i)

		if rewardPanel then
			wireRewardButtonClick(rewardPanel:getChildById("rewardButton" .. i))
			wireHover(rewardPanel:getChildById("rewardButton" .. i), function(e)
				rewardWallController:onhoverRewardType(e)
			end)
			wireHover(rewardPanel:getChildById("rewardGold" .. i), function(e)
				rewardWallController:onhoverStatusReward(e)
			end)
		end
	end
end

-- swap in the official 15.33 graphics when the owner installed them (data/images/1533/)
local function applyOfficialArtwork()
	local ui = rewardWallController.ui

	if not usesNewLayout() then
		return
	end

	local frame = official1533("1pixel-down-frame")
	local backdrop = official1533("dailyreward/reward-scroll-backdrop")
	local banner = official1533("dailyreward/icon-reward-premium-banner")
	local dither = official1533("ditherpattern")

	for i = 1, 7 do
		local rewardPanel = ui.dailyRewardsPanel:getChildById("reward" .. i)
		local button = rewardPanel and rewardPanel:getChildById("rewardButton" .. i)

		if button and button.backdrop and frame and backdrop then
			button.officialArt = true
			button.officialFrame = frame

			button:setImageSource(frame)
			button:setImageBorder(1)
			button:setImageClip("0 0 0 0")
			button.backdrop:setImageSource(backdrop)
			button.backdrop:setVisible(true)
			button.premiumBanner:setImageSource(banner or "")

			if dither then
				button.ditherpattern:setImageSource(dither)
				button.ditherpattern:setImageRepeated(true)
			end
		end
	end

	local arrowActive = official1533("dailyreward/icon-rewardarrow-active")
	local arrowInactive = official1533("dailyreward/icon-rewardarrow-inactive")

	if arrowActive and arrowInactive then
		for i = 1, 6 do
			local arrow = ui.dailyRewardsPanel:getChildById("arrow" .. i)

			if arrow then
				arrow.officialActive = arrowActive
				arrow.officialInactive = arrowInactive

				arrow:setImageSource(arrowInactive)
				arrow:setImageClip("0 0 0 0")
			end
		end
	end

	local restingInfo = ui.restingAreaPanel.restingAreaInfo
	local help = official1533("skin/classic/show-gui-help-grey")

	if help then
		restingInfo.timeLeftHelp:setImageSource(help)
		restingInfo.jokerHelp:setImageSource(help)
		ui.restingAreaPanel.streakBonusPanel.streakBonusHelp:setImageSource(help)
	end

	ui.streakArrow:setImageSource(official1533("icon-arrow-rightlarge", "/images/game/forge/icon-arrow-rightlarge"))

	local footer = ui.footerPanel
	local jokerIcon = official1533("icon-daily-reward-joker", "/game_rewardwall/images/icon-daily-reward-joker")
	local cosmeticIcon = official1533("icon-cosmetic-token", imageExists(COSMETIC_TOKEN_ICON_1533) and COSMETIC_TOKEN_ICON_1533 or nil)

	if cosmeticIcon then
		footer.footerCosmetic.gold:setImageSource(cosmeticIcon)
	end

	footer.footerReroll.gold:setImageSource(official1533("taskboard/icon-currency-taskreroll", "/images/game_taskboard/icon-currency-taskreroll"))
	footer.footerGold1.gold:setImageSource(jokerIcon)
	footer.footerGold2.gold:setImageSource(official1533("instant-reward-access-icon", "/game_rewardwall/images/instant-reward-access-icon"))
	restingInfo.restingAreaGold.gold:setImageSource(jokerIcon)
end

local function setupRewardWallUi()
	rewardWallController.ui.footerPanel.footerGold1.text:setTextAlign(AlignRightCenter)
	applyOfficialArtwork()
	clearInfoPanel()
	setupRewardWallHovers()
	initRewardGoldSlots()
end

-- the window is built before the protocol version is known; 15.33 gets its own landscape layout
local function loadRewardWallUi(name)
	local controller = rewardWallController

	if controller.ui and controller.dataUI and controller.dataUI.name == name then
		return
	end

	stopDailyRewardSlotTimer()
	stopRestingAreaTimer()

	pendingRewardButton = nil
	lastTimerHelpState = nil

	if controller.ui then
		g_modalManager.hide(controller.ui)
		controller.ui:destroy()

		controller.ui = nil
	end

	controller.dataUI = {
		name = name
	}
	controller.ui = g_ui.loadUI("/game_rewardwall/" .. name, g_ui.getRootWidget())

	if not controller.ui then
		g_logger.error("[game_rewardwall] failed to load " .. name .. ".otui")

		return
	end

	controller.ui:hide()
	setupRewardWallUi()
end

function onHoverBonusChange(widget, hovered)
	rewardWallController:onhoverBonus({
		target = widget,
		value = hovered
	})
end

function onHoverStatusPlayerChange(widget, hovered)
	rewardWallController:onhoverStatusPlayer({
		target = widget,
		value = hovered
	})
end

function onHoverRewardTypeChange(widget, hovered)
	rewardWallController:onhoverRewardType({
		target = widget,
		value = hovered
	})
end

function onHoverStatusRewardChange(widget, hovered)
	rewardWallController:onhoverStatusReward({
		target = widget,
		value = hovered
	})
end

function onClickPickReward(widget)
	rewardWallController:onClickDisplayWindowsPickRewardWindow({
		target = widget
	})
end

function rewardWallController:onInit()
	g_ui.importStyle("styles/style.otui")
	g_ui.importStyle("styles/style1533.otui")
	rewardWallController:loadUI(UI_CLASSIC)

	if not rewardWallController.ui then
		g_logger.error("[game_rewardwall] failed to load game_rewardwall.otui")

		return
	end

	rewardWallController.ui:hide()
	rewardWallController:registerEvents(g_game, {
		onOpenRewardWall = onOpenRewardWall,
		onCloseRewardWall = onCloseRewardWall,
		onDailyReward = onDailyReward,
		onRewardHistory = onRewardHistory,
		onRestingAreaState = onRestingAreaState,
		onDailyRewardCollectionState = onDailyRewardCollectionState,
		onResourceBalance = onRewardWallResourceBalance
	})
	setupRewardWallUi()
end

function rewardWallController:onTerminate()
	stopDailyRewardSlotTimer()
	stopRestingAreaTimer()

	generalBox, windowsPickWindow, ButtonRewardWall = destroyWindows({
		generalBox,
		windowsPickWindow,
		ButtonRewardWall
	})
end

function rewardWallController:onGameStart()
	if g_game.getClientVersion() > 1140 then
		loadRewardWallUi(is1533() and UI_1533 or UI_CLASSIC)
		applyVersionLayout()

		if not ButtonRewardWall then
			ButtonRewardWall = modules.game_mainpanel.addToggleButton("rewardWall", tr("Open Reward Wall"), "/images/options/button_reward_wall", toggle, false, 21)
		end
	else
		scheduleEvent(function()
			g_modules.getModule("game_rewardwall"):unload()
		end, 100)
	end
end

function rewardWallController:onGameEnd()
	stopDailyRewardSlotTimer()
	stopRestingAreaTimer()

	if claimCloseResetEvent then
		removeEvent(claimCloseResetEvent)

		claimCloseResetEvent = nil
	end

	claimPending = false

	if rewardWallController.ui:isVisible() then
		g_modalManager.hide(rewardWallController.ui)
		rewardWallController.ui:hide()

		if ButtonRewardWall then
			ButtonRewardWall:setOn(false)
		end
	end

	generalBox, windowsPickWindow = destroyWindows({
		generalBox,
		windowsPickWindow
	})
end

function rewardWallController:onClickshowHistory()
	visibleHistory(not rewardWallController.ui.historyPanel:isVisible())
	g_game.requestOpenRewardHistory()
	rewardWallController.ui.footerPanel.historyButton:setText(rewardWallController.ui.historyPanel:isVisible() and "Back" or "History")
end

function rewardWallController:onClickToggle()
	toggle()
end

function rewardWallController:onClickSendStoreRewardWall()
	modules.game_store.openPremiumBoost()
end

local STORE_INSTANT_REWARD_ACCESS = 2

function rewardWallController:onClickGetInstantRewardAccess()
	if ButtonRewardWall then
		ButtonRewardWall:setOn(false)
	end

	hide(true)

	if modules.game_store and modules.game_store.openUsefulThings then
		modules.game_store.openUsefulThings(STORE_INSTANT_REWARD_ACCESS)
	end
end

function rewardWallController:onClickDisplayWindowsPickRewardWindow(event)
	if event.target.rewardVisualMode ~= REWARD_BUTTON_MODE.COLLECTABLE or claimPending then
		return
	end

	if event.target.bundleType == bundleType.ITEMS then
		local isPremium = g_game.getLocalPlayer():isPremium()
		local itemsToSelect = event.target.itemsToSelect

		if not windowsPickWindow then
			if type(itemsToSelect) == "table" then
				itemsToSelect = isPremium and itemsToSelect[1] or itemsToSelect[2]
			else
				itemsToSelect = itemsToSelect or 1
			end

			windowsPickWindow = g_ui.displayUI("styles/pickreward")

			windowsPickWindow:show()
			g_modalManager.show(windowsPickWindow)
			windowsPickWindow:getChildById("capacity"):setText("Free capacity: " .. g_game:getLocalPlayer():getFreeCapacity() .. " oz")

			local text = string.format("You have selected [color=#D33C3C]0[/color] of %d reward items", itemsToSelect)

			windowsPickWindow:getChildById("rewardLabel"):parseColoredText(text, "#c0c0c0")

			for i, item in pairs(event.target.rewardItem) do
				local getItem = g_ui.createWidget("ItemReward", windowsPickWindow:getChildById("rewardList"))

				getItem:getChildById("item"):setItemId(item.itemId)
				getItem:getChildById("title"):setText(item.name)
				getItem:setBackgroundColor(i % 2 == 0 and COLORS.BASE_1 or COLORS.BASE_2)

				getItem.totalWeight = item.weight or 1
				getItem.itemsToSelect = itemsToSelect
			end

			actualUsed = {}

			scheduleEvent(function()
				refreshAllPickRewardRows()
			end, 1)
			hide()
		else
			windowsPickWindow:show()
			g_modalManager.show(windowsPickWindow)
		end
	elseif event.target.bundleType == bundleType.XPBOOST or event.target.bundleType == bundleType.PREY or event.target.bundleType == bundleType.FIXED then
		if not beginClaim() then
			return
		end

		hide()

		actualUsed = {}

		claimInstantDailyReward()
	end
end

function rewardWallController:onhoverBonus(event)
	if not event.value then
		clearInfoPanel()

		return
	end

	local id = event.target:getId()
	local index = tonumber(id:match("%d+"))
	local bonus = bonuses[index]

	if not bonus then
		showInfoPanelDescription("Unknown bonus.", false)

		return
	end

	local isPremium = g_game.getLocalPlayer():isPremium()
	local bonusText = string.format("Allow [color=#909090]%s[/color]%s\nThis bonus is active because you are [color=%s]Premium[/color] and reached a reward streak of at least [color=#44AD25]%d[/color].%s", bonus.name, isPremium and "" or "[color=#ff0000](Locked)[/color]", isPremium and "#44AD25" or "#ff0000", bonus.id, isPremium and ("\n\nActive bonuses: [color=#909090]%s[/color]."):format(getBonusStrings(bonuses)) or "")

	showInfoPanelDescription(bonusText, true)
end

function rewardWallController:onhoverStatusPlayer(event)
	if not event.value then
		clearInfoPanel()

		return
	end

	local playerStatus = {
		rewardStreakIcon = "This explains the reward streak system. You need to claim your daily reward between regular server saves to maintain your streak. At a streak of 2+, your character gets resting area bonuses. Free accounts can reach a maximum bonus at streak level 3, while premium players can reach higher levels. Characters on the same account share the streak.",
		timeLeft = "This is an urgent notification to claim your daily reward within one minute (before the next server save) to raise your reward streak by 1. It mentions that 3 Daily Reward Jokers will be used to prevent resetting your streak. It also encourages raising your streak to benefit from bonuses in resting areas.",
		restingAreaGold = "This explains how Daily Reward Jokers work. They help you maintain your streak on days when you can't claim your daily reward. Each character receives one Daily Reward Joker on the first day of each month. The message recommends collecting rewards daily to stay safe."
	}
	local DEFAULT_MESSAGE = "Unknown bonus."
	local id = event.target:getId()
	local info = playerStatus[id]

	if usesNewLayout() then
		-- same texts as the info icons of the 15.33 window
		local restingPanel = rewardWallController.ui.restingAreaPanel
		local newLayoutStatus = {
			rewardStreakIcon = restingPanel.streakBonusPanel.streakBonusHelp:getTooltip(),
			timeLeft = restingPanel.restingAreaInfo.timeLeftHelp:getTooltip(),
			restingAreaGold = TEXT_1533.jokers
		}

		info = newLayoutStatus[id] or info
	end

	showInfoPanelDescription(info or DEFAULT_MESSAGE, true)
end

function rewardWallController:onhoverRewardType(event)
	if not event.value then
		clearInfoPanel()

		return
	end

	local entries = event.target.rewardEntries

	if entries then
		showInfoPanelRewardSplit("Reward for Free Accounts:\n" .. formatRewardEntries(entries.free), "Reward for Premium Accounts:\n" .. formatRewardEntries(entries.premium))

		return
	end

	local itemsToSelect = event.target.itemsToSelect or {
		1,
		1
	}
	local freeAmount = 0
	local premiumAmount = 0

	if type(itemsToSelect) == "table" then
		freeAmount = itemsToSelect[2] or 0
		premiumAmount = itemsToSelect[1] or 0
	else
		freeAmount = itemsToSelect
		premiumAmount = itemsToSelect
	end

	local rewardType = event.target.bundleType
	local rewardTexts = {}

	if rewardType == bundleType.ITEMS then
		local sampleNames = {}
		if event.target.rewardItem and #event.target.rewardItem > 0 then
			for i = 1, math.min(3, #event.target.rewardItem) do
				local it = event.target.rewardItem[i]
				if it and it.name and it.name ~= "" then
					table.insert(sampleNames, it.name)
				end
			end
		end

		local sampleText = ""
		if #sampleNames > 0 then
			sampleText = " Among\nother items it contains: " .. table.concat(sampleNames, ", ")
		end

		rewardTexts = {
			free = string.format("Reward for Free Accounts:\nPick %d %s from the list.%s", freeAmount, freeAmount == 1 and "item" or "items", sampleText),
			premium = string.format("Reward for Premium Accounts:\nPick %d %s from the list.%s", premiumAmount, premiumAmount == 1 and "item" or "items", sampleText)
		}
	elseif rewardType == bundleType.PREY then
		local itemName = event.target.itemName or "Prey Wildcard"

		rewardTexts = {
			free = string.format("Reward for Free Accounts:\n %dx %s", freeAmount, itemName),
			premium = string.format("Reward for Premium Accounts:\n %dx %s", premiumAmount, itemName)
		}
	elseif rewardType == bundleType.XPBOOST then
		rewardTexts = {
			free = string.format("Reward for Free Accounts:\n %d minutes 50%% XP Boost", freeAmount),
			premium = string.format("Reward for Premium Accounts:\n %d minutes 50%% XP Boost", premiumAmount)
		}
	else
		print("WARNING: Unknown rewardType:", rewardType)

		return
	end

	showInfoPanelRewardSplit(rewardTexts.free, rewardTexts.premium)
end

function rewardWallController:onhoverStatusReward(event)
	local statusReward = {
		[STATUS.COLLECTED] = "You have already collected this daily reward.\nThe daily rewards follow a specific cycle where each day you claim it, you get another reward. The cycle repeats after 7 claimed rewards. You will be able to claim this daily reward again as soon as you have reached this postion in the next cycle.",
		[STATUS.ACTIVE] = "The daily reward can be claimed now.\nIf you claim this reward now, it will cost you one Instant Reward Access.\nGet your daily reward for free by visiting a reward shrine.\nYou did not claim your daily reward in time.\nToo bad, you do not have enough Daily Reward Jokers.",
		[STATUS.LOCKED] = "This daily reward is still locked.\nFirst collect the previous daily rewards of this cycle."
	}

	if not event.value then
		clearInfoPanel()

		return
	end

	local status = event.target.status

	showInfoPanelDescription(statusReward[status] or "Unknown reward status.", false)
end

function onClickBtnOk()
	g_logger.info(string.format("[rewardwall] OK: selected=%d claimPending=%s bonusShrine=%s", table.size(actualUsed), tostring(claimPending), tostring(bonusShrine)))

	if table.empty(actualUsed) or claimPending then
		g_logger.info("[rewardwall] OK aborted: nothing selected or a previous claim is in progress")

		return
	end

	if not beginClaim() then
		return
	end

	claimInstantDailyReward()
end

function destroyPickReward(bool)
	windowsPickWindow = destroyWindows(windowsPickWindow)

	if bool then
		rewardWallController.ui:show()
		g_modalManager.show(rewardWallController.ui)
	end
end

local REWARD_ITEM_WEIGHT_SCALE = 100

local function formatRewardItemWeight(weightUnits)
	return string.format("%.2f oz", (weightUnits or 0) / REWARD_ITEM_WEIGHT_SCALE)
end

local function getPickRewardMaxAllowed(row, itemId)
	local thisPanelUsed = actualUsed[itemId] or 0
	local alreadyUsed = 0

	for _, count in pairs(actualUsed) do
		alreadyUsed = alreadyUsed + (count or 0)
	end

	return math.max(0, row.itemsToSelect - (alreadyUsed - thisPanelUsed))
end

local function resolvePickRewardRow(widget)
	local row = widget

	while row do
		if row.itemsToSelect then
			return row
		end

		row = row:getParent()
	end

	return nil
end

local function updatePickRewardQuantityUi(row)
	if not row or not row.itemsToSelect or not windowsPickWindow then
		return
	end

	local itemWidget = row:recursiveGetChildById("item")
	local quantity = row:recursiveGetChildById("quantity")

	if not itemWidget or not quantity then
		return
	end

	local itemId = itemWidget:getItemId()
	local maxAllowed = getPickRewardMaxAllowed(row, itemId)
	local value = math.min(actualUsed[itemId] or 0, maxAllowed)

	actualUsed[itemId] = value

	local numberValue = quantity:recursiveGetChildById("numberValue")
	local btnMin = quantity:getChildById("btnMin")
	local btnDec = quantity:getChildById("btnDec")
	local btnInc = quantity:getChildById("btnInc")
	local btnMax = quantity:getChildById("btnMax")

	if not numberValue or not btnMin or not btnDec or not btnInc or not btnMax then
		return
	end

	numberValue:setText(tostring(value))
	btnMin:setEnabled(value > 0)
	btnDec:setEnabled(value > 0)
	btnInc:setEnabled(value < maxAllowed)
	btnMax:setEnabled(value < maxAllowed)

	local weightLabel = row:recursiveGetChildById("weight")

	if weightLabel then
		weightLabel:setText(formatRewardItemWeight(value * row.totalWeight))
	end
end

local function refreshPickRewardSummary(referenceRow)
	if not windowsPickWindow or not referenceRow or not referenceRow.itemsToSelect then
		return
	end

	local alreadyUsed = 0

	for _, count in pairs(actualUsed) do
		alreadyUsed = alreadyUsed + (count or 0)
	end

	local color = alreadyUsed == 0 and "#D33C3C" or "#00FF00"

	windowsPickWindow:getChildById("btnOk"):setEnabled(alreadyUsed > 0)

	local text = string.format("You have selected [color=%s]%d[/color] of %d reward items", color, alreadyUsed, referenceRow.itemsToSelect)

	windowsPickWindow:getChildById("rewardLabel"):parseColoredText(text, "#c0c0c0")

	local totalWeight = 0

	for _, widget in pairs(windowsPickWindow:getChildById("rewardList"):getChildren()) do
		if widget.itemsToSelect and widget.totalWeight then
			local itemWidget = widget:recursiveGetChildById("item")

			if itemWidget then
				local id = itemWidget:getItemId()

				totalWeight = totalWeight + (actualUsed[id] or 0) * widget.totalWeight
			end
		end
	end

	local weightLabel = windowsPickWindow:getChildById("weight")

	weightLabel:setText(string.format("Total weight: %s", formatRewardItemWeight(totalWeight)))
	weightLabel:resizeToText()
end

function refreshAllPickRewardRows()
	if not windowsPickWindow then
		return
	end

	local rewardList = windowsPickWindow:getChildById("rewardList")
	local referenceRow

	for _, row in pairs(rewardList:getChildren()) do
		if row.itemsToSelect and row:recursiveGetChildById("quantity") then
			referenceRow = row

			updatePickRewardQuantityUi(row)
		end
	end

	if referenceRow then
		refreshPickRewardSummary(referenceRow)
	end
end

function onPickRewardQtyClick(widget, action)
	local row = resolvePickRewardRow(widget)

	if not row then
		return
	end

	local itemWidget = row:recursiveGetChildById("item")

	if not itemWidget then
		return
	end

	local itemId = itemWidget:getItemId()
	local value = actualUsed[itemId] or 0
	local maxAllowed = getPickRewardMaxAllowed(row, itemId)

	if action == "min" then
		value = 0
	elseif action == "dec" then
		value = math.max(0, value - 1)
	elseif action == "inc" then
		value = math.min(maxAllowed, value + 1)
	elseif action == "max" then
		value = maxAllowed
	end

	actualUsed[itemId] = value

	refreshAllPickRewardRows()
end

function displayGeneralBox3(title, message, buttons, onEnterCallback, onEscapeCallback)
	if generalBox then
		generalBox = destroyWindows(generalBox)
	end

	generalBox = g_ui.createWidget("MessageBoxWindow", rootWidget)

	if not generalBox then
		return nil
	end

	local titleWidget = generalBox:getChildById("title")

	if titleWidget then
		titleWidget:setText(title)
	end

	local holder = generalBox:getChildById("holder")

	if holder and buttons then
		for i = 1, #buttons do
			local button = g_ui.createWidget("Button", holder)
			local buttonId = buttons[i].text:lower():gsub(" ", "_")

			button:setId(buttonId)
			button:setText(buttons[i].text)
			button:setWidth(math.max(86, 10 + string.len(buttons[i].text) * 8))
			button:setHeight(20)
			button:setMarginTop(-5)

			if i == 1 then
				button:addAnchor(AnchorTop, "parent", AnchorTop)
				button:addAnchor(AnchorRight, "parent", AnchorRight)
			else
				button:addAnchor(AnchorTop, "parent", AnchorTop)
				button:addAnchor(AnchorRight, "prev", AnchorLeft)
				button:setMarginRight(5)
			end

			button.onClick = buttons[i].callback
		end
	end

	if onEnterCallback then
		generalBox.onEnter = onEnterCallback
	end

	if onEscapeCallback then
		generalBox.onEscape = onEscapeCallback
	end

	local content = generalBox:getChildById("content")

	if not content then
		generalBox = destroyWindows(generalBox)

		return nil
	end

	content:setText(message)
	content:resizeToText()

	local contentWidth = content:getWidth() + 32
	local contentHeight = content:getHeight() + 42 + (holder and holder:getHeight() or 0)

	generalBox:setWidth(math.min(916, math.max(300, contentWidth)))
	generalBox:setHeight(math.min(616, math.max(119, contentHeight)))

	function generalBox:setContent(newMessage)
		local content = generalBox:getChildById("content")

		if not content then
			return
		end

		content:setText(newMessage)
		content:resizeToText()
		content:setTextWrap(false)
		content:setTextAutoResize(false)

		local holder = generalBox:getChildById("holder")

		if not holder then
			return
		end

		local contentWidth = content:getWidth() + 32
		local contentHeight = content:getHeight() + 50 + holder:getHeight()

		generalBox:setWidth(math.min(736, math.max(300, contentWidth)))
		generalBox:setHeight(math.min(300, math.max(89, contentHeight)))
	end

	function generalBox:setTitle(newTitle)
		local titleWidget = generalBox:getChildById("title")

		if not titleWidget then
			return
		end

		titleWidget:setText(newTitle)
	end

	function generalBox:modifyButton(buttonId, newText, newCallback)
		local holder = generalBox:getChildById("holder")

		if not holder then
			return nil
		end

		local button = holder:getChildById(buttonId)

		if button then
			if newText then
				button:setText(newText)
				button:setWidth(math.max(86, 10 + string.len(newText) * 8))
			end

			if newCallback then
				disconnect(button, {
					onClick = button.onClick
				})
				connect(button, {
					onClick = newCallback
				})

				button.onClick = newCallback
			end
		end

		return button
	end

	generalBox:show()
	g_modalManager.show(generalBox)

	return generalBox
end

function managerMessageBoxWindow(id)
	local config = BOX_CONFIGS[id]

	if not config then
		return
	end

	local function cancelCallback()
		generalBox, windowsPickWindow = destroyWindows({
			generalBox,
			windowsPickWindow
		})

		rewardWallController.ui:show()
		g_modalManager.show(rewardWallController.ui)
	end

	local okCallback = config.okCallback or function()
		generalBox, windowsPickWindow = destroyWindows({
			generalBox,
			windowsPickWindow
		})

		rewardWallController.ui:show()
		g_modalManager.show(rewardWallController.ui)
	end
	local standardButtons = {
		{
			text = "cancel",
			callback = cancelCallback
		},
		{
			text = "ok",
			callback = okCallback
		}
	}

	generalBox = displayGeneralBox3(config.title, config.content, standardButtons)

	g_modalManager.hide(rewardWallController.ui)
	rewardWallController.ui:hide()

	if windowsPickWindow then
		windowsPickWindow = destroyWindows(windowsPickWindow)
	end
end
