# Checks the settings files and the layout math without moving any window. Prints "all tests ok" or throws.
$ErrorActionPreference = 'Stop'   # any error fails the test run
. "$PSScriptRoot\Layout.ps1"

$cfg = Read-TileSettings "$PSScriptRoot\settings.default.json"
if ($cfg.Weights['code'] -lt 3 -or $cfg.Weights['Discord'] -ne 2.5 -or @($cfg.WideApps) -notcontains 'chrome') { throw "weights not read from settings.default.json" }
if (Test-Path "$PSScriptRoot\settings.json") { $null = Read-TileSettings "$PSScriptRoot\settings.json" }   # your own settings must load too

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("tw-test-" + [guid]::NewGuid()); New-Item -ItemType Directory $tmp | Out-Null
Copy-Item "$PSScriptRoot\settings.default.json" $tmp
try { if (-not (Test-Path (Get-SettingsFile $tmp))) { throw "settings.json not created from defaults" } } finally { Remove-Item $tmp -Recurse }

# Checks a layout: shown slots inside the area, readable, no two overlapping.
function Assert-Layout($L, [int]$n, [string]$what) {
    $shown = @(0..($L.Count - 1) | ForEach-Object { , $L.Slots[$_] })
    if ($L.Count -lt 1 -or $L.Count -gt $n) { throw "$what : shows $($L.Count) of $n" }
    foreach ($s in $shown) { if ($s[0] -lt 0 -or $s[1] -lt 0 -or $s[0] + $s[2] -gt 1896 -or $s[1] + $s[3] -gt 1014) { throw "$what : slot outside screen $s" }
        if ($L.Count -gt 1 -and ($s[2] - 12 -lt 500 -or $s[3] - 12 -lt 300)) { throw "$what : unreadable slot $s" } }
    for ($i = 0; $i -lt $shown.Count; $i++) { for ($j = $i + 1; $j -lt $shown.Count; $j++) { $a = $shown[$i]; $b = $shown[$j]
        if ($a[0] -lt $b[0] + $b[2] -and $b[0] -lt $a[0] + $a[2] -and $a[1] -lt $b[1] + $b[3] -and $b[1] -lt $a[1] + $a[3]) { throw "$what : slots overlap" } } }
}
function Get-L([double[]]$w, [int[]]$nw = @(), [int[]]$nh = @(), [bool]$right = $false) { Get-BestLayout $w $nw $nh 0 0 1896 1014 $right 12 500 300 }

foreach ($case in @(@(5), @(5, 4, 4), @(2.5, 2, 2, 1.5), @(1, 1, 1, 1, 1, 1), @(3, 3, 3, 3), @(2, 1))) { $L = Get-L $case; Assert-Layout $L $case.Count "$case" }
$L = Get-L @(5, 4, 4); if ($L.Count -ne 3) { throw "3 main apps should all fit" }
if ($L.Slots[0][2] * $L.Slots[0][3] -le $L.Slots[1][2] * $L.Slots[1][3]) { throw "most important app should get the most area" }
$L = Get-L @(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1); Assert-Layout $L 12 "12 apps"; if ($L.Count -gt 9) { throw "12 apps can't all be readable" }
$L = Get-L @(2.5, 2, 2) @(952, 0, 0); Assert-Layout $L 3 "Discord min width"; if ($L.Slots[0][2] -lt 952) { throw "Discord's minimum width ignored" }
$L = Get-L @(2, 2) @(1200, 1200); if ($L.Count -ne 2 -or $L.Slots[0][0] -ne $L.Slots[1][0]) { throw "two wide apps should stack" }
$L = Get-L @(2, 2) @(1200, 1200) @(800, 800); if ($L.Count -ne 1) { throw "two big apps (1200x800) cannot share one screen" }
$L = Get-L @(2, 2) @() @(800, 800); if ($L.Count -ne 2 -or $L.Slots[0][1] -ne $L.Slots[1][1]) { throw "two tall apps should go side by side" }
$L = Get-BestLayout ([double[]]@(5, 5, 4)) ([int[]]@(0, 0, 614)) @() 0 0 1896 1014 $false 12 500 300 ([int[]]@(800, 1280, 800)); Assert-Layout $L 3 "wide Brave"; if ($L.Slots[1][2] -lt 1000) { throw "a wide app should get a wide slot" }
$L = Get-L @(2.5, 2, 2, 1.5) @(814, 812, 0, 0) @(0, 612, 0, 0); Assert-Layout $L 4 "Discord+Spotify"; if ($L.Count -lt 3) { throw "Discord, Spotify and one more should fit (Spotify stacked)" }
$L = Get-L @(3, 2) @() @(800, 800) $true; if ($L.Count -ne 2 -or $L.Slots[0][0] -le $L.Slots[1][0]) { throw "mirrored layout should put the main app on the right" }

$it = @(3, 3, 2, 1, 1) | ForEach-Object { [pscustomobject]@{ W = $_ } }
$g = Get-MonitorGroups $it 2; if ($g[0].Count -ne 2 -or $g[1].Count -ne 3) { throw "main monitor should get only weight-3 apps" }
$g = Get-MonitorGroups @($it[3], $it[4]) 2; if ($g[0].Count -ne 1) { throw "main monitor should get the top app when none is weight 3" }
$g = Get-MonitorGroups $it 1; if ($g[0].Count -ne 5) { throw "single monitor should get everything" }

$t = Set-NewApps "{`n    `"New`": [`"a`"],`n    `"Gap`": 12`n}" @('a', 'b'); if ($t -notmatch '"New": \["a", "b"\],\s+"Gap": 12') { throw "New list not written: $t" }
$t = Set-NewApps '{ "New": ["a", "b"] }' @(); if ($t -ne '{ "New": [] }') { throw "New list not cleared: $t" }
"all tests ok"
