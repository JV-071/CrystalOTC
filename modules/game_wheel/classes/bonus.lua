-- chunkname: @/game_wheel/classes/bonus.lua

WheelPointTooltip = "From level 51 onwards, you receive one promotion point with each level, of which you currently have %s.\n\nFor each fully enhanced mod, you will receive another promotion point. This currently gives you %s out of a maximum of 69 points.\n\nCertain rare items and special game accomplishments can earn you bonus promotion points, of wich you currently have %s:"
ConvictionTooltip = "The Conviction Perk is unlocked when the maximum number of\npromotion points for this slice has been assigned.\n\nMost Conviction Perks can be found more than once within the\nWheel of Destiny. When they are unlocked, thier effect adds up."
WheelDedicationHeight = {
	{
		45,
		60,
		60,
		74
	},
	{
		45,
		45,
		60,
		74
	},
	{
		45,
		60,
		60,
		74
	},
	{
		45,
		60,
		74,
		74
	},
	{
		45,
		60,
		60,
		74
	}
}
WheelConsts = {
	lifeleech = 0.75,
	skill = 1,
	manaleech = 0.25,
	mitigation = 0.075,
	lifemana = {
		life = {
			3,
			2,
			1,
			1,
			2
		},
		mana = {
			1,
			3,
			6,
			6,
			2
		}
	},
	special_1 = {
		{
			"Battle Instinct",
			"Gain +6 shielding and +1 sword/axe/club fighting when 5\ncreatures are on adjacent squares.\nFor each additional creature, up to a maximum of 8, you get +6\nshielding and +1 sword/axe/club fighting more."
		},
		{
			"Positional Tactics",
			"Gain +3 distance fighting while no monster is within 1 squares.\nOtherwise gain +3 holy magic level and +3 healing magic level."
		},
		{
			"Runic Mastery",
			"If you use a rune, you have a 25% chance of increasing your magic\nlevel by 10%, or by 20% if you use a rune that can be created by\nyour vocation."
		},
		{
			"Healing Link",
			"If you heal someone with Nature's Embrace or Heal Friend, you\nalso heal yourself for 10% of the applied healing."
		},
		{
			"Guiding Presence",
			"Gain an aura that shares 50% of your mantra with members of your group."
		}
	},
	special_2 = {
		{
			"Battle Healing",
			"For each creature challenged, you will heal yourself for a small\namount. This amount scales with your shielding skill. Heals for\ndouble the amount if you have less than 60% of your hit points and\ntriple the amount if you have less than 30% of your hit points."
		},
		{
			"Ballistic Mastery",
			"The critical extra damage for attacks with a crossbow is increased\nby 10%. While wielding a bow your attacks and spells treat the\ntargets physical and holy sensitivity as being 2% higher."
		},
		{
			"Focus Mastery",
			"Increases the damage of your next damage spell by 35% within 12\nseconds after casting a focus spell."
		},
		{
			"Runic Mastery",
			"If you use a rune, you have a 25% chance of increasing your magic\nlevel by 10%, or by 20% if you use a rune that can be created by\nyour vocation."
		},
		{
			"Sanctuary",
			"Consuming Harmony creates a field lasting 5 seconds, increasing your damage and healing done by 2% for each Harmony consumed."
		}
	},
	health = {
		3,
		2,
		1,
		1,
		2
	},
	mana = {
		1,
		3,
		6,
		6,
		2
	},
	spell_1 = {
		6,
		21
	},
	spell_2 = {
		8,
		24
	},
	capacity = {
		5,
		4,
		2,
		2,
		5
	},
	spell_3 = {
		11,
		26
	},
	spell_4 = {
		13,
		29
	},
	spell_5 = {
		16,
		31
	}
}
WheelBonus = {
	[0] = {
		domain = 1,
		maxPoints = 200,
		conviction = "special_1",
		dedication = "lifemana"
	},
	{
		domain = 1,
		maxPoints = 150,
		conviction = "manaleech",
		dedication = "mitigation"
	},
	{
		domain = 1,
		maxPoints = 100,
		modType = 1,
		conviction = "vessel",
		dedication = "health"
	},
	{
		domain = 2,
		maxPoints = 100,
		conviction = "skill",
		dedication = "mana"
	},
	{
		domain = 2,
		maxPoints = 150,
		modType = 2,
		conviction = "vessel",
		dedication = "health"
	},
	{
		domain = 2,
		maxPoints = 200,
		conviction = "spell_1",
		dedication = "lifemana"
	},
	{
		domain = 1,
		maxPoints = 150,
		modType = 2,
		conviction = "vessel",
		dedication = "mitigation"
	},
	{
		domain = 1,
		maxPoints = 100,
		conviction = "spell_2",
		dedication = "health"
	},
	{
		domain = 1,
		maxPoints = 75,
		conviction = "lifeleech",
		dedication = "mana"
	},
	{
		domain = 2,
		maxPoints = 75,
		modType = 0,
		conviction = "vessel",
		dedication = "capacity"
	},
	{
		domain = 2,
		maxPoints = 100,
		conviction = "spell_3",
		dedication = "mana"
	},
	{
		domain = 2,
		maxPoints = 150,
		conviction = "manaleech",
		dedication = "health"
	},
	{
		domain = 1,
		maxPoints = 100,
		conviction = "spell_4",
		dedication = "health"
	},
	{
		domain = 1,
		maxPoints = 75,
		conviction = "skill",
		dedication = "mana"
	},
	{
		domain = 1,
		maxPoints = 50,
		modType = 0,
		conviction = "vessel",
		dedication = "capacity"
	},
	{
		domain = 2,
		maxPoints = 50,
		conviction = "spell_5",
		dedication = "mitigation"
	},
	{
		domain = 2,
		maxPoints = 75,
		conviction = "lifeleech",
		dedication = "capacity"
	},
	{
		domain = 2,
		maxPoints = 100,
		modType = 1,
		conviction = "vessel",
		dedication = "mana"
	},
	{
		domain = 3,
		maxPoints = 100,
		modType = 1,
		conviction = "vessel",
		dedication = "mitigation"
	},
	{
		domain = 3,
		maxPoints = 75,
		conviction = "manaleech",
		dedication = "health"
	},
	{
		domain = 3,
		maxPoints = 50,
		conviction = "spell_1",
		dedication = "mana"
	},
	{
		domain = 4,
		maxPoints = 50,
		modType = 0,
		conviction = "vessel",
		dedication = "health"
	},
	{
		domain = 4,
		maxPoints = 75,
		conviction = "skill",
		dedication = "mitigation"
	},
	{
		domain = 4,
		maxPoints = 100,
		conviction = "spell_2",
		dedication = "capacity"
	},
	{
		domain = 3,
		maxPoints = 150,
		conviction = "lifeleech",
		dedication = "capacity"
	},
	{
		domain = 3,
		maxPoints = 100,
		conviction = "spell_3",
		dedication = "mitigation"
	},
	{
		domain = 3,
		maxPoints = 75,
		modType = 0,
		conviction = "vessel",
		dedication = "health"
	},
	{
		domain = 4,
		maxPoints = 75,
		conviction = "manaleech",
		dedication = "mitigation"
	},
	{
		domain = 4,
		maxPoints = 100,
		conviction = "spell_4",
		dedication = "capacity"
	},
	{
		domain = 4,
		maxPoints = 150,
		modType = 2,
		conviction = "vessel",
		dedication = "mana"
	},
	{
		domain = 3,
		maxPoints = 200,
		conviction = "spell_5",
		dedication = "lifemana"
	},
	{
		domain = 3,
		maxPoints = 150,
		modType = 2,
		conviction = "vessel",
		dedication = "capacity"
	},
	{
		domain = 3,
		maxPoints = 100,
		conviction = "skill",
		dedication = "mitigation"
	},
	{
		domain = 4,
		maxPoints = 100,
		modType = 1,
		conviction = "vessel",
		dedication = "capacity"
	},
	{
		domain = 4,
		maxPoints = 150,
		conviction = "lifeleech",
		dedication = "mana"
	},
	{
		domain = 4,
		maxPoints = 200,
		conviction = "special_2",
		dedication = "lifemana"
	}
}
WheelDomainOrder = {
	[0] = {
		15,
		14,
		9,
		13,
		8,
		3,
		7,
		2,
		1
	},
	{
		16,
		10,
		17,
		4,
		11,
		18,
		5,
		12,
		6
	},
	{
		21,
		20,
		27,
		19,
		26,
		33,
		25,
		32,
		31
	},
	{
		22,
		23,
		28,
		24,
		29,
		34,
		30,
		35,
		36
	}
}

local function firstSpellIsUnlocked(attribute)
	return WheelOfDestiny.isLitFull(attribute[1]) or WheelOfDestiny.isLitFull(attribute[2])
end

local function secondSpellIsUnlocked(attribute)
	return WheelOfDestiny.isLitFull(attribute[1]) and WheelOfDestiny.isLitFull(attribute[2])
end
-- Augmented-spell conviction perks, one entry per (slice pair, vocation).
--
-- Opcode 0x5F carries only how many promotion points sit in each of the 36 slices; it never
-- says which perk a slice holds. That mapping is fixed by the official client's own grid table
-- (tibia::skillwheel::TGridConfiguration) and CrystalOTC mirrors it in WheelIcons. This table is
-- the matching one for the augment slices, and it is the single source of truth for all three
-- consumers below -- the selection panel, the tooltip and the Conviction Perks summary -- which
-- previously each carried their own copy and had drifted apart.
--
-- Slice pairs, in WheelBonus slot numbers (slot = official tile index + 1):
--   spell_1 = 6/21   spell_2 = 8/24   spell_3 = 11/26   spell_4 = 13/29   spell_5 = 16/31
--
-- Effect text mirrors what crystalserver actually grants in
-- src/io/io_wheel.cpp initialize<Vocation>Spells(). Change one, change the other.
--
-- Entries are positional in vocation order -- knight, paladin, sorcerer, druid, monk -- because
-- classes/icons.lua (which defines KNIGHT..MONK) loads after this file.
WheelAugments = {
	spell_1 = {
		{
			name = "Front Sweep",
			short = "Aug. Front Sweep",
			aug1 = "+40% Base Damage",
			aug2 = "Affected area enlarged"
		},
		{
			name = "Ethereal Barrage",
			short = "Aug. Ethereal Barrage",
			aug1 = "+10% Life Leech",
			aug2 = "+10% Critical Hit Chance"
		},
		{
			name = "Focus Spells",
			short = "Aug. Focus Spells",
			aug1 = "+5% Base Damage for Hell's Core and Rage of the Skies",
			aug2 = "-4s Cooldown; Focus secondary group cooldown -4s for Hell's Core and Rage of the Skies"
		},
		{
			name = "Forked Spells",
			short = "Aug. Forked Spells",
			aug1 = "-2s Cooldown",
			aug2 = "Adds +1 target"
		},
		{
			name = "Chained Penance",
			short = "Aug. Chained Penance",
			aug1 = "Jumps to +1 additional target",
			aug2 = "Jumps to +1 additional target"
		}
	},
	spell_2 = {
		{
			name = "Shield Slam",
			short = "Aug. Shield Slam",
			aug1 = "+15% Life Leech",
			aug2 = "Enemies hit deal 25% damage instead of 50% for the debuff's duration"
		},
		{
			name = "Strong Ethereal Spear",
			short = "Aug. Strong Eth. Spear",
			aug1 = "-2s Cooldown",
			aug2 = "+380% Base Damage"
		},
		{
			name = "Special Spells",
			short = "Aug. Special Spells",
			aug1 = "-4s Cooldown",
			aug2 = "+50% Base Damage"
		},
		{
			name = "Mass Healing",
			short = "Aug. Mass Healing",
			aug1 = "+4% Base Healing",
			aug2 = "Affected area enlarged"
		},
		{
			name = "Mass Spirit Mend",
			short = "Aug. Mass Spirit Mend",
			aug1 = "+8% Base Healing",
			aug2 = "-4s Cooldown"
		}
	},
	spell_3 = {
		{
			name = "Groundshaker",
			short = "Aug. Groundshaker",
			aug1 = "-2s Cooldown",
			aug2 = "+12.5% Base Damage"
		},
		{
			name = "Divine Dazzle",
			short = "Aug. Divine Dazzle",
			aug1 = "Jumps to +2 additional targets",
			aug2 = "Duration increased; -8s Cooldown"
		},
		{
			name = "Death Echo",
			short = "Aug. Death Echo",
			aug1 = "-2s Cooldown",
			aug2 = "+8% Base Damage"
		},
		{
			name = "Heal Friend",
			short = "Aug. Heal Friend",
			aug1 = "+4% Base Healing",
			aug2 = "+6% Base Healing"
		},
		{
			name = "Mystic Repulse",
			short = "Aug. Mystic Repulse",
			aug1 = "-6s Cooldown",
			aug2 = "+40% Base Damage"
		}
	},
	spell_4 = {
		{
			name = "Intense Wound Cleansing",
			short = "Aug. Intense Wound C.",
			aug1 = "+125% Base Healing",
			aug2 = "-60s Cooldown"
		},
		{
			name = "Divine Barrage",
			short = "Aug. Divine Barrage",
			aug1 = "+10% Base Damage",
			aug2 = "+15% Base Damage"
		},
		{
			name = "Energy Wave",
			short = "Aug. Energy Wave",
			aug1 = "Affected area enlarged",
			aug2 = "+10% Base Damage"
		},
		{
			name = "Terra Wave",
			short = "Aug. Terra Wave",
			aug1 = "+6.5% Base Damage",
			aug2 = "Adds 10% life leech to this spell"
		},
		{
			name = "Flurry of Blows",
			short = "Aug. Flurry of Blows",
			aug1 = "Affected area enlarged",
			aug2 = "+12% Base Damage"
		}
	},
	spell_5 = {
		{
			name = "Fierce Berserk",
			short = "Aug. Fierce Berserk",
			aug1 = "-30 Mana Cost",
			aug2 = "+10% Base Damage"
		},
		{
			name = "Divine Caldera",
			short = "Aug. Divine Caldera",
			aug1 = "-20 Mana Cost",
			aug2 = "+8.5% Base Damage"
		},
		{
			name = "Great Fire Wave",
			short = "Aug. Great Fire Wave",
			aug1 = "Adds 15% critical extra damage for this spell and grants a 10% chance (non-cumulative) for a critical hit.",
			aug2 = "+5% Base Damage"
		},
		{
			name = "Strong Ice Wave",
			short = "Aug. Strong Ice Wave",
			aug1 = "+6% Base Damage",
			aug2 = "Affected area enlarged"
		},
		{
			name = "Thousand Fist Blows",
			short = "Aug. Thousand Fist Blows",
			aug1 = "Adds 40% critical extra damage for this spell",
			aug2 = "-6s Cooldown"
		}
	}
}

local AUG_ACTIVE = "#C0C0C0"
local AUG_INACTIVE = "#707070"
local AUG_MARKER = "#FFFFFF"
local AUG_PANEL_WIDTH = 30

-- UIWidget:setColoredText takes "{text, colour}" markup, not the {text, colour, ...} array that
-- setStringColor builds. Passing the raw array casts to an empty string through lua_tolstring and
-- the panel renders blank, which is what used to happen to every augment slice.
function wheelColoredText(parts)
	if type(parts) ~= "table" then
		return parts or ""
	end

	local result = ""

	for i = 1, #parts, 2 do
		result = result .. "{" .. (parts[i] or "") .. ", " .. (parts[i + 1] or "#ffffff") .. "}"
	end

	return result
end

-- The conviction panels are fixed-size widgets with wrapping disabled, so long effect text has to
-- be broken by hand. `used` is how much of the first line the caller has already spent on a prefix.
local function wrapWheelText(text, width, used)
	local lines, current, length = {}, "", used or 0

	for word in string.gmatch(text, "%S+") do
		local separator = current == "" and "" or " "

		if length + #separator + #word > width and (current ~= "" or length > 0) then
			table.insert(lines, current)
			current, length = word, #word
		else
			current = current .. separator .. word
			length = length + #separator + #word
		end
	end

	table.insert(lines, current)

	return table.concat(lines, "\n")
end

-- Cut wrapped text to at most `maxLines` lines and mark the cut. Without this the overflow is
-- painted outside the fixed-size widget, where nothing can scroll to it.
local function clampWheelLines(text, maxLines)
	local lines = {}

	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if #lines >= maxLines then
			lines[#lines] = lines[#lines] .. "..."

			return table.concat(lines, "\n")
		end

		table.insert(lines, line)
	end

	return table.concat(lines, "\n")
end

local function countWheelLines(text)
	local _, breaks = string.gsub(text, "\n", "")

	return breaks + 1
end

-- Selection-panel body for an augment slice: the perk name, then bonus I and bonus II, each dimmed
-- until the slice pair that unlocks it is filled. Bonus I is capped short of the full budget so
-- that bonus II is always visible too; the tooltip carries the untruncated text.
function getWheelAugmentText(augment, attribute, points, maxPoints, maxLines)
	local first = firstSpellIsUnlocked(attribute)
	local second = secondSpellIsUnlocked(attribute)

	local name = wrapWheelText("Augmented " .. augment.name, AUG_PANEL_WIDTH, 0)
	local budget = math.max(2, maxLines - countWheelLines(name))
	local firstText = clampWheelLines(wrapWheelText(augment.aug1, AUG_PANEL_WIDTH, 3), math.max(1, budget - 2))
	local secondText = clampWheelLines(wrapWheelText(augment.aug2, AUG_PANEL_WIDTH, 4), math.max(1, budget - countWheelLines(firstText)))

	local parts = {}

	setStringColor(parts, name .. "\n", points >= maxPoints and AUG_ACTIVE or AUG_INACTIVE)
	setStringColor(parts, "I", first and AUG_MARKER or AUG_INACTIVE)
	setStringColor(parts, ": " .. firstText .. "\n", first and AUG_ACTIVE or AUG_INACTIVE)
	setStringColor(parts, "II", second and AUG_MARKER or AUG_INACTIVE)
	setStringColor(parts, ": " .. secondText, second and AUG_ACTIVE or AUG_INACTIVE)

	return parts
end

-- Tooltips wrap themselves and understand [color=#rrggbb] markup, so they need neither the manual
-- wrapping above nor the {text, colour} form.
function getWheelAugmentTooltip(augment, attribute)
	local first = firstSpellIsUnlocked(attribute)
	local second = secondSpellIsUnlocked(attribute)

	return "[color=" .. (first and AUG_MARKER or AUG_INACTIVE) .. "]I[/color] " .. augment.aug1 .. "\n[color=" .. (second and AUG_MARKER or AUG_INACTIVE) .. "]II[/color] " .. augment.aug2
end


function getDedicationBonus(index)
	local bonus = WheelBonus[index - 1]
	local vocation = WheelOfDestiny.vocationId
	local points = WheelOfDestiny.pointInvested[index]

	if not vocation or vocation == 0 then
		return
	end

	local attribute = WheelConsts[bonus.dedication]
	local vocationAttribute = 0

	if type(attribute) == "table" then
		vocationAttribute = attribute[vocation] or 0
	end

	if bonus.dedication == "capacity" then
		return string.format("+%d Capacity", points * vocationAttribute)
	elseif bonus.dedication == "mana" then
		return string.format("+%d Mana", points * vocationAttribute)
	elseif bonus.dedication == "health" then
		return string.format("+%d Hit Points", points * vocationAttribute)
	elseif bonus.dedication == "mitigation" then
		return string.format("%.2f%% Mitigation Multiplier", points * attribute)
	elseif bonus.dedication == "lifemana" then
		return string.format("+%d Hit Points\n+%d Mana", points * attribute.life[vocation], points * attribute.mana[vocation])
	end

	return ""
end

function getDedicationTooltip(index)
	local bonus = WheelBonus[index - 1]
	local vocation = WheelOfDestiny.vocationId
	local points = WheelOfDestiny.pointInvested[index]

	if not vocation or vocation == 0 then
		return ""
	end

	local attribute = WheelConsts[bonus.dedication]
	local vocationAttribute = 0

	if type(attribute) == "table" then
		vocationAttribute = attribute[vocation] or 0
	end

	if bonus.dedication == "capacity" then
		return string.format("Per promotion point:\n+%d Capacity", vocationAttribute)
	elseif bonus.dedication == "mana" then
		return string.format("Per promotion point:\n+%d Mana", vocationAttribute)
	elseif bonus.dedication == "health" then
		return string.format("Per promotion point:\n+%d Hit Points", vocationAttribute)
	elseif bonus.dedication == "mitigation" then
		return string.format("Increases your mitigation multiplicatively.\n\n%.2f%% Mitigation Multiplier", attribute)
	elseif bonus.dedication == "lifemana" then
		return string.format("Per promotion point:\n+%d Hit Points\n+%d Mana", attribute.life[vocation], attribute.mana[vocation])
	end

	return ""
end

function getConvictionBonusTooltip(index)
	local bonus = WheelBonus[index - 1]
	local vocation = WheelOfDestiny.vocationId
	local points = WheelOfDestiny.pointInvested[index]
	local attribute = WheelConsts[bonus.conviction]

	if bonus.conviction == "vessel" then
		local domain = bonus.domain

		if domain == 1 then
			return "Each level of Vessel Resonance unlocks equivalent Gem Mods in its\ndomain. If the Vessel Resonance matches the gem quality, a\ndamage and healing bonus is granted."
		elseif domain == 2 then
			return "Each level of Vessel Resonance unlocks equivalent Gem Mods in its\ndomain. If the Vessel Resonance matches the gem quality, a\ndamage and healing bonus is granted."
		elseif domain == 3 then
			return "Each level of Vessel Resonance unlocks equivalent Gem Mods in its\ndomain. If the Vessel Resonance matches the gem quality, a\ndamage and healing bonus is granted."
		elseif domain == 4 then
			return "Each level of Vessel Resonance unlocks equivalent Gem Mods in its\ndomain. If the Vessel Resonance matches the gem quality, a\ndamage and healing bonus is granted."
		end
	elseif bonus.conviction == "special_1" then
		if vocation == KNIGHT then
			return "Gain +6 shielding and +1 sword/axe/club fighting when 5\ncreatures are on adjacent squares.\nFor each additional creature, up to a maximum of 8, you get +6\nshielding and +1 sword/axe/club fighting more."
		elseif vocation == PALADIN then
			return "Gain +3 distance fighting while no monster is within 1 squares.\nOtherwise gain +3 holy magic level and +3 healing magic level."
		elseif vocation == SORCERER then
			return "If you use a rune, you have a 25% chance of increasing your magic\nlevel by 10%, or by 20% if you use a rune that can be created by\nyour vocation."
		elseif vocation == DRUID then
			return "If you heal someone with Nature's Embrace or Heal Friend, you\nalso heal yourself for 10% of the applied healing."
		elseif vocation == MONK then
			return "Gain an aura that shares 50% of your\nmantra with members of your group."
		end
	elseif bonus.conviction == "special_2" then
		if vocation == KNIGHT then
			return "For each creature challenged, you will heal yourself for a small\namount. This amount scales with your shielding skill. Heals for\ndouble the amount if you have less than 60% of your hit points and\ntriple the amount if you have less than 30% of your hit points."
		elseif vocation == PALADIN then
			return "The critical extra damage for attacks with a crossbow is increased\nby 10%. While wielding a bow your attacks and spells treat the\ntargets physical and holy sensitivity as being 2% higher."
		elseif vocation == SORCERER then
			return "Increases the damage of your next damage spell by 35% within 12\nseconds after casting a focus spell."
		elseif vocation == DRUID then
			return "If you use a rune, you have a 25% chance of increasing your magic\nlevel by 10%, or by 20% if you use a rune that can be created by\nyour vocation."
		elseif vocation == MONK then
			return "Consuming Harmony creates a field lasting 5 seconds, increasing\nyour damage and healing done by 2% for each Harmony\nconsumed."
		end
	elseif WheelAugments[bonus.conviction] then
		local augment = WheelAugments[bonus.conviction][vocation]

		if augment then
			return getWheelAugmentTooltip(augment, attribute)
		end
	elseif bonus.conviction == "skill" then
		-- Only the knight's weapon skill carries extra detail; the other four skill boosts and both
		-- leeches have no long description on the official wheel either.
		if vocation == KNIGHT then
			return "Applies to sword, axe and club fighting"
		end
	end

	return ""
end

function getConvictionBonus(index, fullMessage)
	local bonus = WheelBonus[index - 1]
	local vocation = WheelOfDestiny.vocationId
	local points = WheelOfDestiny.pointInvested[index]
	local attribute = WheelConsts[bonus.conviction]

	if bonus.conviction == "vessel" then
		local domain = bonus.domain

		if domain == 1 then
			if not fullMessage then
				return "Vessel Resonance Top Left\nEach level of Vessel\nResonance unlocks equivalent\nGem Mods in its domain. If the\nVessel Resonance matches t..."
			else
				return "Vessel Resonance Top Left\nEach level of Vessel\nResonance unlocks equivalent\nGem Mods in its domain. If the\nVessel Resonance matches\nthe gem quality, a damage\nand healing bonus is granted."
			end
		elseif domain == 2 then
			if not fullMessage then
				return "Vessel Resonance Top Right\nEach level of Vessel\nResonance unlocks equivalent\nGem Mods in its domain. If the\nVessel Resonance matches t..."
			else
				return "Vessel Resonance Top Right\nEach level of Vessel\nResonance unlocks equivalent\nGem Mods in its domain. If the\nVessel Resonance matches\nthe gem quality, a damage\nand healing bonus is granted."
			end
		elseif domain == 3 then
			if not fullMessage then
				return "Vessel Resonance Bottom Left\nEach level of Vessel\nResonance unlocks equivalent\nGem Mods in its domain. If the\nVessel Resonance matches t..."
			else
				return "Vessel Resonance Bottom Left\nEach level of Vessel\nResonance unlocks equivalent\nGem Mods in its domain. If the\nVessel Resonance matches\nthe gem quality, a damage\nand healing bonus is granted."
			end
		elseif domain == 4 then
			if not fullMessage then
				return "VR Bottom Right\nEach level of Vessel\nResonance unlocks equivalent\nGem Mods in its domain. If the\nVessel Resonance matches t..."
			else
				return "VR Bottom Right\nEach level of Vessel\nResonance unlocks equivalent\nGem Mods in its domain. If the\nVessel Resonance matches\nthe gem quality, a damage\nand healing bonus is granted."
			end
		end
	elseif bonus.conviction == "skill" then
		if vocation == KNIGHT then
			return string.format("+%d Weapon Skill Boost\nApplies to sword, axe and club\nfighting", attribute)
		elseif vocation == PALADIN then
			return string.format("+%d Distance Skill Boost", attribute)
		elseif vocation == SORCERER or vocation == DRUID then
			return string.format("+%d Magic Skill Boost", attribute)
		elseif vocation == MONK then
			return string.format("+%d Fist Fighting Skill Boost", attribute)
		end
	elseif bonus.conviction == "lifeleech" then
		return string.format("+%.2f%% Life Leech", attribute)
	elseif bonus.conviction == "manaleech" then
		return string.format("+%.2f%% Mana Leech", attribute)
	elseif WheelAugments[bonus.conviction] then
		local augment = WheelAugments[bonus.conviction][vocation]

		if augment then
			-- The selection panel is 185x80 and the info tab 185x105, at a 13px line height.
			return getWheelAugmentText(augment, attribute, points, bonus.maxPoints, fullMessage and 8 or 6)
		end
	elseif bonus.conviction == "special_1" then
		if vocation == KNIGHT then
			if not fullMessage then
				return "Battle Instinct\nGain +6 shielding and +1\nsword/axe/club fighting when\n5 creatures are on adjacent\nsquares..."
			else
				return "Battle Instinct\nGain +6 shielding and +1\nsword/axe/club fighting when\n5 creatures are on adjacent\nsquares.\nFor each additional creature,\nup to a maximum of 8, you get\n+6 shielding and +1 sword/\naxe/club fighting more."
			end
		elseif vocation == PALADIN then
			if not fullMessage then
				return "Positional Tactics\nGain +3 distance fighting\nwhile no monster is within 1\nsquares. Otherwise gain +3\nholy magic level and +3 hea..."
			else
				return "Positional Tactics\nGain +3 distance fighting\nwhile no monster is within 1\nsquares. Otherwise gain +3\nholy magic level and +3\nhealing magic level."
			end
		elseif vocation == SORCERER then
			if not fullMessage then
				return "Runic Mastery\nIf you use a rune, you have a\n25% chance of increasing\nyour magic level by 10%, or\nby 20% if you use a rune th..."
			else
				return "Runic Mastery\nIf you use a rune, you have a\n25% chance of increasing\nyour magic level by 10%, or\nby 20% if you use a rune that\ncan be created by your\nvocation."
			end
		elseif vocation == DRUID then
			if not fullMessage then
				return "Healing Link\nIf you heal someone with\nNature's Embrace or Heal\nFriend, you also heal yourself\nfor 10% of the applied heali..."
			else
				return "Healing Link\nIf you heal someone with\nNature's Embrace or Heal\nFriend, you also heal yourself\nfor 10% of the applied\nhealing."
			end
		elseif vocation == MONK then
			if not fullMessage then
				return "Guiding Presence\nGain an aura that shares 50% of your\nmantra with members of your\ngroup."
			else
				return "Guiding Presence\nGain an aura that shares 50% of your\nmantra with members of your\ngroup."
			end
		end
	elseif bonus.conviction == "special_2" then
		if vocation == KNIGHT then
			if not fullMessage then
				return "Battle Healing\nFor each creature challenged,\nyou will heal yourself for a\nsmall amount. This amount\nscales with your shielding s..."
			else
				return "Battle Healing\nFor each creature challenged,\nyou will heal yourself for a\nsmall amount. This amount\nscales with your shielding\nskill. Heals for double the\namount if you have less than\n60% of your hit points and\ntriple the amount if you hav..."
			end
		elseif vocation == PALADIN then
			if not fullMessage then
				return "Ballistic Mastery\nThe critical extra damage for\nattacks with a crossbow is\nincreased by 10%.\nWhile wielding a bow your a..."
			else
				return "Ballistic Mastery\nThe critical extra damage for\nattacks with a crossbow is\nincreased by 10%.\nWhile wielding a bow your\nattacks and spells treat the\ntargets physical and holy\nsensitivity as being 2%\nhigher."
			end
		elseif vocation == SORCERER then
			return "Focus Mastery\nIncreases the damage of your\nnext damage spell by 35%\nwithin 12 seconds after\ncasting a focus spell."
		elseif vocation == DRUID then
			if not fullMessage then
				return "Runic Mastery\nIf you use a rune, you have a\n25% chance of increasing\nyour magic level by 10%, or\nby 20% if you use a rune th..."
			else
				return "Runic Mastery\nIf you use a rune, you have a\n25% chance of increasing\nyour magic level by 10%, or\nby 20% if you use a rune that\ncan be created by your\nvocation."
			end
		elseif vocation == MONK then
			if not fullMessage then
				return "Sanctuary\nConsuming Harmony creates\na field lasting 5 seconds,\nincreasing damage and..."
			else
				return "Sanctuary\nConsuming Harmony creates\na field lasting 5 seconds,\nincreasing your damage and\nhealing done by 2% for each\nHarmony consumed."
			end
		end
	end

	return ""
end

function getConvictionPerks()
	local convictions = {}
	local vocation = WheelOfDestiny.vocationId
	-- Position of each conviction perk in the returned list. These numbers are load-bearing: the
	-- Summary tab in wheelclass.lua indexes this result directly. They must stay dense, because a
	-- hole makes `#convictions` stop early and the Conviction Perks scrollbar never appear.
	local order = {
		special_1 = 1,
		special_2 = 2,
		skill = 3,
		lifeleech = 4,
		manaleech = 5,
		spell_1 = 6,
		spell_2 = 7,
		spell_3 = 8,
		spell_4 = 9,
		spell_5 = 10,
		["vessel.1"] = 11,
		["vessel.2"] = 12,
		["vessel.3"] = 13,
		["vessel.4"] = 14
	}

	for id, bonus in pairs(WheelBonus) do
		local index = id + 1

		if not WheelOfDestiny.isLit(index) then
			-- block empty
		else
			local t = order[bonus.conviction] or table.size(order) + 1
			local attribute = WheelConsts[bonus.conviction]
			local pointsInvested = WheelOfDestiny.pointInvested[index] or 0

			if pointsInvested ~= bonus.maxPoints then
				-- block empty
			elseif bonus.conviction == "special_1" then
				convictions[t] = {
					perk = attribute[vocation][1],
					tooltip = attribute[vocation][2]
				}
			elseif bonus.conviction == "special_2" then
				convictions[t] = {
					perk = attribute[vocation][1],
					tooltip = attribute[vocation][2]
				}
			elseif bonus.conviction == "manaleech" then
				if not convictions[t] then
					convictions[t] = {
						points = 0,
						perk = "Mana Leech",
						stringPoint = ""
					}
				end

				convictions[t].points = convictions[t].points + attribute
				convictions[t].stringPoint = string.format("+%.2f%%", convictions[t].points)
			elseif bonus.conviction == "lifeleech" then
				if not convictions[t] then
					convictions[t] = {
						points = 0,
						perk = "Life Leech",
						stringPoint = ""
					}
				end

				convictions[t].points = convictions[t].points + attribute
				convictions[t].stringPoint = string.format("+%.2f%%", convictions[t].points)
			elseif bonus.conviction == "vessel" then
				t = "vessel." .. bonus.domain
				t = order[t]

				if bonus.domain == 1 then
					if not convictions[t] then
						convictions[t] = {
							points = 0,
							perk = "VR Top Left",
							stringPoint = "I"
						}
					end

					convictions[t].points = convictions[t].points + 1

					if convictions[t].points == 1 then
						convictions[t].stringPoint = "I"
					elseif convictions[t].points == 2 then
						convictions[t].stringPoint = "II"
					else
						convictions[t].stringPoint = "III"
					end
				elseif bonus.domain == 2 then
					if not convictions[t] then
						convictions[t] = {
							points = 0,
							perk = "VR Top Right",
							stringPoint = "I"
						}
					end

					convictions[t].points = convictions[t].points + 1

					if convictions[t].points == 1 then
						convictions[t].stringPoint = "I"
					elseif convictions[t].points == 2 then
						convictions[t].stringPoint = "II"
					else
						convictions[t].stringPoint = "III"
					end
				elseif bonus.domain == 3 then
					if not convictions[t] then
						convictions[t] = {
							points = 0,
							perk = "VR Bottom Left",
							stringPoint = "I"
						}
					end

					convictions[t].points = convictions[t].points + 1

					if convictions[t].points == 1 then
						convictions[t].stringPoint = "I"
					elseif convictions[t].points == 2 then
						convictions[t].stringPoint = "II"
					else
						convictions[t].stringPoint = "III"
					end
				else
					if not convictions[t] then
						convictions[t] = {
							points = 0,
							perk = "VR Bottom Right",
							stringPoint = "I"
						}
					end

					convictions[t].points = convictions[t].points + 1

					if convictions[t].points == 1 then
						convictions[t].stringPoint = "I"
					elseif convictions[t].points == 2 then
						convictions[t].stringPoint = "II"
					else
						convictions[t].stringPoint = "III"
					end
				end

				convictions[t].tooltip = "Each level of Vessel Resonance unlocks equivalent Gem Mods in its\ndomain. If the Vessel Resonance matches the gem quality, a\ndamage and healing bonus is granted."
			elseif bonus.conviction == "skill" then
				if not convictions[t] then
					convictions[t] = {
						points = 0,
						perk = "",
						stringPoint = ""
					}
				end

				if vocation == KNIGHT then
					convictions[t].perk = "Weapon Skill Boost"
					convictions[t].points = convictions[t].points + attribute
					convictions[t].stringPoint = string.format("+%d", convictions[t].points)
					convictions[t].tooltip = "Applies to sword, axe and club fighting"
				elseif vocation == PALADIN then
					convictions[t].perk = "Distance Skill Boost"
					convictions[t].points = convictions[t].points + attribute
					convictions[t].stringPoint = string.format("+%d", convictions[t].points)
				elseif vocation == SORCERER or vocation == DRUID then
					convictions[t].perk = "Magic Skill Boost"
					convictions[t].points = convictions[t].points + attribute
					convictions[t].stringPoint = string.format("+%d", convictions[t].points)
				elseif vocation == MONK then
					convictions[t].perk = "Fist Fighting Skill Boost"
					convictions[t].points = convictions[t].points + attribute
					convictions[t].stringPoint = string.format("+%d", convictions[t].points)
				end
			elseif WheelAugments[bonus.conviction] then
				local augment = WheelAugments[bonus.conviction][vocation]

				if augment then
					if not convictions[t] then
						convictions[t] = {
							points = 0,
							perk = augment.short,
							stringPoint = ""
						}
					end

					convictions[t].points = convictions[t].points + 1
					convictions[t].stringPoint = convictions[t].points == 1 and "I" or "II"
					convictions[t].tooltip = getWheelAugmentTooltip(augment, attribute)
				end
			end
		end
	end

	return convictions
end

function getPassiveInfo(domain)
	local extraPoints = WheelOfDestiny.extraPassivePoints[domain] or 0
	local passive = WheelOfDestiny.passivePoints[domain] + extraPoints
	local message = {}

	local function currentUnlocked(i)
		if passive >= 1000 and i == 3 then
			return true
		elseif passive >= 500 and passive < 1000 and i == 2 then
			return true
		elseif passive >= 250 and passive < 500 and i == 1 then
			return true
		else
			return false
		end
	end

	local m1 = ""
	local m2 = ""
	local vocation = WheelOfDestiny.vocationId

	if domain == 1 then
		setStringColor(message, "If an attack (except with agony damage) were to kill you but the\noverkill damage amounts to less than ", "#3F3F3F")
		setStringColor(message, "20%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "/", "#3F3F3F")
		setStringColor(message, "25%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "/", "#3F3F3F")
		setStringColor(message, "30% ", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "of your\nmaximum hit points, you will heal yourself for ", "#3F3F3F")
		setStringColor(message, "20%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "/", "#3F3F3F")
		setStringColor(message, "25%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "/", "#3F3F3F")
		setStringColor(message, "30% ", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
		setStringColor(message, " of\nyour maximum hit points. Only after that is the damage applied.\nIn addition, all your spell cooldowns are reduced by 60 seconds.\n\nCooldown: ", "#3F3F3F")
		setStringColor(message, "30h", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "/", "#3F3F3F")
		setStringColor(message, "20h", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "/", "#3F3F3F")
		setStringColor(message, "10h ", currentUnlocked(3) and "#ffffff" or "#3F3F3F")

		m1 = "Gift of Life\nAllows you to survive an\notherwise fatal blow."
		m2 = message
	elseif domain == 2 then
		if vocation == KNIGHT then
			m1 = "Executioner's Throw\nThrowing attack that deals\nmassive damage to enemies\nwith low hit points."

			setStringColor(message, "This spell throws your weapon on your target and jumps on ", "#3F3F3F")
			setStringColor(message, "2", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "3", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "4\n ", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "nearby enemies. Deals ", "#3F3F3F")
			setStringColor(message, "100%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "125%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "150%  ", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "additional damage to\ntargets with less than 30% of their hit points.\nCooldown: ", "#3F3F3F")
			setStringColor(message, "18", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "14", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "10", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " seconds", "#3F3F3F")

			m2 = message
		elseif vocation == PALADIN then
			setStringColor(message, "This spell plants a marker at the feet of your target that explodes\nafter 3 seconds, dealing holy damage. +16% Base Damage with\nhigher spell stages.\n\nCooldown: ", "#3F3F3F")
			setStringColor(message, "26", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "20", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "14", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " seconds", "#3F3F3F")

			m1 = "Divine Grenade\nDeploy a powerful delayed\neffect that deals holy damage."
			m2 = message
		elseif vocation == SORCERER then
			setStringColor(message, "This beam spell deals death damage. Damage and length increase\nwith higher spell stages.\nCooldown: ", "#3F3F3F")
			setStringColor(message, "10", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "8", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "6", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " seconds\n\nIn addition, for each target hit by a beam spell, the cooldown of all\nother spells is reduced by 1 sec (up to a maximum of 3 sec) and\nthe damage of beam spells is increased by ", "#3F3F3F")
			setStringColor(message, "10%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "12%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "14%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " (up to\na maximum of ", "#3F3F3F")
			setStringColor(message, "30%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "36%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "42%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, ").", "#3F3F3F")

			m1 = "Beam Mastery\nBoosts all of your beam spells\nand unlocks a beam spell that\ndeals death damage."
			m2 = message
		elseif vocation == DRUID then
			setStringColor(message, "You healing is increased by\n", "#3F3F3F")
			setStringColor(message, "6%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "9%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "12%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "if the target has less\nthan 60% but more than 30% of\ntheir hit points.\n", "#3F3F3F")
			setStringColor(message, "You healing is increased by\n", "#3F3F3F")
			setStringColor(message, "12%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "18%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "24%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "if the target has less\nthan 30% of their hit points.", "#3F3F3F")

			m1 = "Blessing of the Grove\nIncreases your healing if the target's\nmissing hit points is below certain \nthresholds."
			m2 = message
		elseif vocation == MONK then
			setStringColor(message, "This spell consumes your Harmony. Releases a massive attack\nchaining to ", "#3F3F3F")
			setStringColor(message, "7", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " additional enemies. When used with full Harmony,\n", "#3F3F3F")
			setStringColor(message, "repeats after 1 second for ", "#3F3F3F")
			setStringColor(message, "37.5%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "50%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "62.5%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " of its original\ndamage. Cooldown: ", "#3F3F3F")
			setStringColor(message, "24", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "20", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "16", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " seconds.", "#3F3F3F")

			m1 = "Spiritual Outburst\nA powerful spell that consumes\nHarmony to release a massive\nchain attack."
			m2 = message
		end
	elseif domain == 3 then
		if vocation == KNIGHT then
			setStringColor(message, "Increases the defence value of shields by ", "#3F3F3F")
			setStringColor(message, "10", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "20", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "30.\n", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "Increases your critical extra damage by ", "#3F3F3F")
			setStringColor(message, "4%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "8%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "12%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " while\nwielding a two-handed weapon.", "#3F3F3F")

			m1 = "Combat Mastery\nImprove your combat\nprowess based on the\nequipment you use."
			m2 = message
		elseif vocation == PALADIN then
			setStringColor(message, "This support spell creates a field of holy energy around your feet\nfor 5 seconds. As long as you stand in this field, your dealt damage\nincreases by ", "#3F3F3F")
			setStringColor(message, "8%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "10%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "12%.\n\n", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "Cooldown: ", "#3F3F3F")
			setStringColor(message, "32", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "28", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "24", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "seconds", "#3F3F3F")

			m1 = "Divine Empowerment\nThis support spell creates a\nfield that increases your dealt\ndamage."
			m2 = message
		elseif vocation == SORCERER then
			-- Lord of Destruction replaced Drain Body; values mirror combat.cpp applyElementalStance.
			setStringColor(message, "Grants ", "#3F3F3F")
			setStringColor(message, "2%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "3%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "4%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " more fire damage for Master of Flames,\n", "#3F3F3F")
			setStringColor(message, "2%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "3%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "4%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " more critical hit chance for Master of\nThunder and ", "#3F3F3F")
			setStringColor(message, "15%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "22.5%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "30%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " more critical damage for Master of Decay.", "#3F3F3F")

			m1 = "Lord of Destruction\nImprove damage, critical hit\nchance and critical damage for\nspells with the damage type of\nyour elemental stance."
			m2 = message
		elseif vocation == DRUID then
			setStringColor(message, "Decide wisely whether you want to cast ice or earth damage in a\nsmall area around you, as these two ring spells share the same\ncooldown. Both spells deal ", "#3F3F3F")
			setStringColor(message, "20%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "40%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "60%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " additional damage to\ntargets with more than 60% of their hit points.\nCooldown: ", "#3F3F3F")
			setStringColor(message, "22", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "18", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "14", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " seconds", "#3F3F3F")

			m1 = "Twin Bursts\nPowerful ring spell that deals\nice or earth damage that is\nenhanced against targets with\nhigh hit points."
			m2 = message
		elseif vocation == MONK then
			setStringColor(message, "Increases the Harmony base bonus by ", "#3F3F3F")
			setStringColor(message, "1%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "2%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "3%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " and your\nautoattacks deal additional damage equal to ", "#3F3F3F")
			setStringColor(message, "100%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "200%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
			setStringColor(message, "/", "#3F3F3F")
			setStringColor(message, "300%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
			setStringColor(message, " of\nyour mantra.", "#3F3F3F")

			m1 = "Ascetic\nImprove all spenders and allows\nmantra to improve the damage\nof your attacks."
			m2 = message
		end
	elseif domain == 4 then
		setStringColor(message, "This spell transforms yourself into a powerful avatar for 15 \nseconds.\nWhile in this form, you benefit from ", "#3F3F3F")
		setStringColor(message, "5%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "/", "#3F3F3F")
		setStringColor(message, "10%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "/", "#3F3F3F")
		setStringColor(message, "15%", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
		setStringColor(message, " damage \nreduction and all your attacks are critical hits with ", "#3F3F3F")
		setStringColor(message, "5%", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "/", "#3F3F3F")
		setStringColor(message, "10%", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "/", "#3F3F3F")
		setStringColor(message, "15%\n", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "critical extra damage.\nCooldown: ", "#3F3F3F")
		setStringColor(message, "120", currentUnlocked(1) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "/", "#3F3F3F")
		setStringColor(message, "90", currentUnlocked(2) and "#ffffff" or "#3F3F3F")
		setStringColor(message, "/", "#3F3F3F")
		setStringColor(message, "60", currentUnlocked(3) and "#ffffff" or "#3F3F3F")
		setStringColor(message, " minutes", "#3F3F3F")

		if vocation == KNIGHT then
			m1 = "Avatar of Steel\nTransforms you into a\npowerful form that reduces\ndamage taken and increases\ndamage dealt."
			m2 = message
		elseif vocation == PALADIN then
			m1 = "Avatar of Light\nTransforms you into a\npowerful form that reduces\ndamage taken and increases\ndamage dealt."
			m2 = message
		elseif vocation == SORCERER then
			m1 = "Avatar of Storm\nTransforms you into a\npowerful form that reduces\ndamage taken and increases\ndamage dealt."
			m2 = message
		elseif vocation == DRUID then
			m1 = "Avatar of Nature\nTransforms you into a\npowerful form that reduces\ndamage taken and increases\ndamage dealt."
			m2 = message
		elseif vocation == MONK then
			m1 = "Avatar of Balance\nTransforms you into a\npowerful form that reduces\ndamage taken and increases\ndamage dealt."
			m2 = message
		end
	end

	return m1, m2
end

function getRevelationDisplayName(domain)
	local title = select(1, getPassiveInfo(domain))

	return title:match("^([^\n]+)") or title
end

function getBonusValueUpgrade(currentBonusID, gemID, supreme, firstBonus)
	local gem = GemAtelier.getGemDataById(gemID)

	if not gem then
		return 0
	end

	local slot = 0

	if gem.lesserBonus == currentBonusID then
		slot = 0
	elseif gem.regularBonus == currentBonusID then
		slot = 1
	elseif gem.supremeBonus == currentBonusID then
		slot = 2
	end

	local effectiveLevel = GemAtelier.getEffectiveLevel(gem, currentBonusID, supreme, slot)
	local modInfo = Workshop.getDataByBonus(currentBonusID, supreme)
	local bonus = Workshop.getBonusValue(modInfo, effectiveLevel, firstBonus)

	return bonus
end

function getValueByVocation(bonusType, steps)
	local step = bonusStep[WheelOfDestiny.vocationId]
	local bonus = 0

	if bonusType == "mana" then
		bonus = steps * step.mana
	elseif bonusType == "life" then
		bonus = steps * step.life
	elseif bonusType == "capacity" then
		bonus = steps * step.capacity
	end

	return bonus
end

function getVesselBonus()
	local bonuses = {}
	local defenses = {}

	local function findBonusByText(text)
		for i, b in ipairs(bonuses) do
			if b.text == text then
				return b, i
			end
		end

		return nil
	end

	local function findDefenseByText(text)
		for i, b in ipairs(defenses) do
			if b.text == text then
				return b, i
			end
		end

		return nil
	end

	for _, k in pairs(WheelOfDestiny.equipedGemBonuses) do
		if k.bonusID == -1 then
			-- block empty
		else
			local bonus = k.supreme and SupremeGemDescription[k.bonusID] or RegularGemDescription[k.bonusID]
			local firstString, secondString
			local skipIndex = bonus.text:find("\n")

			if skipIndex then
				firstString = bonus.text:sub(1, skipIndex - 1)
				secondString = bonus.text:sub(skipIndex + 1)
			else
				firstString = bonus.text
			end

			if not k.supreme then
				if firstString then
					if firstString:find("Mitigation") then
						local number = getBonusValueUpgrade(k.bonusID, k.gemID, k.supreme, true)
						local existingBonus = findBonusByText("Mitigation Mult.")

						if existingBonus then
							existingBonus.value = existingBonus.value + tonumber(number)
						else
							bonuses[#bonuses + 1] = {
								text = "Mitigation Mult.",
								bonusType = bonus.type1,
								value = number,
								tooltip = bonus.tooltip
							}
						end

						goto label_13_0
					end

					local number = getBonusValueUpgrade(k.bonusID, k.gemID, k.supreme, true)
					local message = firstString:match("@%s*(.+)")

					if bonus.type1 == "defense" then
						number = getBonusValueUpgrade(k.bonusID, k.gemID, k.supreme, true)
						message = firstString:gsub("^%+%s*%% ", "")
					end

					local existingBonus = findBonusByText(message)

					if bonus.type1 == "defense" then
						existingBonus = findDefenseByText(message)
					end

					if existingBonus then
						existingBonus.value = existingBonus.value + tonumber(number)
					elseif bonus.type1 == "defense" then
						defenses[#defenses + 1] = {
							bonusType = bonus.type1,
							text = message,
							value = number
						}
					else
						bonuses[#bonuses + 1] = {
							bonusType = bonus.type1,
							text = message,
							value = "+" .. number
						}
					end
				end

				if secondString then
					local number = getBonusValueUpgrade(k.bonusID, k.gemID, k.supreme, false)
					local message = secondString:match("@%s*(.+)")

					if bonus.type2 == "defense" then
						if bonus.bonus2 and bonus.bonus2 == -1 then
							number, message = secondString:match("([-]?%d+%.?%d*)%% (.+)")
						else
							number = getBonusValueUpgrade(k.bonusID, k.gemID, k.supreme, false)
							message = secondString:gsub("^%+%s*%% ", "")
						end
					end

					local existingBonus = findBonusByText(message)

					if bonus.type2 == "defense" then
						existingBonus = findDefenseByText(message)
					end

					if existingBonus then
						existingBonus.value = existingBonus.value + tonumber(number)
					elseif bonus.type2 == "defense" then
						defenses[#defenses + 1] = {
							bonusType = bonus.type2,
							text = message,
							value = number
						}
					else
						bonuses[#bonuses + 1] = {
							bonusType = bonus.type2,
							text = message,
							value = "+" .. number
						}
					end
				end
			elseif bonus.text:find("RM") then
				local number = getBonusValueUpgrade(k.bonusID, k.gemID, k.supreme, true)
				local existingBonus = findBonusByText(short_text(bonus.text, 17))

				if existingBonus then
					existingBonus.value = existingBonus.value + tonumber(number)
				else
					bonuses[#bonuses + 1] = {
						bonusType = "revelation",
						text = short_text(bonus.text, 17),
						value = number,
						tooltip = bonus.tooltip
					}
				end
			elseif not bonus.text:find("\n") then
				local number, message = firstString:match("([-]?%d+%.?%d*)%% (.+)")
				local existingBonus = findBonusByText(message)

				if existingBonus then
					existingBonus.value = existingBonus.value + tonumber(number)
				else
					bonuses[#bonuses + 1] = {
						bonusType = "special",
						text = message,
						value = number
					}
				end
			elseif bonus.text:find("Aug.") then
				local bonusName = firstString
				local number = getBonusValueUpgrade(k.bonusID, k.gemID, k.supreme, true)
				local tooltip = bonus.tooltip

				bonusName = bonusName:gsub("Aug. ", "")

				if vocation == 5 and bonusName == "Greater Flurry of Blows" then
					tooltip = string.format("+%d%% Base Damage", number)
				end

				local existingBonus = findBonusByText(bonusName)

				if existingBonus then
					existingBonus.value = existingBonus.value + tonumber(number)

					if string.find(tooltip, "%%") then
						existingBonus.tooltip = tr(tooltip, existingBonus.value)
					end
				else
					if string.find(tooltip, "%%") then
						tooltip = tr(tooltip, number)
					end

					bonuses[#bonuses + 1] = {
						bonusType = "augment",
						text = short_text(bonusName, 15),
						value = number,
						tooltip = tooltip
					}
				end
			end
		end

		::label_13_0::
	end

	if #defenses > 0 then
		bonuses[#bonuses + 1] = {
			text = "Resistances:",
			bonusType = "defense",
			value = -1
		}
	end

	for _, v in pairs(defenses) do
		if v.value == 0 then
			-- block empty
		else
			local valueString = tonumber(v.value) > 0 and "+" .. v.value or v.value

			bonuses[#bonuses + 1] = {
				bonusType = v.bonusType,
				text = "  " .. v.text:gsub(" Resistance", ""),
				value = valueString .. "%"
			}
		end
	end

	local DHcount = GemAtelier:getDamageAndHealing()

	if DHcount > 0 then
		table.insert(bonuses, 1, {
			text = "Damage and Healing",
			tooltip = "If the Vessel Resonance matches the gem quality in this domain, a\nbonus of +1 to all damage and healing is granted. This bonus is\nincreased by 1 for greater gems.\n\nRegardless of the match, gems will always grant mod bonuses\nbased on the Vessel Resonance.\n? Lesser gems match Dormant Vessels (VR I)\n? Regular gems match Awakened Vessels (VR II)\n? Greater gems match Radiant Vessels (VR III)",
			bonusType = "damagehealing",
			value = "+" .. DHcount
		})
	end

	return bonuses
end
