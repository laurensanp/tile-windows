// Tiny hotkey helper. Setup compiles it to TileWindowsHotkeys.exe and starts it with Windows.
// Usage: TileWindowsHotkeys.exe "CTRL+ALT+W" "C:\...\Tile-Windows.ps1" "CTRL+ALT+R" "C:\...\Restore-Windows.ps1"
// A pair "START" "C:\...\Restore-Windows.ps1" runs that script once with -Startup when the helper starts (at sign-in).
// Each pressed hotkey runs its script in a hidden PowerShell. Nothing else happens in the background.
// (Shortcut-file hotkeys are not used: Explorer often stops reacting to them after the shortcut changes.)
using System; using System.Diagnostics; using System.Runtime.InteropServices; using System.Threading;

static class Hotkeys {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern int GetMessage(out MSG msg, IntPtr hWnd, uint min, uint max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int MessageBox(IntPtr h, string text, string caption, uint type);
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public int x, y; }

    // "CTRL+ALT+W" -> modifiers and virtual key. Supports CTRL, ALT, SHIFT, WIN with a letter, digit or F1-F24.
    // A letter or digit needs at least one of CTRL, ALT, SHIFT, WIN: alone it would take that key away from every app.
    static bool Parse(string text, out uint mods, out uint vk) {
        mods = 0x4000; vk = 0; // MOD_NOREPEAT
        foreach (string raw in text.ToUpperInvariant().Split('+')) {
            string p = raw.Trim();
            if (p == "CTRL" || p == "CONTROL") mods |= 2; else if (p == "ALT") mods |= 1; else if (p == "SHIFT") mods |= 4; else if (p == "WIN") mods |= 8;
            else if (p.Length == 1 && char.IsLetterOrDigit(p[0])) vk = p[0];
            else if (p.Length > 1 && p[0] == 'F') { int n; if (int.TryParse(p.Substring(1), out n) && n >= 1 && n <= 24) vk = (uint)(0x6F + n); else return false; }
            else return false;
        }
        bool fKey = vk >= 0x70 && vk <= 0x87;
        return vk != 0 && (fKey || (mods & 0xF) != 0);
    }

    static void Main(string[] args) {
        bool first; var single = new Mutex(true, "TileWindowsHotkeys", out first);
        if (!first) return; // already running
        string ps = Environment.ExpandEnvironmentVariables(@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe");
        string problems = "";
        var used = new System.Collections.Generic.List<ulong>();
        for (int i = 0; i + 1 < args.Length; i += 2) {
            uint mods, vk;
            if (args[i] == "START") { Run(ps, args[i + 1], " -Startup"); continue; }
            if (!Parse(args[i], out mods, out vk)) problems += "Can't use the hotkey \"" + args[i] + "\" (use e.g. CTRL+ALT+W: a letter or digit needs CTRL, ALT, SHIFT or WIN).\n";
            else if (used.Contains(((ulong)mods << 32) | vk)) problems += args[i] + " is set for both hotkeys.\n";
            else if (!RegisterHotKey(IntPtr.Zero, i / 2 + 1, mods, vk)) problems += args[i] + " is already used by another program.\n";
            else used.Add(((ulong)mods << 32) | vk);
        }
        if (problems != "") { // shown on its own thread so the hotkeys that did work keep working meanwhile
            string text = problems + "Pick another hotkey in settings.json, then run the install command again and choose Update.";
            new Thread(() => MessageBox(IntPtr.Zero, text, "Tile Windows", 0x30)).Start();
        }
        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0) {
            if (msg.message != 0x0312) continue; // WM_HOTKEY
            int idx = (msg.wParam.ToInt32() - 1) * 2 + 1;
            if (idx < 1 || idx >= args.Length) continue;
            Run(ps, args[idx], "");
        }
        GC.KeepAlive(single);
    }

    static void Run(string ps, string script, string extra) {
        var start = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"" + extra);
        start.UseShellExecute = false; start.CreateNoWindow = true;
        try { Process.Start(start); } catch { }
    }
}
