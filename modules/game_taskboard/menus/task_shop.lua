-- chunkname: @/game_taskboard/menus/task_shop.lua

TaskBoard.TaskShop = {}

local TaskShop = TaskBoard.TaskShop
local TYPE_ITEM = 0
local TYPE_MOUNT = 1
local TYPE_OUTFIT = 2
local TYPE_ITEMS = 3
local TYPE_WHEEL_POINTS = 4
-- offer status as the server sends it (Otc::TaskBoardShopStatus_t)
local STATUS_BUYABLE = 0
local STATUS_NOT_AVAILABLE = 1
local STATUS_NO_POINTS = 2
local STATUS_NEEDS_BASE = 3
local STATUS_PURCHASED = 4
local CATEGORY_ICON = {
	[TYPE_ITEM] = "/modules/game_taskboard/images/backdrop_huntingtaskpoint_shop_decoration",
	[TYPE_MOUNT] = "/modules/game_taskboard/images/backdrop_huntingtaskpoint_shop_Mount",
	[TYPE_OUTFIT] = "/modules/game_taskboard/images/backdrop_huntingtaskpoint_shop_outfit",
	[TYPE_ITEMS] = "/modules/game_taskboard/images/backdrop_huntingtaskpoint_shop_decoration",
	[TYPE_WHEEL_POINTS] = "/modules/game_taskboard/images/backdrop_huntingtaskpoint_shop_boost"
}
local STATUS_TOOLTIP = {
	[STATUS_NOT_AVAILABLE] = tr("Not available."),
	[STATUS_NO_POINTS] = tr("You don't have enough Hunting Task Points."),
	[STATUS_NEEDS_BASE] = tr("Requires the base outfit."),
	[STATUS_PURCHASED] = tr("You have already purchased this offer.")
}
local PROMOTION_POINT_TITLE = "Bonus Promotion Point"
local PROMOTION_POINT_NAME = "a Bonus Promotion Point"

-- mounts and outfits are previewed in the colours of the own character, like the official shop
local function previewOutfit(lookType, addons)
	local outfit = {
		type = lookType or 0,
		addons = addons or 0,
		head = 0,
		body = 0,
		legs = 0,
		feet = 0,
		mount = 0
	}
	local player = g_game.getLocalPlayer()

	if player then
		local own = player:getOutfit()

		if own then
			outfit.head = own.head or 0
			outfit.body = own.body or 0
			outfit.legs = own.legs or 0
			outfit.feet = own.feet or 0
		end
	end

	return outfit
end

local function getHuntingTaskPoints()
	local player = g_game.getLocalPlayer()

	return player and player:getResourceBalance(TaskBoard.resourceTypes.taskHunting) or 0
end

function TaskShop:getListPanel()
	if not TaskBoard.taskShopPanel then
		return nil
	end

	return TaskBoard.taskShopPanel:getChildById("shopItemList")
end

function TaskShop:clearShop()
	local list = self:getListPanel()

	if list then
		list:destroyChildren()
	end
end

-- ADAPTER for our engine: onTaskHuntingShopData passes the offers under different field names
-- and - more importantly - ALL values as text. The module compares them numerically
-- (e.g. `(data.clientId or 0) > 0`), which throws a Lua error on a string, hence tonumber everywhere.
local SHOP_TYPE_ITEM, SHOP_TYPE_MOUNT, SHOP_TYPE_ITEMS = 0, 1, 3

function onEngineTaskHuntingShopData(shopData)
	local offers = {}

	for _, o in ipairs(shopData or {}) do
		local offerType = tonumber(o.offerType) or 0
		local itemId = tonumber(o.itemId) or 0
		local lookType = tonumber(o.lookType) or 0

		local clientId = 0
		if offerType == SHOP_TYPE_ITEM or offerType == SHOP_TYPE_ITEMS then
			clientId = itemId
		elseif offerType == SHOP_TYPE_MOUNT then
			clientId = lookType
		end

		local status = tonumber(o.status)

		if status == nil then
			status = (tonumber(o.bought) == 1) and STATUS_PURCHASED or STATUS_BUYABLE
		end

		offers[#offers + 1] = {
			offerId = tonumber(o.id) or 0,
			offerType = offerType,
			name = o.title or "",
			description = o.description or "",
			price = tonumber(o.price) or 0,
			bought = tonumber(o.bought) or 0,
			status = status,
			clientId = clientId,
			-- double offers (beds): second part drawn under the first
			clientId2 = tonumber(o.itemId2) or 0,
			lookType = lookType,
			addons = tonumber(o.lookAddons) or 0,
			itemId = itemId,
			maxPurchases = tonumber(o.maxPurchases) or 0,
			points = tonumber(o.currentPurchases) or 0,
			nextCost = tonumber(o.nextCost) or 0
		}
	end

	onShopTasks(offers)
end

function onShopTasks(offers)
	TaskShop:clearShop()

	TaskShop.offers = offers

	if not offers then
		return
	end

	for i, offer in ipairs(offers) do
		TaskShop:createCard(offer)
	end
end

-- the Buy buttons depend on the Hunting Task Points balance, which can change without a new offer list
local function onShopResourceBalance(resourceType)
	if resourceType ~= TaskBoard.resourceTypes.taskHunting or not TaskShop.offers then
		return
	end

	local list = TaskShop:getListPanel()

	if not list then
		return
	end

	for _, card in ipairs(list:getChildren()) do
		if card.offerData then
			TaskShop:applyStatus(card, card.offerData)
		end
	end
end

function TaskShop:init()
	connect(g_game, {
		onShopTasks = onShopTasks,
		onTaskHuntingShopData = onEngineTaskHuntingShopData,
		onResourceBalance = onShopResourceBalance,
		onGameEnd = function()
			TaskShop:cancelPurchase()
		end
	})
end

function TaskShop:terminate()
	disconnect(g_game, {
		onShopTasks = onShopTasks,
		onTaskHuntingShopData = onEngineTaskHuntingShopData,
		onResourceBalance = onShopResourceBalance
	})
	self:cancelPurchase()
	self:clearShop()
end

function TaskShop:createCard(data)
	local list = self:getListPanel()

	if not list then
		return
	end

	local card = g_ui.createWidget("ShopItemCard", list)

	if not card then
		return
	end

	card.offerData = data

	if data.offerType == TYPE_WHEEL_POINTS then
		card:setText(tr(PROMOTION_POINT_TITLE))
	else
		card:setText(data.name or "")
	end

	local descLabel = card:getChildById("descLabel")

	if descLabel then
		if data.offerType == TYPE_WHEEL_POINTS then
			local purchased = data.points or 0

			descLabel:setText(tr("Earn up to 50 Promotion Points to spend in your Wheel of Destiny.\nAlready purchased %d / 50.", purchased))

			local iconBox = card:getChildById("iconBox")

			if iconBox then
				iconBox:setImageSource("/modules/game_taskboard/images/icon_tasksystem_promotionpoint")
			end
		else
			descLabel:setText(data.description or "")
		end
	end

	local currencyWidget = card:getChildById("currencyTypeWidget")

	if currencyWidget then
		local icon = CATEGORY_ICON[data.offerType]

		if icon then
			currencyWidget:setImageSource(icon)
		end
	end

	self:applyPrice(card, data)
	self:applyIcon(card, data)
	self:applyStatus(card, data)
end

function TaskShop:applyPrice(card, data)
	local pricePanel = card:getChildById("pricePanel")

	if not pricePanel then
		return
	end

	local coinIcon = pricePanel:getChildById("coinIcon")

	if coinIcon then
		coinIcon:setImageSource("/modules/game_taskboard/images/preyhuntingtask-tokens")
	end

	local priceLabel = pricePanel:getChildById("priceLabel")

	if priceLabel then
		priceLabel:setText(TaskBoard:formatNumberWithCommas(data.price or 0))
	end
end

function TaskShop:applyIcon(card, data)
	local iconBox = card:getChildById("iconBox")

	if not iconBox then
		return
	end

	local itemIcon = iconBox:getChildById("itemIcon")
	local itemIcon2 = iconBox:getChildById("itemIcon2")
	local outfitIcon = iconBox:getChildById("outfitIcon")

	if itemIcon then
		itemIcon:setVisible(false)
	end

	if itemIcon2 then
		itemIcon2:setVisible(false)
	end

	if outfitIcon then
		outfitIcon:setVisible(false)
	end

	local offerType = data.offerType

	if offerType == TYPE_OUTFIT then
		if outfitIcon and (data.lookType or 0) > 0 then
			outfitIcon:setOutfit(previewOutfit(data.lookType, data.addons))
			outfitIcon:setVisible(true)
		end
	elseif offerType == TYPE_MOUNT then
		if outfitIcon and (data.clientId or 0) > 0 then
			outfitIcon:setOutfit(previewOutfit(data.clientId, 0))
			outfitIcon:setVisible(true)
		end
	elseif offerType == TYPE_ITEM then
		if itemIcon and (data.clientId or 0) > 0 then
			itemIcon:setItemId(data.clientId)
			itemIcon:setVisible(true)
		end
	elseif offerType == TYPE_ITEMS then
		TaskShop:showDoubleItem(itemIcon, itemIcon2, data)
	elseif offerType == TYPE_WHEEL_POINTS then
		-- block empty
	end
end

-- a bed comes as two items: head board on top, foot board right under it
function TaskShop:showDoubleItem(itemIcon, itemIcon2, data)
	if not itemIcon or (data.clientId or 0) <= 0 then
		return
	end

	itemIcon:setItemId(data.clientId)
	itemIcon:setVisible(true)

	if not itemIcon2 or (data.clientId2 or 0) <= 0 then
		return
	end

	itemIcon:breakAnchors()
	itemIcon:addAnchor(AnchorTop, "parent", AnchorTop)
	itemIcon:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
	itemIcon:setSize(tosize("32 32"))
	itemIcon:setMarginTop(0)
	itemIcon:setMarginLeft(0)
	itemIcon2:breakAnchors()
	itemIcon2:addAnchor(AnchorTop, "itemIcon", AnchorBottom)
	itemIcon2:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
	itemIcon2:setSize(tosize("32 32"))
	itemIcon2:setMarginTop(0)
	itemIcon2:setMarginRight(0)
	itemIcon2:setMarginBottom(0)
	itemIcon2:setItemId(data.clientId2)
	itemIcon2:setVisible(true)
end

function TaskShop:applyStatus(card, data)
	local buyButton = card:getChildById("buyButton")
	local boughtWidget = card:getChildById("boughtWidget")

	if not buyButton or not boughtWidget then
		return
	end

	local status = data.status or STATUS_BUYABLE

	if status == STATUS_PURCHASED then
		buyButton:setVisible(false)
		boughtWidget:setVisible(true)
		boughtWidget:setTooltip(STATUS_TOOLTIP[STATUS_PURCHASED])

		return
	end

	boughtWidget:setVisible(false)
	buyButton:setVisible(true)

	-- like the official shop: Buy needs the points in hand and an offer the server marks as buyable
	if status == STATUS_BUYABLE and getHuntingTaskPoints() < (data.price or 0) then
		status = STATUS_NO_POINTS
	end

	if status == STATUS_BUYABLE then
		buyButton:setEnabled(true)
		buyButton:setTooltip("")

		function buyButton.onClick()
			TaskShop:onBuyItem(data)
		end
	else
		buyButton:setEnabled(false)
		buyButton:setTooltip(STATUS_TOOLTIP[status] or STATUS_TOOLTIP[STATUS_NOT_AVAILABLE])
	end
end

function TaskShop:onBuyItem(data)
	if not data then
		return
	end

	self:showPurchaseConfirmation(data)
end

function TaskShop:showPurchaseConfirmation(data)
	self:cancelPurchase()

	local window = g_ui.createWidget("TaskShopConfirmWindow", rootWidget)

	if not window then
		return
	end

	self.confirmWindow = window
	self.pendingOffer = data

	local name = data.offerType == TYPE_WHEEL_POINTS and tr(PROMOTION_POINT_NAME) or (data.name or "")
	local preview = window:getChildById("previewBox")
	local itemIcon = preview:getChildById("itemIcon")
	local itemIcon2 = preview:getChildById("itemIcon2")
	local outfitIcon = preview:getChildById("outfitIcon")
	local promotionIcon = preview:getChildById("promotionIcon")

	if data.offerType == TYPE_OUTFIT and (data.lookType or 0) > 0 then
		outfitIcon:setOutfit(previewOutfit(data.lookType, data.addons))
		outfitIcon:setVisible(true)
	elseif data.offerType == TYPE_MOUNT and (data.clientId or 0) > 0 then
		outfitIcon:setOutfit(previewOutfit(data.clientId, 0))
		outfitIcon:setVisible(true)
	elseif data.offerType == TYPE_WHEEL_POINTS then
		promotionIcon:setVisible(true)
	elseif data.offerType == TYPE_ITEMS then
		self:showDoubleItem(itemIcon, itemIcon2, data)
	elseif (data.clientId or 0) > 0 then
		itemIcon:setItemId(data.clientId)
		itemIcon:setVisible(true)
	end

	window:getChildById("questionLabel"):setText(tr('Would you like to buy "%s" for', name))

	local priceRow = window:getChildById("priceRow")
	local priceLabel = priceRow:getChildById("priceLabel")

	priceLabel:setText(TaskBoard:formatNumberWithCommas(data.price or 0))
	priceRow:setWidth(priceLabel:getTextSize().width + 3 + 11 + 1 + 8)
	window:raise()
	window:focus()
	g_modalManager.show(window)
end

function TaskShop:confirmPurchase()
	local data = self.pendingOffer

	self:cancelPurchase()

	if data then
		g_game.sendOnBuyHuntingTaskShop(data.offerId)
	end
end

function TaskShop:cancelPurchase()
	self.pendingOffer = nil

	if self.confirmWindow then
		if not self.confirmWindow:isDestroyed() then
			g_modalManager.hide(self.confirmWindow)
			self.confirmWindow:destroy()
		end

		self.confirmWindow = nil
	end
end
