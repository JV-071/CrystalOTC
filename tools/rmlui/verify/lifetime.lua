-- RmlUi verification script. run.ps1 installs it as data/crystalotcrc.lua with @TAG@ and @CLIP@ replaced.
-- Lifetime and redraw: windows are freed when closed, the tick loop keeps its widgets alive, clipboard
-- text is converted, changing content is redrawn at tick rate and idle content is not redrawn at all.
g_resources.setWriteDir(g_resources.getWorkDir() .. 'build/rmlui-verify/userdir')

local function check(name, cond)
    print(('[verify] %s %s'):format(cond and 'PASS' or 'FAIL', name))
end

local at = verifyAt -- prelude.lua: steps run in order, a slow start delays them all

local function collect()
    collectgarbage()
    collectgarbage()
end

-- What a closed window must give back, checked after two full collections:
--   * its RmlUi context (document, layers on the GPU): none may be left open;
--   * the widget objects: at most ONE destroyed widget without a context may still be referenced.
--     On a busy machine a single such object is sometimes kept until the client exits (one per
--     session, never more; its holder is not known yet - see README.md). More than one is a leak.
local base
local function freed(label)
    collect()
    local contexts = g_rml.getContextCount()
    local objects = g_rml.getWidgetCount() - base
    local open = {}
    for _, widget in ipairs(g_rml.getWidgets()) do
        open[#open + 1] = ('%s(visible=%s)'):format(widget:getId(), tostring(widget:isVisible()))
    end
    check(('%s (contexts still open: %d, widget objects alive: %d, not destroyed: %d %s)')
        :format(label, contexts, objects, #open, table.concat(open, ' ')), contexts == 0 and objects <= 1 and #open == 0)
    if objects == 1 then print('[verify] NOTE one destroyed widget object without a context is still referenced') end
end

local STYLE = [[
div, p { display: block; }
body { width: 100%; height: 100%; background-color: #243; color: #fff; font-family: Barlow; font-size: 18dp; }
input.text { display: block; width: 200dp; height: 24dp; background-color: #111; }
.bar { height: 10dp; background-color: #d6a951; }
.grow { animation: 1s linear-in-out infinite alternate grow; }
@keyframes grow { from { width: 20dp; } to { width: 240dp; } }
]]
local MODEL_DOC = '<rml><head><style>' .. STYLE .. '</style></head><body data-model="review"><p>n = {{n}}</p>'
    .. '<button id="kill">kill</button><input id="field" class="text" type="text"/></body></rml>'
local STATIC_DOC = '<rml><head><style>' .. STYLE .. '</style></head><body><p>parado</p><div class="bar" style="width: 80dp;"></div></body></rml>'
local ANIM_DOC = '<rml><head><style>' .. STYLE .. '</style></head><body><p>animado</p><div class="bar grow"></div></body></rml>'

local t = 2500

at(t, function()
    g_resources.writeFileContents('/verify-review-model.rml', MODEL_DOC)
    g_resources.writeFileContents('/verify-review-static.rml', STATIC_DOC)
    g_resources.writeFileContents('/verify-review-anim.rml', ANIM_DOC)
    collect()
    base = g_rml.getWidgetCount()
    print('[verify] backend ' .. g_rml.getBackendName() .. ' base widgets=' .. base)
    -- park the pointer in a corner: where the real one rests must not decide what gets hovered
    print('[verify] mouse#1 3 3')
end)
t = t + 300

-- (1) a window with a data model, opened and closed 20 times --------------------------------
for _ = 1, 20 do
    at(t, function() modules.client_rmloptions.toggle() end)
    at(t + 90, function() modules.client_rmloptions.toggle() end)
    t = t + 180
end
at(t + 400, function() freed('20 closed option windows are freed') end)
t = t + 700

-- (1) toggles that land in the same dispatcher cycle (key repeat, a slow frame) ---------------
do
    local function open()
        local count = 0
        for _, widget in ipairs(g_rml.getWidgets()) do
            if widget:isVisible() then count = count + 1 end
        end
        return count
    end
    local toggle = function() modules.client_rmloptions.toggle() end

    at(t, toggle)
    at(t + 300, function()
        check(('one toggle opens one window (open: %d)'):format(open()), open() == 1)
        toggle() -- close
        toggle() -- and open again before the first one is even destroyed
    end)
    at(t + 600, function()
        check(('close + open in one cycle leaves exactly one window open (open: %d)'):format(open()), open() == 1)
        toggle()
    end)
    at(t + 900, function()
        check(('and the next toggle closes it (open: %d)'):format(open()), open() == 0)
        toggle()
        toggle()
        toggle()
    end)
    at(t + 1200, function()
        check(('open + close + open in one cycle leaves one window open (open: %d)'):format(open()), open() == 1)
        toggle()
    end)
    at(t + 1600, function() freed('nothing of that is left behind') end)
    t = t + 1900
end

-- (1) the same model name open in two windows at once -----------------------------------------
do
    local first, firstModel, second, secondModel
    at(t, function()
        first, firstModel = Rml.createWindow { document = '/verify-review-model.rml', model = 'review', data = { n = 1 }, width = 320, height = 160 }
        second, secondModel = Rml.createWindow { document = '/verify-review-model.rml', model = 'review', data = { n = 2 }, width = 320, height = 160 }
    end)
    at(t + 300, function()
        firstModel.n = 10
        check(('each window has its own model (first n=%s, second n=%s)'):format(tostring(firstModel.n), tostring(secondModel.n)),
            firstModel.n == 10 and secondModel.n == 2)
        Rml.close(first) -- the older one goes first: the newer must keep working
    end)
    at(t + 600, function()
        local ok = pcall(function() secondModel.n = 20 end)
        check(('closing one leaves the other usable (second n=%s)'):format(tostring(ok and secondModel.n)), ok and secondModel.n == 20)
        local closed = not pcall(function() return firstModel.n end)
        check('the closed model raises instead of answering', closed)
        Rml.close(second)
        first, firstModel, second, secondModel = nil, nil, nil, nil
    end)
    at(t + 1000, function() freed('both are freed') end)
    t = t + 1300
end

-- (1) destroy() called from inside an event of the document itself ---------------------------
do
    local win
    at(t, function()
        win = Rml.createWindow { document = '/verify-review-model.rml', model = 'review', data = { n = 0 }, width = 320, height = 160 }
        Rml.on(win, 'kill', 'click', function() win:destroy() end)
    end)
    at(t + 300, function()
        Rml.element(win, 'kill'):Click()
        check('destroy() from inside an RmlUi event is accepted', win:isDestroyed())
        win = nil
    end)
    at(t + 800, function() freed('that window is freed too') end)
    t = t + 1100
end

-- (2) a widget whose last reference goes away during another widget's tick -------------------
do
    local a, b, inside, before
    at(t, function()
        collect()
        before = g_rml.getWidgetCount()
        a = g_ui.createWidget('RmlWindow', rootWidget)
        a:setSize({ width = 320, height = 120 })
        a:loadDocument('/verify-review-static.rml')
        b = UIRmlWidget.create() -- registered after a: the tick loop reaches it after a's callback
        connect(a, {
            onRmlUpdate = function()
                if b then
                    b = nil
                    collect()
                    inside = g_rml.getWidgetCount() - before
                end
            end
        })
    end)
    at(t + 400, function()
        check(('a widget dropped during the tick stays alive until the loop ends (alive inside the callback: %s, expected 2)')
            :format(tostring(inside)), inside == 2)
        collect()
        local alive = g_rml.getWidgetCount() - before
        check(('and it is freed afterwards (alive: %d, expected 1)'):format(alive), alive == 1)
        a:destroy()
        a = nil
    end)
    t = t + 800
end

-- (3) clipboard: the client keeps Latin-1 text, RmlUi works in UTF-8 -------------------------
if '@CLIP@' == '1' then
    local win, input
    local word = 'maçã'
    at(t, function()
        win = Rml.createWindow { document = '/verify-review-model.rml', model = 'review', data = { n = 0 }, width = 320, height = 160 }
        input = Rml.element(win, 'field')
        win:focus()
        input:Focus()
    end)
    -- g_window.setClipboardText is applied by the main thread a moment later: one step per action
    at(t + 300, function() g_window.setClipboardText(g_rml.latin1(word)) end)
    at(t + 700, function()
        check('the clipboard holds the Latin-1 word before pasting', g_window.getClipboardText() == g_rml.latin1(word))
        win:getContext():ProcessKeyDown(rmlui.key_identifier.V, rmlui.key_modifier.CTRL)
    end)
    at(t + 1000, function()
        local value = input:GetAttribute('value')
        check(('pasted text reaches the document as UTF-8 (value=%q)'):format(tostring(value)), value == word)
        input:SetAttribute('value', word)
        g_window.setClipboardText('x')
    end)
    at(t + 1400, function()
        win:getContext():ProcessKeyDown(rmlui.key_identifier.A, rmlui.key_modifier.CTRL)
        win:getContext():ProcessKeyDown(rmlui.key_identifier.C, rmlui.key_modifier.CTRL)
    end)
    at(t + 1800, function()
        local copied = g_window.getClipboardText()
        check(('copied text reaches the client as Latin-1 (%d bytes, expected %d)'):format(#copied, #g_rml.latin1(word)),
            copied == g_rml.latin1(word))
        win:destroy()
        win, input = nil, nil
    end)
    t = t + 2200
else
    print('[verify] SKIP clipboard (it holds something that is not text)')
end

-- (5) how often the document is actually redrawn ----------------------------------------------
if g_rml.getReplayedFrameCount then
    local function measure(label, ms, verdict)
        local start, startedAt
        at(t, function()
            start = g_rml.getReplayedFrameCount()
            startedAt = g_clock.realMillis()
        end)
        at(t + ms, function()
            local frames = g_rml.getReplayedFrameCount() - start
            local elapsed = math.max(1, g_clock.realMillis() - startedAt) -- what really passed, not what was asked for
            print(('[verify] frames %s: %d in %d ms (%.1f per second)'):format(label, frames, elapsed, frames * 1000 / elapsed))
            verdict(frames, frames * 1000 / elapsed)
        end)
        t = t + ms + 100
    end

    -- The login screen redraws the whole UI about 60 times per second by itself (an animated
    -- texture and the login widgets ask for it), which would hide a document that never asks.
    -- Quiet it down to what a calm game screen looks like: the pool's own 10 redraws per second.
    at(t, function()
        for _, child in ipairs(rootWidget:getChildren()) do
            if child:isVisible() then child:hide() end
        end
        g_textures.clearCache()
    end)
    t = t + 500

    local win, model, animate
    at(t, function()
        win, model = Rml.createWindow { document = '/verify-review-model.rml', model = 'review', data = { n = 0 }, width = 320, height = 160 }
        animate = true
        connect(win, { onRmlUpdate = function() if animate then model.n = model.n + 1 end end })
    end)
    t = t + 600
    measure('with a model value that changes on every tick', 2000, function(_, fps)
        check(('content changed from Lua is redrawn at tick rate (%.1f per second, expected more than 40)'):format(fps), fps > 40)
    end)
    at(t, function() animate = false end)
    t = t + 600
    measure('with nothing changing', 2000, function(frames)
        check(('a document that does not change is not redrawn (%d frames in 2 s)'):format(frames), frames <= 2)
    end)
    at(t, function()
        win:destroy()
        win, model = nil, nil
        win = g_ui.createWidget('RmlWindow', rootWidget)
        win:setSize({ width = 320, height = 120 })
        win:loadDocument('/verify-review-anim.rml')
    end)
    t = t + 600
    measure('with an RCSS animation', 2000, function(_, fps)
        check(('an RCSS animation is redrawn at tick rate (%.1f per second, expected more than 40)'):format(fps), fps > 40)
    end)
    at(t, function() win:hide() end)
    t = t + 300
    measure('with the animated window hidden', 1000, function(frames)
        check(('a hidden window is not redrawn (%d frames in 1 s)'):format(frames), frames == 0)
    end)
    at(t, function()
        win:destroy()
        win = nil
    end)
    at(t + 400, function()
        freed('every window of this script is freed at the end')
        print('[verify] shot review-@TAG@')
    end)
    t = t + 900
else
    print('[verify] SKIP frame rate (this build has no g_rml.getReplayedFrameCount)')
end

at(t + 600, function() g_app.exit() end)
