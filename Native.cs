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
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hh, uint f);
    [DllImport("user32.dll")] static extern bool IsHungAppWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
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

    // Real app windows only: visible, unowned, titled, resizable, not tool windows, not cloaked (hidden UWP/other desktops),
    // not hung (moving a hung window blocks until it responds).
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
            if (IsHungAppWindow(h)) return true;
            list.Add(h); return true;
        }, IntPtr.Zero);
        return list;
    }

    // Place so the *visible* frame fills the slot (Win11 adds invisible resize borders around most windows).
    // Returns Placed, TooBig when the window refused to shrink to the slot (app minimum size, e.g. Steam), or
    // CannotMove when Windows doesn't let us move it (an app running as administrator).
    // Never activates the window, so a game or app you are in keeps focus (and a fullscreen game stays fullscreen).
    public const int Placed = 0, TooBig = 1, CannotMove = 2;
    public static int Place(IntPtr h, int x, int y, int w, int hh) {
        if (IsIconic(h) || IsZoomed(h)) ShowWindow(h, 4); // SW_SHOWNOACTIVATE: back to normal size without focusing it
        if (!SetWindowPos(h, IntPtr.Zero, x, y, w, hh, 0x54) && Marshal.GetLastWin32Error() == 5) return CannotMove; // SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW; 5 = access denied

        if (IsZoomed(h)) { ShowWindow(h, 4); SetWindowPos(h, IntPtr.Zero, x, y, w, hh, 0x54); } // some apps (e.g. FilmCraft) stay flagged maximized: broken title bar
        RECT win, vis; GetWindowRect(h, out win);
        if (DwmGetWindowAttribute(h, 9, out vis, 16) != 0) return Placed;
        int l = vis.L - win.L, t = vis.T - win.T, r = win.R - vis.R, b = win.B - vis.B;
        if (l != 0 || t != 0 || r != 0 || b != 0) SetWindowPos(h, IntPtr.Zero, x - l, y - t, w + l + r, hh + t + b, 0x54);
        DwmGetWindowAttribute(h, 9, out vis, 16);
        return vis.R - vis.L <= w + 2 && vis.B - vis.T <= hh + 2 ? Placed : TooBig;
    }

    public static void Minimize(IntPtr h) { ShowWindow(h, 7); } // SW_SHOWMINNOACTIVE: minimize without focusing another window

    // Sets where a minimized window comes back to (normal, not maximized) and leaves it minimized.
    [StructLayout(LayoutKind.Sequential)] struct WINDOWPLACEMENT { public int length, flags, showCmd, minX, minY, maxX, maxY; public RECT normal; }
    [DllImport("user32.dll")] static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT p);
    [DllImport("user32.dll")] static extern bool SetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT p);
    public static void SetRestoreRect(IntPtr h, int x, int y, int w, int hh) {
        var p = new WINDOWPLACEMENT(); p.length = Marshal.SizeOf(p); GetWindowPlacement(h, ref p);
        p.flags = 0; p.showCmd = 7; p.normal.L = x; p.normal.T = y; p.normal.R = x + w; p.normal.B = y + hh;
        SetWindowPlacement(h, ref p);
    }

    // Size, position and state (normal, maximized, minimized) of a window as text, to put it back later (Ctrl+Alt+R).
    public static string SavePlacement(IntPtr h) {
        var p = new WINDOWPLACEMENT(); p.length = Marshal.SizeOf(p);
        if (!GetWindowPlacement(h, ref p)) return null;
        return string.Join(",", p.flags, p.showCmd, p.normal.L, p.normal.T, p.normal.R, p.normal.B);
    }

    // Puts a window back as SavePlacement saw it, without activating it (a game you are in keeps focus): normal and
    // minimized windows through SetWindowPlacement, maximized ones are then maximized by the app itself (WM_SYSCOMMAND),
    // which Windows doesn't let take the focus from the foreground app.
    public static void RestorePlacement(IntPtr h, string saved) {
        if (string.IsNullOrEmpty(saved) || !IsWindow(h)) return;
        var v = Array.ConvertAll(saved.Split(','), int.Parse);
        var p = new WINDOWPLACEMENT(); p.length = Marshal.SizeOf(p);
        if (!GetWindowPlacement(h, ref p)) return;
        p.flags = v[0]; p.normal.L = v[2]; p.normal.T = v[3]; p.normal.R = v[4]; p.normal.B = v[5];
        bool max = v[1] == 3, min = v[1] == 2;   // SW_SHOWMAXIMIZED, SW_SHOWMINIMIZED
        p.showCmd = min ? 7 : 4;                 // SW_SHOWMINNOACTIVE, SW_SHOWNOACTIVATE
        SetWindowPlacement(h, ref p);
        if (max) PostMessage(h, 0x0112, new IntPtr(0xF030), IntPtr.Zero);   // WM_SYSCOMMAND, SC_MAXIMIZE
    }

    // Gives focus back to h if something else took it.
    public static void Refocus(IntPtr h) {
        if (h == IntPtr.Zero || GetForegroundWindow() == h) return;
        SetForegroundWindow(h);
    }

    public static RECT Visible(IntPtr h) { RECT v; DwmGetWindowAttribute(h, 9, out v, 16); return v; }
    public static int VisibleWidth(IntPtr h) { RECT v = Visible(h); return v.R - v.L; }
}
