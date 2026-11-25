// Win32 calls for Tile-Windows: find app windows and place them.
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;

public struct RECT { public int L, T, R, B; }

public static class Tiler {
    delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT v, int s);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hh, uint f);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
    [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);
    struct POINT { public int X, Y; }

    // Real pixels on every monitor, even with different scaling per monitor (Windows 10 1703+; older: system DPI).
    public static void MakeDpiAware() {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch (EntryPointNotFoundException) { } // PER_MONITOR_AWARE_V2
        SetProcessDPIAware();
    }

    // Display scaling of the monitor at (x, y): 1.0 = 100%, 1.5 = 150%. Settings in px are scaled by this.
    public static double ScaleAt(int x, int y) {
        try {
            uint dx, dy; var p = new POINT { X = x, Y = y };
            if (GetDpiForMonitor(MonitorFromPoint(p, 2), 0, out dx, out dy) == 0 && dx > 0) return dx / 96.0;
        } catch (DllNotFoundException) { } catch (EntryPointNotFoundException) { }
        return 1.0;
    }

    // Real app windows only: visible, unowned, titled, resizable, not tool windows, not cloaked (hidden UWP/other desktops).
    public static List<IntPtr> AppWindows(uint skipPid) {
        var list = new List<IntPtr>();
        EnumWindows((h, p) => {
            if (!IsWindowVisible(h) || GetWindow(h, 4) != IntPtr.Zero || GetWindowTextLength(h) == 0) return true;
            int style = GetWindowLong(h, -16), ex = GetWindowLong(h, -20);
            if ((style & 0x40000) == 0 || (ex & 0x80) != 0) return true;
            int cloaked; if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
            var cls = new StringBuilder(256); GetClassName(h, cls, 256);
            if (cls.ToString() == "Progman" || cls.ToString() == "WorkerW") return true;
            uint pid; GetWindowThreadProcessId(h, out pid); if (pid == skipPid) return true;
            list.Add(h); return true;
        }, IntPtr.Zero);
        return list;
    }

    // Place so the *visible* frame fills the slot (Win11 adds invisible resize borders around most windows).
    // Returns false when the window refused to shrink to the slot (app minimum size, e.g. Steam).
    // Never activates the window, so a game or app you are in keeps focus (and a fullscreen game stays fullscreen).
    public static bool Place(IntPtr h, int x, int y, int w, int hh) {
        if (IsIconic(h) || IsZoomed(h)) ShowWindow(h, 4); // SW_SHOWNOACTIVATE: back to normal size without focusing it
        SetWindowPos(h, IntPtr.Zero, x, y, w, hh, 0x54);   // SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW
        if (IsZoomed(h)) { ShowWindow(h, 4); SetWindowPos(h, IntPtr.Zero, x, y, w, hh, 0x54); } // some apps (e.g. FilmCraft) stay flagged maximized: broken title bar
        RECT win, vis; GetWindowRect(h, out win);
        if (DwmGetWindowAttribute(h, 9, out vis, 16) != 0) return true;
        int l = vis.L - win.L, t = vis.T - win.T, r = win.R - vis.R, b = win.B - vis.B;
        if (l != 0 || t != 0 || r != 0 || b != 0) SetWindowPos(h, IntPtr.Zero, x - l, y - t, w + l + r, hh + t + b, 0x54);
        DwmGetWindowAttribute(h, 9, out vis, 16);
        return vis.R - vis.L <= w + 2 && vis.B - vis.T <= hh + 2;
    }

    public static void Minimize(IntPtr h) { ShowWindow(h, 7); } // SW_SHOWMINNOACTIVE: minimize without focusing another window

    // Gives focus back to h if something else took it. SW_SHOW activates without changing size (SetForegroundWindow
    // alone is often refused for background processes).
    public static void Refocus(IntPtr h) {
        if (h == IntPtr.Zero || GetForegroundWindow() == h) return;
        if (!SetForegroundWindow(h)) ShowWindow(h, 5);
    }

    public static RECT Visible(IntPtr h) { RECT v; DwmGetWindowAttribute(h, 9, out v, 16); return v; }
    public static int VisibleWidth(IntPtr h) { RECT v = Visible(h); return v.R - v.L; }
}
