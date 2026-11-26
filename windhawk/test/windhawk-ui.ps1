# Opens the Windhawk UI and takes screenshots: the home page with the installed mods,
# the Tile Windows details page and its settings. Clicks through UI Automation.
# Run after windhawk-real.ps1 (Windhawk installed, mod installed).
param([string]$Out = "$PSScriptRoot\screenshots-windhawk")
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Mouse {
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    public static void Click(int x, int y) { SetCursorPos(x, y); mouse_event(2, 0, 0, 0, UIntPtr.Zero); mouse_event(4, 0, 0, 0, UIntPtr.Zero); }
}
'@
$ui = [System.Windows.Automation.AutomationElement]

function Save-Screen($name) {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size); $bmp.Save("$Out\$name.png"); "saved $name" } finally { $g.Dispose(); $bmp.Dispose() }
}

# The Windhawk main window (any top-level window titled Windhawk).
function Find-Window {
    $cond = New-Object System.Windows.Automation.PropertyCondition($ui::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
    @($ui::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)) | Where-Object { $_.Current.Name -like '*Windhawk*' } | Select-Object -First 1
}

# Clicks the first element whose name contains $text (cards, tabs and buttons in the web UI).
# $minY skips matches above it (the top bar also has a "Settings" button).
function Click-Text($text, [int]$minY = 0) {
    $win = Find-Window; if (-not $win) { Write-Host "no Windhawk window"; return $false }
    $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    $hit = @($all | Where-Object { $_.Current.Name -like "*$text*" -and -not $_.Current.BoundingRectangle.IsEmpty -and $_.Current.BoundingRectangle.Width -gt 0 -and $_.Current.BoundingRectangle.Y -ge $minY }) | Select-Object -First 1
    if (-not $hit) { Write-Host "no element named '$text'"; return $false }
    $r = $hit.Current.BoundingRectangle
    Write-Host "click '$($hit.Current.Name)' ($($hit.Current.ControlType.ProgrammaticName)) at $([int]($r.X + $r.Width / 2)),$([int]($r.Y + $r.Height / 2))"
    [Mouse]::Click([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2))
    return $true
}

# Close leftover test windows so the UI is in view.
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force
$exe = "$env:ProgramFiles\Windhawk\windhawk.exe"
Start-Process $exe
$win = $null
for ($i = 0; $i -lt 30 -and -not $win; $i++) { Start-Sleep 2; $win = Find-Window }
if (-not $win) {
    'main window did not show, trying -run-ui'
    Start-Process $exe -ArgumentList '-run-ui'
    for ($i = 0; $i -lt 30 -and -not $win; $i++) { Start-Sleep 2; $win = Find-Window }
}
Get-Process windhawk* | Format-Table Name, Id, MainWindowTitle -AutoSize | Out-String
if (-not $win) { Save-Screen 'ui-0-no-window'; throw 'no Windhawk window' }
"window: $($win.Current.Name)"
$h = [IntPtr]$win.Current.NativeWindowHandle
[void][Mouse]::ShowWindow($h, 3); [void][Mouse]::SetForegroundWindow($h)
Start-Sleep 8   # the web UI loads after the window appears
Save-Screen 'ui-1-home'

# Names the web UI exposes, to see what can be clicked.
$names = @($win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) |
    ForEach-Object { $_.Current.Name } | Where-Object { $_ } | Select-Object -Unique -First 60)
"UI elements: $($names -join ' | ')"

# The only installed mod, so the first "Details" button is the Tile Windows card.
if (Click-Text 'Details') {
    Start-Sleep 6
    Save-Screen 'ui-2-mod-details'
    # The mod's own Settings tab sits below the top bar (y > 130).
    if (Click-Text 'Settings' 130) { Start-Sleep 4; Save-Screen 'ui-3-mod-settings' }
}
