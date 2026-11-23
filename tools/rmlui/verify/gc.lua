-- RmlUi verification script. run.ps1 installs it as data/crystalotcrc.lua.
-- Closed data models under an active garbage collector: a window with a model that has nested
-- tables is opened and closed 150 times while Lua allocates on every dispatcher cycle, with no
-- forced collection in between. Stock RmlUi 6.3 crashes here within a second or two: the
-- finalizer of a nested table reads its model after the collector has freed it
-- (vcpkg-overlays/rmlui/lua-datamodel-lifetime.patch).
g_resources.setWriteDir(g_resources.getWorkDir() .. 'build/rmlui-verify/userdir')

local function check(name, cond)
    print(('[verify] %s %s'):format(cond and 'PASS' or 'FAIL', name))
end

local at = verifyAt -- prelude.lua: steps run in order, a slow start delays them all

at(2000, function()
    -- garbage of many small sizes: drives the incremental collector and reuses whatever it frees
    cycleEvent(function()
        local keep = {}
        for i = 1, 4000 do
            keep[i % 64 + 1] = { i, tostring(i) .. string.rep('x', i % 72) }
        end
    end, 4)
end)

local t = 2500
for i = 1, 150 do
    at(t, function() modules.client_rmloptions.toggle() end)
    at(t + 70, function() modules.client_rmloptions.toggle() end)
    if i % 50 == 0 then
        at(t + 100, function() check(('still running after %d windows with a data model'):format(i), true) end)
    end
    t = t + 130
end

at(t + 500, function()
    collectgarbage()
    collectgarbage()
    -- at most one destroyed widget object without a context may remain (see lifetime.lua)
    local contexts, objects = g_rml.getContextCount(), g_rml.getWidgetCount()
    check(('all of them are freed (contexts still open: %d, widget objects alive: %d)'):format(contexts, objects),
        contexts == 0 and objects <= 1)
    if objects == 1 then print('[verify] NOTE one destroyed widget object without a context is still referenced') end
end)
at(t + 900, function() g_app.exit() end)
