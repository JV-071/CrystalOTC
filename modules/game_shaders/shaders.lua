-- chunkname: @/game_shaders/shaders.lua

local MAP_SHADERS = {
	{
		name = "Map - Default"
	},
	{
		tex1 = "images/clouds",
		name = "Map - Fog",
		frag = "shaders/fragment/fog.frag"
	},
	{
		frag = "shaders/fragment/rain.frag",
		name = "Map - Rain"
	},
	{
		tex1 = "images/snow",
		name = "Map - Snow",
		frag = "shaders/fragment/snow.frag"
	},
	{
		frag = "shaders/fragment/grayscale.frag",
		name = "Map - Gray Scale"
	},
	{
		frag = "shaders/fragment/bloom.frag",
		name = "Map - Bloom"
	},
	{
		frag = "shaders/fragment/sepia.frag",
		name = "Map - Sepia"
	},
	{
		drawViewportEdge = true,
		name = "Map - Pulse",
		frag = "shaders/fragment/pulse.frag"
	},
	{
		frag = "shaders/fragment/oldtv.frag",
		name = "Map - Old Tv"
	},
	{
		frag = "shaders/fragment/party.frag",
		name = "Map - Party"
	},
	{
		drawViewportEdge = true,
		name = "Map - Radial Blur",
		frag = "shaders/fragment/radialblur.frag"
	},
	{
		drawViewportEdge = true,
		name = "Map - Zomg",
		frag = "shaders/fragment/zomg.frag"
	},
	{
		drawViewportEdge = true,
		name = "Map - Heat",
		frag = "shaders/fragment/heat.frag"
	},
	{
		frag = "shaders/fragment/noise.frag",
		name = "Map - Noise"
	}
}

OUTFIT_SHADERS = {
	{
		name = "Outfit - Default"
	},
	{
		frag = "shaders/fragment/party.frag",
		name = "Outfit - Rainbow"
	},
	{
		drawColor = false,
		name = "Outfit - Ghost",
		frag = "shaders/fragment/radialblur.frag"
	},
	{
		frag = "shaders/fragment/heat.frag",
		name = "Outfit - Jelly"
	},
	{
		frag = "shaders/fragment/noise.frag",
		name = "Outfit - Fragmented"
	},
	{
		frag = "shaders/fragment/cyclopedia.frag",
		name = "Outfit - cyclopedia-black"
	},
	{
		name = "Outfit - Outline",
		useFramebuffer = true,
		frag = "shaders/fragment/outline.frag"
	}
}
ITEM_SHADERS = {
	{
		name = "Item - Default"
	},
	{
		frag = "shaders/fragment/hover_desaturate.frag",
		name = "Hover - Desaturate"
	}
}
MOUNT_SHADERS = {
	{
		name = "Mount - Default"
	},
	{
		frag = "shaders/fragment/party.frag",
		name = "Mount - Rainbow"
	}
}

-- Shaders addressed by widgets through `image-shader:` / setImageShader, rather than
-- offered in the shader picker. They are not in MAP/OUTFIT/MOUNT_SHADERS because nothing
-- calls setupMapShader-family on them: a widget names them directly.
--
-- image_black_white is the greyed-out state the wheel uses for gems and fragments the
-- player does not own (game_wheel/styles/gemMenu.otui, fragmentMenu.otui). It was being
-- requested by name with nothing registering it, so the widgets drew at full colour and
-- the disabled state was invisible.
--
-- It points at grayscale.frag rather than the donor client's own image_black-white
-- fragment because grayscale.frag is already in the generated Metal material set
-- (render/metal/metalmodulematerials.h). A .frag with no translated material falls back
-- to the built-in on non-GL backends, which would put us back where we started on macOS.
-- The donor source is at data/shaders/image_black-white_fragment.frag if the exact
-- original look is ever wanted; it needs tools/generate_metal_shaders.py run over it.
IMAGE_SHADERS = {
	{
		frag = "shaders/fragment/grayscale.frag",
		name = "image_black_white"
	}
}

function registerItemShaders()
	for _, opts in pairs(ITEM_SHADERS) do
		if opts.frag then
			g_shaders.createFragmentShader(opts.name, opts.frag, opts.useFramebuffer or false)
		end
	end
end

function registerImageShaders()
	for _, opts in pairs(IMAGE_SHADERS) do
		if opts.frag then
			g_shaders.createFragmentShader(opts.name, opts.frag, opts.useFramebuffer or false)
		end
	end
end

local function attachShaders()
	local map = modules.game_interface.getMapPanel()

	map:setShader("Default")

	local player = g_game.getLocalPlayer()

	player:setShader("Default")
	player:setMountShader("Default")
end

local function registerShader(opts, method)
	local fragmentShaderPath = resolvepath(opts.frag)

	if fragmentShaderPath ~= nil then
		g_shaders.createFragmentShader(opts.name, opts.frag, opts.useFramebuffer or false)

		if opts.tex1 then
			g_shaders.addMultiTexture(opts.name, opts.tex1)
		end

		if opts.tex2 then
			g_shaders.addMultiTexture(opts.name, opts.tex2)
		end

		g_shaders[method](opts.name)
	end
end

ShaderController = Controller:new()

function ShaderController:onInit()
	for _, opts in pairs(MAP_SHADERS) do
		registerShader(opts, "setupMapShader")
	end

	for _, opts in pairs(OUTFIT_SHADERS) do
		registerShader(opts, "setupOutfitShader")
	end

	for _, opts in pairs(MOUNT_SHADERS) do
		registerShader(opts, "setupMountShader")
	end

	registerItemShaders()
	registerImageShaders()
end

function ShaderController:onTerminate()
	g_shaders.clear()
	Keybind.delete("Windows", "show/hide Shader Windows")
end

function ShaderController:onGameStart()
	attachShaders()
	self:loadHtml("shaders.html", modules.game_interface.getMapPanel())

	for _, opts in pairs(MAP_SHADERS) do
		self.ui.mapComboBox:addOption(opts.name, opts)
	end

	for _, opts in pairs(OUTFIT_SHADERS) do
		self.ui.outfitComboBox:addOption(opts.name, opts)
	end

	for _, opts in pairs(MOUNT_SHADERS) do
		self.ui.mountComboBox:addOption(opts.name, opts)
	end
end

function ShaderController:onMapComboBoxChange(event)
	local map = modules.game_interface.getMapPanel()

	map:setShader(event.text)

	local data = event.target:getCurrentOption().data

	map:setDrawViewportEdge(data.drawViewportEdge == true)
end

function ShaderController:onOutfitComboBoxChange(event)
	local player = g_game.getLocalPlayer()

	if player then
		player:setShader(event.text)

		local data = event.target:getCurrentOption().data

		player:setDrawOutfitColor(data.drawColor ~= false)
	end
end

function ShaderController:onMountComboBoxChange(event)
	local player = g_game.getLocalPlayer()

	if player then
		player:setMountShader(event.text)
	end
end
