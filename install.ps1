# The one command for everything:
#   irm https://raw.githubusercontent.com/laurensanp/tile-windows/main/install.ps1 | iex
# First run installs to %LOCALAPPDATA%\TileWindows. Run again: menu with Update, Settings, Uninstall.
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:LOCALAPPDATA 'TileWindows'
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"   # own process, so the execution policy can't block it

function Install-TileWindows {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('tile-windows-' + [guid]::NewGuid())
    New-Item -ItemType Directory $tmp | Out-Null
    try {
        Write-Host 'Downloading Tile Windows...'
        Invoke-WebRequest 'https://github.com/laurensanp/tile-windows/archive/refs/heads/main.zip' -OutFile "$tmp\tile-windows.zip" -UseBasicParsing
        Expand-Archive "$tmp\tile-windows.zip" $tmp
        New-Item -ItemType Directory $dir -Force | Out-Null
        Get-ChildItem "$tmp\tile-windows-main" -File | Copy-Item -Destination $dir -Force   # settings.json isn't in the download: yours is kept
        Get-ChildItem $dir -File | Unblock-File
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    & $ps -NoProfile -ExecutionPolicy Bypass -File "$dir\Setup.ps1" | Out-Null
    if ($LASTEXITCODE) { throw "Setup failed (exit code $LASTEXITCODE)" }
    Write-Host "Tile Windows is ready: Ctrl+Alt+Shift+W arranges your windows, Ctrl+Alt+Shift+R maximizes them again."
    Write-Host 'Run the same command again to update, change settings or uninstall.'
}

if (-not (Test-Path "$dir\Setup.ps1")) { Install-TileWindows; return }

Write-Host "Tile Windows is installed in $dir"
Write-Host '[1] Update  [2] Settings  [3] Uninstall  [0] Cancel'
switch (Read-Host 'Choose') {
    '1' { Install-TileWindows }
    '2' {
        $file = "$dir\settings.json"
        try { Start-Process $file } catch { Start-Process notepad.exe $file }   # no app for .json: Notepad
        Write-Host 'Changes apply on the next Ctrl+Alt+Shift+W. Changed a hotkey? Run the command again and choose Update.'
    }
    '3' {
        & $ps -NoProfile -ExecutionPolicy Bypass -File "$dir\Setup.ps1" -Uninstall | Out-Null
        if ((Get-Location).Path -like "$dir*") { Set-Location $env:USERPROFILE }
        Remove-Item -LiteralPath $dir -Recurse -Force
        Write-Host 'Tile Windows is uninstalled.'
    }
    default { Write-Host 'Nothing changed.' }
}
