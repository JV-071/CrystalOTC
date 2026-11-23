-- RmlUi verification script. run.ps1 installs it as data/crystalotcrc.lua with @TAG@ replaced.
-- Opens the demo window, reports the backend and asks for a screenshot.
g_resources.setWriteDir(g_resources.getWorkDir() .. 'build/rmlui-verify/userdir')

local clientPrint = print -- RmlUi's Lua plugin must not replace the client's print

local at = verifyAt -- prelude.lua: steps run in order, a slow start delays them all

at(1500, function() modules.client_rmldemo.toggle() end)
at(4500, function()
    print(('[verify] backend=%s ready=%s effects=%s widgets=%d'):format(
        g_rml.getBackendName(), tostring(g_rml.isReady()), tostring(g_rml.supportsAdvancedEffects()), g_rml.getWidgetCount()))
    print(('[verify] %s print is still the client function'):format(print == clientPrint and 'PASS' or 'FAIL'))
    print('[verify] shot demo-@TAG@')
end)
at(7000, function() g_app.exit() end)
