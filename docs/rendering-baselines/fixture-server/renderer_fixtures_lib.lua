--[[
	Renderer baseline fixtures - shared coordinates and builders.

	Purpose
	-------
	The OTClient fork in ../CrystalOTC captures deterministic renderer baseline
	images against this server. Two of those scenes need world state that the
	shipped map does not provide:

	  * "map-core"        - ground/floor/creature drawing, including a hole in an
	                        upper floor so the floor below shows through.
	  * "lighting-overlap" - the CPU light bitmap -> dynamic texture upload ->
	                        MULTIPLY overlay path, with overlapping coloured
	                        light circles whose per-channel maxima can be
	                        asserted on real pixels.

	Why the lighting platform is underground
	----------------------------------------
	src/client/mapview.cpp:564 forces the ambient light to Light{intensity = 0,
	colour = 215} whenever the camera floor is below the sea floor, ignoring the
	world light entirely. src/client/lightview.h:44 only marks the light view as
	"dark" (and therefore draws the LIGHT pool at all) when the ambient intensity
	is below 250. On the surface a player whose group has the hasfulllight flag
	(groups 4/5/6/7 in data/XML/groups.xml) is always sent 255/215
	(src/server/network/protocol/protocolgame.cpp:9425), so the LIGHT pool is
	skipped and no coloured light is ever drawn. Underground that override does
	not matter: the client hard-codes ambient 0 there, so the scene is dark for
	every group and the fixture is immune to both the full-light flag and the
	wall-clock-seeded day/night cycle (src/game/game.cpp:591).

	Item light comes from appearances.dat and is never sent over the wire, so
	placing the item server-side is all that is required.

	Coordinates
	-----------
	Both platforms live beyond every tile the shipped maps touch. The largest
	tile in data-global/world/world.otbm is x = 34143, y = 33812; every other
	.otbm under data-global/world stays below that. Map bounds are 35143x34812,
	so x >= 34304 and y >= 34048 is guaranteed free of tiles, spawns and NPCs
	while staying inside the map. Both fixtures satisfy both conditions.
]]

RendererFixtures = {}

-- Defensive floor: refuse to build anywhere the shipped map might reach.
RendererFixtures.SAFE_MIN_X = 34304
RendererFixtures.SAFE_MIN_Y = 34048

RendererFixtures.GROUND = {
	whiteMarble = 409, -- "white marble floor", bank ground, no animation
	blackMarble = 410, -- "black marble floor", bank ground, no animation
	stoneTile = 431, -- "stone tile", bank ground, no animation
}

RendererFixtures.DECOR = {
	grass = 407, -- clip overlay, non-blocking, no animation
	stoneWall = 1304, -- unpass/unsight, no animation, 2-tile-tall sprite
}

-- Verified against data/items/appearances.dat (AppearanceFlagLight) and the
-- client thing catalog. The 8-bit light colour decodes as
-- r = (c / 36 % 6) * 51, g = (c / 6 % 6) * 51, b = (c % 6) * 51
-- (src/framework/util/color.h:96 in the client).
RendererFixtures.LIGHT_ITEMS = {
	red = 27673, -- brightness 6, colour 180 -> rgb(255,   0,   0)
	green = 27674, -- brightness 6, colour  67 -> rgb( 51, 255,  51)
	cyan = 27675, -- brightness 6, colour  35 -> rgb(  0, 255, 255)
	wide = 31358, -- brightness 15, colour 11 -> rgb(  0,  51, 255)
}

--------------------------------------------------------------------------------
-- Surface fixture: "map-core"
--------------------------------------------------------------------------------
RendererFixtures.surface = {
	upperZ = 6,
	lowerZ = 7,
	fromX = 34385,
	toX = 34415,
	fromY = 34085,
	toY = 34115,
	anchor = { x = 34400, y = 34100, z = 6 },
	-- Hole punched in the upper floor so the lower floor is drawn through it.
	hole = { fromX = 34402, toX = 34404, fromY = 34099, toY = 34101 },
	-- Contrasting ground patch on the upper floor.
	patch = { fromX = 34394, toX = 34398, fromY = 34098, toY = 34102 },
	grassRow = { y = 34104, fromX = 34396, toX = 34404 },
	wallRow = { y = 34096, fromX = 34397, toX = 34401 },
	creatures = {
		{ name = "Rabbit", x = 34398, y = 34103, z = 6 },
		{ name = "Rabbit", x = 34403, y = 34097, z = 6 },
	},
}

--------------------------------------------------------------------------------
-- Underground fixture: "lighting-overlap"
--------------------------------------------------------------------------------
RendererFixtures.lighting = {
	z = 8,
	fromX = 34488,
	toX = 34532,
	fromY = 34189,
	toY = 34213,
	-- Camera anchor. Deliberately NOT one of the probe tiles: the client always
	-- centres the camera on the local player, and the player sprite would cover
	-- the probe pixel.
	anchor = { x = 34500, y = 34201, z = 8 },
	torches = {
		{ id = 27673, x = 34497, y = 34204, z = 8 }, -- red
		{ id = 27674, x = 34503, y = 34204, z = 8 }, -- green
		{ id = 27675, x = 34500, y = 34199, z = 8 }, -- cyan
	},
	-- Widest-radius light in the catalog, parked far enough east that its
	-- 15-tile radius cannot reach any probe tile (nearest probe is 20 tiles
	-- away). Reached with "!fixture wide".
	wideAnchor = { x = 34518, y = 34201, z = 8 },
	wideLight = { id = 31358, x = 34524, y = 34201, z = 8 },
	-- Creature-light probe, also clear of the overlap probes.
	litCreature = { name = "Rabbit", x = 34521, y = 34201, z = 8, colour = 185, level = 7 },
}

--[[
	Expected LIGHT-pool texel values on the lighting platform.

	The client builds one texel per tile (src/client/lightview.cpp:137
	LightView::updatePixels), starting from the ambient colour - black
	underground - and taking a per-channel maximum over every light in range:

	    d          = distance from tile centre to the light, in tiles
	    f          = clamp((brightness - d) * 0.2, 0.01 .. 1.0), skipped if d > brightness
	    channel    = max(channel, from8bit(colour).channel * f)

	The resulting texture is drawn over the map with CompositionMode::MULTIPLY,
	so an on-screen pixel is roughly base_pixel * texel / 255. Probe tiles below
	carry only ground (no item or creature sprite) so the base pixel is the
	white-marble floor.

	  probe                tile                 texel rgb
	  P1 red core       (34496, 34204, 8)   (255,   0,   0)   only the red torch in range
	  P2 green core     (34504, 34204, 8)   ( 51, 255,  51)   only the green torch in range
	  P3 cyan core      (34500, 34198, 8)   (  0, 255, 255)   only the cyan torch in range
	  P4 red + green    (34500, 34204, 8)   (153, 153,  51)
	  P5 red + cyan     (34498, 34201, 8)   (144, 161, 161)
	  P6 green + cyan   (34502, 34201, 8)   ( 28, 161, 161)
	  P7 all three      (34500, 34202, 8)   (122, 153, 153)
	  P8 unlit corner   (34493, 34196, 8)   (  0,   0,   0)
	  P9 unlit corner   (34507, 34196, 8)   (  0,   0,   0)

	The local player emits a forced Light{2, 215} underground
	(src/client/creature.cpp:120), which reaches at most one tile. It raises no
	probe above the values listed here.

	This only holds for a group-1 character. Any group with the hasfulllight flag
	is sent creature light 255/215 for every creature including itself, which
	floods the whole viewport white.
]]

local function assertSafe(x, y)
	if x < RendererFixtures.SAFE_MIN_X or y < RendererFixtures.SAFE_MIN_Y then
		error(("RendererFixtures: refusing to build at (%d, %d); fixtures must stay at x >= %d and y >= %d"):format(x, y, RendererFixtures.SAFE_MIN_X, RendererFixtures.SAFE_MIN_Y))
	end
end

-- Creates the tile if needed and places itemId on it. Ground items become the
-- tile ground (src/items/tile.cpp:1064). Everything placed here is marked as
-- loaded-from-map so Item::isCleanable (src/items/item.hpp:672) can never pick
-- it up during a map clean, and so it is exempt from decay
-- (src/items/decay/decay.cpp:185).
function RendererFixtures.placeItem(x, y, z, itemId)
	assertSafe(x, y)
	local position = { x = x, y = y, z = z }
	Game.createTile(position)
	local item = Game.createItem(itemId, 1, position)
	if not item then
		logger.error(("RendererFixtures: failed to create item %d at %d, %d, %d"):format(itemId, x, y, z))
		return nil
	end
	item:setLoadedFromMap(true)
	return item
end

function RendererFixtures.fillGround(fromX, toX, fromY, toY, z, itemId, skip)
	local placed = 0
	for x = fromX, toX do
		for y = fromY, toY do
			if not (skip and skip(x, y)) then
				if RendererFixtures.placeItem(x, y, z, itemId) then
					placed = placed + 1
				end
			end
		end
	end
	return placed
end

-- Places a creature and then freezes it. The order matters: Tile::queryAdd
-- (src/items/tile.cpp:622) rejects a move-locked creature, so the lock has to
-- be applied after the creature is already standing on the tile.
function RendererFixtures.placeFrozenCreature(name, x, y, z, lightColour, lightLevel)
	assertSafe(x, y)
	local creature = Game.createMonster(name, { x = x, y = y, z = z }, false, true)
	if not creature then
		logger.error(("RendererFixtures: failed to create creature '%s' at %d, %d, %d"):format(name, x, y, z))
		return nil
	end
	creature:setMoveLocked(true)
	creature:setDirectionLocked(true)
	if lightColour and lightLevel then
		-- creature:setLight(COLOR, LEVEL) - colour first
		-- (src/lua/functions/creatures/creature_functions.cpp:417).
		creature:setLight(lightColour, lightLevel)
	end
	return creature
end

function RendererFixtures.buildSurfacePlatform()
	local cfg = RendererFixtures.surface
	local tiles = 0

	-- Lower floor, drawn through the hole in the upper floor.
	tiles = tiles + RendererFixtures.fillGround(cfg.fromX, cfg.toX, cfg.fromY, cfg.toY, cfg.lowerZ, RendererFixtures.GROUND.stoneTile)

	-- Upper floor, minus the hole.
	local hole = cfg.hole
	tiles = tiles + RendererFixtures.fillGround(cfg.fromX, cfg.toX, cfg.fromY, cfg.toY, cfg.upperZ, RendererFixtures.GROUND.whiteMarble, function(x, y)
		return x >= hole.fromX and x <= hole.toX and y >= hole.fromY and y <= hole.toY
	end)

	-- Contrasting ground patch.
	RendererFixtures.fillGround(cfg.patch.fromX, cfg.patch.toX, cfg.patch.fromY, cfg.patch.toY, cfg.upperZ, RendererFixtures.GROUND.blackMarble)

	-- Non-blocking clip overlay and a solid wall run, both static sprites.
	for x = cfg.grassRow.fromX, cfg.grassRow.toX do
		RendererFixtures.placeItem(x, cfg.grassRow.y, cfg.upperZ, RendererFixtures.DECOR.grass)
	end
	for x = cfg.wallRow.fromX, cfg.wallRow.toX do
		RendererFixtures.placeItem(x, cfg.wallRow.y, cfg.upperZ, RendererFixtures.DECOR.stoneWall)
	end

	local creatures = 0
	for _, entry in ipairs(cfg.creatures) do
		if RendererFixtures.placeFrozenCreature(entry.name, entry.x, entry.y, entry.z) then
			creatures = creatures + 1
		end
	end

	return tiles, creatures
end

function RendererFixtures.buildLightingPlatform()
	local cfg = RendererFixtures.lighting
	local tiles = RendererFixtures.fillGround(cfg.fromX, cfg.toX, cfg.fromY, cfg.toY, cfg.z, RendererFixtures.GROUND.whiteMarble)

	for _, torch in ipairs(cfg.torches) do
		RendererFixtures.placeItem(torch.x, torch.y, torch.z, torch.id)
	end
	RendererFixtures.placeItem(cfg.wideLight.x, cfg.wideLight.y, cfg.wideLight.z, cfg.wideLight.id)

	local creatures = 0
	local lit = cfg.litCreature
	if RendererFixtures.placeFrozenCreature(lit.name, lit.x, lit.y, lit.z, lit.colour, lit.level) then
		creatures = creatures + 1
	end

	return tiles, creatures
end

RendererFixtures.DESTINATIONS = {
	["map"] = RendererFixtures.surface.anchor,
	["map-core"] = RendererFixtures.surface.anchor,
	["light"] = RendererFixtures.lighting.anchor,
	["lighting"] = RendererFixtures.lighting.anchor,
	["lighting-overlap"] = RendererFixtures.lighting.anchor,
	["wide"] = RendererFixtures.lighting.wideAnchor,
}
