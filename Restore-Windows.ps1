# Undoes the tiling: maximizes every app window on the monitor it is on (minimized ones too).
# Games and weight-0 apps stay untouched, and the window (or game) you were in keeps focus. settings.json is only read.
# -Startup (run by the hotkey helper at sign-in): apps would reopen in their old tile, so until you press the tile
# hotkey every app window that appears gets a plain default size (2/3 x 3/4 of its monitor, centered). Nothing is tiled.
param([switch]$Startup)
. "$PSScriptRoot\Layout.ps1"
$cfg = Read-TileSettings (Get-SettingsFile $PSScriptRoot)
if (-not ('Tiler' -as [type])) { Add-Type -Path "$PSScriptRoot\Native.cs" }

if ($Startup) {
    $tiled = New-Object Threading.EventWaitHandle($false, 'ManualReset', 'TileWindowsTiled')   # Tile-Windows.ps1 sets it
    [Tiler]::MakeDpiAware(); Add-Type -AssemblyName System.Windows.Forms; $done = @{}
    while (-not $tiled.WaitOne(2000)) {   # until Ctrl+Alt+W
        foreach ($hwnd in [Tiler]::AppWindows([uint32]$PID)) {
            if ($done.ContainsKey($hwnd)) { continue }; $done[$hwnd] = 1
            if ((Get-AppInfo $hwnd $cfg).W -eq 0 -or [Tiler]::IsIconic($hwnd)) { continue }   # games and tray/minimized apps stay as they are
            $a = [Windows.Forms.Screen]::FromHandle($hwnd).WorkingArea; $w = [int]($a.Width * 2 / 3); $h = [int]($a.Height * 3 / 4)
            $focus = [Tiler]::GetForegroundWindow()
            [void][Tiler]::Place($hwnd, $a.X + [int](($a.Width - $w) / 2), $a.Y + [int](($a.Height - $h) / 2), $w, $h); [Tiler]::Refocus($focus)
        }
    }
    return
}

$focus = [Tiler]::GetForegroundWindow()
foreach ($hwnd in [Tiler]::AppWindows([uint32]$PID)) {
    if ((Get-AppInfo $hwnd $cfg).W -eq 0) { continue }
    if ([Tiler]::IsIconic($hwnd)) { [void][Tiler]::ShowWindow($hwnd, 4) }        # SW_SHOWNOACTIVATE: un-minimize without focusing it
    if (-not [Tiler]::IsZoomed($hwnd)) { [void][Tiler]::ShowWindow($hwnd, 3) }   # SW_MAXIMIZE (doesn't steal focus once visible)
}
[Tiler]::Refocus($focus)   # maximizing focuses a window; give it back
