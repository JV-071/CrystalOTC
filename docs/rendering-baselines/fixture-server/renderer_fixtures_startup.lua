--[[
	Builds the renderer baseline fixture platforms.

	Runs at GAME_STATE_INIT (src/game/game.cpp:702), which CrystalServer enters
	only after loadModules() and loadMaps() have both returned
	(src/crystalserver.cpp:90-95), so the .otbm is fully loaded by the time this
	fires and Game.createTile can safely claim the unused coordinates.

	Startup events are only executed on that one transition, so a server that is
	already running will not pick this file up - it has to be restarted.
]]

local rendererFixtures = GlobalEvent("RendererBaselineFixtures")

function rendererFixtures.onStartup()
	local surfaceTiles, surfaceCreatures = RendererFixtures.buildSurfacePlatform()
	local lightingTiles, lightingCreatures = RendererFixtures.buildLightingPlatform()

	local surface = RendererFixtures.surface.anchor
	local lighting = RendererFixtures.lighting.anchor

	logger.info(
		("[renderer-fixtures] map-core platform at %d,%d,%d (%d tiles, %d creatures); lighting-overlap platform at %d,%d,%d (%d tiles, %d creatures); teleport with !fixture map | !fixture lighting | !fixture wide"):format(
			surface.x,
			surface.y,
			surface.z,
			surfaceTiles,
			surfaceCreatures,
			lighting.x,
			lighting.y,
			lighting.z,
			lightingTiles,
			lightingCreatures
		)
	)

	return true
end

rendererFixtures:register()
