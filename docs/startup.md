# Startup, sleep and wake

Status per item: **Verified**, **Documented** or **Experimental**. Checked 3 Nov 2026 on SM-X133 / X133DXS4BZB6.

## How the pieces connect

Decadent, in tablet mode (`https://decadentcoffee.app/app/?display=tablet&decaid=local`), talks to Decaid's
REST and WebSocket API on `localhost:8080`. So **Decaid must be running** whenever Decadent is in front.

| Fact | Status | Source |
|---|---|---|
| Decaid serves REST + WebSocket on port 8080 | Documented | https://github.com/tadelv/reaprime/blob/main/doc/Api.md |
| Decaid can run as a foreground service ("connectedDevice") holding the machine connection in the background | Documented | Decaid README and AndroidManifest.xml |
| Swiping Decaid out of Recents stops that service (`stopWithTask=true`) | Documented | AndroidManifest.xml |
| Decaid 0.9.1 holds `RECEIVE_BOOT_COMPLETED` on this tablet | Verified (permission granted) | `dumpsys package` |
| Decaid does **not** stay running after boot. Its foreground-task `RebootReceiver` starts the process, which exits about 3.5 s later | Verified 4 Nov 2026 (0.9.1) | `am_proc_start` and `am_proc_died` in the event log; no service, no port |
| Decaid keeps port 8080 alive after Home and 90 s of screen off | Verified 3 Nov 2026 (0.9.1); long idle not tested | Same process, port answered |

## Decadent fullscreen

The Decadent manifest asks for `display: fullscreen` and sets no orientation. Tested 4 Nov 2026 on SM-X133 / X133DXS4BZB6, Chrome 154, Wi-Fi on, no Google account.

The tablet has no physical buttons. The status bar is 40 px and the navigation bar 64 px of the 800 px height.

| Route | Result | Status |
|---|---|---|
| Chrome **Install app** with no Google account | Gives a pinned shortcut, not a WebAPK. Runs in `display-mode: standalone`, so both bars stay. Play logs `WebAPK service unknown_account` | Verified |
| Chrome **Install app** with a dedicated Google account | Play builds a WebAPK in about 12 s. `display-mode: fullscreen`, both bars gone, 601 CSS px tall. Stays through sleep, wake and reboot. No tap, no message. **The chosen route** | Verified |
| Samsung Swipe gestures, hint hidden | Bottom bar shrinks from 64 px to a 20 px black strip. Swipe up goes Home with Olauncher. Survives sleep and wake. Status bar stays | Verified; back swipe not confirmed |
| Web Fullscreen API (`requestFullscreen`), sent over USB debugging | Both bars gone, 601 CSS px tall instead of 523. Lost on sleep and on Home. Needs a tap to re-enter, and Chrome shows an exit hint each time. Would need a Decadent change | Verified as a test |

To set Swipe gestures: **Settings → Display → Navigation bar → Swipe gestures**, then `scripts/settings.sh --apply` hides the line.
Undo: choose **Buttons** on the same screen, then `scripts/settings.sh --revert`.

## Sleep and wake

| Setting | Now (Decent's state) | Planned | Status |
|---|---|---|---|
| Screen timeout | never | 10 min (owner, D-7) | Applied 3 Nov 2026 |
| Stay awake while charging | on, all power sources | off | Applied 3 Nov 2026 |
| Double-tap to wake | on | keep | Wake not tested |
| Lock screen | none | keep none (owner: no lock) | Verified |

Apply with `scripts/settings.sh --apply` (also makes Chrome the default browser). Undo with `scripts/settings.sh --revert`.
Original values are in `manifests/original-settings.*.txt`. Changes are logged to `logs/changes.tsv`.

## Cold boot order

Wanted: Decaid starts, then Decadent opens in front. Checked 4 Nov 2026 on One UI 8.5 with Decaid 0.9.1.

| Fact | Status |
|---|---|
| Decaid will not start itself: source sets `autoRunOnBoot: false` in `foreground_service.dart`, and its boot receiver exits within seconds | Verified |
| Fossify and Olauncher cannot launch apps at boot | Documented |
| Samsung Modes and Routines has **no boot trigger**. Its triggers are mode, manual, time, Wi-Fi, Bluetooth, airplane mode, wired headphones, charging, battery, power saving, sound, dark mode, app opened, game, notification, media, share panel and alarm | Verified |
| A background app needs **Display over other apps** to open another app | Documented |
| Started with the DE1 off, Decaid shows "No Bluetooth Devices Found", and its API still answers | Verified |
| Decadent's **Search again** calls Decaid's `/api/v1/devices/scan`, which connects by default, so a late DE1 should connect without opening Decaid | Documented from source, not tested with a DE1 |

For now: after a power cycle, open Decaid once from Home, then open Decadent. A normal screen wake needs none of this.

Options if this should be automatic, none chosen yet:

| Option | Notes |
|---|---|
| Routines Wi-Fi trigger | Installs nothing. May also fire when Wi-Fi drops and returns, bringing apps forward at a bad moment. Not tested |
| A tiny purpose-built boot app, source in this repo | Could wait for port 8080 before opening Decadent, with no internet permission. Needs the Android build tools and **Display over other apps**. Not built |
| MacroDroid | **Rejected.** Its Play data-safety page (read 4 Nov 2026) lists device IDs shared for advertising or marketing, crash logs shared for analytics, and approximate location and diagnostics collected for analytics |
| Easer (GPLv3) | Open source, but its last release is a 2022 beta. Unlikely to suit Android 16. Not tested |


## Single-tap wake

Not available on this tablet with the screen off. Double-tap works (owner, 4 Nov 2026). `dumpsys sensorservice` lists no tap sensor, and there is no Always On Display service. Untested idea: a dim screen saver in place of sleep, which a single tap dismisses, at the cost of the screen staying lit.
