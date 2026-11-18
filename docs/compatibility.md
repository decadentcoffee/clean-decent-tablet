# Compatibility

Labels: **Verified** = tested on a real device. **Documented** = from an official source, not tested here.
**Experimental** = plausible, not tested. **Unsupported** = known not to work.

## Tested devices

| Model | Android / One UI | Firmware (PDA) | Date | Applied | Result |
|---|---|---|---|---|---|
| SM-X133 (gta11wifi), after OTA | 16 / 8.5 | X133DXS5BZI3 | 4 Nov 2026 | everything below, carried over by the upgrade | Upgrade check passed. Most results below come from 8.0 and were not all re-run on 8.5 |
| SM-X133 (gta11wifi) | 16 / 8.0 | X133DXS4BZB6 | 3 Nov 2026 | settings, batches 1–6 and 8, Olauncher | Partial. See below. |

## App versions seen on the reference tablet

| App | Version | Date |
|---|---|---|
| Decaid `net.tadel.reaprime` | 0.9.1 | 3 Nov 2026 |
| Decaid `net.tadel.reaprime` | 0.9.2 (build 3191), updated inside Decaid. Port 8080 answered and the DE1 was connected. Installing it with this project is not tested: the tablet already had Decaid | 16 Nov 2026 |
| Decadent plugin in Decaid, first install | **Verified** by script over adb on the reference tablet (Decaid 0.9.2, DE1 asleep): with no Decadent plugin in Decaid, `finish plugin` started from Android's Home, left Decaid's coffee screen, installed 0.43.0 from `decadentcoffee/plugin` (the repo is `decadentcoffee/decadent-plugin` since 18 Nov 2026: the script now types the new name, not yet re-run on the reference tablet), tapped Load and switched on Auto-load on startup. Decaid reported the plugin loaded and set to start; the seven other plugins were unchanged; the machine stayed asleep. The webpage's own run of this step is not tested | 18 Nov 2026 |
| `finish decaid` on a Decaid already set up | **Verified** on the reference tablet: `STATUS decaid=ready` from the coffee screen (Decaid's stock skin shows its own buttons in the screen read; the first version took them for questions and said `asking`, fixed 18 Nov 2026). Decaid's start-up screen read "Connecting to device" with **Continue to Dashboard**, as in the source | 18 Nov 2026 |
| Decaid's first questions (`finish decaid` on a Decaid never opened) and the tap on Continue to Dashboard | Simulated tablet and the page's safe mode only. **Not run** on a real tablet: it needs Decaid's data cleared; labels are from Decaid 0.9.2's source | 18 Nov 2026 |
| AndroWish `tk.tcl.wish` | 1.0 | 3 Nov 2026 |
| Chrome | 154.0.8037.92 | 3 Nov 2026 |
| Android System WebView | 153.0.8010.36 | 3 Nov 2026 |
| Samsung Internet | 28.0.5.9 (disabled) | 3 Nov 2026 |
| Launcher | Fossify Launcher 1.10.0 (GitHub APK); Olauncher v6.9.17 as backup | 4 Nov 2026 |

## Feature results (SM-X133 / X133DXS4BZB6, 4 Nov 2026, after batches 1–6)

| Check | Result | Note |
|---|---|---|
| Reboot with batches 1–6 disabled | Pass | Uptime confirmed the restart; 100 disabled before and after, including the 3 already disabled when we started |
| Android refuses to disable | Noted | `com.samsung.android.fmm` (Find My Mobile), `com.osp.app.signin` (Samsung account): "Failed to change state". Both stay enabled |
| Reboot straight after a batch | **Fail** | The last 5 of 24 came back. `disable.sh` now waits 30 s; after the wait all stayed |
| Home, app drawer, Settings | Pass | Driven by ADB and checked on screenshots |
| Keyboard appears in a text field | Pass | `mInputShown=true` in launcher search |
| Settings persist over reboot | Pass | Timeout 10 min, stay-awake off, Chrome default |
| Rollback of one package | Pass | `com.samsung.sree` enabled, second run skipped it, then disabled again |
| Rollback leaves original disabled packages alone | Pass | Not listed in the rollback plan |
| Modes and Routines boot trigger | **Unsupported** | No such trigger on One UI 8.5 |
| Decaid stays running after boot | **Fail** | Its boot receiver starts the process, which exits about 3.5 s later with no service and no port |
| Decaid started by hand, after batch 6 | Pass | Port 8080 answers |
| Decaid survives Home, then 90 s screen off | Pass | Same process, port still answers. Long idle not tested |
| Decaid connects to DE1 | Not tested | Final test, DE1 off for now (D-8). Decaid showed "No Bluetooth devices found" with the DE1 off |
| Power key wakes the screen, no lock step | Pass | Simulated with ADB key events. Physical press not tested |
| Double-tap to wake | Pass | Owner confirmed by hand. Single tap is not available: no sensor or always-on display for it |
| Screen sleeps at 10 min idle | Pass | Slept by itself after about 10 minutes (timer seen at 597 s) on USB power, stay-awake off |
| Decadent opens from Home | Pass | Offline, from cache, Samsung Internet disabled. Shows the log-in screen |
| Decadent reaches Decaid | Not tested | Needs log-in and Wi-Fi |
| Decadent fullscreen | Pass | With a dedicated Google account: WebAPK, both bars gone, through sleep, wake and reboot. See `docs/startup.md` |
| Chrome and WebView updates | Pass | With that account, Chrome 154 to 156 and WebView 153 to 156 through Play |
| Olauncher: Home, Decaid and Settings slots, drawer, reboot | Pass | Landscape OK |
| Olauncher slot opens Decadent | Pass | After installing from Chrome with Olauncher as Home. Opens in its own window; status and navigation bars still visible |
| Olauncher drawer without keyboard | Pass | **Auto show keyboard** set to Off |
| Chrome Install app with no Google account | Partial | Gives a pinned shortcut Olauncher can list, with or without Wi-Fi. No WebAPK: `unknown_account` |
| Wi-Fi | Pass | IoT network; Decadent logged in |
| Olauncher lists Decent and Update Decent | **Fail** | Pinned to One UI Home |
| Firmware update check | Pass | Reached Samsung with push service disabled. Offered One UI 8.5; paused at 5%, not installed |
| Fossify on 8.5: four icons open, drawer, Decadent shortcut, reboot | Pass | Decadent opened after a reboot; all four opened later. Labels sat right of centre on 4 × 3; fixed by 5 × 3 |
| Bottom-edge swipe inside an app, five speeds (ADB) | Pass | Always reached Home |
| Bottom-edge swipe on the Fossify Home screen (ADB) | **Fail** | Samsung's `RecentsActivity` opens, then Fossify returns at once. Owner sees a brief preview that never opens. Open programs not reachable from Home this way |
| Upgrade to One UI 8.5 | Pass | Nothing re-enabled; Home, default browser and sleep settings kept; Decadent opens |
| Bottom strip colour on 8.5 | Noted | Gesture strip is light in Decadent's window, was black on 8.0. Likely Decadent's theme colour `#f3f4f1` |
| Phone icon in the app drawer | Changed | Phone left the drawer after batch 2 and Contacts appeared; both packages stay enabled. No use on a Wi-Fi tablet |

## Setup methods (4 Nov 2026)

| Method | Test | Result |
|---|---|---|
| `device/decent-setup.sh` | Full setup and undo on a simulated tablet, `tests/sim-tablet.sh` | Pass |
| `device/decent-setup.sh` | `check`, `status`, `plan`, `apply --dry-run`, `undo --dry-run` on the reference tablet | Pass. 99 re-enables and 3 removals previewed; Decent's 3 not listed |
| `device/decent-setup.sh` | Real `apply` and real `undo` on a real tablet | **Not run.** The owner's tablet was configured by the earlier batch scripts |
| Navigation change by `cmd overlay` | On a real tablet | **Not run.** On the reference tablet it was set by hand in Settings |
| `scripts/setup.sh`, `scripts/undo.sh` | `--dry-run` on the reference tablet | Pass |
| Webpage | All screens in Chromium with a pretend tablet | Pass |
| Webpage connection code | Node over USB, reference tablet | **Not completed.** Found the tablet, then timed out after 25 minutes with no Allow tapped. Whether the prompt appeared was not seen |
| Webpage | Real browser and real tablet | **Not run** |
| Webpage on Windows | | **Not run.** The library's docs warn of Windows driver limits |
| Standard Home screen: three icons on a 5 × 3 grid | Reference tablet, 8 Nov 2026 | Pass. Labels line up with icons. On 3 × 3 they sat about 95 px right, a Fossify layout bug in landscape. A Settings icon hidden by the column change came back at 5 columns; removed |
| `cleanup` and `home` separately, with undo after each | Simulated tablet, `tests/sim-tablet.sh`, 26 checks | Pass |
| `scripts/setup.sh --dry-run` and `--home --dry-run` | Reference tablet, 8 Nov 2026 | Pass. Nothing to change, as expected on a tablet already set up |
| Webpage option checkboxes | Chromium with a pretend tablet | Pass. Neither option shows an error; each alone runs only its part and shows only its finishing steps |
| Webpage per-app ticks | Chromium with a pretend tablet | Pass. Unticking an app or a group lowers the count and drops it from the plan; apps already off or absent cannot be ticked. That the filtered list reaches a real tablet is **not tested** |
| `scripts/setup.sh --keep` | | **Not run** on a tablet |
| Undo in parts (`--apps`, `--home`, `--pkgs`) | Simulated tablet | Pass. Parts in any order end at the original state; the browser stays Chrome while Samsung Internet is still off. Not run on a real tablet |
| Webpage undo choices and browser back/forward | Chromium with a pretend tablet | Pass |
| Webpage compatibility check | Chromium with a pretend tablet | Pass. Other model: refused, no options shown. SM-X133 on new firmware: warning, options only after accepting, runs with `--force`. Tested build: straight through |
| `finish` steps on the reference tablet (Fossify 1.10.0, One UI 8.5, Chrome 156) | 9 Nov 2026 | **Verified:** `status`; `icons` (Chrome dragged onto Home, then removed); `launcher` (rows 4 → 3, columns 3 → 5, drawer switch back on; a second run skips); `place` (Settings removed, then dragged back to its cell; the two in place skipped); `updates` (both up to date, read correctly). **Not run:** tapping **Update** in Play, installing Decadent from scratch (it was already installed), `wifi` and `account-open` on a real tablet |
| `finish` steps on the simulator | `tests/sim-tablet.sh` | Pass |
| Webpage last steps (Wi-Fi, account, Finish for me, fallbacks) | Chromium with a pretend tablet, including `?demo=manual` | Pass. Restart and reconnect over WebUSB **not run** on a real tablet |

## The webpage on a real tablet (18 Nov 2026)

Reference tablet (SM-X133, X133DXS5BZI3, One UI 8.5), driven through the page itself in headless Chrome 157 on macOS over WebUSB.
The browser's device chooser was the one thing not clicked: headless Chrome cannot show it, so the test profile was given the tablet beforehand.
The page ran from the local build, with the fixes of D-30 from run 3 on. The DE1 stayed asleep through every run.

| Run | Start | Chosen | Result |
|---|---|---|---|
| Connect | Tablet fully set up | Connect tablet | **Verified.** Android's Allow prompt showed for the page's new key; with Always allow ticked, every later connection and the reconnect after a restart needed no tap |
| 1 | Fully set up | Turn apps back on and the original Home screen | **Verified.** 99 apps on again, Samsung's Home with its own icons, bottom buttons, side panel, Samsung Internet as browser; Fossify, Olauncher and Decadent removed; 6 apps that were off before stayed off |
| 2 | Stock, Decaid present | Clean up only, Gmail unticked | **Verified.** 98 off, Gmail left on (the per-app choice reaches the tablet), all still off after the restart. Finish for me: restart and reconnect by itself, Chrome updated through Play (157 to 158), Decaid opened |
| 3 | After run 2 | Turn apps back on, then New Home screen, Decadent wanted | **Verified.** Undo ran, then the Home option without a second visit. Finish for me in 5 minutes: plugin step (plugin already there), icons, grid, Decadent installed from Chrome as a WebAPK, three icons placed, both apps opened. Found: Samsung Internet stayed on Home (fixed, D-30) |
| 4 | Stock, no Decaid | Both options, Skip Decaid, Decadent unticked | **Verified** after the D-30 fix. First try: the icon and grid steps ran before Home was ready after the restart and were left for the person. Home ends with Settings alone |
| 5 | Stock, no Decaid | Both options, install Decaid from the downloaded file, Decadent wanted | **Verified.** No file and a wrong file are refused with nothing installed. Decaid 0.9.2 installed (122 MB in about 80 s with everything else). The page paused at Decaid's first questions, went on by itself when they were answered, installed the plugin into the new Decaid (loaded and set to start), then Decadent. Decadent, still logged in from before, linked the new Decaid by itself. Home and the list of switched-off apps ended identical to the start of the day |

Not tested: the browser's own device chooser, Windows, joining Wi-Fi and the Google sign-in from the page (the tablet had both), a tablet with no Google account.

Seen and left: the first time Decadent opens after it is installed, a dark strip stays where the status bar was; it is gone the next time the app is opened.

| `finish more` (19 Nov 2026) | Home with one page | Second Home page | **Verified** by script over adb: SE Profiler, Coffee Flow and AZ Screen Recorder in the middle cells of a new second page, no third page; a second run skips all three. Its run from the webpage is **not tested** |
| Open step: Decadent, Home, Decadent again | | | **Not tested** as a step. By hand on the reference tablet, Home and back removed the empty strip above Decadent both times it was seen |
