-- RmlUi verification script. run.ps1 installs it as data/crystalotcrc.lua with @TAG@ replaced.
-- Walks every tab of the showcase, then opens the options, outfit and minimap examples.
g_resources.setWriteDir(g_resources.getWorkDir() .. 'build/rmlui-verify/userdir')

local function check(name, cond)
    print(('[verify] %s %s'):format(cond and 'PASS' or 'FAIL', name))
end

local at = verifyAt -- prelude.lua: steps run in order, a slow start delays them all

local TABS = { { 'home', 'Início' }, { 'binding', 'Data binding' }, { 'forms', 'Formulários' }, { 'sprites', 'Sprites' },
    { 'native', 'OTUI no RML' }, { 'images', 'Imagens' }, { 'effects', 'Efeitos' }, { 'otui', 'OTUI para RmlUi' }, { 'dom', 'Lua e DOM' } }
local t = 3000

-- clicks the first element matching selector whose text is exactly `text`
local function clickText(window, selector, text)
    local list = window:getDocument():QuerySelectorAll(selector)
    for i = 0, 64 do
        local element = list[i]
        if element then
            local label = tostring(element.inner_rml or ''):gsub('<[^>]*>', ''):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
            if label == text then
                element:Click()
                return true
            end
        end
    end
    return false
end

at(t, function() modules.client_rmlshowcase.toggle() end)

for index, tab in ipairs(TABS) do
    t = t + 2400 -- the capture happens up to ~0.7 s after its marker: leave room before the next click
    at(t, function()
        local window = rootWidget:getChildById('rmlShowcase')
        if not window then error('showcase window not found') end
        check('tab ' .. tab[1] .. ' clicked', clickText(window, '.otc-tab', tab[2]))
    end)
    at(t + 900, function() print('[verify] shot showcase-' .. index .. '-' .. tab[1] .. '-@TAG@') end)
end

t = t + 2400
at(t, function() modules.client_rmlshowcase.toggle() end)

local function example(label, module, windowId)
    t = t + 700
    at(t, function() modules[module].toggle() end)
    at(t + 1400, function()
        check(label .. ' window exists', rootWidget:getChildById(windowId) ~= nil)
        print('[verify] shot ' .. label .. '-@TAG@')
    end)
    t = t + 2400
    at(t, function()
        modules[module].toggle()
    end)
    at(t + 500, function() check(label .. ' window closed', rootWidget:getChildById(windowId) == nil) end)
end

example('options', 'client_rmloptions', 'rmlOptions')
example('outfit', 'game_rmloutfit', 'rmlOutfit')
t = t + 700
at(t, function() modules.game_rmlminimap.toggle() end)
at(t + 800, function()
    local window = rootWidget:getChildById('rmlMinimap')
    check('minimap window exists', window ~= nil)
    for _ = 1, 6 do check('floor up clicked', clickText(window, 'button', 'Andar acima')) end
end)
at(t + 2600, function() print('[verify] shot minimap-@TAG@') end)
t = t + 3800
at(t, function() modules.game_rmlminimap.toggle() end)
at(t + 500, function() check('minimap window closed', rootWidget:getChildById('rmlMinimap') == nil) end)

t = t + 1500
at(t, function()
    collectgarbage(); collectgarbage()
    check(('all example windows closed: %d live RmlUi widgets'):format(#g_rml.getWidgets()), #g_rml.getWidgets() == 0)
    print(('[verify] backend=%s effects=%s'):format(g_rml.getBackendName(), tostring(g_rml.supportsAdvancedEffects())))
end)
at(t + 1000, function() g_app.exit() end)
