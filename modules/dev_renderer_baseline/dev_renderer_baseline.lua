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

local function beginClientScene(title, subtitle)
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
local function stabilizeOnlineUi()
    if modules.client_options and modules.client_options.setOption then
        pcall(modules.client_options.setOption, "showFps", false, true)
    end

    if EnterGame and EnterGame.hide then
        EnterGame.hide()
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

function RendererBaseline.captureScene(scene, delay)
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

    -- A fixed logical viewport keeps same-backend comparisons meaningful. The normal
    -- startup flow has finished by the time this delayed event fires, so fonts, images,
    -- clipping, translucent widgets, and the initial framebuffer resize are all live.
    g_window.resize({ width = CAPTURE_WIDTH, height = CAPTURE_HEIGHT })
    g_logger.info("[renderer-baseline] capturing " .. scene .. " to " .. realPath)

    captureEvent = scheduleEvent(function()
        -- Startup modules can open windows after onRun. Keep scripted fixtures above
        -- them, then allow one frame to repaint before requesting the screenshot.
        if sceneRoot then
            isolateClientScene()
        end

        captureEvent = scheduleEvent(function()
            suppressCaptureTooltip()

            -- Record the geometry the capture was actually taken at. Baseline provenance
            -- depends on it, and a drifting map panel is otherwise only visible as a large
            -- unexplained pixel diff.
            local mapPanel = modules.game_interface and modules.game_interface.getMapPanel
                and modules.game_interface.getMapPanel()
            if mapPanel and not mapPanel:isDestroyed() then
                local rect = mapPanel:getRect()
                g_logger.info(string.format("[renderer-baseline] map panel rect=%d,%d %dx%d",
                    rect.x, rect.y, rect.width, rect.height))
            end

            g_app.doScreenshot(virtualPath)

            -- Screenshot encoding is dispatched asynchronously. Poll for the new file, then
            -- leave a short settle period because the encoder can still own application
            -- resources after the directory entry becomes visible.
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
        end, 250)
    end, delay)
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

function RendererBaseline.onGameStart()
    if activeScenario ~= "map-core" and activeScenario ~= "map-screenshot" then
        return
    end

    if loginTimeoutEvent then
        removeEvent(loginTimeoutEvent)
        loginTimeoutEvent = nil
    end

    stabilizeOnlineUi()

    if activeScenario == "map-screenshot" then
        RendererBaseline.captureMapScreenshot(activeScenario, 4000)
    else
        RendererBaseline.captureScene(activeScenario, 4000)
    end
end

function RendererBaseline.onLoginError(message)
    if activeScenario == "map-core" or activeScenario == "map-screenshot" then
        fail("fixture-server login failed: " .. tostring(message))
    end
end

function RendererBaseline.onRun()
    activeScenario = optionValue("renderer-baseline")
    if activeScenario == "startup-ui" then
        RendererBaseline.captureScene(activeScenario, 2500)
    elseif activeScenario == "map-core" or activeScenario == "map-screenshot" then
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
