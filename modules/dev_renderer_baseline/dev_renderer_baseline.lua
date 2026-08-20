RendererBaseline = {}

local captureEvent
local exitEvent
local loginTimeoutEvent
local setupEvent
local activeScenario
local sceneRoot

local CAPTURE_WIDTH = 1020
local CAPTURE_HEIGHT = 644

local function optionValue(name)
    local options = g_app.getStartupOptions()
    return options:match("%-%-" .. name:gsub("%-", "%%-") .. "=([^%s]+)")
end

local function fail(message)
    g_logger.error("[renderer-baseline] " .. message)
    exitEvent = scheduleEvent(function()
        g_app.exit()
    end, 100)
end

local function place(widget, x, y, width, height)
    widget:setPosition({ x = x, y = y })
    widget:setSize({ width = width, height = height })
    return widget
end

local function makePanel(parent, x, y, width, height, color, borderColor)
    local panel = place(g_ui.createWidget("UIWidget", parent), x, y, width, height)
    panel:setBackgroundColor(color)
    if borderColor then
        panel:setBorderWidth(1)
        panel:setBorderColor(borderColor)
    end
    return panel
end

local function makeLabel(parent, x, y, width, height, text, font, color, alignment)
    local label = place(g_ui.createWidget("UILabel", parent), x, y, width, height)
    label:setText(text)
    label:setFont(font or "verdana-11px-antialised")
    label:setColor(color or "#e5e7ebff")
    label:setTextAlign(alignment or AlignLeft)
    return label
end

-- Every shader in the registry reads u_Time as wall-clock seconds, so an animated shader makes
-- its scene irreproducible: outfit-masks and temporary-framebuffers each carry one Outline probe
-- and already spend 520 and 449 of the 656-pixel tolerance budget on it. Pin the phase instead.
-- 2.0 s is deliberately away from t=0, where several shaders sit at a degenerate value.
local CAPTURE_SHADER_TIME = 2.0

local function freezeShaderTime()
    if g_shaders and g_shaders.setFixedTime then
        g_shaders.setFixedTime(CAPTURE_SHADER_TIME)
    end
end

local function beginClientScene(title, subtitle)
    freezeShaderTime()

    if EnterGame and EnterGame.hide then
        EnterGame.hide()
    end

    g_window.resize({ width = CAPTURE_WIDTH, height = CAPTURE_HEIGHT })
    local rootWidget = g_ui.getRootWidget()
    for _, child in ipairs(rootWidget:getChildren()) do
        child:hide()
    end
    sceneRoot = makePanel(rootWidget, 0, 0, CAPTURE_WIDTH, CAPTURE_HEIGHT, "#111827ff")
    sceneRoot:setId("rendererBaselineScene")
    sceneRoot:setPhantom(true)
    sceneRoot:raise()

    makeLabel(sceneRoot, 48, 30, 924, 32, title, "Verdana Bold-13px", "#f9fafbff", AlignTopLeft)
    makeLabel(sceneRoot, 48, 60, 924, 24, subtitle, "verdana-11px-antialised", "#94a3b8ff", AlignTopLeft)
    makePanel(sceneRoot, 48, 91, 924, 1, "#334155ff")
    return sceneRoot
end

local function isolateClientScene()
    if not sceneRoot then
        return
    end

    for _, child in ipairs(g_ui.getRootWidget():getChildren()) do
        if child ~= sceneRoot then
            child:hide()
        end
    end
    sceneRoot:show()
    sceneRoot:raise()
end

-- Online scenes capture the whole client, so anything that repaints per frame or
-- reopens itself would make the image irreproducible. Two things do:
--   * the FPS/ping HUD row, which client_topmenu draws INSIDE the map panel, so its
--     changing text lands on top of the very MAP pool the scene exists to exercise;
--   * the enter-game window, which the driver hides before calling loginWorld, but
--     which the normal startup flow then re-shows because EnterGame.show() only guards
--     on g_game.isOnline() and the client is still offline at that moment. Nothing
--     hides it again once the game starts, so it covers the map centre.
-- Online captures must show the game interface and nothing else. The server can push a
-- modal at any moment -- a Sample character arrives with the outfit-customisation window
-- open, which covers the whole map -- and any such window is both unwanted and
-- unpredictable. This is the online counterpart of isolateClientScene().
local function isolateGameInterface()
    if not g_game.isOnline() then
        return
    end

    local gameRoot = modules.game_interface and modules.game_interface.getRootPanel
        and modules.game_interface.getRootPanel()
    if not gameRoot then
        return
    end

    local rootWidget = g_ui.getRootWidget()
    local keep = gameRoot
    while keep and keep:getParent() and keep:getParent() ~= rootWidget do
        keep = keep:getParent()
    end

    for _, child in ipairs(rootWidget:getChildren()) do
        if child ~= keep and child:isVisible() then
            child:hide()
        end
    end
end

-- The map panel takes whatever vertical space the console splitter leaves it, and that
-- settled at three different values across consecutive runs of the same scene (308, 370
-- and 461 px tall), which alone made an online capture irreproducible. Waiting longer did
-- not converge, so pin the splitter instead of hoping the layout agrees with itself.
-- Light configuration is applied straight to the map widget rather than through
-- client_options.setOption, whose action runs against the options module's panel table
-- and is not necessarily built yet at game start.
--
-- The requested ambient floor of 0 is NOT what the capture ends up with: client_options
-- applies its own 25% default during game start and wins, so the unlit ground settles at
-- a mid grey rather than black. That is left as observed behaviour because it is stable
-- and the scene's purpose -- proving the CPU light bitmap, its dynamic texture upload and
-- the MULTIPLY overlay with overlapping coloured sources -- is unaffected. Do not read
-- the unlit tiles as a zero-ambient reference.
local lightingSceneActive = false

local function applyLightingSetup()
    if not lightingSceneActive or not g_game.isOnline() then
        return
    end

    local gameInterface = modules.game_interface
    local mapPanel = gameInterface and gameInterface.getMapPanel and gameInterface.getMapPanel()
    if not mapPanel or mapPanel:isDestroyed() then
        return
    end

    mapPanel:setDrawLights(true)
    mapPanel:setMinimumAmbientLight(0)
end

local BASELINE_SPLITTER_MARGIN = 161

local function pinInterfaceLayout()
    if not g_game.isOnline() then
        return
    end

    local gameInterface = modules.game_interface
    local gameRoot = gameInterface and gameInterface.getRootPanel and gameInterface.getRootPanel()
    if not gameRoot then
        return
    end

    local splitter = gameRoot:getChildById("bottomSplitter")
    if not splitter or splitter:isDestroyed() then
        return
    end

    splitter:setMarginBottom(BASELINE_SPLITTER_MARGIN)
    if gameInterface.bottomSplitterOnGeometryChange then
        pcall(gameInterface.bottomSplitterOnGeometryChange, splitter)
    end
end

-- The fixture torches carry six animation phases and creatures idle, so their sprites
-- would land at a different phase in every capture even though the light they emit is
-- phase-independent. Freeze every visible thing on the player's floor.
local function freezeMapAnimation()
    if not g_game.isOnline() then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    for _, tile in ipairs(g_map.getTiles(player:getPosition().z)) do
        for _, thing in ipairs(tile:getThings()) do
            if thing.setAnimate then
                thing:setAnimate(false)
            end
        end
    end
end

-- Server broadcasts and the fixture talkaction's own confirmation both draw centred text
-- over the map, so anything left on screen has to go before the shutter.
local function clearOnScreenMessages()
    if modules.game_textmessage and modules.game_textmessage.clearMessages then
        pcall(modules.game_textmessage.clearMessages)
    end
end

local function stabilizeOnlineUi()
    freezeShaderTime()

    -- The hovered-tile crosshair is drawn into the MAP pool wherever the pointer happens to
    -- be, so it lands in the map framebuffer readback as well as the window capture. That is
    -- the same class of contamination as the hovered tooltip, but suppressCaptureTooltip does
    -- not reach it: it is a map texture, not a widget. Disabling the texture is permanent for
    -- the session, so once at game start is enough.
    local gameInterface = modules.game_interface
    local mapPanel = gameInterface and gameInterface.getMapPanel and gameInterface.getMapPanel()
    if mapPanel and not mapPanel:isDestroyed() then
        mapPanel:setCrosshairTexture(nil)
    end

    -- Isolate immediately and then again while the server may still be pushing windows.
    -- Hiding a modal at capture time is not enough: it has already been laid out by then,
    -- and the game interface keeps the geometry it settled on, which showed up as a map
    -- panel of a different size from run to run.
    isolateGameInterface()
    pinInterfaceLayout()
    for _, delay in ipairs({ 500, 1500, 2500 }) do
        scheduleEvent(function()
            isolateGameInterface()
            -- Pin the layout here too, not only in the shutter path. The splitter reflows on
            -- the following frame, so a capture that pins in its own tick still records the
            -- pre-pin geometry -- which showed up in the multi-capture map-shader scene as a
            -- first frame whose map panel was shorter than the thirteen after it.
            pinInterfaceLayout()
        end, delay)
    end

    if modules.client_options and modules.client_options.setOption then
        pcall(modules.client_options.setOption, "showFps", false, true)
    end

    if EnterGame and EnterGame.hide then
        EnterGame.hide()
    end
end

-- client_background picks one of six login backgrounds at random on every startup, seeded
-- from the wall clock (modules/client_background/background.lua). Any scene that shows the
-- login screen -- startup-ui and windowing -- is therefore only one-in-six likely to match a
-- previous capture. Pin it to the first background so those scenes are comparable at all.
local BASELINE_LOGIN_BACKGROUND = "/images/background_crystal1"

local function pinLoginBackground()
    local backgroundModule = modules.client_background
    if not backgroundModule or not backgroundModule.getBackground then
        return
    end

    local background = backgroundModule.getBackground()
    if background and not background:isDestroyed() then
        background:setImageSource(BASELINE_LOGIN_BACKGROUND)
    end
end

local function suppressCaptureTooltip()
    local rootWidget = g_ui.getRootWidget()
    local hovered = rootWidget:getHoveredChild()
    while hovered do
        hovered:setTooltip(nil)
        if hovered.setSpecialToolTip then
            hovered:setSpecialToolTip(nil)
        end
        hovered = hovered:getHoveredChild()
    end

    if g_tooltip then
        g_tooltip.hide()
        g_tooltip.hideSpecial()
    end
end

function RendererBaseline.buildClippingOpacityScene()
    local root = beginClientScene(
        "OpenGL UI clipping and opacity",
        "Nested scissors, a scroll-area viewport, and stacked alpha at fixed logical coordinates"
    )

    makeLabel(root, 58, 116, 410, 24, "NESTED CLIPPING", "Verdana Bold-11px-new", "#7dd3fcff")
    local outer = makePanel(root, 58, 146, 410, 205, "#0f172aff", "#38bdf8ff")
    outer:setClipping(true)

    makePanel(outer, 16, 169, 510, 54, "#2563ebff"):setRotation(-7)
    makePanel(outer, 15, 232, 510, 54, "#db2777dd"):setRotation(8)
    makePanel(outer, 41, 292, 480, 45, "#f59e0bff"):setRotation(-4)

    local inner = makePanel(outer, 138, 185, 230, 126, "#020617cc", "#f8fafcff")
    inner:setClipping(true)
    makePanel(inner, 101, 165, 310, 44, "#22c55eff"):setRotation(18)
    makePanel(inner, 100, 222, 310, 44, "#a855f7dd"):setRotation(-14)
    makeLabel(inner, 153, 229, 200, 32, "inner scissor", "Verdana Bold-11px-new", "#ffffffff", AlignCenter)

    makeLabel(root, 510, 116, 440, 24, "SCROLL-AREA VIEWPORT", "Verdana Bold-11px-new", "#86efacff")
    local scroll = place(g_ui.createWidget("UIScrollArea", root), 510, 146, 440, 205)
    scroll:setBackgroundColor("#0f172aff")
    scroll:setBorderWidth(1)
    scroll:setBorderColor("#4ade80ff")
    for index = 1, 8 do
        local y = 120 + index * 43
        local color = index % 2 == 0 and "#1e293bff" or "#334155ff"
        local row = makePanel(scroll, 532, y, 490, 34, color)
        makePanel(row, 542, y + 8, 18, 18, index % 3 == 0 and "#fb7185ff" or "#34d399ff")
        makeLabel(row, 574, y + 4, 350, 26, string.format("scroll row %02d  /  clipped at the viewport edge", index), nil, "#e2e8f0ff")
    end

    makeLabel(root, 58, 383, 892, 24, "ALPHA COMPOSITION", "Verdana Bold-11px-new", "#fda4afff")
    local alphaCard = makePanel(root, 58, 414, 892, 166, "#0f172aff", "#fb7185ff")
    local alphaColors = { "#ef4444ff", "#22c55eff", "#3b82f6ff", "#f59e0bff", "#a855f7ff" }
    local alphaValues = { 1.0, 0.8, 0.6, 0.4, 0.2 }
    for index, opacity in ipairs(alphaValues) do
        local x = 95 + (index - 1) * 155
        local swatch = makePanel(alphaCard, x, 445, 125, 92, alphaColors[index], "#ffffffff")
        swatch:setOpacity(opacity)
        makeLabel(alphaCard, x, 544, 125, 24, string.format("%d%%", opacity * 100), nil, "#f8fafcff", AlignCenter)
    end
    makePanel(alphaCard, 330, 433, 290, 114, "#38bdf866"):setRotation(5)
    makeLabel(alphaCard, 330, 473, 290, 32, "overlapping translucent parent", "Verdana Bold-11px-new", "#ffffffff", AlignCenter):setRotation(5)
end

function RendererBaseline.buildTextMatrixScene()
    local root = beginClientScene(
        "OpenGL text rendering matrix",
        "Bitmap and TrueType glyphs, TTF strokes, alignment anchors, scaling, and widget rotation"
    )

    local columns = {
        { x = 48, title = "BITMAP", border = "#38bdf8ff" },
        { x = 358, title = "TRUETYPE", border = "#4ade80ff" },
        { x = 668, title = "ALIGNMENT + ROTATION", border = "#c084fcff" }
    }
    for _, column in ipairs(columns) do
        makeLabel(root, column.x + 10, 114, 280, 24, column.title, "Verdana Bold-11px-new", column.border)
        makePanel(root, column.x, 144, 286, 430, "#0f172aff", column.border)
    end

    local bitmapSamples = {
        { font = "verdana-11px-antialised", text = "Antialiased bitmap 012345" },
        { font = "verdana-11px-monochrome", text = "Monochrome bitmap ABC xyz" },
        { font = "Verdana Bold-11px-new", text = "Bold bitmap !? @ # $ %" },
        { font = "Verdana-8px-outline", text = "Outlined bitmap edge sample" }
    }
    for index, sample in ipairs(bitmapSamples) do
        local y = 168 + (index - 1) * 82
        makeLabel(root, 67, y, 248, 24, sample.font, "Verdana-8px-outline", "#94a3b8ff")
        local label = makeLabel(root, 67, y + 27, 248, 38, sample.text, sample.font, "#f8fafcff", AlignCenter)
        label:setBackgroundColor(index % 2 == 0 and "#1e293bff" or "#172033ff")
    end

    local ttfPlain = makeLabel(root, 377, 170, 248, 55, "Verdana TTF 18px\nAa Bb 0123", nil, "#f8fafcff", AlignCenter)
    ttfPlain:setTTFFont("Verdana", 18, 0, "#000000ff")
    ttfPlain:setBackgroundColor("#172033ff")

    local ttfStroke = makeLabel(root, 377, 247, 248, 66, "TTF stroke 2px\ncrisp outline", nil, "#fbbf24ff", AlignCenter)
    ttfStroke:setTTFFont("Verdana", 20, 2, "#7c2d12ff")
    ttfStroke:setBackgroundColor("#1e293bff")

    local scaled = makeLabel(root, 377, 337, 248, 70, "Bitmap scale 1.6", "verdana-11px-antialised", "#67e8f9ff", AlignCenter)
    scaled:setFontScale(1.6)
    scaled:setBackgroundColor("#172033ff")

    local italic = makeLabel(root, 377, 430, 248, 82, "Italic TrueType\nsubpixel curves", nil, "#a7f3d0ff", AlignCenter)
    italic:setTTFFont("Verdana-Italic", 19, 1, "#064e3bff")
    italic:setBackgroundColor("#1e293bff")

    local alignments = {
        { align = AlignTopLeft, label = "top left", color = "#38bdf8ff" },
        { align = AlignCenter, label = "center", color = "#4ade80ff" },
        { align = AlignBottomRight, label = "bottom right", color = "#fb7185ff" }
    }
    for index, sample in ipairs(alignments) do
        local y = 167 + (index - 1) * 83
        local box = makeLabel(root, 687, y, 248, 62, sample.label, "Verdana Bold-11px-new", sample.color, sample.align)
        box:setBackgroundColor("#172033ff")
        box:setBorderWidth(1)
        box:setBorderColor(sample.color)
    end

    local rotatedLeft = makeLabel(root, 696, 430, 150, 42, "rotation -12 deg", "Verdana Bold-11px-new", "#f9a8d4ff", AlignCenter)
    rotatedLeft:setBackgroundColor("#831843cc")
    rotatedLeft:setRotation(-12)

    local rotatedRight = makeLabel(root, 790, 493, 150, 42, "rotation +17 deg", "Verdana Bold-11px-new", "#ddd6feff", AlignCenter)
    rotatedRight:setBackgroundColor("#5b21b6cc")
    rotatedRight:setRotation(17)
end

local function makeParticleCard(root, x, title, mode, effectName, accent)
    makeLabel(root, x + 10, 118, 270, 24, title, "Verdana Bold-11px-new", accent)
    local card = makePanel(root, x, 148, 286, 390, "#0f172aff", accent)

    local tileColors = { "#f8fafcff", "#64748bff" }
    for row = 0, 5 do
        for column = 0, 3 do
            makePanel(card, x + 23 + column * 60, 181 + row * 48, 60, 48, tileColors[(row + column) % 2 + 1])
        end
    end

    local particles = place(g_ui.createWidget("UIParticles", card), x + 23, 181, 240, 288)
    particles:setEffect(effectName)
    makeLabel(card, x + 23, 481, 240, 30, mode, "Verdana Bold-11px-new", "#ffffffff", AlignCenter):setBackgroundColor("#020617dd")
    return particles
end

function RendererBaseline.buildParticlesBlendScene()
    if not g_particles.importParticle("/modules/dev_renderer_baseline/renderer-baseline-particles.otps") then
        fail("failed to import deterministic particle definitions")
        return false
    end

    local root = beginClientScene(
        "OpenGL particle composition modes",
        "One fixed particle per card exercises the three blend modes used by live rendering"
    )

    makeParticleCard(root, 48, "NORMAL", "SRC_A, 1 - SRC_A", "renderer-baseline-normal", "#fb7185ff")
    makeParticleCard(root, 358, "MULTIPLY", "DST_COLOR, 1 - SRC_A", "renderer-baseline-multiply", "#67e8f9ff")
    makeParticleCard(root, 668, "ADD (LEGACY)", "1 - SRC_COLOR (both)", "renderer-baseline-add-weird", "#fde047ff")

    makeLabel(root, 48, 558, 906, 32, "Static single-burst emitters remove timing and random-position variance while retaining the real particle draw path.", nil, "#94a3b8ff", AlignCenter)
    return true
end

local function makeOutfitCard(root, x, title, outfit, description, shader, previewSize)
    makeLabel(root, x + 8, 118, 160, 24, title, "Verdana Bold-11px-new", "#f0abfcff", AlignCenter)
    local card = makePanel(root, x, 148, 174, 390, "#0f172aff", "#c084fcff")
    makePanel(card, x + 12, 174, 150, 150, "#334155ff")
    previewSize = previewSize or 150
    local previewInset = math.floor((150 - previewSize) / 2)
    local preview = place(g_ui.createWidget("UICreature", card), x + 12 + previewInset, 174 + previewInset, previewSize, previewSize)
    preview:setOutfit(outfit)
    preview:setDirection(South)
    preview:setAutoFit(false)
    local creature = preview:getCreature()
    if creature then
        creature:setAnimate(false)
    end
    if shader then
        preview:setShader(shader)
    end
    makeLabel(card, x + 14, 344, 146, 72, description, "verdana-11px-antialised", "#e2e8f0ff", AlignTopCenter):setTextWrap(true)
    return preview
end

function RendererBaseline.buildOutfitMaskScene()
    local root = beginClientScene(
        "OpenGL outfit masks and preview framebuffers",
        "Fixed creature previews cover recolor layers, addon patterns, mounts, and the framebuffer-backed outline shader"
    )

    local coloredOutfit = { type = 128, head = 9, body = 40, legs = 80, feet = 114, addons = 0, mount = 0 }
    makeOutfitCard(root, 48, "BASE", coloredOutfit, "Four independent mask colors\nMULTIPLY composition")
    makeOutfitCard(root, 232, "ADDONS", { type = 128, head = 9, body = 40, legs = 80, feet = 114, addons = 3, mount = 0 }, "Both addon pattern layers\ninside the preview FBO")
    makeOutfitCard(root, 416, "MOUNT", { type = 128, head = 9, body = 40, legs = 80, feet = 114, addons = 0, mount = 368 }, "Mounted z-pattern with\noutfit color masks")
    makeOutfitCard(root, 600, "OUTLINE", coloredOutfit, "Nested framebuffer path\nplus animated fragment shader", "Outfit - Outline", 80)
    makeOutfitCard(root, 784, "ALT COLORS", { type = 128, head = 114, body = 80, legs = 40, feet = 9, addons = 1, mount = 0 }, "Reordered mask palette\nwith addon one")

    makeLabel(root, 48, 558, 910, 32, "Creature animation is frozen; only the outline shader's surveyed time-based brightness remains live.", nil, "#94a3b8ff", AlignCenter)
    return true
end

local function makeFboCard(root, x, y, width, height, title, accent)
    makeLabel(root, x + 8, y - 28, width - 16, 24, title, "Verdana Bold-11px-new", accent, AlignCenter)
    return makePanel(root, x, y, width, height, "#0f172aff", accent)
end

function RendererBaseline.buildTemporaryFramebufferScene()
    local root = beginClientScene(
        "OpenGL temporary framebuffer matrix",
        "Every surveyed offscreen-widget idiom is represented, including flip blits and nested shader framebuffers"
    )

    local outfit = { type = 128, head = 9, body = 40, legs = 80, feet = 114, addons = 3, mount = 0 }

    local creatureCard = makeFboCard(root, 48, 146, 286, 176, "CREATURE PREVIEW", "#38bdf8ff")
    local creature = place(g_ui.createWidget("UICreature", creatureCard), 116, 158, 150, 150)
    creature:setOutfit(outfit)
    creature:setDirection(South)
    creature:getCreature():setAnimate(false)

    local outlineCard = makeFboCard(root, 358, 146, 286, 176, "OUTLINE + NESTED FBO", "#c084fcff")
    local outline = place(g_ui.createWidget("UICreature", outlineCard), 466, 189, 70, 70)
    outline:setOutfit(outfit)
    outline:setDirection(South)
    outline:getCreature():setAnimate(false)
    outline:setShader("Outfit - Outline")

    local itemCard = makeFboCard(root, 668, 146, 286, 176, "ITEM BLIT FLIPS", "#4ade80ff")
    local itemFlips = {
        { value = 0, label = "none" },
        { value = 1, label = "horizontal" },
        { value = 2, label = "vertical" }
    }
    for index, flip in ipairs(itemFlips) do
        local x = 684 + (index - 1) * 86
        local item = place(g_ui.createWidget("UIItem", itemCard), x, 174, 76, 76)
        item:setBackgroundColor("#334155ff")
        item:setItemId(3582)
        item:setFlipDirection(flip.value)
        if item:getItem() then
            item:getItem():setAnimate(false)
        end
        makeLabel(itemCard, x, 262, 76, 24, flip.label, "Verdana-8px-outline", "#e2e8f0ff", AlignCenter)
    end

    local effectCard = makeFboCard(root, 48, 382, 286, 176, "EFFECT WIDGET", "#fb7185ff")
    local effect = place(g_ui.createWidget("UIEffect", effectCard), 111, 394, 160, 150)
    effect:setBackgroundColor("#334155ff")
    effect:setEffectId(1)
    if effect:getEffect() then
        effect:getEffect():setAnimate(false)
    end

    local missileCard = makeFboCard(root, 358, 382, 286, 176, "MISSILE WIDGET", "#fbbf24ff")
    local missile = place(g_ui.createWidget("UIMissile", missileCard), 421, 394, 160, 150)
    missile:setBackgroundColor("#334155ff")
    missile:setMissileId(1)
    missile:setDirection(SouthEast)
    if missile:getMissile() then
        missile:getMissile():setAnimate(false)
    end

    local spellCard = makeFboCard(root, 668, 382, 286, 176, "SPELL PREVIEW", "#60a5faff")
    local spell = place(g_ui.createWidget("UISpellPreview", spellCard), 680, 394, 262, 150)
    spell:setGridBounds(-1, -1, 1, 1)
    spell:addObject(0, 0, 3582)
    spell:setTargetPosition(1, 0)

    makeLabel(root, 48, 582, 906, 26, "Creature, ThingType, item, effect, missile, and spell-preview paths all allocate and composite temporary targets.", nil, "#94a3b8ff", AlignCenter)
    return true
end

function RendererBaseline.buildCompositionScene()
    local root = beginClientScene(
        "OpenGL composition mode matrix",
        "A native fixture submits identical solid geometry through every painter blend descriptor"
    )

    local fixture = place(g_ui.createWidget("UICompositionFixture", root), 48, 152, 924, 278)
    fixture:setBackgroundColor("#020617ff")
    fixture:setBorderWidth(1)
    fixture:setBorderColor("#64748bff")

    local modes = {
        { name = "NORMAL", formula = "SRC_A / 1-SRC_A", live = true, color = "#fb7185ff" },
        { name = "MULTIPLY", formula = "DST_COLOR / 1-SRC_A", live = true, color = "#67e8f9ff" },
        { name = "ADD", formula = "1-SRC_COLOR (both)", live = true, color = "#fde047ff" },
        { name = "REPLACE", formula = "ONE / ZERO", live = false, color = "#c4b5fdff" },
        { name = "DESTINATION", formula = "1-DST_A / DST_A", live = false, color = "#86efacff" },
        { name = "LIGHT", formula = "ZERO / SRC_COLOR", live = false, color = "#fdba74ff" }
    }
    for index, mode in ipairs(modes) do
        local x = 48 + (index - 1) * 156
        makeLabel(root, x, 449, 144, 24, mode.name, "Verdana Bold-11px-new", mode.color, AlignCenter)
        makeLabel(root, x, 475, 144, 34, mode.formula, "Verdana-8px-outline", "#e2e8f0ff", AlignCenter):setTextWrap(true)
        makeLabel(root, x, 516, 144, 24, mode.live and "live caller" or "descriptor only", nil, mode.live and "#4ade80ff" or "#94a3b8ff", AlignCenter)
    end

    makeLabel(root, 48, 572, 924, 28, "The destination cell intentionally remains unchanged over opaque content; that is the defined destination-alpha equation.", nil, "#94a3b8ff", AlignCenter)
    return true
end

function RendererBaseline.buildGraphLineScene()
    local root = beginClientScene(
        "OpenGL line-strip geometry",
        "Fixed UIGraph samples exercise line smoothing, joins, slopes, and the surveyed wide-line states"
    )

    local graph = place(g_ui.createWidget("UIGraph", root), 78, 138, 864, 392)
    graph:setBackgroundColor("#0f172aff")
    graph:setBorderWidth(1)
    graph:setBorderColor("#475569ff")
    graph:setPadding(28)
    graph:setFont("verdana-11px-antialised")
    graph:setTitle("DETERMINISTIC SAMPLE SERIES")
    graph:setCapacity(25)
    graph:setShowLabels(true)
    graph:setShowInfo(false)

    local series = {
        {
            color = "#38bdf8ff",
            width = 1,
            values = { 12, 18, 16, 29, 35, 31, 44, 39, 52, 48, 63, 57, 71, 66, 78, 73, 85, 76, 91, 83, 96, 88, 99, 93, 104 }
        },
        {
            color = "#f472b6ff",
            width = 3,
            values = { 88, 82, 91, 76, 69, 73, 58, 64, 49, 55, 42, 48, 34, 40, 27, 35, 22, 31, 18, 28, 15, 24, 12, 20, 9 }
        },
        {
            color = "#facc15ff",
            width = 6,
            values = { 45, 58, 72, 61, 43, 29, 36, 55, 74, 81, 67, 46, 31, 24, 39, 62, 79, 86, 70, 51, 34, 28, 44, 68, 82 }
        }
    }

    for _, sample in ipairs(series) do
        local index = graph:createGraph()
        graph:setLineColor(index, sample.color)
        graph:setLineWidth(index, sample.width)
        for _, value in ipairs(sample.values) do
            graph:addValue(index, value)
        end
    end

    local legend = {
        { x = 188, color = "#38bdf8ff", text = "1 px line" },
        { x = 438, color = "#f472b6ff", text = "3 px line" },
        { x = 688, color = "#facc15ff", text = "6 px line" }
    }
    for _, entry in ipairs(legend) do
        makePanel(root, entry.x, 558, 42, 5, entry.color)
        makeLabel(root, entry.x + 52, 546, 150, 28, entry.text, "Verdana Bold-11px-new", entry.color, AlignLeft)
    end

    return true
end

function RendererBaseline.buildAtlasResourceScene()
    local root = beginClientScene(
        "OpenGL atlas resource lifecycle",
        "Smooth-padding uploads, multi-layer growth, a large sheet, APNG frame upload, and cache reload"
    )

    local atlasPaths = {}
    local quadrants = { "bottom_left", "bottom_right", "top_left", "top_right" }
    for _, quadrant in ipairs(quadrants) do
        for image = 1, 4 do
            table.insert(atlasPaths, string.format("/images/game/wheel/wheel-border/%s/%d", quadrant, image))
        end
    end

    local atlasWidgets = {}
    for index, path in ipairs(atlasPaths) do
        local column = (index - 1) % 8
        local row = math.floor((index - 1) / 8)
        local x = 70 + column * 110
        local y = 136 + row * 116
        local tile = place(g_ui.createWidget("UIWidget", root), x, y, 96, 96)
        tile:setBackgroundColor("#0f172aff")
        tile:setBorderWidth(1)
        tile:setBorderColor(row == 0 and "#38bdf8ff" or "#c084fcff")
        tile:setImageSmooth(true)
        tile:setImageFixedRatio(true)
        tile:setImageSource(path)
        atlasWidgets[index] = tile
        makeLabel(root, x, y + 94, 96, 18, string.format("L%02d", index), "Verdana-8px-outline", "#cbd5e1ff", AlignCenter)
    end

    local large = place(g_ui.createWidget("UIWidget", root), 70, 396, 510, 122)
    large:setBackgroundColor("#0f172aff")
    large:setBorderWidth(1)
    large:setBorderColor("#4ade80ff")
    large:setImageSmooth(true)
    large:setImageFixedRatio(true)
    large:setImageSource("/images/game/imbuing/imbuement-icons-64")

    local animated = place(g_ui.createWidget("UIWidget", root), 610, 396, 330, 122)
    animated:setBackgroundColor("#0f172aff")
    animated:setBorderWidth(1)
    animated:setBorderColor("#f59e0bff")
    animated:setImageSmooth(true)
    animated:setImageFixedRatio(true)
    animated:setImageSource("/images/ui/dragon-animated")

    makeLabel(root, 70, 528, 510, 22, "1344 x 320 atlas-eligible sheet", "Verdana Bold-11px-new", "#4ade80ff", AlignCenter)
    makeLabel(root, 610, 528, 330, 22, "APNG frame frozen after cache release", "Verdana Bold-11px-new", "#f59e0bff", AlignCenter)
    local stats = makeLabel(root, 70, 558, 870, 34, "Waiting for atlas flush...", "Verdana-8px-outline", "#94a3b8ff", AlignCenter)

    setupEvent = scheduleEvent(function()
        setupEvent = nil
        local before = g_atlas.getStats()
        for index = 1, 4 do
            atlasWidgets[index]:setImageSource("")
        end
        g_textures.clearCache()
        collectgarbage()

        setupEvent = scheduleEvent(function()
            setupEvent = nil
            for index = 1, 4 do
                atlasWidgets[index]:setImageSource(atlasPaths[index])
            end

            setupEvent = scheduleEvent(function()
                setupEvent = nil
                local after = g_atlas.getStats()
                g_logger.info("[renderer-baseline] atlas before reload: " .. before)
                g_logger.info("[renderer-baseline] atlas after reload: " .. after)
                stats:setText("linear atlas grew past one layer; four 522 px entries were released and reloaded")
            end, 600)
        end, 250)
    end, 600)

    return true
end

-- Everything that must be true of the frame at the instant it is captured. Shared by the
-- full-window path and the MAP framebuffer readback: the readback samples the MAP pool, so
-- animation frozen here matters there too even though the UI hardening does not.
local function prepareForShutter()
    pinLoginBackground()
    suppressCaptureTooltip()
    isolateGameInterface()
    pinInterfaceLayout()
    applyLightingSetup()
    clearOnScreenMessages()
    freezeMapAnimation()
end

-- Every fragment program the client ships, exercised against one identical textured cell so
-- any difference between cells is the shader and nothing else.
--
-- Map shaders cannot be exercised in their real route offline: Client::canDraw(MAP) is
-- literally g_game.isOnline(), so a UIMap with no connection produces no MAP-pool content and
-- the map-composition bind at mapview.cpp is unreachable. Their fragment programs are still
-- reachable, because a plain UIWidget can carry any registered shader -- production code
-- already does this, the bestiary puts a map shader on a text input. So this scene covers
-- every .frag; a later online scene has to cover the map-composition route itself.
--
-- The cells must be textured. Painter::drawCoords only binds the extra multi-texture units
-- inside its textured branch, and an untextured draw leaves the texcoord attribute disabled
-- and v_TexCoord undefined, so a solid-colour cell would not exercise Fog or Snow at all.
-- A large, fully opaque image. A mostly-transparent one left half the cells reading as
-- black, and being too large for the atlas keeps it out of atlas packing, so the
-- offset-sampling shaders (bloom, radial blur, zomg, pulse, heat, noise) cannot pick up
-- whatever happens to be packed next to it.
local SHADER_CELL_IMAGE = "/images/background_crystal1"

local MAP_FRAGMENT_SHADERS = {
    "Map - Fog", "Map - Rain", "Map - Snow", "Map - Gray Scale", "Map - Bloom",
    "Map - Sepia", "Map - Pulse", "Map - Old Tv", "Map - Party", "Map - Radial Blur",
    "Map - Zomg", "Map - Heat", "Map - Noise"
}

local OTHER_FRAGMENT_SHADERS = { "Hover - Desaturate", "Mount - Rainbow", "forge_result_silhouette" }

local OUTFIT_SHADERS = {
    "Outfit - Rainbow", "Outfit - Ghost", "Outfit - Jelly",
    "Outfit - Fragmented", "Outfit - cyclopedia-black", "Outfit - Outline"
}

local function makeShaderCell(root, x, y, width, height, label, shaderName)
    local cell = makePanel(root, x, y, width, height, "#0f172aff", "#334155ff")
    local image = place(g_ui.createWidget("UIWidget", cell), x + 6, y + 6, width - 12, height - 26)
    image:setImageSource(SHADER_CELL_IMAGE)

    if shaderName then
        if g_shaders.getShader(shaderName) then
            image:setShader(shaderName)
        else
            -- Not a capture failure: forge_result_silhouette is registered by
            -- game_exaltationforge's onLoad, which does not come up in an environment without
            -- game assets. The cell simply renders unshaded there. This must not go through
            -- g_logger.error, which CI reads as a failed capture.
            g_logger.info("[renderer-baseline] shader unavailable in this environment: " .. shaderName)
        end
    end

    makeLabel(cell, x + 2, y + height - 20, width - 4, 18, label,
        "Verdana-8px-outline", "#e2e8f0ff", AlignCenter)
    return image
end

-- Both shader scenes share one grid so a cell keeps its geometry across the fragment/outfit
-- split: the fragment cells still occupy rows 0-2 at exactly the coordinates they held when
-- the outfit row was part of this scene.
local SHADER_GRID = { x = 48, y = 104, columns = 6, cellWidth = 148, cellHeight = 118, gap = 8 }

local function shaderCellOrigin(index)
    local column = (index - 1) % SHADER_GRID.columns
    local row = math.floor((index - 1) / SHADER_GRID.columns)
    return SHADER_GRID.x + column * (SHADER_GRID.cellWidth + SHADER_GRID.gap),
        SHADER_GRID.y + row * (SHADER_GRID.cellHeight + SHADER_GRID.gap)
end

function RendererBaseline.buildShaderMatrixScene()
    local root = beginClientScene(
        "OpenGL shader matrix",
        "Every shipped fragment program over one identical textured cell, with u_Time pinned"
    )

    local cells = {}
    for _, name in ipairs(MAP_FRAGMENT_SHADERS) do
        table.insert(cells, { label = name:gsub("^Map %- ", ""), shader = name })
    end
    for _, name in ipairs(OTHER_FRAGMENT_SHADERS) do
        table.insert(cells, { label = name:gsub("^Mount %- ", "Mount "):gsub("^Hover %- ", ""), shader = name })
    end
    table.insert(cells, { label = "no shader", shader = nil })

    for index, cell in ipairs(cells) do
        local x, y = shaderCellOrigin(index)
        makeShaderCell(root, x, y, SHADER_GRID.cellWidth, SHADER_GRID.cellHeight,
            cell.label, cell.shader)
    end

    return true
end

-- The outfit shaders in their real route, split out of shader-matrix so the fragment half can
-- be CI-gated. These cells render UICreature previews from data/things/*, which is gitignored,
-- so a runner without game assets draws them empty; gating that would freeze a blank image as
-- the accepted reference. The fragment cells have no such dependency -- they draw a tracked
-- image from data/images -- which is the whole reason for the split.
--
-- Outline is the only shader in the registry declaring useFramebuffer, and that route is
-- honoured for Creature and ThingType draws, so this scene is the only automated coverage of
-- a shader applied at an offscreen blit.
local OUTFIT_SHADER_OUTFIT = { type = 128, head = 9, body = 40, legs = 80, feet = 114, addons = 0, mount = 0 }

local function makeOutfitShaderCard(root, index, name)
    local x, y = shaderCellOrigin(index)
    local width, height = SHADER_GRID.cellWidth, SHADER_GRID.cellHeight
    local card = makePanel(root, x, y, width, height, "#0f172aff", "#c084fcff")
    local preview = place(g_ui.createWidget("UICreature", card), x + 34, y + 4, 80, 80)
    preview:setOutfit(OUTFIT_SHADER_OUTFIT)
    preview:setDirection(South)
    preview:setAutoFit(false)

    local creature = preview:getCreature()
    if creature then
        creature:setAnimate(false)
    end

    if g_shaders.getShader(name) then
        preview:setShader(name)
    else
        g_logger.info("[renderer-baseline] shader unavailable in this environment: " .. name)
    end

    makeLabel(card, x + 2, y + height - 22, width - 4, 18,
        name:gsub("^Outfit %- ", ""), "Verdana-8px-outline", "#f0abfcff", AlignCenter)
    return preview
end

function RendererBaseline.buildShaderMatrixOutfitsScene()
    local root = beginClientScene(
        "OpenGL outfit shader matrix",
        "Every outfit shader on a creature preview, including the only useFramebuffer route"
    )

    for index, name in ipairs(OUTFIT_SHADERS) do
        makeOutfitShaderCard(root, index, name)
    end

    return true
end

local function resolveCaptureTarget(outputName)
    if outputName:find("[/\\]") or not outputName:match("^[%w%._%-]+%.png$") then
        fail("--renderer-baseline-output must be a PNG filename without a directory")
        return nil
    end

    if not g_resources.directoryExists("/render-baselines") then
        g_resources.makeDir("/render-baselines")
    end

    local virtualPath = "/render-baselines/" .. outputName
    if g_resources.fileExists(virtualPath) then
        g_resources.deleteFile(virtualPath)
    end

    return virtualPath, g_resources.getWriteDir() .. "render-baselines/" .. outputName
end

local function logCaptureGeometry()
    -- Baseline provenance depends on the geometry the capture was actually taken at; a
    -- drifting map panel is otherwise only visible as a large unexplained pixel diff.
    local mapPanel = modules.game_interface and modules.game_interface.getMapPanel
        and modules.game_interface.getMapPanel()
    if mapPanel and not mapPanel:isDestroyed() then
        local rect = mapPanel:getRect()
        g_logger.info(string.format("[renderer-baseline] map panel rect=%d,%d %dx%d",
            rect.x, rect.y, rect.width, rect.height))
    end
end

-- Take one screenshot and hand control to onComplete once the encoder has finished with it.
-- The terminal action is a parameter rather than a hardcoded exit, so a multi-step scene can
-- chain captures; every single-capture scene simply passes g_app.exit.
local function takeCapture(outputName, onComplete)
    local virtualPath, realPath = resolveCaptureTarget(outputName)
    if not virtualPath then
        return
    end

    g_logger.info("[renderer-baseline] capturing to " .. realPath)
    prepareForShutter()
    logCaptureGeometry()
    g_app.doScreenshot(virtualPath)

    -- Screenshot encoding is dispatched asynchronously. Poll for the new file, then leave a
    -- short settle period because the encoder can still own application resources after the
    -- directory entry becomes visible.
    local attempts = 0
    local function waitForCapture()
        attempts = attempts + 1
        if g_resources.fileExists(virtualPath) then
            exitEvent = scheduleEvent(function()
                g_logger.info("[renderer-baseline] capture complete: " .. realPath)
                onComplete()
            end, 1500)
        elseif attempts >= 100 then
            fail("capture timed out after 10 seconds: " .. realPath)
        else
            exitEvent = scheduleEvent(waitForCapture, 100)
        end
    end

    exitEvent = scheduleEvent(waitForCapture, 100)
end

function RendererBaseline.captureScene(scene, delay)
    local outputName = optionValue("renderer-baseline-output") or (scene .. ".png")

    -- A fixed logical viewport keeps same-backend comparisons meaningful. The normal
    -- startup flow has finished by the time this delayed event fires, so fonts, images,
    -- clipping, translucent widgets, and the initial framebuffer resize are all live.
    g_window.resize({ width = CAPTURE_WIDTH, height = CAPTURE_HEIGHT })

    captureEvent = scheduleEvent(function()
        -- Startup modules can open windows after onRun. Keep scripted fixtures above
        -- them, then allow one frame to repaint before requesting the screenshot.
        if sceneRoot then
            isolateClientScene()
        end

        captureEvent = scheduleEvent(function()
            takeCapture(outputName, function() g_app.exit() end)
        end, 250)
    end, delay)
end

-- windowing is the only multi-capture scene. It drives the real startup UI -- which is
-- anchored and genuinely reflows -- through a sequence of window states, capturing after each.
--
-- Only resize and display density are assertable from an image. doScreenshot reads the
-- PHYSICAL viewport, so a resize changes the PNG dimensions outright, and a HUD-scale change
-- is a real difference rather than a rescale: GraphicalApplication::resize sizes the UI and
-- the FOREGROUND framebuffer at viewport/scale, but that framebuffer is blitted 1:1 into a
-- destination rect equal to its own size inside a painter at full physical resolution.
--
-- focus is not assertable at all: hasFocus() has no consumers anywhere in the tree, so it is
-- a pure state bit. fullscreen and maximize are honoured by a real window manager but are
-- silently dropped under a headless X server, while the client still flips its own state
-- bits -- so asserting isFullscreen() headlessly would be a false positive. Both are recorded
-- as state alongside the images rather than being pretended to be pixels.
--
-- The window is only ever made SMALLER than the capture size: a headless X server is
-- typically created at exactly the capture size, and growing past it would exceed the root
-- window.
--
-- The window can only be tested by GROWING it: modules/startup/startup.lua sets a desktop
-- minimum size of exactly the capture size (1020x644), so the window manager clamps any
-- smaller request and the resize never lands. A headless X server created at exactly the
-- capture size therefore cannot exercise the resize step at all, which is one more reason
-- this scene is not CI-gated.
local WINDOWING_LARGE = { width = 1200, height = 700 }

local function windowingReportLine(label)
    local size = g_window.getSize()
    local position = g_window.getPosition()
    return string.format(
        "%-10s size=%dx%d position=%d,%d density=%.2f scaled=%s fullscreen=%s maximized=%s focus=%s visible=%s",
        label, size.width, size.height, position.x, position.y,
        g_window.getDisplayDensity(), tostring(g_app.isScaled()),
        tostring(g_window.isFullscreen()), tostring(g_window.isMaximized()),
        tostring(g_window.hasFocus()), tostring(g_window.isVisible()))
end

-- X11Window::resize is posted to the main dispatcher and the client's own size only updates
-- later, from ConfigureNotify inside poll(). Poll for the landed value rather than trusting a
-- fixed delay.
local function waitForWindowSize(width, height, onReady, attempts)
    attempts = (attempts or 0) + 1
    local size = g_window.getSize()

    if size.width == width and size.height == height then
        setupEvent = scheduleEvent(onReady, 400)
    elseif attempts >= 60 then
        g_logger.error(string.format(
            "[renderer-baseline] window never reached %dx%d, stuck at %dx%d", width, height,
            size.width, size.height))
        setupEvent = scheduleEvent(onReady, 400)
    else
        setupEvent = scheduleEvent(function()
            waitForWindowSize(width, height, onReady, attempts)
        end, 100)
    end
end

function RendererBaseline.runWindowingScene()
    local base = (optionValue("renderer-baseline-output") or "windowing.png"):gsub("%.png$", "")
    local report = {}

    local function output(suffix)
        return string.format("%s-%s.png", base, suffix)
    end

    local function finish()
        report[#report + 1] = "platform=" .. g_window.getPlatformType()
        report[#report + 1] = "display=" .. g_window.getDisplayWidth() .. "x" .. g_window.getDisplayHeight()

        if not g_resources.directoryExists("/render-baselines") then
            g_resources.makeDir("/render-baselines")
        end

        local path = "/render-baselines/" .. base .. "-state.txt"
        g_resources.writeFileContents(path, table.concat(report, "\n") .. "\n")
        g_logger.info("[renderer-baseline] window state written: "
            .. g_resources.getWriteDir() .. "render-baselines/" .. base .. "-state.txt")
        g_app.exit()
    end

    -- The fullscreen and focus probe runs LAST and takes no image. Toggling fullscreen
    -- recreates the window, and the framebuffer read back immediately afterwards came out
    -- entirely black, so no capture may follow it. focus is unobservable in an image anyway,
    -- and a headless X server has no window manager to honour the request while the client
    -- still flips its own state bit -- so both are recorded as state, never asserted as pixels.
    local function stepStateProbe()
        g_window.setFullscreen(true)
        setupEvent = scheduleEvent(function()
            report[#report + 1] = windowingReportLine("fullscreen")
            g_window.setFullscreen(false)

            setupEvent = scheduleEvent(function()
                report[#report + 1] = windowingReportLine("windowed")
                finish()
            end, 800)
        end, 800)
    end

    local function stepScaled()
        g_app.setHUDScale(2)
        setupEvent = scheduleEvent(function()
            report[#report + 1] = windowingReportLine("scaled")
            takeCapture(output("4-scaled"), function()
                g_app.setHUDScale(1)
                setupEvent = scheduleEvent(stepStateProbe, 400)
            end)
        end, 800)
    end

    local function stepRestored()
        g_window.resize({ width = CAPTURE_WIDTH, height = CAPTURE_HEIGHT })
        waitForWindowSize(CAPTURE_WIDTH, CAPTURE_HEIGHT, function()
            report[#report + 1] = windowingReportLine("restored")
            takeCapture(output("3-restored"), stepScaled)
        end)
    end

    local function stepGrown()
        g_window.resize(WINDOWING_LARGE)
        waitForWindowSize(WINDOWING_LARGE.width, WINDOWING_LARGE.height, function()
            report[#report + 1] = windowingReportLine("grown")
            takeCapture(output("2-grown"), stepRestored)
        end)
    end

    g_window.resize({ width = CAPTURE_WIDTH, height = CAPTURE_HEIGHT })
    waitForWindowSize(CAPTURE_WIDTH, CAPTURE_HEIGHT, function()
        report[#report + 1] = windowingReportLine("initial")
        takeCapture(output("1-initial"), stepGrown)
    end)
end

-- shader-matrix-map covers what shader-matrix structurally cannot: the map-composition
-- route. A map shader is bound at the MAP framebuffer to screen blit through the pool's
-- onBeforeDraw hook, and that hook is also where the four map uniforms are written. None of
-- it is reachable offline, because Client::canDraw(MAP) is literally g_game.isOnline().
--
-- A map shader applies to the whole composed map, so only one can be shown per frame. This
-- is therefore a multi-capture scene: one image per shader, plus a Default frame to diff
-- against. Fade is set to 0/0, which makes the switch immediate and removes the only
-- timing-dependent term besides u_Time, and u_Time is already pinned.
--
-- drawViewportEdge is carried per shader in the registry and changes which tiles the map view
-- renders, so it has to be applied alongside the shader exactly as game_shaders does.
local MAP_SHADER_SEQUENCE = {
    { name = "Default" },
    { name = "Map - Fog" },
    { name = "Map - Rain" },
    { name = "Map - Snow" },
    { name = "Map - Gray Scale" },
    { name = "Map - Bloom" },
    { name = "Map - Sepia" },
    { name = "Map - Pulse", edge = true },
    { name = "Map - Old Tv" },
    { name = "Map - Party" },
    { name = "Map - Radial Blur", edge = true },
    { name = "Map - Zomg", edge = true },
    { name = "Map - Heat", edge = true },
    { name = "Map - Noise" }
}

function RendererBaseline.runMapShaderScene()
    local base = (optionValue("renderer-baseline-output") or "shader-matrix-map.png"):gsub("%.png$", "")
    local index = 0

    local function slug(name)
        return name:gsub("^Map %- ", ""):gsub("%s+", "-"):lower()
    end

    local function captureNext()
        index = index + 1
        local entry = MAP_SHADER_SEQUENCE[index]

        if not entry then
            g_logger.info(string.format("[renderer-baseline] captured %d map shaders",
                #MAP_SHADER_SEQUENCE))
            g_app.exit()
            return
        end

        local mapPanel = modules.game_interface and modules.game_interface.getMapPanel
            and modules.game_interface.getMapPanel()
        if not mapPanel or mapPanel:isDestroyed() then
            fail("no map panel available for shader-matrix-map")
            return
        end

        if entry.name ~= "Default" and not g_shaders.getShader(entry.name) then
            g_logger.info("[renderer-baseline] shader unavailable in this environment: " .. entry.name)
        end

        mapPanel:setShader(entry.name, 0, 0)
        mapPanel:setDrawViewportEdge(entry.edge == true)

        -- Let the switch land and the map repaint before the shutter. A shader keeps its pool
        -- repainting, so the frame never settles by itself; this only has to outlast the bind.
        setupEvent = scheduleEvent(function()
            takeCapture(string.format("%s-%02d-%s.png", base, index, slug(entry.name)), captureNext)
        end, 900)
    end

    captureNext()
end

function RendererBaseline.captureMapScreenshot(scene, delay)
    local outputName = optionValue("renderer-baseline-output") or (scene .. ".png")
    if outputName:find("[/\\]") or not outputName:match("^[%w%._%-]+%.png$") then
        fail("--renderer-baseline-output must be a PNG filename without a directory")
        return
    end

    if not g_resources.directoryExists("/render-baselines") then
        g_resources.makeDir("/render-baselines")
    end

    local virtualPath = "/render-baselines/" .. outputName
    local realPath = g_resources.getWriteDir() .. "render-baselines/" .. outputName
    if g_resources.fileExists(virtualPath) then
        g_resources.deleteFile(virtualPath)
    end

    g_logger.info("[renderer-baseline] capturing " .. scene .. " to " .. realPath)
    -- Only the animation freeze applies to a MAP framebuffer readback. The rest of the
    -- shutter hardening -- tooltips, interface isolation, the splitter, on-screen messages --
    -- concerns the FOREGROUND pool, which this readback does not sample, and running the
    -- interface isolation immediately before doMapScreenshot relayouts the widget tree and
    -- intermittently leaves it without a map widget to read back from.
    captureEvent = scheduleEvent(freezeMapAnimation, math.max(delay - 500, 0))

    captureEvent = scheduleEvent(function()
        g_app.doMapScreenshot(virtualPath)

        local attempts = 0
        local function waitForCapture()
            attempts = attempts + 1
            if g_resources.fileExists(virtualPath) then
                exitEvent = scheduleEvent(function()
                    g_logger.info("[renderer-baseline] capture complete: " .. realPath)
                    g_app.exit()
                end, 1500)
            elseif attempts >= 100 then
                fail("capture timed out after 10 seconds: " .. realPath)
            else
                exitEvent = scheduleEvent(waitForCapture, 100)
            end
        end

        exitEvent = scheduleEvent(waitForCapture, 100)
    end, delay)
end

function RendererBaseline.loginFixtureServer()
    -- Size the window before logging in. game_interface.show() computes the map panel
    -- geometry from the window size at the instant the game starts, and captureScene()
    -- only resizes once that has already happened, so an online capture raced the
    -- resize and produced a differently sized map panel from run to run. Offline scenes
    -- never had the problem because beginClientScene() resizes during onRun.
    g_window.resize({ width = CAPTURE_WIDTH, height = CAPTURE_HEIGHT })

    local account = os.getenv("CRYSTALOTC_BASELINE_ACCOUNT")
    local password = os.getenv("CRYSTALOTC_BASELINE_PASSWORD")
    local character = os.getenv("CRYSTALOTC_BASELINE_CHARACTER")
    local host = os.getenv("CRYSTALOTC_BASELINE_HOST") or "127.0.0.1"
    local port = tonumber(os.getenv("CRYSTALOTC_BASELINE_PORT")) or 7182
    local clientVersion = tonumber(os.getenv("CRYSTALOTC_BASELINE_VERSION")) or 1525

    if not account or not password or not character then
        fail("online scenes require CRYSTALOTC_BASELINE_ACCOUNT, CRYSTALOTC_BASELINE_PASSWORD, and CRYSTALOTC_BASELINE_CHARACTER")
        return
    end

    g_game.setClientVersion(clientVersion)
    g_game.setProtocolVersion(g_game.getClientProtocolVersion(clientVersion))
    g_game.chooseRsa(host)

    if not modules.game_things.isLoaded() then
        fail("client assets failed to load for version " .. clientVersion)
        return
    end

    g_logger.info(string.format("[renderer-baseline] connecting %s to %s:%d with protocol %d", character, host, port, clientVersion))
    if EnterGame and EnterGame.hide then
        EnterGame.hide()
    end
    g_game.loginWorld(account, password, "Crystal", host, port, character, "", account .. "\n" .. password)

    loginTimeoutEvent = scheduleEvent(function()
        loginTimeoutEvent = nil
        fail("fixture-server login timed out after 30 seconds")
    end, 30000)
end

-- lighting-overlap proves the CPU light bitmap, its dynamic texture upload and the
-- MULTIPLY overlay. It only works underground and only for a character WITHOUT the
-- hasfulllight group flag: that flag makes the server report world light 255 and every
-- creature light 255/215, and the client skips the whole LIGHT pool once ambient
-- intensity reaches 250. Underground the client substitutes Light{0,215} for the
-- server's world light, which also removes the wall-clock day/night cycle.
-- Ambient is pinned to 0 so unlit ground stays black and the light bitmap is the only
-- thing modulating the scene.
function RendererBaseline.prepareLightingScene()
    lightingSceneActive = true
    applyLightingSetup()

    -- setMinimumAmbientLight only takes effect on the next rendered frame, and
    -- client_options applies its own stored ambient default during game start, which can
    -- land after this call. Re-apply on a schedule that finishes well before the shutter
    -- so the light texture is recomputed and drawn at least once with the pinned values.
    for _, delay in ipairs({ 1000, 3000, 4500 }) do
        scheduleEvent(applyLightingSetup, delay)
    end
end

-- map-core and map-screenshot capture the surface fixture platform rather than the live
-- development world, whose walking NPCs and timed broadcasts left ~0.15% of pixels drifting
-- between runs. GOD is the correct character here precisely because its group carries
-- hasfulllight: the server pins world light to 255, the client skips the LIGHT pool, and the
-- capture becomes immune to the wall-clock day/night cycle that cannot be frozen from Lua.
-- Where the server's startup fixture puts each platform. The client waits until the player
-- has actually arrived rather than assuming the teleport landed: the talkaction is fired at
-- game start and can be swallowed outright -- Game::playerSaySpell returns early while the
-- player is walk-exhausted, and the player may not be fully placed when the first one goes
-- out. Trusting a fixed delay produced captures whose camera sat somewhere else entirely,
-- differing from the previous run across 38% of the frame.
local FIXTURE_ANCHORS = {
    map = { x = 34400, y = 34100, z = 6 },
    lighting = { x = 34500, y = 34201, z = 8 }
}

local function waitForFixturePosition(key, onReady, attempts)
    attempts = (attempts or 0) + 1

    local anchor = FIXTURE_ANCHORS[key]
    local player = g_game.getLocalPlayer()
    local position = player and player:getPosition()

    if position and position.x == anchor.x and position.y == anchor.y and position.z == anchor.z then
        g_logger.info(string.format("[renderer-baseline] on fixture '%s' at %d,%d,%d after %d checks",
            key, position.x, position.y, position.z, attempts))
        -- Arrived. Let the map stream, then freeze animation with time to spare. Freezing
        -- inside the shutter tick is too late: setAnimate stops a thing advancing from the
        -- following frame, so the frame being captured still shows whatever phase it was
        -- already on -- which left the fixture's idling creatures drifting between runs.
        setupEvent = scheduleEvent(function()
            freezeMapAnimation()
            setupEvent = scheduleEvent(function()
                freezeMapAnimation()
                onReady()
            end, 1200)
        end, 1300)
        return
    end

    if attempts >= 60 then
        fail(string.format("never reached fixture '%s' at %d,%d,%d", key, anchor.x, anchor.y, anchor.z))
        return
    end

    -- Re-send periodically rather than once, so a swallowed talkaction self-heals.
    if attempts % 8 == 1 then
        g_game.talk("!fixture " .. key)
    end

    setupEvent = scheduleEvent(function()
        waitForFixturePosition(key, onReady, attempts)
    end, 250)
end

function RendererBaseline.onGameStart()
    if activeScenario ~= "map-core" and activeScenario ~= "map-screenshot"
        and activeScenario ~= "lighting-overlap" and activeScenario ~= "shader-matrix-map" then
        return
    end

    if loginTimeoutEvent then
        removeEvent(loginTimeoutEvent)
        loginTimeoutEvent = nil
    end

    stabilizeOnlineUi()

    if activeScenario == "map-screenshot" then
        waitForFixturePosition("map", function()
            RendererBaseline.captureMapScreenshot(activeScenario, 500)
        end)
    elseif activeScenario == "shader-matrix-map" then
        waitForFixturePosition("map", RendererBaseline.runMapShaderScene)
    elseif activeScenario == "lighting-overlap" then
        -- The teleport is a server round trip, so allow it to land and the light
        -- bitmap to be recomputed before the shutter.
        RendererBaseline.prepareLightingScene()
        waitForFixturePosition("lighting", function()
            RendererBaseline.captureScene(activeScenario, 1500)
        end)
    else
        waitForFixturePosition("map", function()
            RendererBaseline.captureScene(activeScenario, 500)
        end)
    end
end

function RendererBaseline.onLoginError(message)
    if activeScenario == "map-core" or activeScenario == "map-screenshot"
        or activeScenario == "lighting-overlap" or activeScenario == "shader-matrix-map" then
        fail("fixture-server login failed: " .. tostring(message))
    end
end

function RendererBaseline.onRun()
    pinLoginBackground()
    activeScenario = optionValue("renderer-baseline")
    if activeScenario == "startup-ui" then
        RendererBaseline.captureScene(activeScenario, 2500)
    elseif activeScenario == "map-core" or activeScenario == "map-screenshot"
        or activeScenario == "lighting-overlap" or activeScenario == "shader-matrix-map" then
        RendererBaseline.loginFixtureServer()
    elseif activeScenario == "ui-clipping-opacity" then
        RendererBaseline.buildClippingOpacityScene()
        RendererBaseline.captureScene(activeScenario, 1000)
    elseif activeScenario == "text-matrix" then
        RendererBaseline.buildTextMatrixScene()
        RendererBaseline.captureScene(activeScenario, 1000)
    elseif activeScenario == "particles-blends" then
        if RendererBaseline.buildParticlesBlendScene() then
            -- The foreground pool is retained and refresh-capped. Give the one-shot
            -- particle systems enough time to reach a stable cached frame.
            RendererBaseline.captureScene(activeScenario, 2500)
        end
    elseif activeScenario == "outfit-masks" then
        if RendererBaseline.buildOutfitMaskScene() then
            RendererBaseline.captureScene(activeScenario, 1500)
        end
    elseif activeScenario == "temporary-framebuffers" then
        if RendererBaseline.buildTemporaryFramebufferScene() then
            RendererBaseline.captureScene(activeScenario, 1500)
        end
    elseif activeScenario == "composition-all" then
        -- Build after startup dialogs have opened so the retained foreground target is
        -- populated exclusively from the isolated fixture on its next refresh.
        setupEvent = scheduleEvent(function()
            setupEvent = nil
            if RendererBaseline.buildCompositionScene() then
                RendererBaseline.captureScene(activeScenario, 750)
            end
        end, 1500)
    elseif activeScenario == "graph-lines" then
        if RendererBaseline.buildGraphLineScene() then
            RendererBaseline.captureScene(activeScenario, 1000)
        end
    elseif activeScenario == "windowing" then
        -- Drives the real startup UI, so no scripted scene is built.
        setupEvent = scheduleEvent(function()
            setupEvent = nil
            RendererBaseline.runWindowingScene()
        end, 2000)
    elseif activeScenario == "shader-matrix" then
        if RendererBaseline.buildShaderMatrixScene() then
            RendererBaseline.captureScene(activeScenario, 2000)
        end
    elseif activeScenario == "shader-matrix-outfits" then
        if RendererBaseline.buildShaderMatrixOutfitsScene() then
            RendererBaseline.captureScene(activeScenario, 2000)
        end
    elseif activeScenario == "atlas-resources" then
        if RendererBaseline.buildAtlasResourceScene() then
            RendererBaseline.captureScene(activeScenario, 2200)
        end
    else
        fail("unknown automated scenario '" .. tostring(activeScenario) .. "'")
    end
end

function RendererBaseline.init()
    connect(g_app, { onRun = RendererBaseline.onRun })
    connect(g_game, {
        onGameStart = RendererBaseline.onGameStart,
        onLoginError = RendererBaseline.onLoginError
    })
end

function RendererBaseline.terminate()
    disconnect(g_app, { onRun = RendererBaseline.onRun })
    disconnect(g_game, {
        onGameStart = RendererBaseline.onGameStart,
        onLoginError = RendererBaseline.onLoginError
    })

    if captureEvent then
        removeEvent(captureEvent)
        captureEvent = nil
    end
    if exitEvent then
        removeEvent(exitEvent)
        exitEvent = nil
    end
    if loginTimeoutEvent then
        removeEvent(loginTimeoutEvent)
        loginTimeoutEvent = nil
    end
    if setupEvent then
        removeEvent(setupEvent)
        setupEvent = nil
    end
    if sceneRoot then
        sceneRoot:destroy()
        sceneRoot = nil
    end
end
