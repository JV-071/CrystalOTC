RendererBaseline = {}

local captureEvent
local exitEvent
local loginTimeoutEvent
local activeScenario

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
    g_window.resize({ width = 1020, height = 644 })
    g_logger.info("[renderer-baseline] capturing " .. scene .. " to " .. realPath)

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
end
