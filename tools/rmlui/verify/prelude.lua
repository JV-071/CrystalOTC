-- Prepended by run.ps1 to every verification script (which ends with a call to verifyStart()).
--
-- Steps registered with verifyAt(ms, fn) run in time order, each one scheduled when the previous
-- one has run. A slow start (cold caches, a busy machine) or a slow step then delays everything
-- after it; with plain scheduleEvent the overdue steps would all run in the same dispatcher
-- cycle and the checks would look at things that have not had a cycle to happen.

local steps = {}
local started = false

local function guarded(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then print('[verify] FAIL ' .. tostring(err)) end
    end
end

function verifyAt(ms, fn)
    if started then
        -- registered by a running step: relative to now
        scheduleEvent(guarded(fn), ms)
        return
    end
    steps[#steps + 1] = { ms = ms, fn = guarded(fn), order = #steps }
end

function verifyStart()
    started = true
    table.sort(steps, function(a, b)
        if a.ms ~= b.ms then return a.ms < b.ms end
        return a.order < b.order
    end)

    local function run(index)
        local step = steps[index]
        step.fn()
        local following = steps[index + 1]
        if not following then return end
        if following.ms == step.ms then
            run(index + 1) -- registered for the same moment: same cycle
        else
            scheduleEvent(function() run(index + 1) end, following.ms - step.ms)
        end
    end

    if steps[1] then scheduleEvent(function() run(1) end, steps[1].ms) end
end
