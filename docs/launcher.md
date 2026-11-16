# Launcher

**Current choice: Fossify Launcher (D-14). Setup steps are in `docs/installation.md`.** The rest of this page is the Olauncher assessment, kept as the backup option.

Olauncher status: GitHub APK v6.9.17 installed and tested on SM-X133 / X133DXS4BZB6, 4 Nov 2026 (**Verified** where marked).

## Olauncher (`app.olauncher`)

Open source (GPLv3), ad-free, text-only home screen by tanujnotes. Source: https://github.com/tanujnotes/Olauncher

| Requirement | Olauncher | Source |
|---|---|---|
| Clock and date on Home | Yes (can be hidden) | `DATE_TIME_VISIBILITY` pref, Prefs.kt |
| Home shortcuts | 4 by default; code has 8 slots | `HOME_APPS_NUM`, `isShortcut1..8` in Prefs.kt (inferred from code) |
| Decadent (Chrome web shortcut / PWA) | Supported: lists pinned shortcuts and launches them | `LauncherApps.ShortcutQuery FLAG_MATCH_PINNED` in Utils.kt; issues #693, #697 |
| App drawer | Swipe up, with search | F-Droid description |
| Settings | Long-press empty space opens Olauncher settings; Android Settings goes in a Home slot | F-Droid description |
| Landscape | Follows the system (no fixed orientation). Look in landscape: not checked | AndroidManifest.xml |
| Ads / trackers | None stated; `INTERNET` only for daily wallpapers (can be off) | README, manifest |
| Starts apps at boot | **No.** No boot receiver, no auto-launch code | AndroidManifest.xml |

Caveats:
- Pinned website shortcuts broke in v6.3.15 and were fixed later (issue #697). Test the exact version you install.
- Olauncher can see pinned shortcuts only while it is the default Home app.
- Double-tap to lock uses an optional accessibility service or device admin. Leave it off: the tablet's own double-tap wake does not need it.

## Versions (3 Nov 2026)

| Source | Version | Signed by |
|---|---|---|
| GitHub releases | v6.9.17 (17 Sep 2026), `Olauncher-v6.9.17.apk` | developer |
| F-Droid | v6.10.27 (added 31 Oct 2026) | F-Droid, with a reproducible-build check |
| Google Play | `app.olauncher`; version not read | developer |

Builds signed by different keys cannot update each other. Pick one source and keep it.
Play needs a signed-in Google account, and the reference tablet has none. Installing the GitHub or F-Droid APK with `adb install` needs no account and no Wi-Fi on the tablet, but updates are by hand. Owner chooses.

## Olauncher Pro / Pro Launcher (`app.prolauncher`)

Pro Launcher is the same developer's paid-feature launcher, with a widget wall, weather, folders, categories and notes.
Its Play data-safety section lists third-party analytics and crash reporting. It is not needed here: four to
eight shortcuts, a clock and the drawer cover the requirement. "Olauncher Clutter Free" (`app.olaunchercf`)
is an unrelated fork and is archived.

## Steps

**Verified 4 Nov 2026**, installed over USB, no Google account, Wi-Fi off:

1. Download the APK from the GitHub release. Compare its SHA-256 with the digest on the release page. v6.9.17: `bc72df3b8162f68a7bfed886fa21eb62ee1d53eadb9526498606b8f0aae5aa19`.
2. Install it: `adb install Olauncher-v6.9.17.apk`. Check the package: `adb shell pm list packages app.olauncher`.
3. Make it Home: `adb shell cmd role add-role-holder --user 0 android.app.role.HOME app.olauncher`. This stays set over a reboot.
4. Press Home. Olauncher shows the clock, date, battery and four `App` slots. It works in landscape.
5. **Long-press** a slot to pick its app. A short tap only shows a hint. Pick the Decaid and Settings slots this way.
6. Swipe up for the app drawer. Press Home to return.
7. Turn off the keyboard that covers the drawer: long-press empty space, then under **Appearance** tap **Auto show keyboard**, tap **Okay** on the message, and tap it again. It now reads Off.

Undo: `adb shell cmd role add-role-holder --user 0 android.app.role.HOME com.sec.android.app.launcher`.

**Adding Decadent (Verified 4 Nov 2026, Wi-Fi off):** Olauncher lists only shortcuts pinned to it, so a shortcut made under One UI Home does not appear.
With Olauncher as Home, open `https://decadentcoffee.app/app/` in Chrome, tap the install icon in the address bar, then **Install**. Nothing visible happens, but Decadent appears in Olauncher's list.
Long-press a slot and pick it. Offline this made a Chrome pinned shortcut, not a WebAPK package. Whether Wi-Fi gives a WebAPK and true fullscreen is not tested.

**Decent and Update Decent** are pinned to One UI Home, so Olauncher cannot list them.

## Other launchers tried (4 Nov 2026, One UI 8.5, installed over USB, checksums matched GitHub)

| Launcher | Result |
|---|---|
| Lawnchair 15 Beta 3 (`app.lawnchair`) | Landscape, icons, one page of four, dock hidden, Decadent added from Chrome. Launches and swipe up to Home work. Owner rejected it: looks like normal Samsung rearranged, blank screens and too many swipes to learn. Removed |
| Fossify Launcher 1.10.0 (`org.fossify.home`) | Four very large icons in one row on a 4 × 3 grid, on the owner's wallpaper. Decadent added from Chrome. All four open; survives a reboot. Labels sit right of centre, large icons look slightly soft. Owner chose it: "looks great" |
| DNA Launcher | Not installed. Play lists device IDs shared for advertising and no way to delete data |

## Sources

- https://github.com/tanujnotes/Olauncher (README, Prefs.kt, Utils.kt, AndroidManifest.xml)
- https://github.com/tanujnotes/Olauncher/issues/693 · https://github.com/tanujnotes/Olauncher/issues/697
- https://f-droid.org/packages/app.olauncher
- https://play.google.com/store/apps/details?id=app.prolauncher
