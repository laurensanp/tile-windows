# Undoes the tiling: puts every window Tile-Windows.ps1 moved back to the size, position and state (normal, maximized,
# minimized) it had before the first Ctrl+Alt+W. Windows opened since stay as they are; games were never moved.
# Nothing is activated, so the window (or game) you are in keeps focus. settings.json is only read.
# -Startup (run by the hotkey helper at sign-in): apps would reopen in their old tile, so until you press the tile
# hotkey every app window that appears (minimized ones when you open them) gets a plain default size (2/3 x 3/4 of its monitor, centered),
# except the apps in AtSignIn: Maximized ones are maximized, Minimized ones minimized. Nothing is tiled.
param([switch]$Startup)
. "$PSScriptRoot\Layout.ps1"
$cfg = Read-TileSettings (Get-SettingsFile $PSScriptRoot)
if (-not ('Tiler' -as [type])) { Add-Type -Path "$PSScriptRoot\Native.cs" }

if ($Startup) {
    $tiled = New-Object Threading.EventWaitHandle($false, 'ManualReset', 'TileWindowsTiled')   # Tile-Windows.ps1 sets it
    [Tiler]::MakeDpiAware(); Add-Type -AssemblyName System.Windows.Forms; $done = @{}
    $max = @($cfg.AtSignIn.Maximized); $min = @($cfg.AtSignIn.Minimized)
    while (-not $tiled.WaitOne(2000)) {   # until Ctrl+Alt+W
        foreach ($hwnd in [Tiler]::AppWindows([uint32]$PID)) {
            if ($done.ContainsKey($hwnd)) { continue }; $done[$hwnd] = 1
            $app = Get-AppInfo $hwnd $cfg; if ($app.W -eq 0) { continue }   # games stay as they are
            $a = [Windows.Forms.Screen]::FromHandle($hwnd).WorkingArea; $w = [int]($a.Width * 2 / 3); $h = [int]($a.Height * 3 / 4)
            $x = $a.X + [int](($a.Width - $w) / 2); $y = $a.Y + [int](($a.Height - $h) / 2)
            $focus = [Tiler]::GetForegroundWindow()
            if ($max -contains $app.Name) { if ([Tiler]::IsIconic($hwnd)) { [void][Tiler]::ShowWindow($hwnd, 4) }; [void][Tiler]::ShowWindow($hwnd, 3); [Tiler]::Refocus($focus); continue }
            if ($min -contains $app.Name -or [Tiler]::IsIconic($hwnd)) { [Tiler]::SetRestoreRect($hwnd, $x, $y, $w, $h); continue }   # (stays) minimized, opens at the default size
            [void][Tiler]::Place($hwnd, $x, $y, $w, $h); [Tiler]::Refocus($focus)
        }
    }
    return
}

$undoFile = Join-Path $env:TEMP 'tile-windows-undo.txt'   # written by Tile-Windows.ps1
if (-not (Test-Path $undoFile)) { return }   # nothing tiled since the last restore
[Tiler]::MakeDpiAware()   # the same pixels Tile-Windows.ps1 saved them in
$focus = [Tiler]::GetForegroundWindow()
foreach ($line in Get-Content $undoFile) {
    $k, $v = $line -split "`t", 2
    if ($v) { [Tiler]::RestorePlacement([IntPtr][long]$k, $v) }
}
Remove-Item $undoFile
[Tiler]::Refocus($focus)   # in case Windows moved focus anyway
