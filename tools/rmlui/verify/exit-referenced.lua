-- RmlUi verification script (exit regression): RmlUi widgets that Lua still references at exit.
-- They are only collected in lua_close(), after g_rml.terminate() has shut RmlUi down.
g_resources.setWriteDir(g_resources.getWorkDir() .. 'build/rmlui-verify/userdir')
scheduleEvent(function()
    g_resources.writeFileContents('/verify-leak.rml', '<rml><head><style>body{width:100%;height:100%;background-color:#243;color:#fff;font-family:Barlow;font-size:18dp;}</style></head><body><p>ainda referenciado ao sair</p></body></rml>')
    _G.__rmlAlive = g_ui.createWidget('RmlWindow', rootWidget)          -- alive, never destroyed
    _G.__rmlAlive:setSize({ width = 320, height = 120 })
    print('[verify] alive loaded=' .. tostring(_G.__rmlAlive:loadDocument('/verify-leak.rml')))
    _G.__rmlDestroyed = g_ui.createWidget('RmlWindow', rootWidget)      -- destroyed, still referenced
    _G.__rmlDestroyed:setSize({ width = 320, height = 120 })
    print('[verify] destroyed loaded=' .. tostring(_G.__rmlDestroyed:loadDocument('/verify-leak.rml')))
    scheduleEvent(function() _G.__rmlDestroyed:destroy() end, 1500)
end, 1500)
scheduleEvent(function() g_app.exit() end, 5000)
