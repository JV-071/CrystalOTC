# Regression check for "OTUI text vanishes after RmlUi starts": counts the bright, unsaturated
# pixels of the top-menu label ("0 Players online") in a full-window capture. With the text
# drawn there are hundreds of them; with a blank font atlas region there are almost none.
# usage: powershell -File check-text.ps1 shot.png [min]     exit code 1 when below min (default 150)
param([Parameter(Mandatory = $true)][string]$File, [int]$Min = 150)
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap ((Resolve-Path $File).Path)
$cx = [int]($bmp.Width / 2)
$count = 0
for ($y = 30; $y -lt 60; $y++) {
    for ($x = $cx - 60; $x -lt $cx + 170; $x++) {
        $p = $bmp.GetPixel($x, $y)
        $hi = [Math]::Max($p.R, [Math]::Max($p.G, $p.B)); $lo = [Math]::Min($p.R, [Math]::Min($p.G, $p.B))
        if ($hi -gt 185 -and ($hi - $lo) -lt 40) { $count++ }
    }
}
$bmp.Dispose()
"{0}: {1} text pixels (min {2})" -f (Split-Path $File -Leaf), $count, $Min
if ($count -lt $Min) { exit 1 }
