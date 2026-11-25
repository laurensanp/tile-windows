# Creates (or updates) the Start-menu shortcuts with the hotkeys from settings.json:
#   "Tile Windows"    (Hotkey)        -> Tile-Windows.ps1
#   "Restore Windows" (RestoreHotkey) -> Restore-Windows.ps1
# Also creates settings.json from settings.default.json on first run.
# Run again after changing a hotkey or moving this folder. Use -Uninstall to remove both shortcuts.
param([switch]$Uninstall)
$menu = [Environment]::GetFolderPath('Programs')   # the user's Start-menu Programs folder

if ($Uninstall) { Remove-Item "$menu\Tile Windows.lnk", "$menu\Restore Windows.lnk" -ErrorAction SilentlyContinue; "Shortcuts removed."; return }

. "$PSScriptRoot\Layout.ps1"
$cfg = Read-TileSettings (Get-SettingsFile $PSScriptRoot)
$shell = New-Object -ComObject WScript.Shell
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
foreach ($sc in @(@('Tile Windows', 'Tile-Windows.ps1', $cfg.Hotkey, 174), @('Restore Windows', 'Restore-Windows.ps1', $cfg.RestoreHotkey, 15))) {
    $s = $shell.CreateShortcut("$menu\$($sc[0]).lnk")
    $s.TargetPath = $ps
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSScriptRoot\$($sc[1])`""
    $s.WorkingDirectory = $PSScriptRoot
    $s.Hotkey = $sc[2]; $s.WindowStyle = 7; $s.IconLocation = "$env:SystemRoot\System32\imageres.dll,$($sc[3])"
    $s.Save()
    "Shortcut ready: $($sc[2]) runs $($sc[1])"
}
"Settings: $PSScriptRoot\settings.json"
