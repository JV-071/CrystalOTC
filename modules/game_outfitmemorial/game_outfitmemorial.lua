-- chunkname: @/game_outfitmemorial/game_outfitmemorial.lua

-- Golden Outfit and Royal Costume memorial (S2C 0xB0, sent when a memorial item is used).
-- Index 1 is the basic outfit, 2 the outfit with one addon and 3 the full outfit.

outfitMemorialWindow = nil

local TAB_GOLDEN = 1
local TAB_ROYAL = 2

local memorialData
local activeTab = TAB_GOLDEN

local tabTexts = {
	[TAB_GOLDEN] = {
		header = "The following characters have spent a fortune on a Golden Outfit:",
		empty = "The Golden Outfit has not been acquired by anyone yet."
	},
	[TAB_ROYAL] = {
		header = "The following characters have spent a fortune on a Royal Costume:",
		empty = "The Royal Costume has not been acquired by anyone yet."
	}
}

local sectionNames = {
	[1] = "Basic Outfit",
	[2] = "With One Addon",
	[3] = "Full Outfit"
}

local function formatNumber(value)
	return comma_value(tostring(tonumber(value) or 0))
end

local function getWidget(id)
	if not outfitMemorialWindow or outfitMemorialWindow:isDestroyed() then
		return nil
	end

	return outfitMemorialWindow:recursiveGetChildById(id)
end

local function sectionPrice(tab, index)
	if tab == TAB_GOLDEN then
		return tr("%s for %s gold:", tr(sectionNames[index]), formatNumber(memorialData.goldenPrices[index]))
	end

	local price = memorialData.royalPrices[index] or {}

	return tr("%s for %s Silver Tokens and %s Gold Tokens:", tr(sectionNames[index]), formatNumber(price[1]), formatNumber(price[2]))
end

local function buildText(tab)
	local owners = tab == TAB_GOLDEN and memorialData.goldenOwners or memorialData.royalOwners
	local hasAny = false

	for index = 1, 3 do
		if #(owners[index] or {}) > 0 then
			hasAny = true

			break
		end
	end

	if not hasAny then
		return tr(tabTexts[tab].empty)
	end

	local lines = { tr(tabTexts[tab].header), "" }

	-- Most expensive first, like the official dialog.
	for index = 3, 1, -1 do
		local names = owners[index] or {}

		if #names > 0 then
			table.insert(lines, sectionPrice(tab, index))

			for _, name in ipairs(names) do
				table.insert(lines, "- " .. name)
			end

			table.insert(lines, "")
		end
	end

	return table.concat(lines, "\n")
end

local function refresh()
	if not memorialData then
		return
	end

	local goldenTab = getWidget("goldenOutfitTab")
	local royalTab = getWidget("royalCostumeTab")

	if goldenTab then
		goldenTab:setChecked(activeTab == TAB_GOLDEN)
	end

	if royalTab then
		royalTab:setChecked(activeTab == TAB_ROYAL)
	end

	local textWidget = getWidget("memorialText")

	if textWidget then
		textWidget:setText(buildText(activeTab))
		textWidget:setCursorPos(0)

		local scroll = getWidget("memorialScroll")

		if scroll then
			scroll:setValue(0)
		end
	end
end

local function destroyWindow()
	if outfitMemorialWindow and not outfitMemorialWindow:isDestroyed() then
		g_modalManager.hide(outfitMemorialWindow)
		outfitMemorialWindow:destroy()
	end

	outfitMemorialWindow = nil
	memorialData = nil
end

local function onOutfitMemorial(goldenPrices, goldenOwners, royalPrices, royalOwners)
	local alreadyOpen = outfitMemorialWindow and not outfitMemorialWindow:isDestroyed()

	memorialData = {
		goldenPrices = goldenPrices or {},
		goldenOwners = goldenOwners or {},
		royalPrices = royalPrices or {},
		royalOwners = royalOwners or {}
	}

	if not alreadyOpen then
		activeTab = TAB_GOLDEN
		outfitMemorialWindow = g_ui.createWidget("OutfitMemorialWindow", rootWidget)
	end

	refresh()
	outfitMemorialWindow:show()
	outfitMemorialWindow:raise()
	outfitMemorialWindow:focus()

	if not alreadyOpen then
		g_modalManager.show(outfitMemorialWindow)
	end
end

function selectTab(tab)
	if tab ~= TAB_GOLDEN and tab ~= TAB_ROYAL then
		return
	end

	activeTab = tab

	refresh()
end

function close()
	destroyWindow()
end

function init()
	g_ui.importStyle("game_outfitmemorial")
	connect(g_game, {
		onGameEnd = destroyWindow,
		onOutfitMemorial = onOutfitMemorial
	})
end

function terminate()
	disconnect(g_game, {
		onGameEnd = destroyWindow,
		onOutfitMemorial = onOutfitMemorial
	})
	destroyWindow()
end
