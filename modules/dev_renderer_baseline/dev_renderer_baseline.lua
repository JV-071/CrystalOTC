RendererBaseline = {}

local captureEvent
local exitEvent

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

function RendererBaseline.captureStartupUi()
    local outputName = optionValue("renderer-baseline-output") or "startup-ui.png"
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
    g_logger.info("[renderer-baseline] capturing startup-ui to " .. realPath)

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
    end, 2500)
end

function RendererBaseline.onRun()
    local scenario = optionValue("renderer-baseline")
    if scenario == "startup-ui" then
        RendererBaseline.captureStartupUi()
    else
        fail("unknown automated scenario '" .. tostring(scenario) .. "'")
    end
end

function RendererBaseline.init()
    connect(g_app, { onRun = RendererBaseline.onRun })
end

function RendererBaseline.terminate()
    disconnect(g_app, { onRun = RendererBaseline.onRun })

    if captureEvent then
        removeEvent(captureEvent)
        captureEvent = nil
    end
    if exitEvent then
        removeEvent(exitEvent)
        exitEvent = nil
    end
end
