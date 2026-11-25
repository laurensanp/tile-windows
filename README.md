# Tile Windows

Arranges all your open app windows across all monitors with one hotkey, sized by how much you use each app. Press **Ctrl+Alt+W** to arrange, **Ctrl+Alt+R** to maximize everything again. Only a tiny hotkey helper (about 5 MB) runs in the background; after you sign in, apps open at a normal default size (centered, not tiled) until you press Ctrl+Alt+W; otherwise it does nothing until you press a hotkey.

- **Main monitor** gets only the apps you work in directly (editor, browser…). Chat, music and tools go to the other monitors.
- **Best fit, not a fixed grid:** each monitor gets the mix of side-by-side columns and stacked rows that gives important apps the most room while every window stays readable.
- **Never unreadable:** windows don't get smaller than 500×300 (scaled with your display scaling). If too many apps are open, the least important ones are minimized.
- **Respects apps' own minimum sizes** (Discord, Steam, Spotify can't get very small) and works them into the layout.
- **Games are left alone** and **keep focus**: pressing the hotkey while in a game doesn't pull you out of it.
- **Reminds you about new apps:** apps it doesn't know yet are listed in `settings.json` with a notification, so you can give them a weight.
- Works with any number of monitors, resolutions and mixed display scaling.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in) — nothing to install

## Install

Paste this into PowerShell:

```powershell
irm https://raw.githubusercontent.com/laurensanp/tile-windows/main/install.ps1 | iex
```

It installs to `%LOCALAPPDATA%\TileWindows` and adds the hotkeys **Ctrl+Alt+W** (arrange) and **Ctrl+Alt+R** (maximize again).

Run the same line again for a menu: **Update** (keeps your settings), **Settings** (opens `settings.json`), **Uninstall**.

## Settings

Run the install command and choose **Settings**, or edit `settings.json` directly (created from `settings.default.json`; the `_help` block at the top explains every entry). Changes apply on the next keypress.

| Setting | Meaning |
|---|---|
| `New` | Filled in automatically with open apps that have no weight yet. Move each into a group under `Weights`. |
| `Hotkey`, `RestoreHotkey` | Shortcut keys, e.g. `"CTRL+ALT+W"`. After changing them, run the install command again and choose **Update**. |
| `Gap` | Space between windows and to the screen edge, in px at 100% scaling. |
| `MinWidth`, `MinHeight` | Smallest readable window, in px at 100% scaling. |
| `Weights` | Process names (Task Manager → Details, without `.exe`) grouped by how much you use them. |
| `WideApps` | Apps that need width (videos, websites). They get wide slots (~1280 px) instead of narrow columns when possible. |
| `MainScreenApps` | Apps that get the whole main monitor to themselves when open; everything else moves to the other monitors. Optional. |
| `GameFolders` | Anything started from these folders counts as a game and is never touched. |

### Weights

| Weight | Meaning |
|---|---|
| 3 and up | You work in it directly → main monitor. Higher = more space. |
| below 3 | Second monitor (or main, if you have one monitor). Not listed = 1. |
| 0 | Never touch (games, overlays). |

Any number works as a group, e.g. `"4.5": ["Obsidian"]`. Higher weight = more space and minimized later; with equal weights, the app you used most recently stays visible.

## Files

| File | Purpose |
|---|---|
| `install.ps1` | One-line install / update from GitHub |
| `Setup.ps1` | Builds and starts the hotkey helper, adds Start-menu entries, creates your `settings.json` |
| `Hotkeys.cs` | Source of the hotkey helper (built on your PC by Setup, starts with Windows) |
| `Tile-Windows.ps1` | What Ctrl+Alt+W runs |
| `Restore-Windows.ps1` | What Ctrl+Alt+R runs |
| `Layout.ps1` | Settings loading and layout math |
| `Native.cs` | Windows calls: find, move, minimize windows |
| `settings.default.json` | Default settings, copied to `settings.json` on first run |
| `Test.ps1` | Checks the settings and the layout math without moving windows |

## Troubleshooting

- **Hotkey does nothing:** run `& "$env:LOCALAPPDATA\TileWindows\Test.ps1"`. A typo in `settings.json` (missing comma, a `\` that isn't doubled) shows up there. Another program may also use the same key combination; pick another one in `settings.json`, then run the install command again and choose **Update**.
- **An app is never arranged:** it may run as administrator (Windows doesn't let normal programs move those), or it has weight 0 / is in a game folder.
- **A closed app opens in its old tiled size:** apps remember their own last size. Press Ctrl+Alt+R before closing them, or maximize them once.

## License

[MIT](LICENSE)
