# Settings and layout math shared by the scripts. Only Get-AppInfo talks to Windows, so Test.ps1 can check the rest on its own.

# Your settings live in settings.json (not in git). On first run it is created from settings.default.json.
function Get-SettingsFile([string]$root) {
    $file = Join-Path $root 'settings.json'
    if (-not (Test-Path $file)) { Copy-Item (Join-Path $root 'settings.default.json') $file }
    $file
}

# Reads settings.json. Weights come grouped as { "3": ["Code", ...] } and are turned into a lookup: name -> weight
# (case-insensitive, like process names). Throws on missing keys or an app listed in two groups.
function Read-TileSettings([string]$path) {
    $cfg = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($k in 'Hotkey', 'RestoreHotkey', 'Gap', 'MinWidth', 'MinHeight', 'Weights', 'GameFolders') { if ($null -eq $cfg.$k) { throw "settings.json is missing $k" } }
    $lookup = @{}
    foreach ($grp in $cfg.Weights.PSObject.Properties) {
        $w = [double]::Parse($grp.Name, [Globalization.CultureInfo]::InvariantCulture)
        foreach ($app in $grp.Value) { if ($lookup.ContainsKey($app)) { throw "$app is in two weight groups" }; $lookup[$app] = $w }
    }
    $cfg.Weights = $lookup
    $cfg
}

# Process name and weight of a window. Weight 0 for anything from a game folder; Known = has an entry in Weights.
function Get-AppInfo([IntPtr]$hwnd, $cfg) {
    $p = 0; [void][Tiler]::GetWindowThreadProcessId($hwnd, [ref]$p)
    $proc = Get-Process -Id $p -ErrorAction SilentlyContinue; $name = "$($proc.ProcessName)"; $path = "$($proc.Path)"
    $known = $cfg.Weights.ContainsKey($name)
    $w = if ($known) { [double]$cfg.Weights[$name] } else { 1.0 }
    if ($cfg.GameFolders | Where-Object { $path -like "*$_*" }) { $w = 0; $known = $true }
    [pscustomobject]@{ Name = $name; W = $w; Known = $known }
}

# Apps seen without a weight are kept in "New" in settings.json until you move them into a weight group.
# Returns settings text with "New" set to $names (an app that now has a weight is dropped). Rest of the file stays as is.
function Set-NewApps([string]$text, [string[]]$names) {
    $list = ($names | ForEach-Object { '"' + $_ + '"' }) -join ', '
    $text -replace '"New"\s*:\s*\[[^\]]*\]', ('"New": [' + $list + ']')
}

# Splits $length into parts by weight; a part whose app needs more ($need) keeps that minimum and the others
# share what's left (if even that can't work, plain weights). Returns the cut positions 0..$length (Count+1 values).
function Split-Length([int]$length, [double[]]$weight, [int[]]$need) {
    $n = $weight.Count; $total = 0.0; foreach ($v in $weight) { $total += $v }
    $fixedL = 0; $freeT = 0.0; $isFixed = New-Object bool[] $n
    for ($i = 0; $i -lt $n; $i++) { if ($need[$i] -gt $length * $weight[$i] / $total) { $isFixed[$i] = $true; $fixedL += $need[$i] } else { $freeT += $weight[$i] } }
    if ($fixedL -ge $length -or $freeT -le 0) { $isFixed = New-Object bool[] $n; $fixedL = 0; $freeT = $total }
    $cuts = New-Object int[] ($n + 1); $acc = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $acc += $(if ($isFixed[$i]) { $need[$i] } else { ($length - $fixedL) * $weight[$i] / $freeT })
        $cuts[$i + 1] = if ($i -eq $n - 1) { $length } else { [int][math]::Floor($acc + 0.0001) }
    }
    , $cuts
}

# Slots for given columns. $cols: index arrays in screen order (left to right), each one column stacked top to bottom.
# Column width by weight (its biggest app + a quarter of the rest), row height by weight, both respecting each app's
# own minimum size ($needW/$needH). Returns @(x,y,w,h) per window index ($null = not placed).
function Get-ColumnSlots($cols, [double[]]$w, [int[]]$needW, [int[]]$needH, [int]$x, [int]$y, [int]$width, [int]$height) {
    $nc = $cols.Count; $cw = New-Object double[] $nc; $cn = New-Object int[] $nc
    for ($c = 0; $c -lt $nc; $c++) { $max = 0.0; $sum = 0.0
        foreach ($i in $cols[$c]) { $sum += $w[$i]; if ($w[$i] -gt $max) { $max = $w[$i] }; if ($i -lt $needW.Count -and $needW[$i] -gt $cn[$c]) { $cn[$c] = $needW[$i] } }
        $cw[$c] = $max + 0.25 * ($sum - $max) }
    $xc = Split-Length $width $cw $cn
    $slots = New-Object object[] $w.Count
    for ($c = 0; $c -lt $nc; $c++) {
        $rows = @($cols[$c]); $rw = [double[]]@($rows | ForEach-Object { $w[$_] }); $rn = [int[]]@($rows | ForEach-Object { if ($_ -lt $needH.Count) { $needH[$_] } else { 0 } })
        $yc = Split-Length $height $rw $rn
        for ($r = 0; $r -lt $rows.Count; $r++) { $slots[$rows[$r]] = @(($x + $xc[$c]), ($y + $yc[$r]), ($xc[$c + 1] - $xc[$c]), ($yc[$r + 1] - $yc[$r])) }
    }
    , $slots
}

# Best arrangement for one monitor: columns side by side, apps stacked inside them, whatever fits best.
# $w: weights sorted most important first; $needW/$needH: each app's own minimum size (+gap, 0 = unknown).
# Tries every split of the first k apps into columns (most important in the first column) and keeps as many apps
# as can be shown readably (slot >= $minW x $minH). Among those it picks the highest score: important apps get more
# area, and slots below a comfortable size count less ($comfortW per app, ~800 or 1280 for WideApps, x $comfortH).
# $bigRight mirrors it so the first column faces the other monitor.
# Returns @{ Slots = per-index @(x,y,w,h); Count = how many of the first apps are shown }.
function Get-BestLayout([double[]]$w, [int[]]$needW, [int[]]$needH, [int]$x, [int]$y, [int]$width, [int]$height, [bool]$bigRight, [int]$gap, [int]$minW, [int]$minH, [int[]]$comfortW = @(), [int]$comfortH = 600) {
    $maxCols = [math]::Max(1, [math]::Floor($width / ($minW + $gap))); $maxRows = [math]::Max(1, [math]::Floor($height / ($minH + $gap)))
    for ($k = [math]::Min($w.Count, $maxCols * $maxRows); $k -ge 1; $k--) {
        $best = $null; $bestScore = [double]::NegativeInfinity
        for ($mask = 0; $mask -lt (1 -shl ($k - 1)); $mask++) {
            $cols = New-Object System.Collections.ArrayList; $cur = New-Object System.Collections.ArrayList; [void]$cur.Add(0)
            for ($i = 1; $i -lt $k; $i++) { if ($mask -band (1 -shl ($i - 1))) { [void]$cols.Add($cur.ToArray()); $cur = New-Object System.Collections.ArrayList }; [void]$cur.Add($i) }
            [void]$cols.Add($cur.ToArray())
            if ($cols.Count -gt $maxCols) { continue }
            $tooTall = $false; foreach ($c in $cols) { if ($c.Count -gt $maxRows) { $tooTall = $true } }; if ($tooTall) { continue }
            $order = $cols.ToArray(); if ($bigRight) { [array]::Reverse($order) }
            $slots = Get-ColumnSlots $order $w $needW $needH $x $y $width $height
            $score = 0.0; $ok = $true
            for ($i = 0; $i -lt $k; $i++) { $s = $slots[$i]; $sw = $s[2] - $gap; $sh = $s[3] - $gap
                if ($sw -lt $minW -or $sh -lt $minH -or ($i -lt $needW.Count -and $needW[$i] -gt $s[2] + 1) -or ($i -lt $needH.Count -and $needH[$i] -gt $s[3] + 1)) { $ok = $false; break }
                # Below the comfortable size counts double, so very flat or very narrow windows lose against a balanced mix.
                $score += $w[$i] * ([math]::Log($sw * $sh) + 2 * [math]::Log([math]::Min(1.0, $sw / $(if ($i -lt $comfortW.Count -and $comfortW[$i]) { $comfortW[$i] } else { 800 }))) + 2 * [math]::Log([math]::Min(1.0, $sh / $comfortH))) }   # 1.0, not 1: Min(int,int) would round
            if ($ok -and $score -gt $bestScore) { $bestScore = $score; $best = $slots }
        }
        if ($best) { return @{ Slots = $best; Count = $k } }
    }
    $one = New-Object object[] $w.Count; $one[0] = @($x, $y, $width, $height); @{ Slots = $one; Count = 1 }
}

# Which monitor each app goes to. $items: objects with .W, sorted most-used first; $screenCount: monitors (0 = main).
# Main monitor gets the MainScreenApps alone if one is open, else only weight 3+ apps (or the most-used one if none); the rest spread over the other monitors by weight.
function Get-MonitorGroups($items, [int]$screenCount) {
    $groups = @(0..($screenCount - 1) | ForEach-Object { , (New-Object System.Collections.ArrayList) })
    $direct = @($items | Where-Object { $_.Solo })   # MainScreenApps: the main monitor is theirs alone
    if ($direct.Count -eq 0) { $direct = @($items | Where-Object { $_.W -ge 3 }) }
    if ($direct.Count -eq 0) { $direct = @($items[0]) }
    if ($screenCount -eq 1) { $direct = $items }
    foreach ($it in $direct) { [void]$groups[0].Add($it) }
    $load = @(0.0) * $screenCount
    foreach ($it in @($items | Where-Object { $direct -notcontains $_ })) {
        $m = 1; for ($j = 2; $j -lt $screenCount; $j++) { if ($load[$j] -lt $load[$m]) { $m = $j } }
        [void]$groups[$m].Add($it); $load[$m] += $it.W }
    , $groups
}
