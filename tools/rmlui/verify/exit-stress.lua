-- RmlUi verification script (exit regression): zero size, a resize storm and images that cannot be
-- resolved used to corrupt the heap; the client must leave with exit code 0. run.ps1 replaces @MODE@.
-- @MODE@ = images | resize | zero | img:<source>
g_resources.setWriteDir(g_resources.getWorkDir() .. 'build/rmlui-verify/userdir')
local MODE = '@MODE@'

local at = verifyAt -- prelude.lua: steps run in order, a slow start delays them all

local HEAD = '<rml><head><style>body{width:100%;height:100%;background-color:#1d2733;color:#fff;font-family:Barlow;font-size:18dp;}' ..
    'img{width:32dp;height:32dp;margin-right:4dp;}</style></head><body><p>texto</p>'
local IMAGES = '<img src="item/99999999.png"/><img src="effect/99999999.png"/><img src="outfit/abc.png"/><img src="nao/existe.png"/><img src="item/3031.png"/>'

local body = ''
if MODE == 'images' then body = IMAGES end
local single = MODE:match('^img:(.+)$')
if single then body = '<img src="' .. single .. '"/>' end

at(1500, function()
    g_resources.writeFileContents('/verify-crash.rml', HEAD .. body .. '</body></rml>')
    local w = g_ui.createWidget('RmlWindow', rootWidget)
    if MODE == 'zero' then
        w:setSize({ width = 0, height = 0 })
    else
        w:setSize({ width = 420, height = 160 })
    end
    print('[verify] mode=' .. MODE .. ' loaded=' .. tostring(w:loadDocument('/verify-crash.rml')))

    if MODE == 'resize' then
        local step = 0
        local function resize()
            step = step + 1
            w:setSize(step % 2 == 0 and { width = 420, height = 160 } or { width = 421, height = 161 })
            if step < 60 then scheduleEvent(resize, 16) end
        end
        resize()
    elseif MODE == 'zero' then
        scheduleEvent(function() w:setSize({ width = 420, height = 160 }) end, 1000)
    end
    scheduleEvent(function() w:destroy() print('[verify] destroyed') end, 4000)
end)
at(7500, function() g_app.exit() end)
