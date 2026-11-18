# Decisions

Owner decisions and the facts behind them. Newest last.

## 3 Nov 2026

**D-1 Original state = Decent's shipping state.** The packages already disabled at first inventory
(`com.mygalaxy.service`, `com.samsung.android.knox.zt.framework`, `com.google.android.gms.supervision`)
were disabled by Decent. The first inventory (`inventory-20261103T121837Z`) is the "original state".
Rollback returns to it and never enables those three.

**D-2 Chrome is the browser; Samsung Internet goes.** Decadent runs in Chrome. The owner wants Samsung
Internet uninstalled, not only disabled. Fact: Samsung Internet lives in `/data/app/SBrowser/`, not in the
system image, so an uninstall removes the APK. Reinstall path: Galaxy Store or Play Store. Order: make Chrome
the default browser, check Decadent still opens, then disable (D-7 replaced uninstall with disable).

**D-3 Keep the original Decent app.** AndroWish (`tk.tcl.wish`) stays installed as the backup. It is still
the app Decent ships. Its two pinned home-screen shortcuts stay.

**D-4 Decaid comes from the APK.** The owner installed Decaid 0.9.1 (`net.tadel.reaprime`) by hand from the APK.

**D-5 Decent's extra apps stay.** Decent distributes these with the tablet. Keep them and name them in the guide:
- **SE Profiler** (`hu.kavekalmar.sep`), Smart Espresso Profiler: https://www.naked-portafilter.com/smart-espresso-profiler/
- **Coffee Flow** (`com.pressensor.coffeeflow`), Pressensor: https://pressensor.com/pages/about-the-app
- **Decent** and **Update Decent**: Home-screen shortcuts into AndroWish (`tk.tcl.wish`), not separate packages.
  They show the AndroWish badge and AndroWish holds exactly two pinned shortcuts. Decent is the legacy de1app (owner's understanding).

**D-6 Screen sleeps when idle, wakes on tap or power button.** Today the screen never sleeps: timeout is
"never" and "stay awake while charging" is on for every power source, and the DE1 keeps the tablet charged.
Double-tap to wake is already on. No screen lock is set (`CredentialType: NONE`, lock screen disabled), so a
wake goes straight to the last app. Planned change: turn off stay-awake-while-charging and set an idle timeout.
Applied 3 Nov 2026: timeout 10 min (D-7).

**D-7 Review choices, 3 Nov 2026.** Approved for disabling: batch 1 (23, YouTube stays), batch 2 (24), batch 3
(Samsung Internet: **disable, not uninstall**, reversing the first request in D-2). Screen timeout 10 min. Chrome is the
default browser now. File Manager + and AZ Screen Recorder stay.

**D-8 Test order.** Wi-Fi stays off until the bloat is disabled (the owner kept it off on purpose; it was not a fault).
The DE1 is turned on last, once the owner is happy with the tablet. So Decaid-to-DE1 is the final acceptance test,
and "no Bluetooth devices found" before then says nothing about the tablet.

**Open, owner will come back to these:**
- Samsung Keyboard: owner is "not convinced this isn't spyware". Replacing it needs a verified replacement first.
- `com.samsung.android.app.updatecenter`: owner asked if it is bloat or base OS. See below.

**D-9 Second review, 3 Nov 2026.** Approved: batches 4, 5 and 6, and Olauncher from the GitHub APK. No Google account goes on the
tablet: signing in would give its apps standing access to the owner's account, and it has no screen lock. Telemetry not needed to run the tablet
should go, so the diagnostics agent gets a watched test (batch 7) of the old UAD-ng warning. Android refuses to disable Find My Mobile and Samsung account.

**D-10 Diagnostics agent stays, 4 Nov 2026.** The owner wants Samsung firmware updates and chose to leave `com.sec.android.diagmonagent`
enabled for now. The agent was disabled for 2.5 minutes. Android left its running process alive (same pid), and it logged no crashes. Lines naming it rose from 5 to 44, the three inspected
being package-change notices. It never ran through a reboot, so the UAD-ng warning is neither confirmed nor refuted. No source links this agent to firmware updates.
Firmware updates use `com.wssyncmldm` and `com.sec.android.soagent`, both enabled. `com.sec.spp.push` and `com.samsung.android.dbsc` are disabled; check Software update once Wi-Fi is on.
Chrome (154, updated 5 Oct 2026) and WebView update through Google Play. With no account signed in they may stop updating: not tested.

**D-11 Keep everything Decent shipped, 4 Nov 2026.** Decent's own set is what was installed in one 32-second run on 16 Feb 2026: File Manager +,
Coffee Flow, SE Profiler, AZ Screen Recorder and AndroWish (with its Decent and Update Decent shortcuts). All stay enabled. None was ever disabled. Decaid was added by the owner.
Everything else disabled dates from Samsung's factory image or is a system package. The three packages already disabled at first inventory (D-1) stay disabled.
Samsung Contacts is disabled at the owner's request (batch 8). The owner is considering My Files; File Manager + stays under this rule.
Olauncher slots, in order: Decaid, Decadent, YouTube, Settings.

**Open:** the **Decent** and **Update Decent** shortcuts are pinned to One UI Home, so Olauncher cannot list them. AndroWish is listed; whether it opens the Decent app directly is not tested.

**D-12 Network and navigation, 4 Nov 2026.** The tablet joins the owner's IoT network, not the trusted LAN: Decadent reaches it through the cloud and localhost, and
Decaid's web server is unauthenticated with open CORS. Navigation is Samsung Swipe gestures with the hint hidden, to give the bottom of the screen to Decadent.

**D-13 One UI 8.5, 4 Nov 2026.** The owner installed it for security updates. Gemini and 11 other new packages are unreviewed.
The owner tried One UI Home and Lawnchair and rejected both. Olauncher is the Home app again.

**D-14 Fossify Launcher is Home, 4 Nov 2026.** Four very large icons in one row, on a 4 × 3 grid. The owner: "looks great lets keep this for now". Olauncher was too text-only, One UI Home
looked like a bare tablet, and Lawnchair was rejected. Olauncher stays installed as a backup. One UI Home must stay enabled: it provides the recent-apps screen (`com.android.quickstep.RecentsActivity`), so the earlier idea of disabling it is dropped.

**D-15 More removals, 4 Nov 2026.** Gemini and My Files are disabled (batch 9). Auto-rotate stays on, by owner's choice.

**D-16 Edge panel off, 4 Nov 2026.** The owner removed Samsung's side drawer (`secure edge_enable=0`). Persistence over a reboot not tested yet.

**D-17 Dedicated Google account, 4 Nov 2026.** The owner signed in a throwaway Gmail account. It gives Play updates for Chrome and WebView, and it let Play build Decadent as a WebAPK with true fullscreen. Swipes stay: Decadent gets the whole screen.

**D-18 One core, three front ends, 4 Nov 2026.** The owner asked for a way others can copy this tablet and undo it: an agent list, a script, or a webpage. All three run `device/decent-setup.sh` on the tablet, so they cannot drift apart. The record lives on the tablet, so undo needs no particular computer. The webpage uses WebUSB (Tango, MIT). Hosting is the owner's call; nothing is public. All this work stays in this repo, separate from the Decadent app.

**D-19 Standard Home screen, 8 Nov 2026.** Every set-up tablet gets three icons: Decaid, Decadent, Settings, on a 5 × 3 grid, in the middle three cells (changed from 3 × 3 the same day: labels sat right of their icons). Decadent is a standard step, not an option: this project is made by Decadent's makers. YouTube is off Home (the owner does not use it) and stays installed. The original Decent app stays installed and in the app list, but is not on Home. Owners can add their own icons.

**D-20 Two options, 8 Nov 2026.** Setup offers **Clean up** (disable the tested list, Chrome as browser, sleep after 10 minutes) and **New Home screen** (Fossify with Decaid, Decadent and Settings, swipe gestures, no side panel), either or both. Decadent is part of the Home option, not a separate choice: it is a web app link, so anyone can remove it. The core script has `cleanup` and `home`; `apply` runs both. Undo reverses whichever ran.

**D-21 Pick your own apps; host on GitHub Pages last, 8 Nov 2026.** The webpage lists every app in the tested list with a reason, all ticked by default; anyone can untick apps to keep them, and the script takes `--keep`. People who do not dig in get the tested list. The webpage goes on GitHub Pages once the repo is public (`.github/workflows/pages.yml`, by hand until then).

**D-22 Undo in parts, 8 Nov 2026.** Undo offers **turn apps back on** (all or chosen ones) and **put the original Home screen back**, separately. The browser goes back to the original only if that browser is on again. Samsung's Home keeps its own icons, so reverting Home needs no icon handling. The webpage's steps use browser history, so its back and forward buttons move between screens; they never leave a change that is running.

**D-23 Compatibility check, 8 Nov 2026.** Only the SM-X133 is supported. The webpage refused any other model outright, with no way past it: earlier Decent tablets have different packages and may not run Decaid, and the page only knows the SM-X133 list. On an SM-X133 with untested firmware it warns and asks the person to accept, then runs with `--force`. No package-reading mode for other tablets: the owner chose not to build one. **Changed 9 Nov 2026 (owner):** another model now gets the same treatment as untested firmware, a warning and "I understand and want to go on", then `--force`. The risks are bounded: only listed packages the tablet has are disabled, the protected list still applies, undo works, and screen-driven finishing steps end as MANUAL with written instructions when they cannot run. A dry run no longer saves the original-state record, and the tablet reports an undo record only after a real change.

## Facts found while recording these

- Decadent on the home screen is a **Chrome pinned shortcut**, not an installed WebAPK: Chrome holds one
  pinned shortcut and no `org.chromium.webapk.*` package exists. Tested: it opens in Chrome's `WebappActivity`, with no
  address bar, even offline. The Android status and navigation bars stay visible.
- `com.samsung.android.app.updatecenter` is `AppUpdateCenter.apk` 3.8.03, a system app that holds a list screen and
  a wait-for-Wi-Fi receiver. Android firmware updates are a different package: `com.wssyncmldm` (`FotaAgent.apk`).
  So Update Center is not the OS updater. It appears to update Samsung's own apps (inferred from names, not documented).
  Moved to INVESTIGATE and off the protected list. `com.wssyncmldm` stays protected.
- Boot images (owner asked, for later): not changeable under the project rules. The "Samsung Galaxy / Powered by Android" image
  is `logo.jpg` in the `up_param` partition (XDA guides, mainly for Exynos; this tablet is MediaTek `mt8781`, not confirmed for it).
  `/system/media/bootsamsung.qmg` and `bootsamsungloop.qmg` are root-owned system files. The bootloader is locked. Every method found
  needs root or flashing, which permanently trips Knox. No locked-bootloader method was found.
  Sources: https://xdaforums.com/t/guide-how-to-get-custom-boot-logo-on-exynos-galaxy-devices.4708749/ · https://en.wikipedia.org/wiki/Bootloader_unlocking
- No Google or Samsung account is signed in on the tablet (`dumpsys account`, counts only). Play installs would need a sign-in.

**D-24 Finish steps run themselves, 9 Nov 2026.** The owner asked to cut the by-hand finish steps to what only a person can do. The webpage asks for two things: joining Wi-Fi (typed into the page, sent straight to the tablet, never stored, or joined on the tablet) and signing in to Google (the page opens the sign-in screen and notices when it is done, or the owner goes on without an account). Then `decent-setup.sh finish <step>` drives the tablet's screen over ADB with `uiautomator dump` and `input`: restart, remove Chrome, Play Store and Camera from Home, launcher grid 3 × 5 and drawer setting, Play updates for Chrome and WebView, Decadent install from Chrome, Decaid, Decadent and Settings onto Home, then open Decaid and Decadent. Logging in to Decadent stays with the owner. A step that cannot find its button prints `MANUAL` and the page shows that step's written instructions (owner approved this fallback). Screen-driving depends on English labels and current app layouts, so every finish step is Experimental until tested on a real tablet.

**D-25 Decaid is always the latest release, 16 Nov 2026.** The owner: "we want to offer the latest, just install latest in our installer." `manifests/apks.txt` names Decent's latest-release download instead of a pinned build. `scripts/setup.sh` reads the checksum from the release's `decaid-latest-SHA256SUMS.txt`. The webpage reads it from GitHub's API for the latest release (`latestApk` in `web/src/core.js`), names the version in the download link, and checks the chosen file before it installs anything. With no answer from GitHub it installs nothing. Fossify stays pinned. A tablet that already has Decaid is left as it is: Decaid offers its own updates. Not tested: an install of 0.9.2 through this project (the reference tablet already had Decaid).

**D-26 The Decadent plugin goes in through Decaid's own installer, 17 Nov 2026.** Decaid 0.9.2 lets no outside program install a plugin, so the finish step `plugin` (`fin_plugin` in `device/decent-setup.sh`) does what a person would: it opens Decaid, leaves the coffee screen with Android's Back key (nothing is sent to the espresso machine), then taps Plugins, the cog, Install plugin, GitHub Release, types `decadentcoffee/plugin` and taps Install. Decaid keeps the plugin updated from then on. It runs when Decadent is wanted and Decaid is on the tablet, and ends MANUAL with the same taps written out when a screen is not the expected one (a Decaid that has never been opened shows its first-run questions, which are the owner's to answer). Verified on the reference tablet with Decaid 0.9.2 (38 s, Decaid answered "Plugin installed", an existing link to a Decadent account was kept). Not tested: a Decaid installed minutes earlier by this project, and the webpage's own run of the step (only the script was run, over adb).

**D-27 Decaid's first questions are a pause, and the written instructions are always there, 18 Nov 2026.** The owner: falling back to written instructions is the wrong answer to a Decaid that has never been opened; the written instructions are a second way that is always on offer, for people who would rather do it themselves. So: (1) `finish decaid [open]` reports `ready`, `asking` or `absent`. `asking` is anything that is not Decaid's menu: its Welcome, account, permission and import screens, or an Android dialog over them. The script answers none of them. The webpage shows "Decaid needs you on the tablet", asks again every few seconds for up to 15 minutes, and runs `finish plugin` by itself once Decaid's menu shows; "Skip the plugin for now" ends the wait. (2) The plugin step now runs first after the restart, so the one step that may need the owner comes early. (3) Decaid looks for the machine on every start. The script gives it 12 seconds, then leaves that screen with Decaid's own "Continue to Dashboard" button, and leaves the coffee screen with Back. Neither sends anything to the espresso machine; a Decaid the owner has allowed to use Bluetooth connects to the machine by itself, as it does on every start. (4) The page offers the by-hand way in two places that are always visible: "Rather set Decadent up by hand?" on Before you start (Decaid, the plugin, the app, and the full written guide), and "Rather do a step yourself?" under the last steps. A step the tablet does not allow still lists its own instructions under Left for you. Screen labels for the first-run and scan screens come from Decaid 0.9.2's source. Tested on the simulated tablet and in the page's safe mode; not run on a real tablet with a new Decaid.

**D-28 The plugin step also switches the plugin on, 18 Nov 2026.** Run on the owner's tablet with the Decadent plugin removed first. Two things were wrong and are fixed. (1) Decaid's coffee screen is a web view whose own buttons show in the screen read; `decaid_where` took those buttons for Decaid's first questions, so the step would have waited for an owner who had nothing to answer. A web view is now the coffee screen, whatever it holds. (2) Decaid adds a plugin from a GitHub release switched off and not set to start with Decaid; Load in its menu starts it for that run only. `plugin_on` now taps Load and switches on Auto-load on startup, and reads the switch back before it says `DONE`. When it cannot, the step ends `MANUAL finish plugin it is installed but switched off`, and the written steps name both taps. Neither sends anything to the espresso machine: the machine stayed asleep through every run.
