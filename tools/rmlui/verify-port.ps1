# Checks that the rmlui overlay port (vcpkg-overlays/rmlui) is installed for the MSBuild
# build and that its Lua plugin was compiled against LuaJIT (Lua 5.1 API).
# Run from the repository root:  powershell -File tools\rmlui\verify-port.ps1
$ErrorActionPreference = 'Stop'

$root = "vc18\vcpkg_installed\x64-windows-static"
$must = "lib\rmlui.lib","lib\rmlui_lua.lib","lib\rmlui_debugger.lib",
        "include\RmlUi\Core.h","include\RmlUi\Lua.h","include\RmlUi\Debugger.h",
        "share\rmlui\RmlUiConfig.cmake"
$missing = $must | Where-Object { -not (Test-Path (Join-Path $root $_)) }
if ($missing) { throw "missing: $($missing -join ', ')" }

$dumpbin = (Get-ChildItem 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe' | Select-Object -Last 1).FullName
$syms = & $dumpbin /symbols "$root\lib\rmlui_lua.lib"
if (-not ($syms | Select-String 'lua_objlen')) { throw "rmlui_lua.lib was not built against the Lua 5.1 API (LuaJIT)" }
if ($syms | Select-String 'lua_rawlen') { throw "rmlui_lua.lib references the Lua 5.2+ API" }
"rmlui port OK"
