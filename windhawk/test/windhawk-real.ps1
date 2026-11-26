# Installs the real Windhawk (latest release, incl. 2.0 alpha), installs the mod with
# windhawk-cli from the local source, then presses the real hotkeys and takes screenshots.
# Prints a lot on purpose: it's also how we learn where Windhawk keeps things.
param([string]$Mod = "$PSScriptRoot\..\tile-windows.wh.cpp", [string]$Out = "$PSScriptRoot\screenshots-windhawk")
$ErrorActionPreference = 'Stop'
$Mod = (Resolve-Path $Mod).Path
New-Item -ItemType Directory -Force $Out | Out-Null
Add-Type -Path "$PSScriptRoot\..\..\Native.cs"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Keys {
    [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit, Size = 40)] struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; }
    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    // Ctrl+Alt+<key>
    public static uint Press(char key) {
        ushort[] keys = { 0x11, 0x12, (ushort)key };
        var input = new INPUT[6];
        for (int i = 0; i < 3; i++) {
            input[i].type = 1; input[i].ki.vk = keys[i];
            input[5 - i].type = 1; input[5 - i].ki.vk = keys[i]; input[5 - i].ki.flags = 2;
        }
        return SendInput(6, input, Marshal.SizeOf(typeof(INPUT)));
    }
}
'@

function Show-Windows($what) {
    "--- $what ---"
    foreach ($h in [Tiler]::AppWindows([uint32]$PID)) { $p = 0; [void][Tiler]::GetWindowThreadProcessId($h, [ref]$p); $r = [Tiler]::Visible($h)
        '{0,-16} x={1,6} y={2,6} w={3,5} h={4,5} max={5} min={6}' -f (Get-Process -Id $p).ProcessName, $r.L, $r.T, ($r.R - $r.L), ($r.B - $r.T), [Tiler]::IsZoomed($h), [Tiler]::IsIconic($h) }
}
function Save-Screen($name) {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size); $bmp.Save("$Out\$name.png") } finally { $g.Dispose(); $bmp.Dispose() }
}
function Get-Notepads { @([Tiler]::AppWindows([uint32]$PID) | Where-Object { $p = 0; [void][Tiler]::GetWindowThreadProcessId($_, [ref]$p); (Get-Process -Id $p).ProcessName -eq 'notepad' }) }

# --- 1. Download the newest Windhawk release (prereleases included) ---
'=== releases ==='
gh release list --repo ramensoftware/windhawk --limit 8
# (PS 5.1 passes a JSON array on as one object: assign it first, then it is enumerated)
$all = gh release list --repo ramensoftware/windhawk --limit 8 --json tagName,isPrerelease,publishedAt | ConvertFrom-Json
$rel = $all | Sort-Object publishedAt -Descending | Select-Object -First 1
"using $($rel.tagName) (prerelease=$($rel.isPrerelease))"
gh release view $rel.tagName --repo ramensoftware/windhawk --json assets --jq '.assets[].name'
$dl = Join-Path $env:RUNNER_TEMP 'windhawk-dl'; New-Item -ItemType Directory -Force $dl | Out-Null
gh release download $rel.tagName --repo ramensoftware/windhawk --pattern '*.exe' --dir $dl --clobber
Get-ChildItem $dl | Format-Table Name, Length -AutoSize | Out-String
$setup = Get-ChildItem $dl -Filter '*.exe' | Sort-Object Length -Descending | Select-Object -First 1
if (-not $setup) { throw 'no installer downloaded' }

# --- 2. Silent install ---
'=== install ==='
# /DEVTOOLS: also install the compiler, an optional part of Windhawk 2.0 (core/src/services/update.rs)
$p = Start-Process $setup.FullName -ArgumentList '/S', '/DEVTOOLS' -PassThru -Wait
"installer exit code $($p.ExitCode)"
Start-Sleep 5
foreach ($dir in "$env:ProgramFiles\Windhawk", "$env:ProgramData\Windhawk") {
    if (Test-Path $dir) { "--- $dir ---"; Get-ChildItem $dir -Recurse -Depth 2 | Where-Object { -not $_.PSIsContainer -or $_.FullName.Split('\').Count -lt 6 } | Select-Object -First 80 | ForEach-Object { $_.FullName.Substring($dir.Length) } }
    else { "$dir missing" }
}
'--- windhawk.ini ---'; Get-Content "$env:ProgramFiles\Windhawk\windhawk.ini"
Get-Service *windhawk* -ErrorAction SilentlyContinue | Format-Table Name, Status -AutoSize | Out-String
Get-Process windhawk* -ErrorAction SilentlyContinue | Format-Table Name, Id, Path -AutoSize | Out-String

$cli = Get-ChildItem "$env:ProgramFiles\Windhawk" -Recurse -Filter '*cli*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $cli) { throw 'windhawk-cli not found in this release' }
"cli: $($cli.FullName)"
& $cli.FullName --version

# --- 3. Check the source like Windhawk does, then install it from the file ---
'=== source meta --strict ==='
& $cli.FullName source meta --strict $Mod
if ($LASTEXITCODE) { throw "source meta --strict failed ($LASTEXITCODE)" }
'=== mod install --file ==='
& $cli.FullName --yes mod install --file $Mod --strict
if ($LASTEXITCODE) { throw "mod install failed ($LASTEXITCODE)" }
& $cli.FullName mod list
& $cli.FullName mod show tile-windows
Start-Sleep 5
'=== processes ==='
Get-CimInstance Win32_Process -Filter "Name like 'windhawk%'" | ForEach-Object { "$($_.ProcessId) $($_.Name) $($_.CommandLine)" }

# --- 4. Real windows, real hotkeys ---
1..3 | ForEach-Object { Start-Process notepad }
Start-Sleep 3
$np = Get-Notepads
# One maximized, one minimized, one normal: Ctrl+Alt+R must bring back each state.
[void][Tiler]::ShowWindow($np[0], 3); [void][Tiler]::ShowWindow($np[2], 6); Start-Sleep 1
$wins = @([Tiler]::AppWindows([uint32]$PID))
$before = @{}; foreach ($w in $wins) { $before[[long]$w] = @([Tiler]::IsZoomed($w), [Tiler]::IsIconic($w), [Tiler]::Visible($w)) }
$fg = [Tiler]::GetForegroundWindow()
Show-Windows 'before'
Save-Screen 'windhawk-1-before'
$failed = @()

"SendInput: $([Keys]::Press('W'))"
Start-Sleep 3
Show-Windows 'after Ctrl+Alt+W'
Save-Screen 'windhawk-2-tiled'
$shown = @(Get-Notepads | Where-Object { -not [Tiler]::IsIconic($_) -and -not [Tiler]::IsZoomed($_) })
$rects = @($shown | ForEach-Object { [Tiler]::Visible($_) })
if ($shown.Count -lt 2) { $failed += "expected at least 2 tiled Notepad windows, got $($shown.Count)" }
for ($i = 0; $i -lt $rects.Count; $i++) { for ($j = $i + 1; $j -lt $rects.Count; $j++) { $a = $rects[$i]; $b = $rects[$j]
    if ($a.L -lt $b.R - 2 -and $b.L -lt $a.R - 2 -and $a.T -lt $b.B - 2 -and $b.T -lt $a.B - 2) { $failed += 'tiled windows overlap' } } }
if ([Tiler]::GetForegroundWindow() -ne $fg) { $failed += 'tiling moved the focus' }

"SendInput: $([Keys]::Press('W'))"   # another layout; the saved state must stay the first one
Start-Sleep 2
"SendInput: $([Keys]::Press('R'))"
Start-Sleep 3
Show-Windows 'after Ctrl+Alt+R'
Save-Screen 'windhawk-3-restored'
foreach ($w in $wins) { $b = $before[[long]$w]; $r = [Tiler]::Visible($w)
    if ([Tiler]::IsZoomed($w) -ne $b[0] -or [Tiler]::IsIconic($w) -ne $b[1]) { $failed += "window $w not back in its old state (max=$($b[0]) min=$($b[1]))"; continue }
    if (-not $b[0] -and -not $b[1] -and ([math]::Abs($r.L - $b[2].L) -gt 2 -or [math]::Abs($r.T - $b[2].T) -gt 2 -or [math]::Abs($r.R - $b[2].R) -gt 2 -or [math]::Abs($r.B - $b[2].B) -gt 2)) {
        $failed += "window $w not back at its old position" } }
if ([Tiler]::GetForegroundWindow() -ne $fg) { $failed += 'restoring moved the focus' }

# --- 5. Settings change through Windhawk: new tile hotkey ---
'=== settings ==='
& $cli.FullName mod settings set local@tile-windows tileHotkey=Ctrl+Alt+T
if ($LASTEXITCODE) { $failed += "mod settings set failed ($LASTEXITCODE)" }
& $cli.FullName mod settings get local@tile-windows | Select-Object -First 5
Start-Sleep 3
"SendInput: $([Keys]::Press('T'))"
Start-Sleep 3
Show-Windows 'after Ctrl+Alt+T (hotkey changed in Windhawk)'
if (@(Get-Notepads | Where-Object { -not [Tiler]::IsIconic($_) -and -not [Tiler]::IsZoomed($_) }).Count -lt 2) { $failed += 'the changed hotkey did not tile' }
"SendInput: $([Keys]::Press('R'))"
Start-Sleep 3

# --- 6. A screenshot for the README: a bigger screen, a few typical apps ---
try {
    Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Display {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)] public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency, dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] static extern int ChangeDisplaySettings(ref DEVMODE dm, int flags);
    public static int Set(int w, int h) { var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(dm); EnumDisplaySettings(null, -1, ref dm); dm.dmPelsWidth = w; dm.dmPelsHeight = h; dm.dmFields = 0x180000; return ChangeDisplaySettings(ref dm, 0); }
}
'@
    "resolution 1920x1080: ChangeDisplaySettings = $([Display]::Set(1920, 1080))"
    Start-Sleep 3
    Get-Notepads | Select-Object -Skip 1 | ForEach-Object { [void][Tiler]::ShowWindow($_, 0) }   # one Notepad is enough
    Start-Process msedge -ArgumentList '--no-first-run', '--no-default-browser-check', '--new-window', 'https://github.com/laurensanp/tile-windows'
    Start-Process explorer -ArgumentList "$env:ProgramFiles\Windhawk"
    Start-Process explorer -ArgumentList $env:USERPROFILE
    Start-Sleep 12
    "SendInput: $([Keys]::Press('T'))"
    Start-Sleep 4
    Show-Windows 'showcase'
    Save-Screen 'showcase'
} catch { "showcase failed: $_" }

if ($failed.Count) { $failed | ForEach-Object { "FAIL: $_" }; throw "$($failed.Count) check(s) failed" }
'windhawk test ok'
