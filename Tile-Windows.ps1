# Tiles every open app window across all monitors, weighted by how much you use each app (see settings.json).
# Runs on demand from the Start-menu shortcut (Setup.ps1 creates it with the hotkey).
. "$PSScriptRoot\Layout.ps1"
$settingsFile = Get-SettingsFile $PSScriptRoot
$cfg = Read-TileSettings $settingsFile
if (-not ('Tiler' -as [type])) { Add-Type -Path "$PSScriptRoot\Native.cs" }

try { [Threading.EventWaitHandle]::OpenExisting('TileWindowsTiled').Set() } catch { }   # ends the sign-in default sizing (Restore-Windows.ps1 -Startup)
[Tiler]::MakeDpiAware()                    # real pixels on every monitor, also with mixed display scaling
$focus = [Tiler]::GetForegroundWindow()   # the window (or game) you were in keeps focus
Add-Type -AssemblyName System.Windows.Forms
$screens = @([System.Windows.Forms.Screen]::AllScreens | Sort-Object { -[int]$_.Primary }, { $_.Bounds.X })
$mainX = $screens[0].Bounds.X

# Weigh each open window; weight 0 and anything from a game folder is left alone.
$z = 0; $unknown = New-Object System.Collections.ArrayList
$items = @([Tiler]::AppWindows([uint32]$PID) | ForEach-Object { $app = Get-AppInfo $_ $cfg
    if ($app.Name -and -not $app.Known) { [void]$unknown.Add($app.Name) }
    $comfort = if (@($cfg.WideApps) -contains $app.Name) { 1280 } else { 800 }   # wide apps (videos, websites) prefer wide slots
    if ($app.W -gt 0) { [pscustomobject]@{ H = $_; W = $app.W; Z = $z; Solo = @($cfg.MainScreenApps) -contains $app.Name; MinW = 0; MinH = 0; ComfortW = $comfort } }; $z++ })

# Reminder: open apps without a weight go into "New" in settings.json and a notification asks you to sort them.
$pending = @(@($cfg.New) + @($unknown) | Where-Object { $_ -and -not $cfg.Weights.ContainsKey($_) } | Sort-Object -Unique)
if ((@($cfg.New) -join '|') -ne ($pending -join '|')) {
    [IO.File]::WriteAllText($settingsFile, (Set-NewApps ([IO.File]::ReadAllText($settingsFile)) $pending))
}
if ($pending.Count) {
    $tip = New-Object System.Windows.Forms.NotifyIcon
    $tip.Icon = [System.Drawing.SystemIcons]::Information; $tip.Visible = $true
    $open = $settingsFile; $tip.add_BalloonTipClicked({ Start-Process $open }.GetNewClosure())
    $tip.ShowBalloonTip(8000, 'Tile Windows: apps without a weight', ($pending -join ', ') + "`nClick to open settings.json and add them to a weight group.", 'Info')
    $showUntil = (Get-Date).AddSeconds(8)   # keep running briefly so a click on the notification still works
}
if ($items.Count -eq 0) { return }

# Remember how each window looked before the first tiling, so Ctrl+Alt+R (Restore-Windows.ps1) can put it back.
# Pressing Ctrl+Alt+W again keeps what was saved first; closed windows are dropped.
$undoFile = Join-Path $env:TEMP 'tile-windows-undo.txt'
$undo = [ordered]@{}
if (Test-Path $undoFile) { foreach ($line in Get-Content $undoFile) { $k, $v = $line -split "`t", 2; if ($v -and [Tiler]::IsWindow([IntPtr][long]$k)) { $undo[$k] = $v } } }
foreach ($it in $items) { $k = [string][long]$it.H; if (-not $undo.Contains($k)) { $p = [Tiler]::SavePlacement($it.H); if ($p) { $undo[$k] = $p } } }
Set-Content $undoFile @($undo.Keys | ForEach-Object { "$_`t$($undo[$_])" })
# Most-used first; ties keep z-order (PS 5.1 Sort-Object isn't stable, hence Z).
$items = @($items | Sort-Object -Property @{ e = 'W'; Descending = $true }, @{ e = 'Z' })
$groups = Get-MonitorGroups $items $screens.Count

# Each press picks another good layout at random (columns, rows, mirrored...), never the one shown last on that monitor.
$lastFile = Join-Path $env:TEMP 'tile-windows-last.txt'
$last = @(if (Test-Path $lastFile) { Get-Content $lastFile }); $sigs = New-Object string[] $screens.Count
for ($m = 0; $m -lt $screens.Count; $m++) {
    $seed = Get-Random -Minimum 1 -Maximum ([int]::MaxValue); $avoid = if ($m -lt $last.Count) { $last[$m] } else { '' }
    $g = $groups[$m]; $a = $screens[$m].WorkingArea
    # Sizes in settings are at 100% scaling; this monitor may be scaled (e.g. 150% on a 4K laptop).
    $sc = [Tiler]::ScaleAt($a.X + $a.Width / 2, $a.Y + $a.Height / 2)
    $gap = [int]($cfg.Gap * $sc); $h = [int]($gap / 2); $gap = 2 * $h
    $minW = [int]($cfg.MinWidth * $sc); $minH = [int]($cfg.MinHeight * $sc); $comfortH = [int](600 * $sc)
    # Pick the best mix of columns and stacked rows; apps that don't fit readably are minimized (least important first).
    # If an app refuses to get as small as its slot, its real size is remembered and the layout is worked out again.
    for ($pass = 0; $pass -lt 8 -and $g.Count; $pass++) {
        $layout = Get-BestLayout ([double[]]@($g | ForEach-Object { $_.W })) ([int[]]@($g | ForEach-Object { $_.MinW })) ([int[]]@($g | ForEach-Object { $_.MinH })) `
            ($a.X + $h) ($a.Y + $h) ($a.Width - $gap) ($a.Height - $gap) ($a.X -lt $mainX) $gap $minW $minH `
            ([int[]]@($g | ForEach-Object { [int]($_.ComfortW * $sc) })) $comfortH $seed $avoid
        $sigs[$m] = $layout.Sig
        while ($g.Count -gt $layout.Count) { [Tiler]::Minimize($g[$g.Count - 1].H); $g.RemoveAt($g.Count - 1) }
        $again = $false; $cannotMove = @()
        for ($j = 0; $j -lt $g.Count; $j++) { $s = $layout.Slots[$j]; $it = $g[$j]
            $placed = [Tiler]::Place($it.H, $s[0] + $h, $s[1] + $h, $s[2] - $gap, $s[3] - $gap)
            if ($placed -eq [Tiler]::Placed) { continue }
            $again = $true
            if ($placed -eq [Tiler]::CannotMove) { $cannotMove += $it; continue }   # e.g. an app running as administrator: leave it, lay out the rest again
            $v = [Tiler]::Visible($it.H)
            if ($v.R - $v.L -gt $s[2] - $gap + 2) { $it.MinW = $v.R - $v.L + $gap }
            if ($v.B - $v.T -gt $s[3] - $gap + 2) { $it.MinH = $v.B - $v.T + $gap }
        }
        foreach ($it in $cannotMove) { $g.Remove($it) }
        if (-not $again) { break }
    }
}

Set-Content $lastFile $sigs
[Tiler]::Refocus($focus)   # in case Windows moved focus anyway

if ($tip) { while ((Get-Date) -lt $showUntil) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }; $tip.Dispose() }
