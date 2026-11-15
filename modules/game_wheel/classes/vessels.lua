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
local PERK_ICON_IDS = {
	"perkIconTopLeft",
	"perkIconTopRight",
	"perkIconBottomLeft",
	"perkIconBottomRight"
}
local ASSET_DIR = "/images/game/wheel/1533/"
-- 15.33 icons-skillwheel-mediumperks: icons 0-36 as before, 37 is the Gem Vessel slice (it replaced
-- the four Vessel Resonance icons 37-40), the old icons 41-48 moved to 38-45 and 46-61 are the
-- Revelation Mastery slices, in the order of icons-skillwheel-largeperks.
local MEDIUM_PERKS_1533 = "images/skillwheel/icons-skillwheel-mediumperks"
local MEDIUM_PERKS_LEGACY = "/images/game/wheel/icons-skillwheel-mediumperks"
local VESSEL_ICON_1533 = 37
local MASTERY_ICON_1533 = 46

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

	if WheelVessels.cipImage(MEDIUM_PERKS_1533) then
		WheelVessels.remapMediumPerkIcons()
	end
end

-- Moves the slice icons from the repo sheet positions to the 15.33 sheet ones.
function WheelVessels.remapMediumPerkIcons()
	local vesselSlots = {}

	for _, index in ipairs(VESSEL_NODE_SLOTS) do
		vesselSlots[index] = true
	end

	for _, icons in pairs(WheelIcons) do
		for index, info in pairs(icons) do
			local x = tonumber(tostring(info.iconRect):match("^(%d+)"))

			if x then
				local icon = math.floor(x / 30)

				if vesselSlots[index] or icon >= 37 and icon <= 40 then
					icon = VESSEL_ICON_1533
				elseif icon >= 41 then
					icon = icon - 3
				end

				icons[index] = {
					iconRect = mediumPerkIconRect(icon),
					miniIconRect = info.miniIconRect,
					masteryDomain = info.masteryDomain
				}
			end
		end
	end
end

-- Sheet of the slice icons: the 15.33 one from data/images/1533/ when it is installed.
function WheelVessels.mediumPerkSheet()
	if WheelVessels.isActive() then
		local image = WheelVessels.cipImage(MEDIUM_PERKS_1533)

		if image then
			return image
		end
	end

	return MEDIUM_PERKS_LEGACY
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
				perk = "Gem Vessel",
				tooltip = WheelVessels.getConvictionTooltip(bonus)
			}
		end

		convictions[key].points = convictions[key].points + 1
		convictions[key].stringPoint = string.format("%d / %d", convictions[key].points, VESSEL_COUNT)

		return true
	elseif bonus.conviction == "revelation_mastery" then
		local key = 20 + bonus.domain
		local perkName = getRevelationDisplayName(bonus.domain)

		-- the official client names the entry after the Revelation Perk it feeds: "RM Gift of Life"
		convictions[key] = {
			perk = perkName and perkName ~= "" and "RM " .. perkName or "Revelation Mastery",
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
	local sheet = WheelVessels.cipImage(MEDIUM_PERKS_1533)

	for masteryIndex in pairs(MOVED_AUGMENTS) do
		local widget = wheelPanel:recursiveGetChildById("icon" .. masteryIndex)
		local domain = WheelBonus[masteryIndex - 1].domain

		if widget then
			local modIcon = widget:recursiveGetChildById("modIcon" .. masteryIndex)
			local perkIcon = wheelPanel:recursiveGetChildById(PERK_ICON_IDS[domain])

			if modIcon then
				modIcon:setVisible(false)
			end

			widget:setSize(tosize("30 30"))

			if sheet and perkIcon then
				-- the Revelation Mastery icon of the Revelation Perk the domain corner shows
				local largePerk = math.floor(perkIcon:getImageClip().x / 34)

				widget:setImageSource(sheet)
				widget:setImageClip(mediumPerkIconRect(MASTERY_ICON_1533 + largePerk))
			elseif masteryIcon then
				widget:setImageSource(masteryIcon)
				widget:setImageClip("0 0 30 30")
			else
				widget:setImageSource("/images/game/wheel/icons-skillwheel-largeperks")

				if perkIcon then
					widget:setImageClip(perkIcon:getImageClip())
				end
			end
		end
	end
end

-- Corners of the 15.33 wheel: no gem socket any more (SkillWheelCorner.qml draws only
-- backdrop_skillwheel_largebonus_XX). Uses the 15.33 backdrop from data/images/1533/ when it is
-- installed, else the 15.30 backdrop clipped to the part left of (or right of) its socket.
local CORNER_NAMES = {
	[0] = "TL",
	"TR",
	"BL",
	"BR"
}
local CORNER_SIZE = 85
local LEGACY_CORNER_WIDTH = 118
-- the 15.30 socket circle takes the outer 34 columns of the backdrop
local LEGACY_CORNER_CLIP = {
	[0] = "0 0 84 85",
	"34 0 84 85",
	"0 0 84 85",
	"34 0 84 85"
}

function WheelVessels.configureCornerSockets()
	for domain = 0, 3 do
		local background = wheelPanel:recursiveGetChildById("socketBackground" .. domain)
		local socket = wheelPanel:recursiveGetChildById("gemSocket" .. domain)
		local marker = wheelPanel:recursiveGetChildById("selectVessel" .. domain)

		if background then
			local image = WheelVessels.cipImage("images/skillwheel/backdrop_skillwheel_largebonus_" .. CORNER_NAMES[domain])

			if image then
				background:setImageSource(image)
				background:setImageClip("0 0 " .. CORNER_SIZE .. " " .. CORNER_SIZE)
				background:setSize(tosize(CORNER_SIZE .. " " .. CORNER_SIZE))
			else
				background:setImageSource("/images/game/wheel/backdrop_skillwheel_largebonus_socketdisabled_" .. domain)
				background:setImageClip(LEGACY_CORNER_CLIP[domain])
				background:setSize(tosize("84 " .. CORNER_SIZE))
			end
		end

		if socket then
			socket:setVisible(false)
		end

		if marker then
			marker:setVisible(false)
		end
	end
end

-- Gives the 15.30 corner backdrops their full size back after a 15.33 login.
function WheelVessels.resetCornerBackdrops()
	for domain = 0, 3 do
		local background = wheelPanel:recursiveGetChildById("socketBackground" .. domain)

		if background then
			background:setImageClip("0 0 " .. LEGACY_CORNER_WIDTH .. " " .. CORNER_SIZE)
			background:setSize(tosize(LEGACY_CORNER_WIDTH .. " " .. CORNER_SIZE))
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

function WheelVessels.resetSelection()
	selectedVessel = -1
end

function WheelVessels.getSelectedVessel()
	return selectedVessel
end

function WheelVessels.selectVessel(vessel)
	selectedVessel = vessel

	WheelVessels.setupAtelierPanel()
end

-- CipSoft 15.33 graphics are not in the repo: install_ui_graphics.py copies them to the ignored
-- data/images/1533/ with their original paths. Returns the image path, nil when it is missing.
local cipImages = {}

function WheelVessels.cipImage(path)
	if cipImages[path] == nil then
		local fullPath = "/images/1533/" .. path

		cipImages[path] = g_resources.fileExists(fullPath .. ".png") and fullPath or false
	end

	return cipImages[path] or nil
end

-- Green check badge of a gem that sits in a vessel.
function WheelVessels.setSocketedBadge(widget)
	local image = WheelVessels.cipImage("images/skillwheel/icon-gem-socketed")

	if image then
		widget:setImageSource(image)
		widget:setImageClip("0 0 32 32")
		widget:setSize(tosize("32 32"))
	else
		widget:setImageSource("/images/game/wheel/icon-socketed")
		widget:setImageClip("0 0 12 12")
		widget:setSize(tosize("12 12"))
	end
end

-- Socket bezels of icons-skillwheel-sockets: 6 colour groups (knight, paladin, sorcerer, druid,
-- monk, other) of 3 frames (lesser, regular, greater), 34 x 39 each.
local BEZEL_GROUP = {
	0,
	1,
	2,
	3,
	4
}
local VESSEL_ROW_MARGIN = 5
local VESSEL_SPACING = 2
local MOD_SLOT_WIDTH = 49

-- Box widths like the official row layout: one 49 px mod slot per quality step, the free width
-- shared out in proportion.
local function getVesselBoxWidths(rowWidth)
	local preferred = {}
	local total = 0

	for vessel = 0, VESSEL_COUNT - 1 do
		preferred[vessel] = (VESSEL_QUALITY[vessel] + 1) * MOD_SLOT_WIDTH
		total = total + preferred[vessel]
	end

	local free = rowWidth - 2 * VESSEL_ROW_MARGIN - (VESSEL_COUNT - 1) * VESSEL_SPACING
	local extra = math.max(0, free - total)
	local widths = {}
	local used = 0

	for vessel = 0, VESSEL_COUNT - 1 do
		widths[vessel] = preferred[vessel] + math.floor(extra * preferred[vessel] / total)
		used = used + widths[vessel]
	end

	if extra > 0 then
		widths[VESSEL_COUNT - 1] = widths[VESSEL_COUNT - 1] + free - used
	end

	return widths
end

local function createVesselBoxes(row)
	for vessel = 0, VESSEL_COUNT - 1 do
		local box = g_ui.createWidget("VesselBox1533", row)

		box:setId("vesselBox" .. vessel)
		box:addAnchor(AnchorTop, "parent", AnchorTop)
		box:setMarginTop(VESSEL_ROW_MARGIN)

		if vessel == 0 then
			box:addAnchor(AnchorLeft, "parent", AnchorLeft)
			box:setMarginLeft(VESSEL_ROW_MARGIN)
		else
			box:addAnchor(AnchorLeft, "vesselBox" .. vessel - 1, AnchorRight)
			box:setMarginLeft(VESSEL_SPACING)
		end

		local slots = VESSEL_QUALITY[vessel] + 1

		box.mods:setWidth(slots * MOD_SLOT_WIDTH)

		-- locked vessels do not react, like the disabled boxes of the official client
		local function onClick()
			if WheelVessels.isVesselUnlocked(vessel) then
				WheelVessels.onClickVessel(vessel)
			end
		end

		box.onClick = onClick

		for slot = 0, slots - 1 do
			local frame = g_ui.createWidget("GemModFrame1533", box.mods)

			frame:setId("mod" .. slot)
			frame:addAnchor(AnchorTop, "parent", AnchorTop)
			frame:addAnchor(AnchorLeft, "parent", AnchorLeft)
			frame:setMarginLeft(slot * MOD_SLOT_WIDTH)

			frame.onClick = onClick
		end
	end
end

-- Gem Atelier at 15.33: the row of 8 vessel boxes over the gem grid.
function WheelVessels.setupAtelierPanel()
	if not gemAtelierWindow or not WheelVessels.isActive() then
		return
	end

	local row = gemAtelierWindow:recursiveGetChildById("vesselRow")

	if not row then
		return
	end

	if not row:getChildById("vesselBox0") then
		createVesselBoxes(row)
	end

	local rowWidth = row:getWidth()

	if rowWidth < 200 then
		-- not laid out yet: the width of mainPanel
		rowWidth = 968
	end

	local widths = getVesselBoxWidths(rowWidth)
	local count = WheelVessels.getActiveVesselCount()
	local vessels = WheelVessels.getVessels()
	local vocation = WheelOfDestiny.vocationId or 0
	local gemNames = GemVocations[vocation]
	local bezelImage = WheelVessels.cipImage("images/skillwheel/icons-skillwheel-sockets")
	local backdropImage = WheelVessels.cipImage("images/skillwheel/backdrop_skillwheel_socket_active")
	local gradesImage = WheelVessels.cipImage("images/skillwheel/backdrop_modgrades")
	local ditherImage = WheelVessels.cipImage("images/ditherpattern")
	local group = BEZEL_GROUP[vocation] or 5

	for vessel = 0, VESSEL_COUNT - 1 do
		local box = row:getChildById("vesselBox" .. vessel)
		local quality = VESSEL_QUALITY[vessel]
		local unlocked = vessel < count
		local gem = vessels[vessel + 1] >= 0 and GemAtelier.getGemDataById(vessels[vessel + 1]) or nil

		box:setWidth(widths[vessel])
		box:setBorderWidth(vessel == selectedVessel and 2 or 0)
		box:setBorderColor("white")

		-- socket: dark backdrop of an unlocked vessel, the bezel of its quality, the gem inside
		if backdropImage then
			box.backdrop:setImageSource(backdropImage)
			box.backdrop:setSize(tosize("34 39"))
		else
			box.backdrop:setImageSource("/images/game/wheel/backdrop_skillwheel_socket_active")
			box.backdrop:setSize(tosize("34 34"))
		end

		box.backdrop:setVisible(unlocked)
		box.bezel:setVisible(bezelImage ~= nil)

		if bezelImage then
			box.bezel:setImageSource(bezelImage)
			box.bezel:setImageClip((group * 3 + quality) * 34 .. " 0 34 39")
		end

		box.gem:setVisible(gem ~= nil and gemNames ~= nil)

		if gem and gemNames and gemNames[quality] then
			box.gem:setItemId(gemNames[quality].id)
		end

		for slot = 0, quality do
			local frame = box.mods:getChildById("mod" .. slot)

			frame:setTooltip("")
			frame.hover:setVisible(false)

			if gem then
				GemAtelier.setupModFrame(frame, gem, slot)
				frame:setVisible(true)
			else
				-- an empty slot of an unlocked vessel, nothing in a locked one
				frame:setVisible(unlocked)
				frame.icon:setVisible(false)
				frame.potential:setVisible(false)

				if gradesImage then
					frame:setImageSource(gradesImage)
					frame:setImageClip("400 0 50 50")
					frame:setOpacity(1)
				else
					frame:setImageSource("/images/game/wheel/backdrop_modgrades")
					frame:setImageClip("0 0 50 50")
					frame:setOpacity(0.35)
				end
			end
		end

		-- locked vessels are dimmed with the dither pattern of the official client
		box.overlay:setVisible(not unlocked)

		if ditherImage then
			box.overlay:setImageSource(ditherImage)
		else
			box.overlay:setBackgroundColor("#00000080")
		end
	end
end

function WheelVessels.onClickVessel(vessel)
	local qualitiesBox = gemAtelierWindow:recursiveGetChildById("qualitiesBox")

	-- a second click on the selected vessel drops the selection and the quality filter
	if vessel == selectedVessel then
		selectedVessel = -1

		if qualitiesBox then
			qualitiesBox:setCurrentIndex(1, true)
		end

		GemAtelier.onSortQuality(nil, 1)
		WheelVessels.setupAtelierPanel()

		return
	end

	local gem = WheelVessels.getGemInVessel(vessel)

	if gem then
		GemAtelier.redirectToGem(gem)
	else
		GemAtelier.onSortQuality(nil, VESSEL_QUALITY[vessel] + 2)

		if qualitiesBox then
			qualitiesBox:setCurrentIndex(VESSEL_QUALITY[vessel] + 2, true)
		end
	end

	selectedVessel = vessel

	WheelVessels.setupAtelierPanel()
	GemAtelier.refreshModifyPanel(GemAtelier.getSelectedGemData())
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

-- Reshape row of the 15.33 Modify Gem panel: the Reshape button and the gold and fragment cost.
function WheelVessels.setupReshapeRow(row, gemData, modSlot)
	local cost = RESHAPE_COST[modSlot]
	local reasons = {}
	local goldShort = getGold() < cost.gold
	local fragmentsShort = getFragments(cost.greater) < cost.fragments

	-- texts and order of the official client
	if goldShort then
		table.insert(reasons, tr("You need at least %s gold to reshape gems at this position.", comma_value(cost.gold)))
	end

	if fragmentsShort then
		table.insert(reasons, tr("You need at least %s %s fragments to reshape gems at this position.", comma_value(cost.fragments), cost.greater and "greater" or "lesser"))
	end

	if WheelOfDestiny.isPreview or WheelOfDestiny.changeState ~= 1 then
		table.insert(reasons, tr("You need to be inside a temple to reshape gems."))
	end

	if gemData.locked == 1 then
		table.insert(reasons, tr("Before you can reshape the gem, you must unlock it."))
	end

	local button = row.reshapeButton

	row.goldCost.value:setText(GemAtelier.formatPrice(cost.gold))
	row.goldCost.value:setColor(goldShort and "#d33c3c" or "#c0c0c0")
	row.goldCost:setTooltip(tr("%s gold", comma_value(cost.gold)))
	row.fragmentCost.value:setText(tostring(cost.fragments))
	row.fragmentCost.value:setColor(fragmentsShort and "#d33c3c" or "#c0c0c0")
	row.fragmentCost.icon:setImageSource("/images/game/wheel/fragmentIcon")
	row.fragmentCost.icon:setImageClip(cost.greater and "0 12 12 12" or "0 0 12 12")
	row.fragmentCost:setTooltip(tr("%d %s fragment%s", cost.fragments, cost.greater and "greater" or "lesser", cost.fragments == 1 and "" or "s"))

	-- Keep the button enabled: a disabled widget gets no hover, so the reason tooltip would never show.
	button:setOn(#reasons == 0)
	button:setTooltip(#reasons == 0 and tr("Re-roll this mod at random for %s.", formatCost(cost)) or table.concat(reasons, "\n"))

	local gemID = gemData.gemID

	function button.onClick()
		if not button:isOn() then
			return
		end

		WheelVessels.onReshape(gemID, modSlot)
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

-- Last state the server sent in 0x5F. Placing a gem or moving points is local until Apply, and every gem
-- action makes the server send a new 0x5F that rebuilds the wheel, so this is what the server really has.
local serverPoints
local serverVessels
local pendingWindow
local confirmDismantle

function WheelVessels.rememberServerState()
	if not WheelVessels.isActive() then
		serverPoints = nil
		serverVessels = nil

		return
	end

	serverPoints = {}

	for index, points in pairs(WheelOfDestiny.pointInvested) do
		serverPoints[index] = points
	end

	serverVessels = copyList(WheelVessels.getVessels())

	confirmDismantle()
end

-- True when the server has the gem in a vessel (the server refuses to dismantle it then, whatever the local state).
function WheelVessels.isGemSocketedOnServer(gemID)
	for _, id in ipairs(serverVessels or WheelVessels.getVessels()) do
		if id == gemID then
			return true
		end
	end

	return false
end

function WheelVessels.hasPendingChanges()
	if not WheelVessels.isActive() or not serverPoints or not serverVessels then
		return false
	end

	for i, gemID in ipairs(WheelVessels.getVessels()) do
		if serverVessels[i] ~= gemID then
			return true
		end
	end

	for index, points in pairs(WheelOfDestiny.pointInvested) do
		if (serverPoints[index] or 0) ~= points then
			return true
		end
	end

	for index, points in pairs(serverPoints) do
		if (WheelOfDestiny.pointInvested[index] or 0) ~= points then
			return true
		end
	end

	return false
end

-- The server erases a dismantled gem from its revealed list, so every later gem index moves down by one.
-- Presets keep raw indices: follow the shift so they do not point at a different gem of the same quality.
local function shiftPresetGems(removedIndex)
	local changed = false
	local presets = {}
	local seen = {}

	for _, preset in pairs(WheelOfDestiny.internalPreset or {}) do
		table.insert(presets, preset)
	end

	table.insert(presets, WheelOfDestiny.currentPreset)

	for _, preset in ipairs(presets) do
		if type(preset) == "table" and type(preset.equipedGems) == "table" and not seen[preset.equipedGems] then
			seen[preset.equipedGems] = true

			for i, gemID in pairs(preset.equipedGems) do
				if type(gemID) == "number" then
					if gemID == removedIndex then
						preset.equipedGems[i] = -1
						changed = true
					elseif gemID > removedIndex then
						preset.equipedGems[i] = gemID - 1
						changed = true
					end
				end
			end
		end
	end

	if changed and g_game.getLocalPlayer() then
		WheelOfDestiny.saveWheelPresets()
	end
end

-- Sends a gem action (0xE7) and keeps the local preset data in step with what the server does.
local function countGems()
	local count = 0

	for _ in pairs(WheelOfDestiny.atelierGems or {}) do
		count = count + 1
	end

	return count
end

-- Dismantle sent but not yet confirmed by a 0x5F with one gem less (the server may refuse it).
local pendingDismantle

function confirmDismantle()
	if not pendingDismantle then
		return
	end

	if countGems() == pendingDismantle.count - 1 then
		shiftPresetGems(pendingDismantle.index)

		pendingDismantle = nil
	end
end

function WheelVessels.sendGemAction(actionType, param, pos)
	if WheelVessels.isActive() and actionType == 0 then
		pendingDismantle = {
			index = param,
			count = countGems()
		}
	end

	g_game.gemAction(actionType, param, pos)
end

-- Asks before a gem action would drop unsaved wheel changes. Returns true when the action was deferred.
function WheelVessels.deferGemAction(actionType, param, pos)
	if not WheelVessels.hasPendingChanges() or WheelOfDestiny.changeState == 0 or WheelOfDestiny.isPreview then
		return false
	end

	if pendingWindow then
		return true
	end

	-- Opened on the next frame: the confirm boxes that call this show the wheel window again right after.
	addEvent(function()
		if pendingWindow then
			return
		end

		hideWheelWindow()

		local function close()
			if pendingWindow then
				pendingWindow:destroy()

				pendingWindow = nil
			end

			showWheelWindow()
		end

		local function applyAndSend()
			close()
			onWheelOfDestinyApply(false)
			WheelVessels.rememberServerState()
			WheelVessels.sendGemAction(actionType, param, pos)
		end

		local function discardAndSend()
			close()
			WheelVessels.sendGemAction(actionType, param, pos)
		end

		pendingWindow = displayGeneralBox(tr("Unsaved Changes"), tr("You have changes on the wheel that are not applied yet.\nThe gem action reloads the wheel from the server and would discard them.\n\nApply your changes first?"), {
			{
				text = tr("Apply"),
				callback = applyAndSend
			},
			{
				text = tr("Discard"),
				callback = discardAndSend
			},
			{
				text = tr("Cancel"),
				callback = close
			}
		}, applyAndSend, close)
	end)

	return true
end

function WheelVessels.onGameEnd()
	selectedVessel = -1
	serverPoints = nil
	serverVessels = nil
	pendingDismantle = nil

	if reshapeWindow then
		reshapeWindow:destroy()

		reshapeWindow = nil
	end

	if pendingWindow then
		pendingWindow:destroy()

		pendingWindow = nil
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

	WheelVessels.resetCornerBackdrops()

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
