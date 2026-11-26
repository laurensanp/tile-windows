// Test harness for the Windhawk mod: compiles the mod source unchanged with a
// few stand-ins for the Windhawk API and checks it on its own, without
// Windhawk.
//   harness.exe settings.txt layout   layout math and settings (no windows)
//   harness.exe settings.txt live     real windows and real hotkeys:
//     opens Notepad 3x, presses Ctrl+Alt+W, checks the tiling, presses
//     Ctrl+Alt+R, checks that all are maximized again (needs a desktop)
// settings.txt comes from settings_defaults.py (the mod's default settings).

#include <windows.h>

#include <cstdarg>
#include <cstdio>
#include <fstream>
#include <map>
#include <string>

// ---- Windhawk API stand-ins ----
#define WH_MOD_ID L"tile-windows"
#define WH_MOD_VERSION L"1.0"

static void HarnessLog(const wchar_t* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vfwprintf(stdout, fmt, args);
    va_end(args);
    fwprintf(stdout, L"\n");
    fflush(stdout);
}
#define Wh_Log(fmt, ...) HarnessLog(fmt, ##__VA_ARGS__)

static std::map<std::wstring, std::wstring> g_testSettings;

static std::wstring SettingName(PCWSTR fmt, va_list args) {
    wchar_t name[512];
    vswprintf(name, 512, fmt, args);
    return name;
}

PCWSTR Wh_GetStringSetting(PCWSTR fmt, ...) {
    va_list args;
    va_start(args, fmt);
    std::wstring name = SettingName(fmt, args);
    va_end(args);
    auto it = g_testSettings.find(name);
    return _wcsdup(it == g_testSettings.end() ? L"" : it->second.c_str());
}

void Wh_FreeStringSetting(PCWSTR s) {
    free((void*)s);
}

int Wh_GetIntSetting(PCWSTR fmt, ...) {
    va_list args;
    va_start(args, fmt);
    std::wstring name = SettingName(fmt, args);
    va_end(args);
    auto it = g_testSettings.find(name);
    return it == g_testSettings.end() ? 0 : _wtoi(it->second.c_str());
}

BOOL Wh_SetFunctionHook(void*, void*, void**) {
    return TRUE;
}

#include "../tile-windows.wh.cpp"

// ---- checks ----
static int g_failures = 0;

#define CHECK(cond, what)                      \
    do {                                       \
        if (!(cond)) {                         \
            HarnessLog(L"FAIL: %s", L"" what); \
            g_failures++;                      \
        }                                      \
    } while (0)

static bool Overlap(const Slot& a, const Slot& b) {
    return a[0] < b[0] + b[2] && b[0] < a[0] + a[2] && a[1] < b[1] + b[3] &&
           b[1] < a[1] + a[3];
}

// Shown slots inside the area, readable, no two overlapping (like Test.ps1).
static bool LayoutOk(const Layout& L, int n) {
    if (L.count < 1 || L.count > n) {
        return false;
    }
    for (int i = 0; i < L.count; i++) {
        const Slot& s = L.slots[i];
        if (s[0] < 0 || s[1] < 0 || s[0] + s[2] > 1896 || s[1] + s[3] > 1014) {
            return false;
        }
        if (L.count > 1 && (s[2] - 12 < 500 || s[3] - 12 < 300)) {
            return false;
        }
        for (int j = i + 1; j < L.count; j++) {
            if (Overlap(s, L.slots[j])) {
                return false;
            }
        }
    }
    return true;
}

static Layout GetL(std::vector<double> w,
                   std::vector<int> needW = {},
                   std::vector<int> needH = {},
                   bool bigRight = false,
                   unsigned seed = 0,
                   std::wstring avoid = L"",
                   std::vector<int> comfortW = {}) {
    LayoutRequest r;
    r.w = w;
    r.needW = needW;
    r.needH = needH;
    r.x = 0;
    r.y = 0;
    r.width = 1896;
    r.height = 1014;
    r.bigRight = bigRight;
    r.gap = 12;
    r.minW = 500;
    r.minH = 300;
    r.comfortW = comfortW;
    r.seed = seed;
    r.avoid = avoid;
    return GetBestLayout(r);
}

static double Area(const Slot& s) {
    return (double)s[2] * s[3];
}

static void TestSettings() {
    auto s = LoadSettings();
    CHECK(s->tileHotkey == L"Ctrl+Alt+W", "tile hotkey default");
    CHECK(s->restoreHotkey == L"Ctrl+Alt+R", "restore hotkey default");
    CHECK(s->gap == 12 && s->minWidth == 500 && s->minHeight == 300,
          "sizes default");
    CHECK(s->weights[L"code"] == 5, "Code weight 5");
    CHECK(s->weights[L"discord"] == 2.5, "Discord weight 2.5");
    CHECK(s->weights[L"nvidia app"] == 1, "NVIDIA App weight 1");
    CHECK(s->weights.count(L"javaw") && s->weights[L"javaw"] == 0,
          "javaw weight 0");
    CHECK(Contains(s->wideApps, L"chrome"), "chrome is a wide app");
    CHECK(s->mainScreenApps.empty(), "no main screen apps by default");
    CHECK(Contains(s->gameFolders, L"\\steamapps\\"), "steamapps game folder");

    UINT mods;
    UINT vk;
    CHECK(ParseHotkey(L"Ctrl+Alt+W", &mods, &vk) && vk == 'W' &&
              mods == (MOD_CONTROL | MOD_ALT | MOD_NOREPEAT),
          "parse Ctrl+Alt+W");
    CHECK(ParseHotkey(L"win + shift + f12", &mods, &vk) && vk == VK_F12 &&
              mods == (MOD_WIN | MOD_SHIFT | MOD_NOREPEAT),
          "parse win + shift + f12");
    CHECK(!ParseHotkey(L"Ctrl+Alt", &mods, &vk), "no key is an error");
    CHECK(!ParseHotkey(L"Ctrl+F25", &mods, &vk), "F25 is an error");
    CHECK(!ParseHotkey(L"Ctrl+Space", &mods, &vk), "unknown key is an error");
}

// The layout cases of Test.ps1.
static void TestLayout() {
    for (auto c : std::vector<std::vector<double>>{{5},
                                                   {5, 4, 4},
                                                   {2.5, 2, 2, 1.5},
                                                   {1, 1, 1, 1, 1, 1},
                                                   {3, 3, 3, 3},
                                                   {2, 1}}) {
        CHECK(LayoutOk(GetL(c), (int)c.size()), "basic layouts are readable");
    }
    Layout L = GetL({5, 4, 4});
    CHECK(L.count == 3, "3 main apps should all fit");
    CHECK(Area(L.slots[0]) > Area(L.slots[1]),
          "most important app should get the most area");
    L = GetL(std::vector<double>(12, 1));
    CHECK(LayoutOk(L, 12) && L.count <= 9, "12 apps can't all be readable");
    L = GetL({2.5, 2, 2}, {952, 0, 0});
    CHECK(LayoutOk(L, 3) && L.slots[0][2] >= 952,
          "Discord's minimum width respected");
    L = GetL({2, 2}, {1200, 1200});
    CHECK(L.count == 2 && L.slots[0][0] == L.slots[1][0],
          "two wide apps should stack");
    L = GetL({2, 2}, {1200, 1200}, {800, 800});
    CHECK(L.count == 1, "two big apps (1200x800) cannot share one screen");
    L = GetL({2, 2}, {}, {800, 800});
    CHECK(L.count == 2 && L.slots[0][1] == L.slots[1][1],
          "two tall apps should go side by side");
    L = GetL({5, 5, 4}, {0, 0, 614}, {}, false, 0, L"", {800, 1280, 800});
    CHECK(LayoutOk(L, 3) && L.slots[1][2] >= 1000,
          "a wide app should get a wide slot");
    L = GetL({2.5, 2, 2, 1.5}, {814, 812, 0, 0}, {0, 612, 0, 0});
    CHECK(LayoutOk(L, 4) && L.count >= 3,
          "Discord, Spotify and one more should fit");
    L = GetL({5, 5, 4.5}, {0, 0, 614});
    CHECK(!(L.slots[0][0] == L.slots[1][0] && L.slots[1][0] == L.slots[2][0]),
          "three flat full-width rows should lose against a mix");
    L = GetL({3, 2}, {}, {800, 800}, true);
    CHECK(L.count == 2 && L.slots[0][0] > L.slots[1][0],
          "mirrored layout should put the main app on the right");

    std::map<std::wstring, int> seen;
    for (unsigned s = 1; s <= 30; s++) {
        L = GetL({5, 4.5, 2.5}, {}, {}, false, s);
        CHECK(LayoutOk(L, 3), "random layouts are readable");
        seen[L.sig] = 1;
    }
    CHECK(seen.size() >= 3, "random layouts should vary");
    Layout a = GetL({5, 4.5}, {}, {}, false, 7);
    Layout b = GetL({5, 4.5}, {}, {}, false, 7, a.sig);
    CHECK(a.sig != b.sig, "random layout should not repeat the last one");
    for (unsigned s = 0; s <= 40; s++) {
        L = GetL({5, 4.5, 2.5, 2}, {}, {}, false, s);
        for (int i = 0; i < L.count; i++) {
            CHECK(!(L.slots[i][2] >= 1896 && L.slots[i][3] * 2 < 1014),
                  "no full-width tile less than half the screen tall");
        }
    }
    for (unsigned s = 1; s <= 20; s++) {
        L = GetL({5, 2}, {}, {}, false, s);
        CHECK(L.slots[0][1] == L.slots[1][1],
              "two apps should always be side by side");
    }

    auto item = [](double w, bool solo = false) {
        Item it;
        it.w = w;
        it.solo = solo;
        return it;
    };
    std::vector<Item> it = {item(3), item(3), item(2), item(1), item(1)};
    auto g = GetMonitorGroups(it, 2);
    CHECK(g[0].size() == 2 && g[1].size() == 3,
          "main monitor should get only weight-3 apps");
    g = GetMonitorGroups({item(1), item(1)}, 2);
    CHECK(g[0].size() == 1, "main monitor gets the top app when none is 3");
    auto solo = it;
    solo.push_back(item(2, true));
    g = GetMonitorGroups(solo, 2);
    CHECK(g[0].size() == 1 && g[0][0].solo && g[1].size() == 5,
          "a main screen app should get the main monitor alone");
    g = GetMonitorGroups(it, 1);
    CHECK(g[0].size() == 5, "single monitor should get everything");

    // Many apps must not take forever (the splits double with each app).
    DWORD start = GetTickCount();
    L = GetL(std::vector<double>(30, 1), {}, {}, false, 5);
    CHECK(LayoutOk(L, 30), "30 apps: readable layout");
    DWORD ms = GetTickCount() - start;
    HarnessLog(L"30 apps took %u ms", ms);
    CHECK(ms < 3000, "30 apps should take less than 3 seconds");
}

// ---- live test with real windows and hotkeys ----
static void PressHotkey(WORD key) {
    INPUT in[6] = {};
    WORD keys[3] = {VK_CONTROL, VK_MENU, key};
    for (int i = 0; i < 3; i++) {
        in[i].type = INPUT_KEYBOARD;
        in[i].ki.wVk = keys[i];
        in[5 - i].type = INPUT_KEYBOARD;
        in[5 - i].ki.wVk = keys[i];
        in[5 - i].ki.dwFlags = KEYEVENTF_KEYUP;
    }
    UINT sent = SendInput(6, in, sizeof(INPUT));
    HarnessLog(L"SendInput sent %u of 6", sent);
}

static void SaveScreenshot(const wchar_t* file) {
    int x = GetSystemMetrics(SM_XVIRTUALSCREEN);
    int y = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    int h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    HDC screen = GetDC(nullptr);
    HDC mem = CreateCompatibleDC(screen);
    HBITMAP bmp = CreateCompatibleBitmap(screen, w, h);
    HGDIOBJ old = SelectObject(mem, bmp);
    BitBlt(mem, 0, 0, w, h, screen, x, y, SRCCOPY);
    SelectObject(mem, old);
    BITMAPINFOHEADER bi{sizeof(bi), w, -h, 1, 24, BI_RGB};
    int stride = (w * 3 + 3) & ~3;
    std::vector<BYTE> pixels((size_t)stride * h);
    GetDIBits(mem, bmp, 0, h, pixels.data(), (BITMAPINFO*)&bi, DIB_RGB_COLORS);
    BITMAPFILEHEADER bf{0x4D42};
    bf.bfOffBits = sizeof(bf) + sizeof(bi);
    bf.bfSize = bf.bfOffBits + (DWORD)pixels.size();
    std::ofstream out(file, std::ios::binary);
    out.write((char*)&bf, sizeof(bf));
    out.write((char*)&bi, sizeof(bi));
    out.write((char*)pixels.data(), pixels.size());
    DeleteObject(bmp);
    DeleteDC(mem);
    ReleaseDC(nullptr, screen);
}

static std::vector<HWND> NotepadWindows() {
    std::vector<HWND> result;
    for (HWND hwnd : GetAppWindows()) {
        WCHAR cls[64];
        GetClassName(hwnd, cls, 64);
        if (wcscmp(cls, L"Notepad") == 0) {
            result.push_back(hwnd);
        }
    }
    return result;
}

static void PrintWindows(const wchar_t* what) {
    HarnessLog(L"--- %s ---", what);
    for (HWND hwnd : GetAppWindows()) {
        RECT r = GetVisibleRect(hwnd);
        WCHAR cls[64];
        GetClassName(hwnd, cls, 64);
        HarnessLog(L"%-28s x=%5d y=%5d w=%5d h=%5d max=%d min=%d", cls, r.left,
                   r.top, r.right - r.left, r.bottom - r.top, IsZoomed(hwnd),
                   IsIconic(hwnd));
    }
}

static void TestLive() {
    for (int i = 0; i < 3; i++) {
        ShellExecute(nullptr, L"open", L"notepad.exe", nullptr, nullptr,
                     SW_SHOWNORMAL);
    }
    Sleep(3000);
    std::vector<HWND> notepads = NotepadWindows();
    CHECK(notepads.size() >= 3, "3 Notepad windows open");
    PrintWindows(L"before");
    SaveScreenshot(L"screenshots\\mod-1-before.bmp");

    // Like Windhawk: init on this thread, hotkeys on the mod's own thread.
    CHECK(WhTool_ModInit(), "WhTool_ModInit");

    PressHotkey('W');
    Sleep(2000);
    PrintWindows(L"after Ctrl+Alt+W");
    SaveScreenshot(L"screenshots\\mod-2-tiled.bmp");
    std::vector<RECT> shown;
    for (HWND hwnd : NotepadWindows()) {
        if (!IsIconic(hwnd)) {
            CHECK(!IsZoomed(hwnd), "tiled window is not maximized");
            shown.push_back(GetVisibleRect(hwnd));
        }
    }
    CHECK(shown.size() >= 2, "at least 2 Notepad windows tiled");
    for (size_t i = 0; i < shown.size(); i++) {
        for (size_t j = i + 1; j < shown.size(); j++) {
            RECT a = shown[i];
            RECT b = shown[j];
            CHECK(!(a.left < b.right - 2 && b.left < a.right - 2 &&
                    a.top < b.bottom - 2 && b.top < a.bottom - 2),
                  "tiled windows don't overlap");
        }
    }

    PressHotkey('R');
    Sleep(2000);
    PrintWindows(L"after Ctrl+Alt+R");
    SaveScreenshot(L"screenshots\\mod-3-restored.bmp");
    for (HWND hwnd : NotepadWindows()) {
        CHECK(IsZoomed(hwnd), "every Notepad maximized again");
    }

    // A changed hotkey takes effect without restarting.
    g_testSettings[L"tileHotkey"] = L"Ctrl+Alt+T";
    WhTool_ModSettingsChanged();
    Sleep(500);
    PressHotkey('T');
    Sleep(2000);
    PrintWindows(L"after Ctrl+Alt+T (changed hotkey)");
    int tiled = 0;
    for (HWND hwnd : NotepadWindows()) {
        tiled += !IsZoomed(hwnd) && !IsIconic(hwnd);
    }
    CHECK(tiled >= 2, "changed hotkey tiles");

    WhTool_ModUninit();
    CHECK(g_thread == nullptr, "hotkey thread stopped");
    for (HWND hwnd : NotepadWindows()) {
        PostMessage(hwnd, WM_CLOSE, 0, 0);
    }
}

int wmain(int argc, wchar_t** argv) {
    if (argc < 3) {
        HarnessLog(L"usage: harness settings.txt layout|live");
        return 2;
    }
    std::wifstream in(argv[1]);
    std::wstring line;
    while (std::getline(in, line)) {
        size_t tab = line.find(L'\t');
        if (tab != std::wstring::npos) {
            g_testSettings[line.substr(0, tab)] = line.substr(tab + 1);
        }
    }
    HarnessLog(L"%zu settings read", g_testSettings.size());

    if (wcscmp(argv[2], L"layout") == 0) {
        TestSettings();
        TestLayout();
    } else {
        CreateDirectory(L"screenshots", nullptr);
        TestLive();
    }
    if (g_failures) {
        HarnessLog(L"%d check(s) failed", g_failures);
        return 1;
    }
    HarnessLog(L"all checks ok");
    return 0;
}
