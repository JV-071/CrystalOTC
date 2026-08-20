-- this is the first file executed when the application starts
-- we have to load the first modules form here

-- updater
Services = {
    --updater = "http://localhost/api/updater.php", --./updater
    --status = "http://localhost/login.php", --./client_entergame | ./client_topmenu
    --websites = "http://localhost/?subtopic=accountmanagement", --./client_entergame "Forgot password and/or email"
    --createAccount = "http://localhost/clientcreateaccount.php", --./client_entergame -- createAccount.lua
    --getCoinsUrl = "http://localhost/?subtopic=shop&step=terms", --./game_market
    --minimap = "http://localhost/minimap.otmm", --./game_minimap
}

--- Enables or disables the entire server configuration block.
-- Set to `false` to disable all configuration below.
local ENABLE_SERVERS = true

---
-- @module Servers_init
-- Configuration table for all servers used by the system.
--
-- This entire block is conditionally enabled based on ENABLE_SERVERS.
-- When ENABLE_SERVERS == false, everything is ignored/disabled.
--

---
-- Server configuration system for multi-server or multi-world clients.
--
-- This structure allows a single client build to connect to multiple servers
-- without requiring duplicate client folders.
--
-- A server that hosts several worlds, or that provides a separate test environment,
-- can simply define additional entries inside this configuration table.
--
-- Instead of maintaining multiple client installations (one per world/server),
-- the client can switch between servers by selecting the desired configuration entry.
-- This simplifies testing, avoids redundant directories, and centralizes connection settings.
--
-- The ENABLE_SERVERS flag allows the entire configuration block to be enabled or disabled
-- without deleting or commenting out individual entries.
--

Servers_init = {}

if ENABLE_SERVERS then

    ---
    -- List of servers and their configuration parameters.
    -- Each entry defines port, protocol, and authentication options.
    -- @table Servers_init
    --
    -- This fork targets the local Crystal server only. The HTTP login service listens on
    -- 8080 and advertises a stale game endpoint, so gameHost/gamePort override it with the
    -- real 127.0.0.1:7182 game port. A devserver.flag branch used to exist here, but both
    -- of its arms resolved to this same localhost entry; add one back only when a second
    -- endpoint genuinely exists.
    Servers_init = {
        ["http://127.0.0.1/login.php"] = {
            port = 8080,
            protocol = 1525,
            httpLogin = true,
            useAuthenticator = false,
            gameHost = "127.0.0.1",
            gamePort = 7182
        }
    }
end

g_app.setName("CrystalOTC");
g_app.setCompactName("crystalotc");
g_app.setOrganizationName("Crystal");

-- Renderer baseline captures must be reproducible run to run, and must not disturb the
-- developer's own client. Persisted state broke both properties: game_interface saves and
-- restores the console splitter position (modules/game_interface/gameinterface.lua), so a
-- previous run's saved layout silently resized the map panel in the next capture, and the
-- minimap cache and per-character UI state accumulate across runs. CI runners start with no
-- persisted state at all, so a local capture and a CI capture would diverge for reasons that
-- have nothing to do with the renderer. Capture runs therefore get their own write directory,
-- reset below before any setting is read.
local rendererBaselineRun = g_app.getStartupOptions():find("--renderer-baseline=", 1, true) ~= nil
if rendererBaselineRun then
    g_app.setCompactName(g_app.getCompactName() .. "-baseline")
end

-- Accept both Crystal 15.25 and the existing 15.30 client profile. Crystal 15.25 reuses
-- the checked-in 1530 asset catalog; only the advertised/wire version changes.
g_gameConfig.setLastSupportedVersion(1530)

g_app.hasUpdater = function()
    return (Services.updater and Services.updater ~= "" and g_modules.getModule("updater"))
end

-- setup logger
g_logger.setLogFile(g_resources.getWorkDir() .. g_app.getCompactName() .. '.log')
g_logger.info(os.date('== application started at %b %d %Y %X'))
g_logger.info("== operating system: " .. g_platform.getOSName())

-- print first terminal message
g_logger.info(g_app.getName() .. ' ' .. g_app.getVersion() .. ' rev ' .. g_app.getBuildRevision() .. ' (' ..
    g_app.getBuildCommit() .. ') built on ' .. g_app.getBuildDate() .. ' for arch ' ..
    g_app.getBuildArch())

-- setup lua debugger
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
    require("lldebugger").start()
    g_logger.debug("Started LUA debugger.")
else
    g_logger.debug("LUA debugger not started (not launched with VSCode local-lua).")
end

-- Try to add on-disk data/, modules/, mods/ to the search path.
-- These calls return false (without crashing) when the directory does not
-- physically exist on disk. With the embedded assets.pak mounted at "/" via
-- PHYSFS_mountMemory the corresponding subtrees come from inside the exe, so
-- a missing on-disk folder is not fatal — only the absence of BOTH the embed
-- and the on-disk folder would be a real problem, and that surfaces later
-- when a module fails to load.
g_resources.addSearchPath(g_resources.getWorkDir() .. 'data', true)
g_resources.addSearchPath(g_resources.getWorkDir() .. 'modules', true)

g_html.addGlobalStyle('/data/styles/html.css')
g_html.addGlobalStyle('/data/styles/custom.css')

g_resources.addSearchPath(g_resources.getWorkDir() .. 'mods', true)

-- setup directory for saving configurations
g_resources.setupUserWriteDir(('%s/'):format(g_app.getCompactName()))

-- Reset the capture write directory before g_configs.loadSettings reads anything. Only
-- names owned by the write directory are touched; none of them exist in the mounted data,
-- modules, or mods trees, so this cannot reach repository content. Previously captured
-- images under /render-baselines are deliberately preserved.
if rendererBaselineRun then
    local function purge(path)
        if g_resources.directoryExists(path) then
            for _, file in ipairs(g_resources.listDirectoryFiles(path, true, false, true)) do
                g_resources.deleteFile('/' .. file)
            end
        elseif g_resources.fileExists(path) then
            g_resources.deleteFile(path)
        end
    end

    for _, path in ipairs({ '/config.otml', '/user_minimap.otmm', '/settings',
                            '/characterdata', '/controls' }) do
        purge(path)
    end
end

-- search all packages
g_resources.searchAndAddPackages('/', '.otpkg', true)

-- load settings
g_configs.loadSettings('/config.otml')

g_modules.discoverModules()

-- libraries modules 0-99
g_modules.autoLoadModules(99)
g_modules.ensureModuleLoaded('corelib')
g_modules.ensureModuleLoaded('gamelib')
g_modules.ensureModuleLoaded('modulelib')
g_modules.ensureModuleLoaded("startup")

g_modules.autoLoadModules(999)
g_modules.ensureModuleLoaded('game_shaders') -- pre load

local function loadModules()
    -- client modules 100-499
    g_modules.autoLoadModules(499)
    g_modules.ensureModuleLoaded('client')
    g_modules.ensureModuleLoaded('client_terminal')

    -- game modules 500-999
    g_modules.autoLoadModules(999)
    g_modules.ensureModuleLoaded('game_interface')

    -- mods 1000-9999
    g_modules.autoLoadModules(9999)
    g_modules.ensureModuleLoaded('client_mods')

    local script = '/' .. g_app.getCompactName() .. 'rc.lua'

    if g_resources.fileExists(script) then
        dofile(script)
    end

    -- uncomment the line below so that modules are reloaded when modified. (Note: Use only mod dev)
    -- g_modules.enableAutoReload()
end

-- run updater, must use data.zip
if g_app.hasUpdater() then
    g_modules.ensureModuleLoaded("updater")
    return Updater.init(loadModules)
end

loadModules()

-- Renderer baseline captures are opt-in and must never affect a normal client launch.
-- The module takes the screenshot after the regular startup modules have built the UI,
-- which makes the capture exercise the same DrawPool/OpenGL path as an interactive run.
if g_app.getStartupOptions():find("--renderer-baseline=", 1, true) then
    g_modules.ensureModuleLoaded("dev_renderer_baseline")
end
