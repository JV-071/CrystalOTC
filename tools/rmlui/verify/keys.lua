-- RmlUi verification script. run.ps1 installs it as data/crystalotcrc.lua with @TAG@ replaced.
-- Real keyboard path (OTUI -> UIRmlWidget -> RmlUi): the five shortcuts and typing into a text field.
-- shot.ps1 sends the keys named by each "[verify] keys#N <SendKeys>" line, only if the client has focus.
g_resources.setWriteDir(g_resources.getWorkDir() .. 'build/rmlui-verify/userdir')

local function check(name, cond)
    print(('[verify] %s %s'):format(cond and 'PASS' or 'FAIL', name))
end

local at = verifyAt -- prelude.lua: steps run in order, a slow start delays them all

local SHORTCUTS = {
    { keys = '^+u', label = 'Ctrl+Shift+U', window = 'rmlShowcase', module = 'client_rmlshowcase' },
    { keys = '^+r', label = 'Ctrl+Shift+R', window = 'rmlDemoWindow', module = 'client_rmldemo' },
    { keys = '^+o', label = 'Ctrl+Shift+O', window = 'rmlOptions', module = 'client_rmloptions' },
    { keys = '^+f', label = 'Ctrl+Shift+F', window = 'rmlOutfit', module = 'game_rmloutfit' },
    { keys = '^+m', label = 'Ctrl+Shift+M', window = 'rmlMinimap', module = 'game_rmlminimap' },
}

local t = 3000
for index, shortcut in ipairs(SHORTCUTS) do
    at(t, function() print(('[verify] keys#%d %s'):format(index, shortcut.keys)) end)
    at(t + 1800, function()
        local window = rootWidget:getChildById(shortcut.window)
        check(shortcut.label .. ' opens ' .. shortcut.window, window ~= nil)
        if window then modules[shortcut.module].toggle() end
    end)
    t = t + 2800
end

-- typing: Latin-1 key text from the window system must reach the document as UTF-8
local input
at(t, function() modules.client_rmlshowcase.toggle() end)
at(t + 1200, function()
    local window = rootWidget:getChildById('rmlShowcase')
    local list = window:getDocument():QuerySelectorAll('.otc-tab')
    for i = 0, 16 do
        local tab = list[i]
        if tab and tostring(tab.inner_rml):find('Data binding', 1, true) then tab:Click() break end
    end
end)
at(t + 2200, function()
    local window = rootWidget:getChildById('rmlShowcase')
    local inputs = window:getDocument():QuerySelectorAll('input')
    for i = 0, 16 do
        local element = inputs[i]
        if element and element:GetAttribute('type') == 'text' then input = element break end
    end
    check('text input found on the data binding tab', input ~= nil)
    window:focus()
    input:Focus()
    print('[verify] keys#6 aç')
end)
at(t + 4200, function()
    local value = input and input:GetAttribute('value')
    check(('typed text reached the field as UTF-8 (value=%q)'):format(tostring(value)), value == 'aç')
    print('[verify] shot keys-text-@TAG@')
end)
at(t + 5600, function()
    -- same field through RmlUi's own Lua API, no window system involved
    rootWidget:getChildById('rmlShowcase'):getContext():ProcessTextInput('é')
end)
at(t + 6200, function()
    local value = input and input:GetAttribute('value')
    check(('ProcessTextInput appends UTF-8 (value=%q)'):format(tostring(value)), value == 'açé' or value == 'é')
    modules.client_rmlshowcase.toggle()
end)
at(t + 7500, function() g_app.exit() end)
