-- RmlUi verification script. run.ps1 installs it as data/crystalotcrc.lua and runs it with renderBackend = vulkan.
-- Review Focus 5: with the Vulkan renderer there is no executor yet; RmlUi must say so, the
-- example modules must not break, and nothing may be recorded for a replay that never runs.
g_resources.setWriteDir(g_resources.getWorkDir() .. 'build/rmlui-verify/userdir')

local function check(name, cond)
    print(('[verify] %s %s'):format(cond and 'PASS' or 'FAIL', name))
end

local at = verifyAt -- prelude.lua: steps run in order, a slow start delays them all

at(1500, function()
    print('[verify] render backend: ' .. g_configs.getRenderBackend())
    check('5 g_rml.isReady() is false on Vulkan', g_rml.isReady() == false)
    check('5 getBackendName() says unavailable (got ' .. g_rml.getBackendName() .. ')', g_rml.getBackendName() == 'unavailable')
    check('5 supportsAdvancedEffects() is false', g_rml.supportsAdvancedEffects() == false)

    -- the example module must refuse politely
    modules.client_rmldemo.toggle()
    modules.client_rmldemo.toggle()

    -- a widget created directly gets no context, so it records nothing
    local w = g_ui.createWidget('RmlWindow', rootWidget)
    w:setSize({ width = 300, height = 200 })
    check('5 loadDocument returns false', w:loadDocument('/modules/client_rmldemo/rmldemo.rml') == false)
    check('5 getContext() is nil', w:getContext() == nil)
    scheduleEvent(function() w:destroy() end, 1500)
end)
at(3500, function() print('[verify] shot vulkan-noexec') end)
at(6000, function() g_app.exit() end)
