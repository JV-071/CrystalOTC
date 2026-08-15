@echo off
setlocal enabledelayedexpansion
REM ==========================================================================
REM  CrystalOTC - one-click Windows build
REM  Double-click this file (or run it from cmd). It sets up the MSVC toolchain
REM  and vcpkg, then configures and builds the client with the windows-release
REM  preset. The FIRST run compiles every dependency via vcpkg (30+ minutes);
REM  later runs reuse the cache and are fast.
REM ==========================================================================
cd /d "%~dp0"

echo ==^> Locating Visual Studio (C++ toolchain)...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo ERROR: Visual Studio Installer not found.
    echo        Install Visual Studio 2022 or Build Tools with "Desktop development with C++".
    goto :fail
)
set "VSPATH="
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%i"
if not defined VSPATH (
    echo ERROR: No Visual Studio install with the C++ toolset.
    echo        Open the VS Installer and add "Desktop development with C++".
    goto :fail
)
echo     %VSPATH%

set "VCVARS=%VSPATH%\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCVARS%" (
    echo ERROR: vcvars64.bat not found at "%VCVARS%".
    goto :fail
)
echo ==^> Importing MSVC environment (vcvars64)...
call "%VCVARS%" >nul
if errorlevel 1 goto :fail
cd /d "%~dp0"

REM --- CMake + Ninja (fall back to the copies bundled with Visual Studio) ---
where cmake >nul 2>&1
if errorlevel 1 set "PATH=%VSPATH%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;%PATH%"
where ninja >nul 2>&1
if errorlevel 1 set "PATH=%VSPATH%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%"
where cmake >nul 2>&1
if errorlevel 1 (
    echo ERROR: cmake not found. Install CMake ^>= 3.22 or the VS component "C++ CMake tools for Windows".
    goto :fail
)
where ninja >nul 2>&1
if errorlevel 1 (
    echo ERROR: ninja not found. Install Ninja or the VS component "C++ CMake tools for Windows".
    goto :fail
)

REM --- vcpkg: find an existing install before cloning ------------------------
REM Checked in order: VCPKG_ROOT, vcpkg on PATH, VCPKG_INSTALLATION_ROOT, common
REM folders, then .\vcpkg. Direct folder checks matter because a machine-level
REM VCPKG_ROOT does not reach processes started before it was set.
echo ==^> Checking vcpkg...
call :find_vcpkg "%VCPKG_ROOT%"              && goto :vcpkg_ok
for /f "delims=" %%p in ('where vcpkg 2^>nul') do call :find_vcpkg "%%~dpp." && goto :vcpkg_ok
call :find_vcpkg "%VCPKG_INSTALLATION_ROOT%" && goto :vcpkg_ok
call :find_vcpkg "%SystemDrive%\vcpkg"       && goto :vcpkg_ok
call :find_vcpkg "%USERPROFILE%\vcpkg"       && goto :vcpkg_ok
call :find_vcpkg "%SystemDrive%\dev\vcpkg"   && goto :vcpkg_ok
call :find_vcpkg "%SystemDrive%\src\vcpkg"   && goto :vcpkg_ok
call :find_vcpkg "%SystemDrive%\tools\vcpkg" && goto :vcpkg_ok
call :find_vcpkg "%~dp0vcpkg"                && goto :vcpkg_ok

where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: vcpkg not found and git is unavailable to clone it.
    echo        Install git, or set VCPKG_ROOT to an existing vcpkg checkout.
    goto :fail
)
echo     No vcpkg found - cloning microsoft/vcpkg into .\vcpkg (one time)...
git clone https://github.com/microsoft/vcpkg "%~dp0vcpkg"
if errorlevel 1 goto :fail
call "%~dp0vcpkg\bootstrap-vcpkg.bat" -disableMetrics
if errorlevel 1 goto :fail
set "VCPKG_ROOT=%~dp0vcpkg"
:vcpkg_ok
echo     VCPKG_ROOT=%VCPKG_ROOT%

REM --- sccache is optional; disable it in the preset when it is not installed ---
set "EXTRA="
where sccache >nul 2>&1
if errorlevel 1 set "EXTRA=-DOPTIONS_ENABLE_SCCACHE=OFF"

echo ==^> Configuring (windows-release)...
echo     First run downloads and builds all dependencies via vcpkg - be patient.
cd /d "%~dp0"
cmake --preset windows-release %EXTRA%
if errorlevel 1 goto :fail

echo ==^> Building...
cmake --build --preset windows-release
if errorlevel 1 goto :fail

REM --- place the freshly built client at the repo root ---
set "EXE="
for /r "%~dp0build\windows-release" %%f in (otclient*.exe) do set "EXE=%%f"
if not defined EXE for /r "%~dp0build\windows-release" %%f in (CrystalOTC*.exe) do set "EXE=%%f"
echo.
if defined EXE (
    copy /y "!EXE!" "%~dp0CrystalOTC.exe" >nul
    if errorlevel 1 (
        echo     Build OK: !EXE!
        echo     Could not copy to the repo root ^(is the client running?^) - copy it manually.
    ) else (
        echo     Build OK -^> %~dp0CrystalOTC.exe
    )
) else (
    echo     Build finished but no client exe was found under build\windows-release.
)
echo.
echo Done.
pause
exit /b 0

:find_vcpkg
REM %~1 = candidate directory. Sets VCPKG_ROOT and returns 0 when it holds vcpkg.
if "%~1"=="" exit /b 1
if not exist "%~f1\scripts\buildsystems\vcpkg.cmake" exit /b 1
set "VCPKG_ROOT=%~f1"
exit /b 0

:fail
echo.
echo Build FAILED - see the messages above.
pause
exit /b 1
