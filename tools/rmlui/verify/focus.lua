-- RmlUi verification script. run.ps1 installs it as data/crystalotcrc.lua with @TAG@ replaced.
-- Review Focus cases 1-4: missing / malformed documents, widgets destroyed with frames queued,
-- zero size and per-frame resizing, images that cannot be resolved.
g_resources.setWriteDir(g_resources.getWorkDir() .. 'build/rmlui-verify/userdir')

local function check(name, cond)
    print(('[verify] %s %s'):format(cond and 'PASS' or 'FAIL', name))
end

local at = verifyAt -- prelude.lua: steps run in order, a slow start delays them all

local DOC = [[<rml>
<head>
<style>
body { width: 100%; height: 100%; background-color: #1d2733; color: #ffffff; font-family: Barlow; font-size: 18dp; padding: 8dp; }
p { display: block; margin-bottom: 6dp; }
img { width: 32dp; height: 32dp; margin-right: 4dp; }
</style>
</head>
<body>
<p>ação — texto UTF-8</p>
<img src="item/99999999.png"/><img src="effect/99999999.png"/><img src="outfit/abc.png"/><img src="nao/existe.png"/><img src="item/3031.png"/><img src="item/68567.png"/><img src="outfit/65664-0-0-0-0-0-2.png"/>
</body>
</rml>]]

-- 1. missing document and malformed RML
at(1500, function()
    g_resources.writeFileContents('/verify-bad.rml', '<rml><body><div></body>')
    g_resources.writeFileContents('/verify-doc.rml', DOC)

    local w = g_ui.createWidget('RmlWindow', rootWidget)
    w:setSize({ width = 300, height = 200 })
    check('1 missing document returns false', w:loadDocument('/modules/nao_existe/x.rml') == false)
    check('1 missing document leaves the widget empty', w:hasDocument() == false)
    local loaded = w:loadDocument('/verify-bad.rml')
    check('1 malformed RML did not raise (loadDocument returned ' .. tostring(loaded) .. ')', true)
    w:destroy()
end)

-- 2. open and close 50 times, 50 ms apart, so widgets die with frames still queued
at(2500, function()
    local cycles = 0
    local function cycle()
        modules.client_rmldemo.toggle()
        scheduleEvent(function()
            modules.client_rmldemo.toggle()
            cycles = cycles + 1
            if cycles < 50 then
                scheduleEvent(cycle, 50)
            else
                scheduleEvent(function()
                    collectgarbage(); collectgarbage()
                    check(('2 after 50 open/close cycles: %d live widgets'):format(#g_rml.getWidgets()), #g_rml.getWidgets() == 0)
                end, 500)
            end
        end, 50)
    end
    cycle()
end)

-- 3 + 4. zero size, a resize every frame, images that cannot be resolved
at(9500, function()
    local w = g_ui.createWidget('RmlWindow', rootWidget)
    w:setSize({ width = 0, height = 0 })
    check('3 document loads into a zero-size widget', w:loadDocument('/verify-doc.rml') == true)

    local step = 0
    local function resize()
        step = step + 1
        w:setSize(step % 2 == 0 and { width = 420, height = 160 } or { width = 421, height = 161 })
        if step < 60 then
            scheduleEvent(resize, 16)
        else
            scheduleEvent(function()
                check('3 survived zero size and 60 resizes', w:hasDocument())
                print('[verify] shot focus-@TAG@')
            end, 800)
            scheduleEvent(function() w:destroy() end, 2500)
        end
    end
    resize()
end)

at(14500, function() g_app.exit() end)
