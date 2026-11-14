-- chunkname: @/game_wheel/classes/vessels.lua
--
-- 15.33 gem vessels. Gems no longer belong to a wheel domain: there are 8 vessels, each takes one
-- gem quality (lesser, regular, greater, lesser, greater, regular, greater, greater) and vessel i
-- is unlocked when at least i + 1 of the 8 Gem Vessel slices of the wheel are full. A gem in an
-- unlocked vessel gives all of its mods. The same patch moved the spell augments of the four
-- middle 100 point slices to the slices that lost their vessel and put Revelation Mastery
-- (+125 points for the Revelation Perk of the domain) on the middle slices.
--
-- At 15.33 WheelOfDestiny.equipedGems holds the 8 vessels (Lua index 1..8 = vessel 0..7, gem
-- index or -1), the same list the server sends in 0x5F and expects in 0x62. Older versions keep
-- the 4 domain model of wheelclass.lua and gematelier.lua untouched.

WheelVessels = {}

local VESSEL_COUNT = 8
-- accepted gem quality of vessel 0..7 (0 lesser, 1 regular, 2 greater)
local VESSEL_QUALITY = {
	[0] = 0,
	1,
	2,
	0,
	2,
	1,
	2,
	2
}
-- Lua slot indices (WheelSlots_t) of the Gem Vessel slices
local VESSEL_NODE_SLOTS = {
	5,
	7,
	10,
	15,
	22,
	27,
	30,
	32
}
-- 0 based slot indices of the vessel slices per domain (GemDomains order)
local VESSEL_INDEX_1533 = {
	[0] = {
		6,
		14
	},
	{
		4,
		9
	},
	{
		26,
		31
	},
	{
		21,
		29
	}
}
-- Revelation Mastery slice -> slice that received its old spell augment
local MOVED_AUGMENTS = {
	[8] = 3,
	[11] = 18,
	[26] = 19,
	[29] = 34
}
local MASTERY_POINTS = 125
local MAX_REVEALED_GEMS = 600
local RESHAPE_COST = {
	[0] = {
		gold = 125000,
		fragments = 1,
		greater = false
	},
	{
		gold = 1000000,
		fragments = 2,
		greater = false
	},
	{
		gold = 5000000,
		fragments = 3,
		greater = true
	}
}
local QUALITY_NAMES = {
	[0] = "Lesser",
	"Regular",
	"Greater"
}
local QUALITY_SHORT = {
	[0] = "L",
	"R",
	"G"
}
local PERK_ICON_IDS = {
	"perkIconTopLeft",
	"perkIconTopRight",
	"perkIconBottomLeft",
	"perkIconBottomRight"
}
local ASSET_DIR = "/images/game/wheel/1533/"

local legacyTables
local tablesActive = false
local selectedVessel = -1
local reshapeWindow

function WheelVessels.isActive()
	return g_game.getClientVersion() >= 1533
end

function WheelVessels.getCount()
	return VESSEL_COUNT
end

function WheelVessels.getVesselQuality(vessel)
	return VESSEL_QUALITY[vessel]
end

function WheelVessels.getQualityName(quality)
	return QUALITY_NAMES[quality] or "Unknown"
end

function WheelVessels.getMaxRevealedGems()
	return MAX_REVEALED_GEMS
end

-- Returns the 15.33 image path when the owner added it, nil otherwise (callers keep the old image).
function WheelVessels.asset(name)
	local path = ASSET_DIR .. name

	if g_resources.fileExists(path .. ".png") then
		return path
	end

	return nil
end

local function copyList(list)
	local copy = {}

	for i, value in ipairs(list) do
		copy[i] = value
	end

	return copy
end

-- Switches the wheel tables between the 15.30 and the 15.33 slice layout. Safe to call often.
function WheelVessels.applyTables()
	local active = WheelVessels.isActive()

	if not legacyTables then
		legacyTables = {
			vesselIndex = {},
			conviction = {},
			consts = {},
			icons = {}
		}

		for domain, list in pairs(VesselIndex) do
			legacyTables.vesselIndex[domain] = copyList(list)
		end

		for id, bonus in pairs(WheelBonus) do
			legacyTables.conviction[id] = bonus.conviction
		end

		for key, value in pairs(WheelConsts) do
			if type(key) == "string" and key:find("^spell_") and type(value) == "table" then
				legacyTables.consts[key] = copyList(value)
			end
		end

		for vocation, icons in pairs(WheelIcons) do
			legacyTables.icons[vocation] = {}

			for index, info in pairs(icons) do
				legacyTables.icons[vocation][index] = info
			end
		end
	end

	if active == tablesActive then
		return
	end

	tablesActive = active

	for domain in pairs(VesselIndex) do
		VesselIndex[domain] = copyList(active and VESSEL_INDEX_1533[domain] or legacyTables.vesselIndex[domain])
	end

	for id, conviction in pairs(legacyTables.conviction) do
		WheelBonus[id].conviction = conviction
	end

	for key, list in pairs(legacyTables.consts) do
		WheelConsts[key] = copyList(list)
	end

	for vocation, icons in pairs(legacyTables.icons) do
		for index, info in pairs(icons) do
			WheelIcons[vocation][index] = info
		end
	end

	if not active then
		return
	end

	for masteryIndex, augmentIndex in pairs(MOVED_AUGMENTS) do
		WheelBonus[augmentIndex - 1].conviction = legacyTables.conviction[masteryIndex - 1]
		WheelBonus[masteryIndex - 1].conviction = "revelation_mastery"

		-- the spell_N lists name the two slices that unlock the two augment stages
		for key in pairs(legacyTables.consts) do
			for i, index in ipairs(WheelConsts[key]) do
				if index == masteryIndex then
					WheelConsts[key][i] = augmentIndex
				end
			end
		end

		for vocation, icons in pairs(legacyTables.icons) do
			local spellIcon = icons[augmentIndex] and icons[masteryIndex]

			if spellIcon then
				WheelIcons[vocation][augmentIndex] = {
					iconRect = icons[masteryIndex].iconRect,
					miniIconRect = icons[augmentIndex].miniIconRect
				}
				WheelIcons[vocation][masteryIndex] = {
					iconRect = icons[augmentIndex].iconRect,
					miniIconRect = icons[masteryIndex].miniIconRect,
					masteryDomain = WheelBonus[masteryIndex - 1].domain
				}
			end
		end
	end
end

function WheelVessels.isMasterySlot(index)
	return WheelVessels.isActive() and MOVED_AUGMENTS[index] ~= nil
end

local function isSlotFull(index)
	local bonus = WheelBonus[index - 1]
	local points = WheelOfDestiny.pointInvested[index] or 0

	return bonus ~= nil and points > 0 and points >= bonus.maxPoints
end

function WheelVessels.getActiveVesselCount()
	local count = 0

	for _, index in ipairs(VESSEL_NODE_SLOTS) do
		if isSlotFull(index) then
			count = count + 1
		end
	end

	return count
end

function WheelVessels.isVesselUnlocked(vessel)
	return vessel < WheelVessels.getActiveVesselCount()
end

function WheelVessels.emptyList()
	local list = {}

	for i = 1, VESSEL_COUNT do
		list[i] = -1
	end

	return list
end

-- Any list of gem indices -> 8 vessel entries (gem index or -1).
function WheelVessels.normalize(list)
	local vessels = WheelVessels.emptyList()

	if type(list) ~= "table" then
		return vessels
	end

	for i = 1, VESSEL_COUNT do
		local value = tonumber(list[i])

		if value and value >= 0 then
			vessels[i] = value
		end
	end

	return vessels
end

function WheelVessels.getVessels()
	if type(WheelOfDestiny.equipedGems) ~= "table" or #WheelOfDestiny.equipedGems ~= VESSEL_COUNT then
		WheelOfDestiny.equipedGems = WheelVessels.normalize(WheelOfDestiny.equipedGems)
	end

	return WheelOfDestiny.equipedGems
end

-- Drops vessel entries the server would refuse (unknown gem, wrong quality, same gem twice).
function WheelVessels.sanitize()
	local vessels = WheelVessels.getVessels()
	local seen = {}

	for i = 1, VESSEL_COUNT do
		local gemID = vessels[i]

		if gemID >= 0 then
			local gem = GemAtelier.getGemDataById(gemID)

			if not gem or gem.gemType ~= VESSEL_QUALITY[i - 1] or seen[gemID] then
				vessels[i] = -1
			else
				seen[gemID] = true
			end
		end
	end
end

function WheelVessels.getVesselOfGem(gemID)
	if type(gemID) ~= "number" or gemID < 0 then
		return nil
	end

	for i, id in ipairs(WheelVessels.getVessels()) do
		if id == gemID then
			return i - 1
		end
	end

	return nil
end

function WheelVessels.getGemInVessel(vessel)
	local gemID = WheelVessels.getVessels()[vessel + 1]

	if not gemID or gemID < 0 then
		return nil
	end

	return GemAtelier.getGemDataById(gemID)
end

function WheelVessels.isGemActive(gemID)
	local vessel = WheelVessels.getVesselOfGem(gemID)

	return vessel ~= nil and WheelVessels.isVesselUnlocked(vessel)
end

-- The vessel a gem goes to: the selected one when it takes the quality, else the first free
-- unlocked vessel, then the first free locked one, then the first unlocked one (replace).
function WheelVessels.findVesselFor(gem, preferred)
	local quality = gem.gemType
	local vessels = WheelVessels.getVessels()
	local count = WheelVessels.getActiveVesselCount()

	if preferred and preferred >= 0 and VESSEL_QUALITY[preferred] == quality then
		return preferred
	end

	for vessel = 0, VESSEL_COUNT - 1 do
		if VESSEL_QUALITY[vessel] == quality and vessel < count and vessels[vessel + 1] < 0 then
			return vessel
		end
	end

	for vessel = 0, VESSEL_COUNT - 1 do
		if VESSEL_QUALITY[vessel] == quality and vessels[vessel + 1] < 0 then
			return vessel
		end
	end

	for vessel = 0, VESSEL_COUNT - 1 do
		if VESSEL_QUALITY[vessel] == quality and vessel < count then
			return vessel
		end
	end

	for vessel = 0, VESSEL_COUNT - 1 do
		if VESSEL_QUALITY[vessel] == quality then
			return vessel
		end
	end

	return nil
end

local function syncPreset()
	if WheelOfDestiny.currentPreset and not table.empty(WheelOfDestiny.currentPreset) then
		WheelOfDestiny.currentPreset.equipedGems = copyList(WheelVessels.getVessels())
	end
end

function WheelVessels.socket(vessel, gemID)
	local vessels = WheelVessels.getVessels()

	for i = 1, VESSEL_COUNT do
		if vessels[i] == gemID then
			vessels[i] = -1
		end
	end

	vessels[vessel + 1] = gemID

	syncPreset()
end

function WheelVessels.unsocket(vessel)
	WheelVessels.getVessels()[vessel + 1] = -1

	syncPreset()
end

-- Gem mods of the gems in unlocked vessels, in the format getVesselBonus and configureSummary read.
function WheelVessels.buildGemBonuses()
	local bonuses = {}
	local count = WheelVessels.getActiveVesselCount()

	-- mods the client has no description for (new 15.33 supreme mods) are left out of the summary
	local function add(bonusID, supreme, gemID)
		local descriptions = supreme and SupremeGemDescription or RegularGemDescription

		if descriptions[bonusID] then
			table.insert(bonuses, {
				supreme = supreme,
				bonusID = bonusID,
				gemID = gemID
			})
		end
	end

	for vessel = 0, count - 1 do
		local gem = WheelVessels.getGemInVessel(vessel)

		if gem then
			add(gem.lesserBonus, false, gem.gemID)

			if gem.gemType >= 1 then
				add(gem.regularBonus, false, gem.gemID)
			end

			if gem.gemType >= 2 then
				add(gem.supremeBonus, true, gem.gemID)
			end
		end
	end

	WheelOfDestiny.equipedGemBonuses = bonuses
end

-- Revelation points from Revelation Mastery slices and Revelation Mastery supreme mods.
function WheelVessels.addExtraPassivePoints(extra)
	for masteryIndex in pairs(MOVED_AUGMENTS) do
		if isSlotFull(masteryIndex) then
			local domain = WheelBonus[masteryIndex - 1].domain

			extra[domain] = (extra[domain] or 0) + MASTERY_POINTS
		end
	end

	local count = WheelVessels.getActiveVesselCount()

	for vessel = 0, count - 1 do
		local gem = WheelVessels.getGemInVessel(vessel)

		if gem and gem.gemType == 2 and gem.supremeBonus > 0 then
			local vocationId = translateVocation(WheelOfDestiny.vocationId)
			local supremeList = gem.supremeBonus > 5 and VocationSupremeMods[vocationId] or FlatSupremeMods
			local bonus = supremeList and supremeList[gem.supremeBonus]

			if bonus and bonus.domain then
				local value = getBonusValueUpgrade(gem.supremeBonus, gem.gemID, true, true)

				extra[bonus.domain + 1] = (extra[bonus.domain + 1] or 0) + value
			end
		end
	end
end

function WheelVessels.getConvictionText(bonus, fullMessage)
	if bonus.conviction == "vessel" then
		return "Gem Vessel\nA full slice unlocks one more\ngem vessel and grants +1\ndamage and healing."
	elseif bonus.conviction == "revelation_mastery" then
		return string.format("Revelation Mastery\n+%d promotion points for\nthe Revelation Perk of\nthis domain.", MASTERY_POINTS)
	end

	return nil
end

function WheelVessels.getConvictionTooltip(bonus)
	if bonus.conviction == "vessel" then
		return "Each full Gem Vessel slice unlocks one gem vessel in the Gem Atelier\nand grants +1 damage and healing. Vessels unlock in order:\nlesser, regular, greater, lesser, greater, regular, greater, greater."
	elseif bonus.conviction == "revelation_mastery" then
		return string.format("A full Revelation Mastery slice counts as %d promotion points\ntowards the Revelation Perk of its domain.", MASTERY_POINTS)
	end

	return nil
end

-- Adds the 15.33 vessel and Revelation Mastery lines to the conviction perk list.
function WheelVessels.addConvictionPerk(convictions, bonus)
	if bonus.conviction == "vessel" then
		local key = 13

		if not convictions[key] then
			convictions[key] = {
				points = 0,
				perk = "Gem Vessels",
				tooltip = WheelVessels.getConvictionTooltip(bonus)
			}
		end

		convictions[key].points = convictions[key].points + 1
		convictions[key].stringPoint = string.format("%d / %d", convictions[key].points, VESSEL_COUNT)

		return true
	elseif bonus.conviction == "revelation_mastery" then
		local key = 20 + bonus.domain
		local names = {
			"RM Top Left",
			"RM Top Right",
			"RM Bottom Left",
			"RM Bottom Right"
		}

		convictions[key] = {
			perk = names[bonus.domain] or "Revelation Mastery",
			stringPoint = "+" .. MASTERY_POINTS,
			tooltip = WheelVessels.getConvictionTooltip(bonus)
		}

		return true
	end

	return false
end

-- Revelation Mastery slices show the large perk of their domain until the 15.33 icon is added.
function WheelVessels.refreshMasteryIcons()
	if not WheelVessels.isActive() or not wheelPanel or not WheelIcons[WheelOfDestiny.vocationId] then
		return
	end

	local masteryIcon = WheelVessels.asset("icon-revelation-mastery")

	for masteryIndex in pairs(MOVED_AUGMENTS) do
		local widget = wheelPanel:recursiveGetChildById("icon" .. masteryIndex)
		local domain = WheelBonus[masteryIndex - 1].domain

		if widget then
			local modIcon = widget:recursiveGetChildById("modIcon" .. masteryIndex)

			if modIcon then
				modIcon:setVisible(false)
			end

			widget:setSize(tosize("30 30"))

			if masteryIcon then
				widget:setImageSource(masteryIcon)
				widget:setImageClip("0 0 30 30")
			else
				local perkIcon = wheelPanel:recursiveGetChildById(PERK_ICON_IDS[domain])

				widget:setImageSource("/images/game/wheel/icons-skillwheel-largeperks")

				if perkIcon then
					widget:setImageClip(perkIcon:getImageClip())
				end
			end
		end
	end
end

-- Corner sockets of the wheel: lit when a vessel slice of the domain is full. Gems are no longer
-- bound to a domain, so the corner shows no gem; a click opens the vessel overview.
function WheelVessels.configureCornerSockets()
	for domain = 0, 3 do
		local background = wheelPanel:recursiveGetChildById("socketBackground" .. domain)
		local socket = wheelPanel:recursiveGetChildById("gemSocket" .. domain)
		local gemIcon = socket and socket:recursiveGetChildById("gemIcon" .. domain)
		local filled = 0

		for _, index in ipairs(VesselIndex[domain] or {}) do
			if isSlotFull(index + 1) then
				filled = filled + 1
			end
		end

		if background then
			background:setImageSource("/images/game/wheel/" .. (filled == 0 and "backdrop_skillwheel_largebonus_socketdisabled_" or "backdrop_skillwheel_largebonus_socketenabled_") .. domain)
		end

		if socket then
			socket:setVisible(true)
			socket:setImageSource(filled > 0 and "/images/game/wheel/backdrop_skillwheel_socket_active" or "/images/game/wheel/backdrop_skillwheel_socket_inactive")
			socket:setImageClip("0 0 34 34")
			socket:setTooltip(tr("Gem Vessel slices of this domain: %d / 2\nClick to see your gem vessels.", filled))
		end

		if gemIcon then
			gemIcon:setVisible(false)
		end
	end
end

function WheelVessels.showVesselSummary()
	local content = wheelOfDestinyWindow.selection.gemContent
	local count = WheelVessels.getActiveVesselCount()
	local vessels = WheelVessels.getVessels()
	local socketed = {
		[0] = 0,
		0,
		0
	}
	local total = {
		[0] = 0,
		0,
		0
	}

	for vessel = 0, VESSEL_COUNT - 1 do
		local quality = VESSEL_QUALITY[vessel]

		total[quality] = total[quality] + 1

		if vessels[vessel + 1] >= 0 then
			socketed[quality] = socketed[quality] + 1
		end
	end

	content.gemName:setText(tr("Gem Vessels"))
	content.modification0:setColor("#c0c0c0")
	content.modification0:setText(tr("Unlocked vessels: %d / %d", count, VESSEL_COUNT))
	content.modification1:setColor("#c0c0c0")
	content.modification1:setText(tr("Gems socketed: %d / %d lesser, %d / %d regular, %d / %d greater", socketed[0], total[0], socketed[1], total[1], socketed[2], total[2]))
	content.modification2:setColor("#707070")
	content.modification2:setText(count < VESSEL_COUNT and tr("Fill more Gem Vessel slices to unlock the next vessel.") or tr("All gem vessels are unlocked."))
	content.sealedInfo:setText(tr("Gem Vessel slices: %d / %d", count, VESSEL_COUNT))

	local text = {}

	setStringColor(text, tr("+%d Damage and Healing", count), count > 0 and "#c0c0c0" or "#707070")
	content.VRBonus:setColoredText(text)
end

function WheelVessels.getFirstVesselToShow()
	local vessels = WheelVessels.getVessels()
	local count = WheelVessels.getActiveVesselCount()

	for vessel = 0, count - 1 do
		if vessels[vessel + 1] < 0 then
			return vessel
		end
	end

	return 0
end

-- Gem image of the given quality. Uses data/images/game/wheel/1533/icons-gematelier-gemvariants
-- (one 32x32 frame per quality, one row per vocation) when present, else the 15.30 sheet.
function WheelVessels.setGemImage(widget, quality, big)
	local vocation = math.max(1, WheelOfDestiny.vocationId or 1)

	if big then
		local source = WheelVessels.asset("icons-gematelier-gemvariants64")

		if source then
			widget:setImageSource(source)
			widget:setImageClip(quality * 64 .. " " .. (vocation - 1) * 64 .. " 64 64")
		else
			widget:setImageSource("/images/game/wheel/icons-gematelier-gemvariants64")
			widget:setImageClip(quality * 64 .. " " .. (vocation - 1) * 64 .. " 64 64")
		end

		return
	end

	local source = WheelVessels.asset("icons-gematelier-gemvariants")

	if source then
		widget:setImageSource(source)
		widget:setImageClip(quality * 32 .. " " .. (vocation - 1) * 32 .. " 32 32")
	else
		widget:setImageSource("/images/game/wheel/icons-gematelier-gemvariants")
		widget:setImageClip((vocation - 1) * 384 + quality * 32 .. " 0 32 32")
	end
end

function WheelVessels.resetSelection()
	selectedVessel = -1
end

function WheelVessels.getSelectedVessel()
	return selectedVessel
end

-- Gem Atelier: 8 vessel sockets in place of the 4 domain sockets.
function WheelVessels.setupAtelierPanel()
	if not gemAtelierWindow then
		return
	end

	local active = WheelVessels.isActive()
	local panel = gemAtelierWindow:recursiveGetChildById("vessels")
	local legacyContent = panel and panel:getChildById("vesselsContent")
	local affinitiesBox = gemAtelierWindow:recursiveGetChildById("affinitiesBox")

	if affinitiesBox then
		affinitiesBox:setVisible(not active)
	end

	if not panel then
		return
	end

	local grid = panel:getChildById("vesselGrid")

	if legacyContent then
		legacyContent:setVisible(not active)
	end

	if not active then
		if grid then
			grid:setVisible(false)
		end

		return
	end

	if not grid then
		grid = g_ui.createWidget("VesselGrid1533", panel)

		grid:setId("vesselGrid")

		for vessel = 0, VESSEL_COUNT - 1 do
			local socket = g_ui.createWidget("VesselSocket1533", grid.sockets)

			socket:setId("vesselSocket" .. vessel)

			function socket.onClick()
				WheelVessels.onClickVessel(vessel)
			end
		end
	end

	grid:setVisible(true)

	local count = WheelVessels.getActiveVesselCount()
	local vessels = WheelVessels.getVessels()
	local socketImage = WheelVessels.asset("vessel-socket")

	for vessel = 0, VESSEL_COUNT - 1 do
		local socket = grid.sockets:getChildById("vesselSocket" .. vessel)
		local quality = VESSEL_QUALITY[vessel]
		local unlocked = vessel < count
		local gem = vessels[vessel + 1] >= 0 and GemAtelier.getGemDataById(vessels[vessel + 1]) or nil

		socket.backdrop:setImageSource(socketImage or (unlocked and "/images/game/wheel/backdrop_skillwheel_socket_active" or "/images/game/wheel/backdrop_skillwheel_socket_inactive"))

		if socketImage then
			socket.backdrop:setImageClip(quality * 34 .. " " .. (unlocked and 0 or 34) .. " 34 34")
		end

		socket.quality:setText(QUALITY_SHORT[quality])
		socket.lock:setVisible(not unlocked)
		socket.marker:setVisible(vessel == selectedVessel)
		socket.gem:setVisible(gem ~= nil)

		if gem then
			WheelVessels.setGemImage(socket.gem, gem.gemType, false)
			socket.gem:setOpacity(unlocked and 1 or 0.5)
		end

		local tooltip = tr("Vessel %d: %s gems", vessel + 1, QUALITY_NAMES[quality])

		if not unlocked then
			tooltip = tooltip .. "\n" .. tr("Locked: fill %d Gem Vessel slices of the wheel to unlock it.", vessel + 1)
		end

		if gem then
			tooltip = tooltip .. "\n" .. tr("Holds a %s gem.", QUALITY_NAMES[gem.gemType])

			if not unlocked then
				tooltip = tooltip .. "\n" .. tr("The gem gives no bonus while the vessel is locked.")
			end
		else
			tooltip = tooltip .. "\n" .. tr("Empty")
		end

		socket:setTooltip(tooltip)
	end

	grid.status:setText(tr("%d / %d unlocked", count, VESSEL_COUNT))
end

function WheelVessels.onClickVessel(vessel)
	local gem = WheelVessels.getGemInVessel(vessel)

	if vessel == selectedVessel and not gem then
		selectedVessel = -1

		WheelVessels.setupAtelierPanel()

		return
	end

	if gem then
		GemAtelier.redirectToGem(gem)
	else
		GemAtelier.onSortQuality(nil, VESSEL_QUALITY[vessel] + 2)

		local qualitiesBox = gemAtelierWindow:recursiveGetChildById("qualitiesBox")

		if qualitiesBox then
			qualitiesBox:setCurrentIndex(VESSEL_QUALITY[vessel] + 2, true)
		end
	end

	selectedVessel = vessel

	WheelVessels.setupAtelierPanel()
end

-- Place or remove the selected gem; the change is sent with Apply/Ok (0x62) like the points.
function WheelVessels.manageVessel(gem, remove)
	if remove then
		local vessel = WheelVessels.getVesselOfGem(gem.gemID)

		if vessel then
			WheelVessels.unsocket(vessel)

			selectedVessel = vessel
		end
	else
		local vessel = WheelVessels.findVesselFor(gem, selectedVessel)

		if not vessel then
			return
		end

		WheelVessels.socket(vessel, gem.gemID)

		selectedVessel = vessel
	end

	WheelVessels.refreshWheelBonuses()
end

function WheelVessels.refreshWheelBonuses()
	if not wheelOfDestinyWindow then
		return
	end

	WheelOfDestiny.configureVessels()
	WheelOfDestiny.configureSummary()
	WheelOfDestiny.configurePassives()
	WheelOfDestiny.configureEquippedGems()
end

function WheelVessels.getVesselStatusText(gem)
	local vessel = WheelVessels.getVesselOfGem(gem.gemID)

	if not vessel then
		return tr("Not in a vessel")
	end

	if WheelVessels.isVesselUnlocked(vessel) then
		return tr("In vessel %d", vessel + 1)
	end

	return tr("In vessel %d (locked)", vessel + 1)
end

local function getFragments(greater)
	local player = g_game.getLocalPlayer()

	if not player then
		return 0
	end

	return player:getResourceBalance(greater and ResourceTypes.GREATER_FRAGMENTS or ResourceTypes.LESSER_FRAGMENTS)
end

local function getGold()
	local player = g_game.getLocalPlayer()

	if not player then
		return 0
	end

	return player:getResourceBalance(ResourceTypes.BANK_BALANCE) + player:getResourceBalance(ResourceTypes.GOLD_EQUIPPED)
end

local function formatCost(cost)
	return tr("%s gold and %d %s fragment%s", comma_value(cost.gold), cost.fragments, cost.greater and "greater" or "lesser", cost.fragments == 1 and "" or "s")
end

-- Reshape buttons next to each mod of the selected gem (replace the 15.30 "switch domain").
function WheelVessels.setupReshape(modsPanel, gemData)
	local active = WheelVessels.isActive()

	for modSlot = 0, 2 do
		local button = modsPanel:getChildById("reshape" .. modSlot)
		local costLabel = modsPanel:getChildById("reshapeCost" .. modSlot)

		if not button and active then
			button = g_ui.createWidget("ReshapeButton1533", modsPanel)

			button:setId("reshape" .. modSlot)
			button:addAnchor(AnchorLeft, "fragmentType" .. modSlot, AnchorRight)
			button:addAnchor(AnchorVerticalCenter, "fragmentType" .. modSlot, AnchorVerticalCenter)

			costLabel = g_ui.createWidget("ReshapeCost1533", modsPanel)

			costLabel:setId("reshapeCost" .. modSlot)
			costLabel:addAnchor(AnchorTop, "reshape" .. modSlot, AnchorBottom)
			costLabel:addAnchor(AnchorHorizontalCenter, "reshape" .. modSlot, AnchorHorizontalCenter)
		end

		if button then
			local show = active and gemData ~= nil and modSlot <= gemData.gemType

			button:setVisible(show)
			costLabel:setVisible(show)

			if show then
				local cost = RESHAPE_COST[modSlot]
				local reasons = {}

				if WheelOfDestiny.isPreview or WheelOfDestiny.changeState ~= 1 then
					table.insert(reasons, tr("You need to be inside a temple to reshape gems."))
				end

				if gemData.locked == 1 then
					table.insert(reasons, tr("Unlock the gem before you reshape it."))
				end

				if getGold() < cost.gold then
					table.insert(reasons, tr("You need at least %s gold to reshape this mod.", comma_value(cost.gold)))
				end

				if getFragments(cost.greater) < cost.fragments then
					table.insert(reasons, tr("You need at least %d %s fragments to reshape this mod.", cost.fragments, cost.greater and "greater" or "lesser"))
				end

				costLabel:setText(string.format("%sk + %d %s", comma_value(cost.gold / 1000), cost.fragments, cost.greater and "G" or "L"))
				costLabel:setColor(#reasons == 0 and "#c0c0c0" or "#d33c3c")
				button:setEnabled(#reasons == 0)

				if #reasons == 0 then
					button:setTooltip(tr("Re-roll this mod at random for %s.", formatCost(cost)))
				else
					button:setTooltip(table.concat(reasons, "\n"))
				end

				local gemID = gemData.gemID

				function button.onClick()
					WheelVessels.onReshape(gemID, modSlot)
				end
			end
		end
	end
end

function WheelVessels.onReshape(gemID, modSlot)
	if reshapeWindow or WheelOfDestiny.isPreview then
		return
	end

	local cost = RESHAPE_COST[modSlot]

	hideWheelWindow()

	local function close()
		if reshapeWindow then
			reshapeWindow:destroy()

			reshapeWindow = nil
		end

		showWheelWindow()
	end

	local function confirm()
		sendgemAction(2, gemID, modSlot)
		close()
	end

	reshapeWindow = displayGeneralBox(tr("Reshape Gem"), tr("Do you want to re-roll this mod at random for %s?", formatCost(cost)), {
		{
			text = tr("Yes"),
			callback = confirm
		},
		{
			text = tr("No"),
			callback = close
		}
	}, confirm, close)
end

function WheelVessels.onGameEnd()
	selectedVessel = -1

	if reshapeWindow then
		reshapeWindow:destroy()

		reshapeWindow = nil
	end
end

-- Wrappers so the 15.30 code paths keep working and the 15.33 parts follow every wheel change.
local legacyGetEquipedGem = GemAtelier.getEquipedGem

function GemAtelier.getEquipedGem(domain)
	if WheelVessels.isActive() then
		-- 15.33 gems belong to vessels, not to a domain
		return nil
	end

	return legacyGetEquipedGem(domain)
end

local legacyGetDamageAndHealing = GemAtelier.getDamageAndHealing

function GemAtelier:getDamageAndHealing()
	if WheelVessels.isActive() then
		return WheelVessels.getActiveVesselCount()
	end

	return legacyGetDamageAndHealing(self)
end

local legacyConfigureVessels = WheelOfDestiny.configureVessels

function WheelOfDestiny.configureVessels()
	if WheelVessels.isActive() then
		WheelVessels.buildGemBonuses()
	end

	return legacyConfigureVessels()
end

local legacyConfigureEquippedGems = WheelOfDestiny.configureEquippedGems

function WheelOfDestiny.configureEquippedGems()
	if WheelVessels.isActive() then
		WheelVessels.configureCornerSockets()
		WheelVessels.setupAtelierPanel()

		return
	end

	return legacyConfigureEquippedGems()
end

local legacyOnCreate = WheelOfDestiny.onCreate

function WheelOfDestiny.onCreate(vocationId)
	local result = legacyOnCreate(vocationId)

	WheelVessels.refreshMasteryIcons()

	return result
end

local legacyInsertPoint = WheelOfDestiny.insertPoint

function WheelOfDestiny.insertPoint(index, points)
	local result = legacyInsertPoint(index, points)

	if WheelVessels.isMasterySlot(index) then
		WheelVessels.refreshMasteryIcons()
	end

	return result
end

local legacyResetWheel = resetWheel

function resetWheel(ignoreprotocol)
	local result = legacyResetWheel(ignoreprotocol)

	WheelVessels.refreshMasteryIcons()

	return result
end

local legacyRemovePoint = WheelOfDestiny.removePoint

function WheelOfDestiny.removePoint(index, points)
	local result = legacyRemovePoint(index, points)

	if WheelVessels.isMasterySlot(index) then
		WheelVessels.refreshMasteryIcons()
	end

	return result
end
