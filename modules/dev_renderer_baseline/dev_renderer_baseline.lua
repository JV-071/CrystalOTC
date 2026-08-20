RendererBaseline = {}

local captureEvent
local exitEvent
local loginTimeoutEvent
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
    sceneRoot = makePanel(g_ui.getRootWidget(), 0, 0, CAPTURE_WIDTH, CAPTURE_HEIGHT, "#111827ff")
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
        end, 100)
    end, delay)
end

function RendererBaseline.loginFixtureServer()
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
    if activeScenario ~= "map-core" then
        return
    end

    if loginTimeoutEvent then
        removeEvent(loginTimeoutEvent)
        loginTimeoutEvent = nil
    end

    RendererBaseline.captureScene(activeScenario, 4000)
end

function RendererBaseline.onLoginError(message)
    if activeScenario == "map-core" then
        fail("fixture-server login failed: " .. tostring(message))
    end
end

function RendererBaseline.onRun()
    activeScenario = optionValue("renderer-baseline")
    if activeScenario == "startup-ui" then
        RendererBaseline.captureScene(activeScenario, 2500)
    elseif activeScenario == "map-core" then
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
    if sceneRoot then
        sceneRoot:destroy()
        sceneRoot = nil
    end
end
