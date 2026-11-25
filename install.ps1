# One-line install / update:
#   irm https://raw.githubusercontent.com/laurensanp/tile-windows/main/install.ps1 | iex
# Downloads the latest version to %LOCALAPPDATA%\TileWindows and creates the hotkey shortcuts.
# Updating keeps your settings.json (it is not part of the download).
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$dir = Join-Path $env:LOCALAPPDATA 'TileWindows'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tile-windows-' + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
try {
    Write-Host 'Downloading Tile Windows...'
    Invoke-WebRequest 'https://github.com/laurensanp/tile-windows/archive/refs/heads/main.zip' -OutFile "$tmp\tile-windows.zip" -UseBasicParsing
    Expand-Archive "$tmp\tile-windows.zip" $tmp
    New-Item -ItemType Directory $dir -Force | Out-Null
    Get-ChildItem "$tmp\tile-windows-main" -File | Copy-Item -Destination $dir -Force
    Get-ChildItem $dir -File | Unblock-File   # downloaded files may be marked as "from the internet"
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# Setup runs in its own process so the machine's script execution policy doesn't block it.
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$dir\Setup.ps1"
if ($LASTEXITCODE) { throw "Setup failed (exit code $LASTEXITCODE)" }

Write-Host ''
Write-Host "Tile Windows is installed in $dir"
Write-Host '  Ctrl+Alt+W  arrange all windows'
Write-Host '  Ctrl+Alt+R  maximize them again'
Write-Host "  Settings:   $dir\settings.json"
