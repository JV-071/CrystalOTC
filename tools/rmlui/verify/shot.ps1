# Runs the client and captures its window every time the verification script prints
#   [verify] shot <name>
# to crystalotc.log. Works for any render backend (the capture is done by Windows).
# usage (from the repository root): powershell -File shot.ps1 -Exe .\CrystalOTC_gl_x64.exe -OutDir <dir> [-TimeoutSec 90]
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [int]$TimeoutSec = 90
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
}
"@
[Win]::SetProcessDPIAware() | Out-Null

$root = (Get-Location).Path
$log = Join-Path $root 'crystalotc.log'
New-Item -ItemType Directory -Force $OutDir | Out-Null
Remove-Item $log -ErrorAction SilentlyContinue

function Read-Log {
    if (-not (Test-Path $log)) { return @() }
    try {
        $fs = [System.IO.File]::Open($log, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object System.IO.StreamReader($fs)
        $text = $sr.ReadToEnd()
        $sr.Dispose(); $fs.Dispose()
        return $text -split "`r?`n"
    } catch { return @() }
}

function Capture($proc, $name) {
    $proc.Refresh()
    $h = $proc.MainWindowHandle
    if ($h -eq [IntPtr]::Zero) { "shot ${name}: no window"; return }
    $r = New-Object Win+RECT
    [Win]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.R - $r.L; $hh = $r.B - $r.T
    if ($w -le 0 -or $hh -le 0) { "shot ${name}: empty window rect"; return }
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [Win]::PrintWindow($h, $hdc, 2)   # PW_RENDERFULLCONTENT: also GPU-drawn content
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save((Join-Path $OutDir "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    "shot ${name}: ${w}x${hh} printwindow=$ok"
}

# "[verify] keys#<n> <SendKeys string>": type into the client, but ONLY if its window really is
# in the foreground - otherwise the keys would land in whatever the user is working on.
function Send-Keys($proc, $keys) {
    $proc.Refresh()
    $h = $proc.MainWindowHandle
    [Win]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 350
    if ([Win]::GetForegroundWindow() -ne $h) { "keys '$keys': SKIPPED (client window is not in the foreground)"; return }
    [System.Windows.Forms.SendKeys]::SendWait($keys)
    "keys '$keys': sent"
}

# "[verify] mouse#<n> <x> <y>": tell the client the mouse is at (x, y) of its client area. Only a
# window message is posted, the real pointer does not move. Scripts use it to make hover state
# the same on every run instead of depending on where the pointer happens to be.
function Send-Mouse($proc, $x, $y) {
    $proc.Refresh()
    $h = $proc.MainWindowHandle
    if ($h -eq [IntPtr]::Zero) { "mouse ${x},${y}: no window"; return }
    $l = [IntPtr](([int]$y -shl 16) -bor ([int]$x -band 0xFFFF))
    [Win]::PostMessage($h, 0x0200, [IntPtr]::Zero, $l) | Out-Null   # WM_MOUSEMOVE
    "mouse ${x},${y}: posted"
}

$p = Start-Process -FilePath $Exe -WorkingDirectory $root -PassThru
$seen = @{}
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 150
    foreach ($line in (Read-Log)) {
        if ($line -match '\[verify\] (keys#\d+) (.+)$') {
            $id = $Matches[1]; $keys = $Matches[2].Trim()
            if (-not $seen.ContainsKey($id)) { $seen[$id] = $true; Send-Keys $p $keys }
        }
        if ($line -match '\[verify\] (mouse#\d+) (\d+) (\d+)') {
            $id = $Matches[1]
            if (-not $seen.ContainsKey($id)) { $seen[$id] = $true; Send-Mouse $p $Matches[2] $Matches[3] }
        }
        if ($line -match '\[verify\] shot (\S+)') {
            $name = $Matches[1]
            if (-not $seen.ContainsKey($name)) {
                $seen[$name] = $true
                Start-Sleep -Milliseconds 500   # let the frame that follows the marker reach the screen
                Capture $p $name
            }
        }
    }
}

if (-not $p.HasExited) { $p.Kill(); "KILLED after ${TimeoutSec}s" } else { "exit code: $($p.ExitCode)" }
