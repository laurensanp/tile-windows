# Sets up Tile Windows in this folder (run by install.ps1; run again after moving the folder or changing a hotkey):
#   - creates settings.json from settings.default.json on first run
#   - builds the small hotkey helper (Hotkeys.cs -> TileWindowsHotkeys.exe), starts it and starts it with Windows
#   - adds "Tile Windows" and "Restore Windows" to the Start menu (click to run, no hotkey on the shortcut itself)
# -Uninstall stops the helper and removes the shortcuts and the autostart entry.
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$menu = [Environment]::GetFolderPath('Programs')
$startup = [Environment]::GetFolderPath('Startup')
$exe = Join-Path $PSScriptRoot 'TileWindowsHotkeys.exe'

# Stop a running helper (from this or an older install) so it can be replaced or the folder removed.
Get-Process TileWindowsHotkeys -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 300

if ($Uninstall) {
    Remove-Item "$menu\Tile Windows.lnk", "$menu\Restore Windows.lnk", "$startup\Tile Windows Hotkeys.lnk" -ErrorAction SilentlyContinue
    'Tile Windows hotkeys and shortcuts removed.'; return
}

. "$PSScriptRoot\Layout.ps1"
$cfg = Read-TileSettings (Get-SettingsFile $PSScriptRoot)
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$tile = Join-Path $PSScriptRoot 'Tile-Windows.ps1'; $restore = Join-Path $PSScriptRoot 'Restore-Windows.ps1'

# Build the hotkey helper on this PC (no download of an .exe needed).
Remove-Item $exe -ErrorAction SilentlyContinue
Add-Type -TypeDefinition (Get-Content (Join-Path $PSScriptRoot 'Hotkeys.cs') -Raw) -OutputAssembly $exe -OutputType WindowsApplication

$shell = New-Object -ComObject WScript.Shell
function New-Shortcut($path, $target, $arguments, $icon) {
    $s = $shell.CreateShortcut($path); $s.TargetPath = $target; $s.Arguments = $arguments; $s.WorkingDirectory = $PSScriptRoot
    $s.WindowStyle = 7; $s.IconLocation = "$env:SystemRoot\System32\imageres.dll,$icon"; $s.Save()
}
New-Shortcut "$menu\Tile Windows.lnk" $ps "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tile`"" 174
New-Shortcut "$menu\Restore Windows.lnk" $ps "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$restore`"" 15
$helperArgs = "`"$($cfg.Hotkey)`" `"$tile`" `"$($cfg.RestoreHotkey)`" `"$restore`""
New-Shortcut "$startup\Tile Windows Hotkeys.lnk" $exe $helperArgs 174
Start-Process $exe $helperArgs

"Hotkeys ready: $($cfg.Hotkey) arranges, $($cfg.RestoreHotkey) maximizes again."
"Settings: $PSScriptRoot\settings.json"
