-- chunkname: @/client_options/cip_import_mappings.lua

CipImportMappings = {}
CipImportMappings.OPTION_KEYS = {
	-- Interface
	mouseHighlightTarget = {
		type = "bool",
		key = "enableHighlightMouseTarget"
	},
	mouseSystemCursor = {
		type = "bool",
		key = "useNativeMouseCursor"
	},
	mouseAnimatedCursor = {
		type = "bool",
		key = "showAnimatedMouseCursor"
	},
	mouseBigCursor = {
		type = "bool",
		key = "showBigMouseCursor"
	},
	cooldownBarEnabled = {
		type = "bool",
		key = "showSpellGroupCooldowns"
	},
	linkCopyWarningEnabled = {
		type = "bool",
		key = "showLinkCopyWarning"
	},
	-- 0 None / 1 Frames / 2 Corners, in the official combo's own order.
	colorizeLootStyle = {
		type = "enum",
		key = "framesRarity",
		values = {
			[0] = "none",
			[1] = "frames",
			[2] = "corners"
		}
	},
	showExpireInInventory = {
		type = "bool",
		key = "showExpiryInInvetory"
	},
	showExpireInContainers = {
		type = "bool",
		key = "showExpiryInContainers"
	},
	showExpireWhenUnused = {
		type = "bool",
		key = "showExpiryOnUnusedItems"
	},

	-- HUD
	playerHudEnabled = {
		type = "bool",
		key = "showHudForOwnCharacter"
	},
	playerHudShowBars = {
		type = "bool",
		key = "showOwnBars"
	},
	playerShowName = {
		type = "bool",
		key = "showOwnName"
	},
	playerShowHealth = {
		type = "bool",
		key = "showOwnHealth"
	},
	playerShowMana = {
		type = "bool",
		key = "showOwnMana"
	},
	playerShowHarmonySerene = {
		type = "bool",
		key = "showOwnHarmony"
	},
	-- One official flag, two checkboxes here: left means beside the health arc.
	playerHudShowHarmonyLeft = {
		type = "bool",
		key = "harmonyNextToHealth",
		also = {
			invert = true,
			key = "harmonyNextToMana"
		}
	},
	playerShowMarks = {
		type = "bool",
		key = "showOwnMarks"
	},
	playerHudShowArcs = {
		type = "bool",
		key = "showArcs"
	},
	playerHudArcDistance = {
		type = "percent",
		key = "showArcsDistanceScroll"
	},
	playerHudArcOpacity = {
		type = "percent",
		key = "showArcsOpacityScroll"
	},
	creatureHudEnabled = {
		type = "bool",
		key = "showHudForOtherCreatures"
	},
	creatureShowName = {
		type = "bool",
		key = "showOtherName"
	},
	creatureShowHealth = {
		type = "bool",
		key = "showOtherHealth"
	},
	creatureShowMarks = {
		type = "bool",
		key = "showOtherMarks"
	},
	-- Misspelled in the official file ("creatue"); it has to be matched verbatim.
	creatueShowNpcIcon = {
		type = "bool",
		key = "showOtherNpcIcons"
	},
	statusBarEnabled = {
		type = "bool",
		key = "showCustomisableStatusBars"
	},
	statusPanelEnabled = {
		type = "bool",
		key = "showStatusBars"
	},

	-- Console
	consoleShowInfoMessages = {
		type = "bool",
		key = "showInfoMessagesInConsole"
	},
	consoleShowEventMessages = {
		type = "bool",
		key = "showEventMessagesInConsole"
	},
	-- Labelled just "Show Status Messages" in the official dialog.
	consoleShowStatusMessagesOwn = {
		type = "bool",
		key = "showStatusMessagesInConsole"
	},
	consoleShowStatusMessagesOfOthers = {
		type = "bool",
		key = "showOthersStatusMessagesInConsole"
	},
	openNewPrivateMessagesInNewTab = {
		type = "bool",
		key = "openNewTabsWhenReceivingPrivateMessages"
	},
	consoleShowTimestamps = {
		type = "bool",
		key = "showTimestampsInConsole"
	},
	consoleShowTimestampsSeconds = {
		type = "bool",
		key = "showTimestampsSecondsInConsole"
	},
	consoleShowLevels = {
		type = "bool",
		key = "showLevelsInConsole"
	},

	-- Game Window
	gameWindowShowTextualEffects = {
		type = "bool",
		key = "showTextualEffects"
	},
	-- The game-window message toggle. It used to point at consoleMessages, which is the
	-- UI *sound* for console messages, so importing flipped the wrong setting.
	gameWindowShowMessages = {
		type = "bool",
		key = "showMessages"
	},
	gameWindowShowPrivateMessages = {
		type = "bool",
		key = "showPrivateMessages"
	},
	gameWindowShowPotionMessages = {
		type = "bool",
		key = "showPotionSoundEffects"
	},
	gameWindowShowOwnSpells = {
		type = "bool",
		key = "showSpells"
	},
	gameWindowShowOthersSpells = {
		type = "bool",
		key = "showSpellsOfOthers"
	},
	gameWindowShowHotkeyUsageMessages = {
		type = "bool",
		key = "showHotkeyUsageNotifications"
	},
	gameWindowShowLootMessages = {
		type = "bool",
		key = "showLootMessages"
	},
	gameWindowShowLootHighlighting = {
		type = "bool",
		key = "showLootHighlighting"
	},
	gameWindowShowBoostedCreatureMessages = {
		type = "bool",
		key = "showBoostedCreature"
	},
	gameWindowShowOfflineTrainingMessages = {
		type = "bool",
		key = "showOfflineTrainingProgress"
	},
	gameWindowShowStoreMessages = {
		type = "bool",
		key = "showStoreNotificationsInCombat"
	},
	combatShowFrames = {
		type = "bool",
		key = "showCombatFrames"
	},
	combatShowPvpFrames = {
		type = "bool",
		key = "showPvPFrames"
	},
	gameWindowShowAttackAnimation = {
		type = "bool",
		key = "showMeleeAttackAnimation"
	},
	gameWindowShowInfoBanner = {
		type = "bool",
		key = "showInfoBanner"
	},

	-- Action Bars
	actionBarsShowBottom = {
		type = "bool",
		key = "allActionBar13"
	},
	actionBarsShowLeft = {
		type = "bool",
		key = "allActionBar46"
	},
	actionBarsShowRight = {
		type = "bool",
		key = "allActionBar79"
	},
	actionBarShowBottom1 = {
		type = "bool",
		key = "actionBarShowBottom1"
	},
	actionBarShowBottom2 = {
		type = "bool",
		key = "actionBarShowBottom2"
	},
	actionBarShowBottom3 = {
		type = "bool",
		key = "actionBarShowBottom3"
	},
	actionBarShowLeft1 = {
		type = "bool",
		key = "actionBarShowLeft1"
	},
	actionBarShowLeft2 = {
		type = "bool",
		key = "actionBarShowLeft2"
	},
	actionBarShowLeft3 = {
		type = "bool",
		key = "actionBarShowLeft3"
	},
	actionBarShowRight1 = {
		type = "bool",
		key = "actionBarShowRight1"
	},
	actionBarShowRight2 = {
		type = "bool",
		key = "actionBarShowRight2"
	},
	actionBarShowRight3 = {
		type = "bool",
		key = "actionBarShowRight3"
	},
	actionBarBottomLocked = {
		type = "bool",
		key = "actionBarBottomLocked"
	},
	actionBarLeftLocked = {
		type = "bool",
		key = "actionBarLeftLocked"
	},
	actionBarRightLocked = {
		type = "bool",
		key = "actionBarRightLocked"
	},
	actionButtonShowHotkey = {
		type = "bool",
		key = "showAssignedHKButton"
	},
	actionButtonShowAmount = {
		type = "bool",
		key = "showHKObjectsBars"
	},
	actionButtonShowSpellParameters = {
		type = "bool",
		key = "showSpellParameters"
	},
	actionButtonShowGraphicalCooldown = {
		type = "bool",
		key = "graphicalCooldown"
	},
	-- Was pointed at "showTooltips", which is not an option name, so it did nothing.
	actionButtonShowCooldownNumbers = {
		type = "bool",
		key = "cooldownSecond"
	},
	actionButtonAllowTooltip = {
		type = "bool",
		key = "actionTooltip"
	},
	actionButtonAutoInsertSpells = {
		type = "bool",
		key = "autoInsertNewSpells"
	},

	-- Controls
	-- Official model order: classic, legacy (our "regular"), left smart-click.
	controlSchemeIndex = {
		type = "enum",
		key = "classicControl",
		values = {
			[0] = "classic",
			[1] = "regular",
			[2] = "leftSmart"
		}
	},
	-- Official model order: right, shift+right, left.
	lootSchemeIndex = {
		type = "enum",
		key = "lootSide",
		values = {
			[0] = "right",
			[1] = "shiftRight",
			[2] = "left"
		}
	},
	keyboardDelayUseDefault = {
		type = "bool",
		key = "useDefaultHotkeyDelay"
	},
	keyboardDelayMs = {
		type = "number",
		key = "hotkeyDelay"
	},
	rotateWithCtrl = {
		type = "bool",
		key = "rotateHoldCtrl"
	},
	rotateWithShift = {
		type = "bool",
		key = "rotateHoldShift"
	},
	rotateWithAlt = {
		type = "bool",
		key = "rotateHoldAlt"
	},
	alwaysTurnTowardsMoveDirection = {
		type = "bool",
		key = "alwaysTurnTowardsMovement"
	},
	-- Inverted: the getter is cmp/sete and the setter xors, so the stored key holds
	-- the opposite of the "Press CTRL to Drag Complete Stacks" checkbox.
	dragAndDropDefaultActionIsMoveAll = {
		invert = true,
		type = "bool",
		key = "moveStack"
	},

	-- Gameplay and Misc
	inspectPlayerAllowAllEnabled = {
		type = "bool",
		key = "allowInspect"
	},
	-- Inverted the same way as the drag option above, confirmed in the accessors.
	autoChaseEnabled = {
		invert = true,
		type = "bool",
		key = "autoChaseOff"
	},
	quickLootAllCorpsesInAreaEnabled = {
		type = "bool",
		key = "quickLootCorpses"
	},
	storeAskBeforeBuyingProducts = {
		type = "bool",
		key = "askBeforeBuying"
	},
	stashAskBeforeStowContainerContent = {
		type = "bool",
		key = "askBeforeStowing"
	},
	containerSortRecursiveShowWarningAgain = {
		type = "bool",
		key = "askBeforeSorting"
	},
	containerMoveToManagedContainerRecursiveShowWarningAgain = {
		type = "bool",
		key = "askBeforeMoving"
	},
	sessionRemainLoggedIn = {
		type = "bool",
		key = "stayLoggedIn"
	},
	-- The last three have no control on the Misc page (nothing here can honour them), but
	-- they are still imported so exporting again does not silently reset them.
	connectionStabilityOptimizationEnabled = {
		type = "bool",
		key = "optimiseConnection"
	},
	quickLogin = {
		type = "bool",
		key = "quickLogin"
	},
	useFreetypeRenderer = {
		type = "bool",
		key = "alternateFontRenderer"
	},
	showFpsLagIndicator = {
		type = "bool",
		key = "showFps"
	},

	-- Graphics and Effects
	-- Capital S. The old entry spelled it vsyncEnabled and therefore never matched.
	vSyncEnabled = {
		type = "bool",
		key = "vsync"
	},
	frameRateLimit = {
		type = "number",
		key = "backgroundFrameRate",
		requires = "frameRateLimitEnabled"
	},
	frameRateLimitEnabled = {
		invert = true,
		type = "bool",
		key = "noFrameRateLimit"
	},
	antialiasingMode = {
		type = "number",
		key = "antialiasingMode"
	},
	gameWindowScaleOnlyByEvenMultiples = {
		type = "bool",
		key = "dontStretchShrink"
	},
	lightEffectsEnabled = {
		type = "bool",
		key = "enableLights"
	},
	lightAmbientLevel = {
		type = "percent",
		key = "ambientLight"
	},
	lightLevelSeparatorLevel = {
		type = "percent",
		key = "levelSeparator"
	},
	ownEffectsOpacity = {
		type = "percent",
		key = "ownSpellEffectOpacity"
	},
	otherPlayersEffectsOpacity = {
		type = "percent",
		key = "othersPlayersEffectOpacity"
	},
	monsterEffectsOpacity = {
		type = "percent",
		key = "creatureSpellEffectsOpacity"
	},
	monsterBossAreaEffectsOpacity = {
		type = "percent",
		key = "bossAreaCreatureSpellEffectOpacity"
	},

	-- Screenshots
	-- Misspelled in the official file ("screnshots").
	screnshotsOnlyGameWindow = {
		type = "bool",
		key = "onlyCaptureGameWindow"
	},
	screenshotsUseBacklog = {
		type = "bool",
		key = "keepBacklog"
	},
	screenshotsAutoScreenshotsEnabled = {
		type = "bool",
		key = "enableAutoScreenshots"
	},
	screenshotsLevelUpEnabled = {
		type = "bool",
		key = "levelUp"
	},
	screenshotsSkillUpEnabled = {
		type = "bool",
		key = "skillUp"
	},
	screenshotsAchievementEnabled = {
		type = "bool",
		key = "achievement"
	},
	screenshotsBestiaryPartlyEnabled = {
		type = "bool",
		key = "bestiaryUnlocked"
	},
	screenshotsBestiaryFullEnabled = {
		type = "bool",
		key = "bestiaryCompleted"
	},
	screenshotsRewardChestEnabled = {
		type = "bool",
		key = "treasureFound"
	},
	screenshotsTrackedLootEnabled = {
		type = "bool",
		key = "valuableLoot"
	},
	screenshotsBossKillEnabled = {
		type = "bool",
		key = "bossDefeated"
	},
	screenshotsDeathPvEEnabled = {
		type = "bool",
		key = "deathPvE"
	},
	screenshotsDeathPvPEnabled = {
		type = "bool",
		key = "deathPvP"
	},
	screenshotsPlayerKillFullEnabled = {
		type = "bool",
		key = "playerKill"
	},
	screenshotsPlayerKillAssistEnabled = {
		type = "bool",
		key = "playerKillAssist"
	},
	screenshotsPvPAttackEnabled = {
		type = "bool",
		key = "playerAttacking"
	},
	screenshotsNewMaxDamageEnabled = {
		type = "bool",
		key = "highestDamage"
	},
	screenshotsNewMaxHealingEnabled = {
		type = "bool",
		key = "highestHealing"
	},
	screenshotsLowHitPointsEnabled = {
		type = "bool",
		key = "lowHealth"
	},
	screenshotsGiftOfLifeEnabled = {
		type = "bool",
		key = "giftOfLife"
	},

	-- Sound
	usedSoundDevice = {
		type = "string",
		key = "soundDevice"
	},
	soundMasterVolume = {
		type = "number",
		key = "masterVolume"
	},
	soundMasterVolumeOld = {
		type = "number",
		key = "masterVolumeOld"
	},
	soundMusicVolume = {
		type = "number",
		key = "musicVolume"
	},
	soundAnthemEnabled = {
		type = "bool",
		key = "anthem"
	},
	soundAmbienceVolume = {
		type = "number",
		key = "ambienceVolume"
	},
	soundItemsVolume = {
		type = "number",
		key = "itemVolume"
	},
	soundEatingEnabled = {
		type = "bool",
		key = "foodAndBeverages"
	},
	soundMoveItemEnabled = {
		type = "bool",
		key = "moveItem"
	},
	soundEventsVolume = {
		type = "number",
		key = "eventVolume"
	},

	-- Battle sounds
	soundBattleOwnVolume = {
		type = "number",
		key = "ownBattleVolume"
	},
	soundBattleOwnSpellsEnabled = {
		type = "bool",
		key = "ownSpells"
	},
	soundBattleOwnAttackSpellsEnabled = {
		type = "bool",
		key = "ownAttack"
	},
	soundBattleOwnHealingSpellsEnabled = {
		type = "bool",
		key = "ownHealing"
	},
	soundBattleOwnSupportSpellsEnabled = {
		type = "bool",
		key = "ownSupport"
	},
	soundBattleOwnWeaponsEnabled = {
		type = "bool",
		key = "ownWeapons"
	},
	soundBattleOthersVolume = {
		type = "number",
		key = "otherPlayersVolume"
	},
	soundBattleOthersSpellsEnabled = {
		type = "bool",
		key = "otherSpells"
	},
	soundBattleOthersAttackSpellsEnabled = {
		type = "bool",
		key = "otherAttack"
	},
	soundBattleOthersHealingSpellsEnabled = {
		type = "bool",
		key = "otherHealing"
	},
	soundBattleOthersSupportSpellsEnabled = {
		type = "bool",
		key = "otherSupport"
	},
	soundBattleOthersWeaponsEnabled = {
		type = "bool",
		key = "otherWeapons"
	},
	soundBattleCreaturesVolume = {
		type = "number",
		key = "creaturesVolume"
	},
	soundBattleCreaturesNoisesEnabled = {
		type = "bool",
		key = "creatureNoises"
	},
	soundBattleCreaturesDeathEnabled = {
		type = "bool",
		key = "creatureDeath"
	},
	soundBattleCreaturesAttacksEnabled = {
		type = "bool",
		key = "attackAndSpells"
	},

	-- UI sounds
	soundUiVolume = {
		type = "number",
		key = "uiVolume"
	},
	soundUiInteractionsEnabled = {
		type = "bool",
		key = "uiInteractions"
	},
	soundPartyEnabled = {
		type = "bool",
		key = "toggleParty"
	},
	soundVipEnabled = {
		type = "bool",
		key = "toggleVip"
	},
	ChatEnabled = {
		type = "bool",
		key = "consoleMessages"
	},
	PartyMessagesEnabled = {
		type = "bool",
		key = "party"
	},
	GuildMessagesEnabled = {
		type = "bool",
		key = "guild"
	},
	PrivateMessagesEnabled = {
		type = "bool",
		key = "privateMessages"
	},
	PrivateMessagesWithoutTabEnabled = {
		type = "bool",
		key = "privateMessagesLocalChat"
	},
	-- Misspelled in the official file ("Messagese"), and stored without the sound prefix.
	NpcMessageseEnabled = {
		type = "bool",
		key = "npcs"
	},
	GlobalMessagesEnabled = {
		type = "bool",
		key = "global"
	},
	TeamFinderMessagesEnabled = {
		type = "bool",
		key = "teamFinder"
	},
	RaidMessagesEnabled = {
		type = "bool",
		key = "raidAnnouncements"
	},
	SystemMessagesEnabled = {
		type = "bool",
		key = "systemAnnouncements"
	},
	-- Stored inverted and over half the range: the official float is 1 - 0.005 * percent,
	-- so the 0.75 it ships reads 50 on our slider.
	lightAttenuationCloudsIndoor = {
		invert = true,
		scale = 200,
		type = "percent",
		key = "cloudsLabel"
	}
}

-- Controls we express as one widget but the official client stores as several keys.
CipImportMappings.COMBINED_OPTIONS = {
	{
		-- "Mark Target Visually" is one combo there too, but it is persisted as the two
		-- booleans it sets. Note the misspelled "Traget" - that is the real key name.
		key = "markTargetVisually",
		sources = {
			"gameWindowShowTragetFrame",
			"gameWindowShowTargetHighlight"
		},
		resolve = function(values)
			local frame = values.gameWindowShowTragetFrame and true or false
			local highlight = values.gameWindowShowTargetHighlight and true or false

			if frame and highlight then
				return "frameAndHighlight"
			elseif frame then
				return "frameOnly"
			elseif highlight then
				return "highlightOnly"
			end

			return "none"
		end
	}
}
CipImportMappings.CONTROL_BUTTON_IDS = {
	compendiumDialog = "compendiumDialog",
	analyticsSelectorWidget = "analyticsSelectorWidget",
	questDialog = "questLogButton",
	bosstiaryDialog = "bosstiary",
	questTrackerWidget = "QuestLogTracker",
	bossslotsDialog = "bossSlot",
	manageShortcuts = "manageShortcuts",
	bosstiaryTrackerWidget = "bosstiarytrackerButton",
	unjustifiedPoinsWidget = "unjustifiedPointsButton",
	skillWheelDialog = "wheelButton",
	vipWidget = "vipListButton",
	partyWidget = "partyWidget",
	rewardWallDialog = "rewardWall",
	battleListWidget = "battleButton",
	taskboard = "taskBoard",
	skillsWidget = "skillsButton",
	weaponProficiency = "ProciencyButton",
	highscoresDialog = "highscoresButton",
	friendsDialog = "friendsDialog",
	exaltationForgeDialog = "forgeButton",
	imbuementTrackerWidget = "imbuementTrackerButton",
	bestiaryTrackerWidget = "trackerButton",
	cyclopediaDialog = "CyclopediaButton",
	preyDialog = "preyButton",
	spellListWidget = "spellListWidget",
	preyWidget = "preyButton"
}
CipImportMappings.USE_TYPE = {
	Use = "use",
	SelectUseTarget = "useWith",
	Equip = "equip",
	UseOnTarget = "useOnTarget",
	UseOnYourself = "useOnSelf"
}
CipImportMappings.USE_TYPE_TO_HOTKEY_ACTION = {
	Equip = HOTKEY_ACTION.EQUIP,
	Use = HOTKEY_ACTION.USE,
	UseOnYourself = HOTKEY_ACTION.USE_YOURSELF,
	UseOnTarget = HOTKEY_ACTION.USE_TARGET,
	SelectUseTarget = HOTKEY_ACTION.USE_CROSSHAIR
}
CipImportMappings.KEYBIND_ACTIONS = {
	AttackNextTarget = {
		"Battle List",
		"Attack Next Target"
	},
	Logout = {
		"Misc",
		"Logout"
	},
	NextChannel = {
		"Chat Channel",
		"Next Channel"
	},
	PreviousChannel = {
		"Chat Channel",
		"Previous Channel"
	},
	OpenChannelList = {
		"Chat Channel",
		"Open Channel List"
	},
	CloseCurrentChannel = {
		"Chat Channel",
		"Close Current Channel"
	},
	OpenHelpChannel = {
		"Chat Channel",
		"Open Help Channel"
	},
	ToggleBattlelist = {
		"Windows",
		"Show/hide battle list"
	},
	ShowQuestlog = {
		"Windows",
		"Show/hide quest Log"
	},
	ShowPrey = {
		"Dialogs",
		"Open Prey Dialog"
	},
	Bugreport = {
		"Dialogs",
		"Open Bug Report"
	},
	QuickLootAreaAtPlayer = {
		"Loot",
		"Quick Loot Nearby Corpses"
	},
	ChatModeTemporaryOn = {
		"Chat Mode",
		"Set to Chat On"
	},
	ToggleManualSortMode = {
		"Containers",
		"Toggle Manual Sort Mode"
	}
}
CipImportMappings.KEY_SEQUENCE_REPLACEMENTS = {
	Return = "Enter",
	Backtab = "BackTab"
}
CipImportMappings.PER_CHARACTER_FILES = {
	"wheelOfDestiny.json",
	"cyclopediaMapConfiguration.json",
	"xpanalyser.json",
	"impactanalyser.json",
	"damageinputanalyser.json",
	"gainandwaste.json",
	"huntingsessionanalyser.json",
	"itemtracking.json",
	"itemprices.json",
	"lootBlackWhitelist.json"
}
CipImportMappings.IGNORED_CHARACTER_FILES = {
	questtracking = true,
	aimattargetconfigurationstorage = true,
	statusBarData = true,
	outfitdialog = true,
	actionbars = true
}
CipImportMappings.SIDEBAR_SKIPPED_TYPES = {
	playerGuide = true,
	container = true
}
CipImportMappings.SIDEBAR_WIDGET_MAP = {
	battleList = {
		primaryInstance = 0,
		widgetId = "battleWindow"
	},
	skills = {
		widgetId = "skillWindow"
	},
	questTracker = {
		widgetId = "QuestLogTracker"
	},
	vip = {
		widgetId = "vipWindow"
	},
	vipList = {
		widgetId = "vipWindow"
	},
	partyList = {
		widgetId = "partyWindow"
	},
	unjustifiedPoints = {
		widgetId = "unjustifiedPointsWindow"
	},
	spellList = {
		widgetId = "spellListMiniWindow"
	},
	helperStats = {
		widgetId = "helperStatsWindow"
	},
	prey = {
		widgetId = "preyTracker"
	},
	imbuementTracker = {
		widgetId = "imbuementTracker"
	},
	bestiaryTracker = {
		widgetId = "BestiaryTrackerWindow"
	},
	bosstiaryTracker = {
		widgetId = "BosstiaryTrackerWindow"
	},
	analyticsSelector = {
		widgetId = "analyserMiniWindow"
	},
	lootAnalyser = {
		widgetId = "lootAnalyserMiniWindow"
	},
	supplyAnalyser = {
		widgetId = "supplyAnalyserMiniWindow"
	},
	impactAnalyser = {
		widgetId = "impactAnalyserMiniWindow"
	},
	damageInputAnalyser = {
		widgetId = "inputAnalyserMiniWindow"
	},
	huntingSessionAnalyser = {
		widgetId = "huntingAnalyserMiniWindow"
	},
	partyHuntAnalyser = {
		widgetId = "phAnalyserMiniWindow"
	},
	xpAnalyser = {
		widgetId = "xpAnalyserMiniWindow"
	}
}
CipImportMappings.SIDEBAR_WIDGET_OPTIONS_KEYS = {
	battleList = {
		section = "battleListsOptions",
		useInstance = true
	},
	skills = {
		section = "skillsWidgetOptions"
	},
	questTracker = {
		section = "questTrackerWidgetOptions"
	},
	vip = {
		section = "vipWidgetOptions"
	},
	partyList = {
		section = "partyWidgetOptions"
	},
	unjustifiedPoints = {
		section = "unjustifiedPointsOptions"
	},
	spellList = {
		section = "spellListWidgetOptions"
	},
	helperStats = {
		section = "helperStatsWidgetOptions"
	},
	prey = {
		section = "preyWidgetOptions"
	},
	imbuementTracker = {
		section = "imbuementTrackerWidgetOptions"
	},
	bestiaryTracker = {
		section = "bestiaryTrackerWidgetOptions"
	},
	bosstiaryTracker = {
		section = "bosstiaryTrackerWidgetOptions"
	},
	analyticsSelector = {
		section = "analyticsSelectorOptions"
	},
	lootAnalyser = {
		section = "lootAnalyserWidgetOptions"
	},
	supplyAnalyser = {
		section = "supplyAnalyserWidgetOptions"
	},
	impactAnalyser = {
		section = "impactAnalyserWidgetOptions"
	},
	damageInputAnalyser = {
		section = "damageInputAnalyserWidgetOptions"
	},
	huntingSessionAnalyser = {
		section = "huntingSessionAnalyserWidgetOptions"
	},
	partyHuntAnalyser = {
		section = "partyHuntAnalyserOptions"
	},
	xpAnalyser = {
		section = "xpAnalyserWidgetOptions"
	}
}

function CipImportMappings.sidebarParentIdForIndex(sidebarIndex)
	sidebarIndex = tonumber(sidebarIndex) or 0

	if sidebarIndex == 0 then
		return "gameRightPanel"
	elseif sidebarIndex == 1 then
		return "gameLeftPanel"
	elseif sidebarIndex == 2 then
		return "gameLeftExtraPanel"
	elseif sidebarIndex == 3 then
		return "gameRightExtraPanel"
	end

	return "gameRightPanel"
end

function CipImportMappings.resolveSidebarWidgetId(widgetType, instance)
	if CipImportMappings.SIDEBAR_SKIPPED_TYPES[widgetType] then
		return nil
	end

	local mapping = CipImportMappings.SIDEBAR_WIDGET_MAP[widgetType]

	if not mapping then
		return nil
	end

	if mapping.primaryInstance ~= nil then
		instance = instance or 0

		if instance ~= mapping.primaryInstance then
			return nil
		end
	end

	return mapping.widgetId
end

function CipImportMappings.widgetSettingsFromSidebarsOptions(sidebars, widgetType, instance)
	local optsKey = CipImportMappings.SIDEBAR_WIDGET_OPTIONS_KEYS[widgetType]

	if not optsKey then
		return {}
	end

	local section = sidebars[optsKey.section]

	if type(section) ~= "table" then
		return {}
	end

	local opts = section

	if optsKey.useInstance then
		opts = section[tostring(instance or 0)]
	end

	if type(opts) ~= "table" then
		return {}
	end

	local settings = {}

	if type(opts.contentHeight) == "number" and opts.contentHeight > 0 then
		settings.height = opts.contentHeight
	end

	if opts.contentMaximized == false then
		settings.minimized = true
	elseif opts.contentMaximized == true then
		settings.minimized = false
	end

	return settings
end

function CipImportMappings.convertSidebarsToCharMiniWindows(sidebars)
	if type(sidebars) ~= "table" then
		return nil
	end

	local manager = sidebars.sidebarWidgetsMangerOptions

	if type(manager) ~= "table" then
		return nil
	end

	local orderPerSidebar = manager.openWidgetsOrderPerSidebar

	if type(orderPerSidebar) ~= "table" then
		return nil
	end

	local result = {}

	for sidebarIndex, widgetList in ipairs(orderPerSidebar) do
		if type(widgetList) == "table" then
			local parentId = CipImportMappings.sidebarParentIdForIndex(sidebarIndex - 1)
			local slotIndex = 0

			for _, widget in ipairs(widgetList) do
				if type(widget) == "table" and type(widget.type) == "string" then
					local widgetType = widget.type
					local instance = widget.instance
					local widgetId = CipImportMappings.resolveSidebarWidgetId(widgetType, instance)

					if widgetId and not result[widgetId] then
						slotIndex = slotIndex + 1

						local settings = CipImportMappings.widgetSettingsFromSidebarsOptions(sidebars, widgetType, instance)

						settings.parentId = parentId
						settings.index = slotIndex
						settings.closed = false
						result[widgetId] = settings
					end
				end
			end
		end
	end

	if table.empty(result) then
		return nil
	end

	return result
end

function CipImportMappings.normalizeKeySequence(keysequence)
	if type(keysequence) ~= "string" or keysequence == "" then
		return nil
	end

	local key = CipImportMappings.KEY_SEQUENCE_REPLACEMENTS[keysequence] or keysequence

	return key
end

function CipImportMappings.isValidKeyCombo(key)
	if type(key) ~= "string" or key == "" then
		return false
	end

	key = CipImportMappings.normalizeKeySequence(key)

	if not key or key == "" then
		return false
	end

	if not retranslateKeyComboDesc then
		return true
	end

	local ok, translated = pcall(retranslateKeyComboDesc, key)

	return ok and translated ~= nil and translated ~= ""
end

function CipImportMappings.slotIdFor(barId, buttonIndex)
	barId = tonumber(barId)
	buttonIndex = tonumber(buttonIndex)

	if not barId or not buttonIndex or barId < 1 or barId > 9 or buttonIndex < 1 then
		return nil
	end

	if barId == 1 then
		return "slot" .. buttonIndex
	end

	return "bar" .. barId .. "_slot" .. buttonIndex
end

function CipImportMappings.parseTriggerActionButton(actionName)
	if type(actionName) ~= "string" then
		return nil, nil
	end

	local barId, buttonIndex = actionName:match("^TriggerActionButton_(%d+)%.(%d+)$")

	return barId, buttonIndex
end

function CipImportMappings.isValidItemId(itemId)
	if type(itemId) ~= "number" or itemId <= 0 then
		return false
	end

	if not g_things or not g_things.getThingType then
		return true
	end

	local thingType = g_things.getThingType(itemId, ThingCategoryItem)

	return thingType ~= nil
end

function CipImportMappings.convertActionSettingToSlot(setting)
	if type(setting) ~= "table" then
		return nil
	end

	if setting.chatText and setting.chatText ~= "" then
		local text = setting.chatText
		local words = text:lower():gsub("^%s+", ""):gsub("%s+$", "")

		if Spells and Spells.getSpellByWords and Spells.getSpellByWords(words) then
			local slot = {
				words = words
			}

			if setting.sendAutomatically then
				slot.autoSend = true
			end

			return slot
		end

		local slot = {
			text = text
		}

		if setting.sendAutomatically then
			slot.autoSend = true
		end

		return slot
	end

	if setting.useObject then
		if not CipImportMappings.isValidItemId(setting.useObject) then
			return nil
		end

		local slot = {
			itemId = setting.useObject,
			useType = CipImportMappings.USE_TYPE[setting.useType] or "use"
		}

		if type(setting.upgradeTier) == "number" and setting.upgradeTier > 0 then
			slot.getTier = setting.upgradeTier
		end

		if setting.useEquipSmartMode then
			slot.smartMode = true
		end

		return slot
	end

	return nil
end

function CipImportMappings.convertActionSettingToHotkey(setting)
	if type(setting) ~= "table" then
		return nil, nil
	end

	if setting.chatText and setting.chatText ~= "" then
		local action = setting.sendAutomatically and HOTKEY_ACTION.TEXT_AUTO or HOTKEY_ACTION.TEXT

		return action, {
			text = setting.chatText
		}
	end

	if setting.useObject then
		if not CipImportMappings.isValidItemId(setting.useObject) then
			return nil, nil
		end

		local action = CipImportMappings.USE_TYPE_TO_HOTKEY_ACTION[setting.useType] or HOTKEY_ACTION.USE

		return action, {
			itemId = setting.useObject
		}
	end

	if setting.action then
		local mapping = CipImportMappings.KEYBIND_ACTIONS[setting.action]

		if mapping then
			return "keybind", mapping
		end
	end

	return nil, nil
end

CipImportMappings.BRIDGE_CHARACTER_FILES = {
	"questtracking.json",
	"outfitdialog.json"
}
CipImportMappings.OTCLIENT_PRESERVED_SETTINGS = {
	"game_helper_data.json",
	"outfit.json",
	"questtracking.json",
	"npc_modal.json"
}

function CipImportMappings.convertQuestTrackingToOtClient(cipData, charNameLower)
	if type(cipData) ~= "table" then
		return nil
	end

	local result = {}

	if type(cipData.options) == "table" then
		if cipData.options.autoTrackNewQuests ~= nil then
			result.autoTrackNewQuests = cipData.options.autoTrackNewQuests
		end

		if cipData.options.autoUntrackCompletedQuests ~= nil then
			result.autoUntrackCompleted = cipData.options.autoUntrackCompletedQuests
		end
	end

	if charNameLower and charNameLower ~= "" and type(cipData.trackedQuests) == "table" then
		local tracked = {}

		for _, entry in ipairs(cipData.trackedQuests) do
			if type(entry) == "table" then
				local missionId = entry.missionId or entry.mission or entry.id
				local questId = entry.questId or entry.quest or entry.questLineId
				local missionName = entry.missionName or entry.name or entry.title or ""
				local missionDesc = entry.missionDescription or entry.description or missionName

				if missionId then
					table.insert(tracked, {
						tonumber(missionId),
						tostring(missionName),
						tostring(missionDesc),
						questId and tonumber(questId) or nil
					})
				end
			end
		end

		if #tracked > 0 then
			result[charNameLower] = tracked
		end
	end

	if table.empty(result) then
		return nil
	end

	return result
end

function CipImportMappings.convertOutfitDialogToOtClient(cipData)
	if type(cipData) ~= "table" then
		return nil
	end

	local presets = cipData.customiseCharacterPresets

	if type(presets) ~= "table" or #presets == 0 then
		return nil
	end

	local convertedPresets = {}

	for index, preset in ipairs(presets) do
		if type(preset) == "table" and not table.empty(preset) then
			convertedPresets[index] = preset
		end
	end

	if #convertedPresets == 0 then
		return nil
	end

	return {
		cipImportedPresets = convertedPresets,
		configureShowOffSocketPresets = cipData.configureShowOffSocketPresets
	}
end
