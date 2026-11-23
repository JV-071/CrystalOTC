# Runs the RmlUi verification scripts against one client executable and prints a summary.
#
# usage (repository root, game assets in data/things):
#   powershell -ExecutionPolicy Bypass -STA -File tools\rmlui\verify\run.ps1 -Exe .\CrystalOTC_gl_x64.exe -Tag gl
#   powershell -ExecutionPolicy Bypass -STA -File tools\rmlui\verify\run.ps1 -Exe .\CrystalOTC.exe -Tag angle -Only lifetime,keys
#
# -Only takes any of: demo, focus, showcase, keys, lifetime, gc, exit, vulkan (default: all of them).
# Everything the runs write goes to build\rmlui-verify (settings of the client under test,
# captures, one log per script). See README.md in this folder for what each script checks.
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$Tag,
    [string[]]$Only = @()
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Get-Location).Path
$out = Join-Path $root 'build\rmlui-verify'
$rc = Join-Path $root 'data\crystalotcrc.lua'
$config = Join-Path $root 'config.ini'
$clientLog = Join-Path $root 'crystalotc.log'
$utf8 = New-Object System.Text.UTF8Encoding $false
$Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

if (-not (Test-Path $Exe)) { "executable not found: $Exe"; exit 2 }
if (Test-Path $rc) { "data\crystalotcrc.lua already exists: the scripts are installed under that name, move it away first"; exit 2 }
foreach ($dir in 'userdir', 'shots', 'logs') { New-Item -ItemType Directory -Force (Join-Path $out $dir) | Out-Null }

$results = New-Object System.Collections.ArrayList
$interesting = '\[verify\] (FAIL|SKIP|NOTE|frames|backend|render backend)|\[rmlui\] (?!Loaded font|Loading Lua|ready)|ERROR(?!: not found|: Failed to load soundbank)|WARNING|Lua exception|stack traceback'

function Wanted($name) { return ($Only.Count -eq 0) -or ($Only -contains $name) }

# A script as the client runs it: prelude.lua (the step scheduler) + the script + verifyStart().
function Compose($file, $map) {
    $prelude = [System.IO.File]::ReadAllText((Join-Path $here 'prelude.lua'), [System.Text.Encoding]::UTF8)
    $text = [System.IO.File]::ReadAllText((Join-Path $here $file), [System.Text.Encoding]::UTF8)
    foreach ($key in $map.Keys) { $text = $text.Replace($key, $map[$key]) }
    return $prelude + "`n" + $text + "`nverifyStart()`n"
}

function Install($file, $map) {
    [System.IO.File]::WriteAllText($rc, (Compose $file $map), $utf8)
}

# $minPass: how many "[verify] PASS" lines the script prints when it runs to the end
function Record($name, $exit, $log, $minPass, $known) {
    $pass = 0; $fail = 0
    if ($log -and (Test-Path $log)) {
        $pass = @(Select-String -Path $log -Pattern '\[verify\] PASS').Count
        $fail = @(Select-String -Path $log -Pattern '\[verify\] FAIL').Count
        Select-String -Path $log -Pattern $interesting | ForEach-Object { '    ' + $_.Line.Substring(0, [Math]::Min(220, $_.Line.Length)) }
    }
    $ok = ("$exit" -eq '0') -and ($fail -eq 0) -and ($pass -ge $minPass)
    $verdict = if ($ok) { 'ok' } elseif ($known) { "KNOWN ISSUE ($known)" } else { 'FAILED' }
    [void]$results.Add([pscustomobject]@{ Script = $name; Exit = "$exit"; Pass = $pass; Fail = $fail; Result = $verdict })
}

# Runs the installed script with shot.ps1 (captures on "[verify] shot <name>", real keys on "[verify] keys#N").
function Run-Captured($name, $file, $map, $minPass, $timeoutSec, $known) {
    "=== $name ($Tag)"
    Install $file $map
    $exit = 'unknown'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'shot.ps1') -Exe $Exe -OutDir (Join-Path $out 'shots') -TimeoutSec $timeoutSec |
        ForEach-Object {
            if ($_ -match '^exit code: (-?\d+)') { $exit = $Matches[1] }
            elseif ($_ -match '^KILLED') { $exit = 'KILLED' }
            elseif ($_ -match '^(keys|mouse) ') { '    ' + $_ }
        }
    $log = Join-Path $out "logs\$name-$Tag.log"
    if (Test-Path $clientLog) { Copy-Item $clientLog $log -Force } else { $log = $null }
    Record $name $exit $log $minPass $known
}

# Runs a script without captures; only the exit code matters.
function Run-ExitOnly($name, $text) {
    [System.IO.File]::WriteAllText($rc, $text, $utf8)
    $p = Start-Process -FilePath $Exe -WorkingDirectory $root -PassThru
    if (-not $p.WaitForExit(40000)) { $p.Kill(); $exit = 'KILLED' } else { $exit = $p.ExitCode }
    Record $name $exit $null 0 $null
}

$tagMap = @{ '@TAG@' = $Tag }

try {
    if (Wanted 'demo') {
        Run-Captured 'demo' 'demo.lua' $tagMap 1 75 $null
        # OTUI text must survive RmlUi starting (the GL state it leaves behind once blanked the font atlas)
        $shot = Join-Path $out "shots\demo-$Tag.png"
        if (Test-Path $shot) {
            $line = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'check-text.ps1') $shot
            "    $line"
            [void]$results.Add([pscustomobject]@{ Script = 'demo: OTUI text'; Exit = "$LASTEXITCODE"; Pass = 0; Fail = 0; Result = $(if ($LASTEXITCODE -eq 0) { 'ok' } else { 'FAILED' }) })
        }
    }
    if (Wanted 'focus') { Run-Captured 'focus' 'focus.lua' $tagMap 6 75 $null }
    if (Wanted 'showcase') { Run-Captured 'showcase' 'showcase.lua' $tagMap 22 120 $null }
    if (Wanted 'keys') { Run-Captured 'keys' 'keys.lua' $tagMap 8 120 $null }

    if (Wanted 'lifetime') {
        # The clipboard check overwrites the clipboard: only when it holds text (put back afterwards) or nothing.
        Add-Type -AssemblyName System.Windows.Forms
        $data = [System.Windows.Forms.Clipboard]::GetDataObject()
        $formats = if ($data) { @($data.GetFormats()) } else { @() }
        $hasText = [System.Windows.Forms.Clipboard]::ContainsText()
        $clip = if ($formats.Count -eq 0 -or $hasText) { '1' } else { '0' }
        $saved = if ($hasText) { [System.Windows.Forms.Clipboard]::GetText() } else { $null }
        try {
            Run-Captured 'lifetime' 'lifetime.lua' @{ '@TAG@' = $Tag; '@CLIP@' = $clip } $(if ($clip -eq '1') { 22 } else { 19 }) 120 $null
        } finally {
            if ($clip -eq '1') {
                if ($saved) { [System.Windows.Forms.Clipboard]::SetText($saved) } else { [System.Windows.Forms.Clipboard]::Clear() }
            }
        }
    }

    if (Wanted 'gc') { Run-Captured 'gc' 'gc.lua' @{} 4 90 $null }

    if (Wanted 'exit') {
        "=== exit ($Tag)"
        Run-ExitOnly 'exit: widgets still referenced' (Compose 'exit-referenced.lua' @{})
        foreach ($i in 1..3) { Run-ExitOnly "exit: resize storm $i" (Compose 'exit-stress.lua' @{ '@MODE@' = 'resize' }) }
        foreach ($i in 1..3) { Run-ExitOnly "exit: bad images $i" (Compose 'exit-stress.lua' @{ '@MODE@' = 'images' }) }
    }

    if (Wanted 'vulkan') {
        # Pure-Vulkan mode: there is no RmlUi executor for it yet, so RmlUi has to stay off and say so.
        $backup = Join-Path $out 'config.ini.before'
        if (Test-Path $config) { Copy-Item $config $backup -Force }
        try {
            [System.IO.File]::WriteAllText($config, "[graphics]`r`nrenderBackend = vulkan`r`n", $utf8)
            Run-Captured 'vulkan' 'vulkan.lua' @{} 5 75 'the Vulkan renderer itself crashes on exit, with or without RmlUi'
            $log = Join-Path $out "logs\vulkan-$Tag.log"
            if (Test-Path $log) {
                $gl = @(Select-String -Path $log -Pattern 'wglCreateContext|creating OpenGL context|rendering with OpenGL').Count
                "    OpenGL context lines in the Vulkan run: $gl"
                [void]$results.Add([pscustomobject]@{ Script = 'vulkan: no GL context'; Exit = '-'; Pass = 0; Fail = $gl; Result = $(if ($gl -eq 0) { 'ok' } else { 'FAILED' }) })
            }
        } finally {
            if (Test-Path $backup) { Move-Item $backup $config -Force } else { Remove-Item $config -ErrorAction SilentlyContinue }
        }
    }
} finally {
    Remove-Item $rc -ErrorAction SilentlyContinue
}

''
$results | Format-Table -AutoSize | Out-String -Width 200
$failed = @($results | Where-Object { $_.Result -eq 'FAILED' }).Count
"captures: $out\shots    logs: $out\logs"
"failed: $failed"
if ($failed -gt 0) { exit 1 }
