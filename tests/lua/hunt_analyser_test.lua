modules = {
	game_cyclopedia = {
		Cyclopedia = {
			getItemCustomSalePrice = function(itemId)
				return itemId == 999 and 777 or nil
			end,
			getItemLootValueSource = function(itemId)
				return (itemId == 100 or itemId == 999) and "market" or "npc"
			end
		}
	}
}

local marketPrices = {
	[100] = {
		[0] = 400,
		[2] = 900
	}
}

g_game = {
	getItemMarketPrice = function(itemId, tier)
		return marketPrices[itemId] and marketPrices[itemId][tier] or 0
	end,
	getLocalPlayer = function()
		return {}
	end
}

ThingCategoryItem = 0
g_things = {
	getThingType = function()
		return {
			getNpcSaleData = function()
				return {
					{ buyPrice = 100, salePrice = 150 },
					{ buyPrice = 120, salePrice = 180 }
				}
			end
		}
	end
}

dofile("modules/game_analysers/analyser.lua")

assert(getLootPrice(100, 0) == 400, "tier-zero market loot price")
assert(getLootPrice(100, 2) == 900, "tiered market loot price")
assert(getCurrentPrice(100, 0) == 400, "market supply price")
assert(getLootPrice(200, 0) == 120, "NPC loot fallback")
assert(getCurrentPrice(200, 0) == 180, "NPC supply fallback")
assert(getLootPrice(999, 0) == 777, "custom loot price")
assert(getCurrentPrice(999, 0) == 777, "custom supply price")

openedWindows = {}
dofile("modules/game_analysers/menus/HuntingAnalyser.lua")
HuntingAnalyser.updateWindow = function() end
HuntingAnalyser.lootedItems = {}
HuntingAnalyser.lootedItemsName = {}
HuntingAnalyser.suppliesItems = {}
HuntingAnalyser.loot = 0
HuntingAnalyser.supplies = 0
HuntingAnalyser.healing = 0
HuntingAnalyser.damage = 0

local function item(id, count, tier)
	return {
		getId = function()
			return id
		end,
		getCount = function()
			return count
		end,
		getTier = function()
			return tier
		end
	}
end

HuntingAnalyser:addLootedItems(item(100, 2, 0), "test item")
HuntingAnalyser:addLootedItems(item(100, 1, 2), "test item")
HuntingAnalyser:addSuppliesItems(100)

assert(HuntingAnalyser.loot == 1700, "tiered loot totals remain separate")
assert(HuntingAnalyser.supplies == 400, "initial supply total")

marketPrices[100][0] = 500
marketPrices[100][2] = 1000
HuntingAnalyser:refreshItemPrices(100)

assert(HuntingAnalyser.loot == 2000, "loot is recalculated after a market update")
assert(HuntingAnalyser.supplies == 500, "supplies are recalculated after a market update")

for _ = 1, 100000 do
	HuntingAnalyser:addHealing(1)
	HuntingAnalyser:addDealDamage(1)
end

assert(HuntingAnalyser.healing == 100000, "healing total")
assert(HuntingAnalyser.damage == 100000, "damage total")
assert(HuntingAnalyser.healingTicks == nil, "healing events must not accumulate")
assert(HuntingAnalyser.damageTicks == nil, "damage events must not accumulate")

print("hunt analyzer logic tests passed")
