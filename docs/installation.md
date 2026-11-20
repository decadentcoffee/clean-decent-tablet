# Setup guide: Decent tablet as a quiet espresso controller

This is the full manual walk-through. It reproduces the reference tablet exactly.

**Two options, either or both.** **Clean up** is steps 3–5 and the Samsung Internet part of step 9: apps disabled, Chrome as browser, sleep after 10 minutes. **New Home screen** is step 7 and the rest of step 9: Fossify, three icons, swipe gestures and no side panel.

**Quicker routes:** `scripts/setup.sh` does the automatic part of both (`--cleanup` or `--home` for one), the webpage in `web/` does the same with no terminal, and `docs/AGENT_RUNBOOK.md` is for an AI agent. All can undo.

**Tested on one tablet only:** Samsung SM-X133, Android 16, set up on One UI 8.0 (X133DXS4BZB6), then upgraded to One UI 8.5 (X133DXS5BZI3), 3–4 Nov 2026.
A fresh setup that starts on 8.5 is not tested.
On any other model or firmware, treat every step as untested. Each step says if it is not verified. `docs/compatibility.md` has the full results.

**You end up with:**

| Area | Result |
|---|---|
| Home screen | Fossify Launcher: three very large icons in one row on the existing wallpaper: Decaid, Decadent, Settings |
| Browser | Chrome is the default; Samsung Internet is disabled |
| Apps | Decent's five apps are all kept; 100 factory apps and agents are disabled, not deleted (one of those only exists on One UI 8.5, another only on 8.0) |
| Screen | Sleeps after 10 minutes, no lock screen, wakes to the last app |
| Decadent | A real installed app in true fullscreen, with no Android bars |
| Navigation | Swipe gestures: swipe up from the bottom edge to leave Decadent |
| Network | Wi-Fi on a separate IoT network |

**Not changed:** no root, no bootloader unlock, no custom firmware, no factory reset. Bluetooth, Wi-Fi, Settings, the keyboard and firmware updates stay on.

**You need:** a computer (tested on macOS 26), a USB data cable, and about an hour.

## Before you start

- A package list is **not a backup**. It does not save app data, settings or files.
- A factory reset gives you Samsung's setup, **not** Decent's. Avoid it. See `docs/recovery.md`.
- Keep Wi-Fi off until step 5, so the disabled apps never get a chance to run.
- Keep the DE1 off until step 11.

## 1. Install ADB on the computer

ADB (Android Debug Bridge) is Google's command-line tool for talking to an Android device over USB.

```sh
brew install --cask android-platform-tools
adb version
```

Expected: `Android Debug Bridge version 1.0.41`.

**If `adb version` prints nothing and never returns** (seen on macOS 26 with 37.0.1): macOS appears to be stuck checking the downloaded file. Run this, put `~/.local/bin` first in your `PATH`, and try again. Repeat it after `brew upgrade`.

```sh
mkdir -p ~/.local/bin && cat "$(brew --prefix)/Caskroom/android-platform-tools/"*/platform-tools/adb > ~/.local/bin/adb && chmod +x ~/.local/bin/adb
```

Other systems (not tested): https://developer.android.com/tools/releases/platform-tools

## 2. Connect the tablet

1. Open **Settings → About tablet → Software information**.
2. Tap **Build number** seven times.
3. Open **Settings → Developer options** and turn on **USB debugging**.
4. Plug the tablet into the computer and unlock it.
5. On **Allow USB debugging?**, tick **Always allow from this computer** and tap **Allow**.

```sh
adb devices -l
```

Expected: one line ending in `device ... model:SM_X133 ...`. `unauthorized` means step 5 is not done. If no prompt appears, replug the cable.

## 3. Save the original state

From this repository's folder:

```sh
scripts/inventory.sh
scripts/verify.sh
```

`inventory.sh` only reads, and writes a timestamped folder under `logs/`. Keep the first one. `verify.sh` will report no network, which is expected here.

**On a different model or firmware**, also do this before any change:
1. Copy the first snapshot's disabled list to `manifests/original-disabled.<model>.<build>.txt`.
2. Compare the installed packages with `docs/packages.md`.
3. Change `manifests/device.expect` only after you have reviewed the list. The scripts refuse a tablet that differs from this file.

## 4. Disable the apps

Read `docs/packages.md` first. It lists every package and why. To keep an app, set its `approval` to anything other than `approved` in `manifests/packages.csv`.

`scripts/lib.sh` refuses to disable protected packages: Decent's apps, Decaid, Chrome, the keyboard, Settings, Bluetooth, Wi-Fi and firmware updates, among others.

Preview one batch, then apply it:

```sh
scripts/disable.sh --batch 1
scripts/disable.sh --batch 1 --apply
```

Type `yes`. Do this for batches **1, 2, 4, 5, 6, 8 and 9**. Leave batch 3 for step 9. After each batch:

1. Let the script finish. It waits 30 seconds. **Do not reboot before that:** an early reboot brought back the last 5 of 24 packages in our test.
2. Run `scripts/verify.sh`. The only failure should be no network.
3. Reboot with `adb reboot`, then check Home, the app drawer, Settings and that the keyboard appears.
4. If something breaks, undo the batch: `scripts/rollback.sh --batch <n> --apply`.

Android refuses to disable Find My Mobile and Samsung account on this build, so they are not in the batches. Details: `docs/debloating.md`.

## 5. Settings

```sh
scripts/settings.sh
scripts/settings.sh --apply
```

This makes the screen sleep after 10 minutes (verified), turns off stay-awake-while-charging, makes Chrome the default browser, and removes Samsung's Edge panel handle from the side of the screen.

On the tablet, choose **Settings → Display → Navigation bar → Swipe gestures**. Then run `scripts/settings.sh --apply` again if the thin line at the bottom still shows.

| Gesture | Action |
|---|---|
| Swipe up from the bottom edge | Home (verified) |
| Swipe in from a side edge | Back (standard Android gesture; not confirmed here) |

**Known flaw:** on the Home screen, a swipe from the very bottom edge shows a brief preview and does nothing else. Samsung's recent-apps screen opens and closes at once. Inside an app the swipe works.

Double-tap to wake is already on. Rotation: the reference tablet shipped locked to landscape; the owner keeps auto-rotate on. Reference tablet: no screen lock is set. Leave it that way only if you are happy for anyone at the machine to use the tablet.

Now join Wi-Fi: **Settings → Connections → Wi-Fi**.

**Use an IoT or guest network, not your main one.** Decadent works through the cloud and through `localhost`, so it needs no local access. Decaid's web server on port 8080 has no password and accepts requests from any website, so keep it away from your own computers. The network must allow outbound internet. Turn on client isolation if you have it.

## 6. Decaid

Install Decent's latest release of Decaid, `net.tadel.reaprime`. The reference tablet runs 0.9.2 (updated inside Decaid on 16 Nov 2026).

1. Download `decaid-android-latest.apk` from https://github.com/decentespresso/decaid/releases/latest. Check it against `decaid-latest-SHA256SUMS.txt` on the same page.
2. Install it: `adb install decaid-android-latest.apk`.
3. Open Decaid. Allow **Nearby devices** and **Notifications**.

**Never swipe Decaid out of the recent-apps list.** That stops its service, and Decadent loses the machine.

## 7. Fossify Launcher

Fossify Launcher is open source (GPLv3). This setup uses the GitHub build, because Google Play needs a signed-in account. It holds no internet permission on the reference tablet.

1. Download `launcher-16-foss-release.apk` from https://github.com/FossifyOrg/Launcher/releases/tag/1.10.0.
2. Check it. The result must be `a603d3d510482feafd73d52a93a1ea9baefd2ca0aae329a14cbf0e21f43638e3`:
   ```sh
   shasum -a 256 launcher-16-foss-release.apk
   ```
3. Install it and make it Home:
   ```sh
   adb install launcher-16-foss-release.apk
   adb shell cmd role add-role-holder --user 0 android.app.role.HOME org.fossify.home
   ```
4. Press Home. You see the browser (Chrome, or Internet when Clean up did not run), Play Store and Camera along the bottom.
5. Long-press each of those three and tap **Remove**. The apps stay installed.
6. Long-press empty space, tap **Launcher Settings**, and set:

| Setting | Value |
|---|---|
| Show a search bar | On |
| Automatically show keyboard in drawer | Off |
| Close app drawer on opening an app | On |
| Show app labels | On |
| Home screen: Row count | **3** |
| Home screen: Column count | **5** |

7. Press Home. Swipe up from low on the screen to open the app list.
8. Touch and hold **Decaid**, then drag it to the second cell of the middle row. Do the same with **Settings** to the fourth cell. The third cell is for Decadent, in step 9.

The standard Home screen is Decaid, Decadent and Settings. Everything else, YouTube and Decent's other apps included, stays in the app list. **Why five columns:** Fossify centres each label across the whole cell but draws the icon in a square at the cell's left. In landscape, cells wider than tall push labels right of their icons. With 5 columns × 3 rows the cells are nearly square, so labels line up. **Set the column count before placing icons:** fewer columns hides icons that sat in the removed ones, and they come back if you add columns again. Verified 8 Nov 2026 on the reference tablet.

Tap the search bar to find an app that is further down the list. To put any other app on Home, touch and hold it in the app list and drag it to an empty space. Nothing that came with the tablet is uninstalled.

To go back to Samsung's Home: `adb shell cmd role add-role-holder --user 0 android.app.role.HOME com.sec.android.app.launcher`

**The original Decent app on the new Home.** On a tablet with no Decaid, the setup page puts **Decent**, Coffee Flow and SE Profiler on the first page, and **Update Decent** and Settings on the second (D-38, D-40). Those two icons are shortcuts that only the page can add: by hand, switch Home back to One UI Home to use them. With Decaid on the tablet, **Decent** alone goes on the second page, between SE Profiler and Coffee Flow (D-42). AndroWish in the app list opens no app by itself, so that icon is the only way to the original app.

**Keep One UI Home installed and enabled.** Samsung's recent-apps screen comes from it, even with another launcher as Home.

Other launchers tried: `docs/launcher.md`.

## 8. A Google account (recommended)

Why keep one on a cleaned-up tablet: the aim is to switch off what the DE1 does not need while keeping updates and security. Chrome is the one browser kept, because Android already builds on Google's WebView and Play services, so it adds no new company; Samsung Internet would add another. A Google account is what lets the Play Store keep Chrome and WebView updated, just as Samsung's firmware updater is kept for Android security patches.

Google Play needs an account to update Chrome and WebView, and to build Decadent as a real app. That real app is what gives true fullscreen. Without any account everything still works, but Chrome may not update and Decadent keeps its bars.

**If an account is already signed in,** keep it and go to step 3 below.

**If not, add one made only for this tablet, not your personal one.** Signing in gives the tablet's apps standing access to the account, and this tablet has no lock.

1. Sign in under **Settings → Accounts and backup → Manage accounts → Add account → Google**, or from the Play Store.
2. Do not sign in to Chrome, and do not turn on sync.
3. In the Play Store, update Chrome and Android System WebView.

**Verified 4 Nov 2026:** Chrome went from 154 to 156 and WebView from 153 to 156 this way.

## 9. Decadent (optional)

Skip this step if you do not use Decadent. The Home screen works with any apps: put whatever you use in its place.

1. Open Chrome and go to `https://decadentcoffee.app/app/`.
2. Tap the install icon in the address bar, then **Install**, once. Wait about 15 seconds. A second install adds a second icon. To remove a spare, long-press it and tap **Remove**.
3. Swipe up from the middle of the Home screen, and find **Decadent** in the app list. Search for it if needed.
4. Touch and hold it, then drag it to the third cell of the middle row.
5. Open it and log in.
6. Check that the whole screen is Decadent, with no bars. Then disable Samsung Internet:

```sh
scripts/disable.sh --batch 3
scripts/disable.sh --batch 3 --apply
```

**Verified 4 Nov 2026:** both bars are gone (`display-mode: fullscreen`, 601 CSS px tall against 523 before), with no tap and no message. It stays through sleep, wake and a reboot. One swipe up from the bottom edge goes to Home, and the bars come back outside Decadent.

**Without a Google account** Chrome makes a shortcut instead (Play logs `WebAPK service unknown_account`). It works, but both bars stay and a strip shows at the bottom.

## 10. Firmware updates

**Settings → Software update → Download and install** works with this setup. **That button starts downloading at once; it is not only a check.** Once the download ends, tap **Install**. **Auto download over Wi-Fi** is on by default.

An OS upgrade cannot be undone.

**Tested 4 Nov 2026:** X133DXS4BZB6 (patch 2026-02-05) to X133DXS5BZI3 (One UI 8.5, patch 2026-08-05), about a 2 GB download.
- Nothing this project disabled came back on, and the disabled total stayed at 101.
- The Home app, Chrome as default, the sleep settings and swipe gestures all stayed.
- Decadent still opened.
- It added 12 packages, including Gemini (`com.google.android.apps.bard`), and removed 9. See `docs/packages.md`.

After any upgrade, run `scripts/verify.sh`, then `scripts/inventory.sh`, and look for new or re-enabled packages.

## 11. The DE1 (not tested yet)

Do this last. It has not been run on the reference tablet with these settings.

1. Turn on the DE1, with the tablet in Bluetooth range.
2. Open Decaid from Home. Let it find the machine. If it does not, tap **Scan Again**.
3. Press Home and open Decadent. It should show the machine.

Phone control also needs the Decadent plugin inside Decaid. It is **not installed** on the reference tablet, and its install steps are not part of this guide yet.

## 12. Each cold boot

**Decaid does not stay running after a reboot.** Its boot receiver starts it for about 3.5 seconds, then it exits. So after a power cycle:

1. Open Decaid from Home.
2. Press Home.
3. Open Decadent.

Automating this is not done yet. Options are in `docs/startup.md`. An ordinary screen wake needs none of this.

## Check the result

```sh
scripts/verify.sh
```

Expected end: `ALL AUTOMATIC CHECKS PASSED`, with Wi-Fi on. By hand:

- [ ] Home shows Decaid, Decadent, Settings in one row, and each opens.
- [ ] Swiping up from low on the screen shows the app list with no keyboard.
- [ ] Decent's apps are all in the app list: AndroWish, AZ Screen Recorder, Coffee Flow, File Manager +, SE Profiler.
- [ ] Decadent opens with no address bar.
- [ ] The screen sleeps after 10 minutes idle.
- [ ] The power button wakes straight into the last app.
- [ ] A double-tap wakes the screen (verified). Single tap is not available.

## Undo everything

```sh
scripts/undo.sh --dry-run
scripts/undo.sh
```

It uses the record kept on the tablet, so it works from any computer. It re-enables only what this project disabled, restores the original Home app, browser and settings, and removes the apps this project added. Add `--keep-apps` to keep them. Packages that were already disabled stay disabled. Remove any Google account by hand. More: `docs/recovery.md`.

## Reference

| Document | What |
|---|---|
| `docs/packages.md` | Every package: disabled, kept and why |
| `manifests/packages.csv` | The same data, used by the scripts |
| `manifests/original-*.txt` | The original state of the reference tablet |
| `docs/compatibility.md` | What has been tested, with results |
| `docs/decisions.md` | Why each choice was made |

## Versions on the reference tablet, 4 Nov 2026

| App | Version | Source |
|---|---|---|
| Decaid `net.tadel.reaprime` | 0.9.1 (0.9.2 since 16 Nov 2026, updated inside Decaid) | GitHub APK |
| Fossify Launcher `org.fossify.home` | 1.10.0 | GitHub APK |
| Decadent `org.chromium.webapk.a45977050c6c6f69b_v2` | installed web app | Chrome and Google Play |
| Olauncher `app.olauncher` (backup, optional) | v6.9.17 | GitHub APK |
| One UI Home | 17.5.11.63 | Preinstalled, kept as a fallback |
| Chrome | 156.0.8078.79 | Google Play |
| Android System WebView | 156.0.8078.47 | Google Play |
| YouTube | 21.39.522 | Preinstalled |
| AndroWish `tk.tcl.wish` | 1.0 | Decent |
| SE Profiler `hu.kavekalmar.sep` | 2.57.0 | Decent |
| Coffee Flow `com.pressensor.coffeeflow` | 1.15 | Decent |
| File Manager + `com.alphainventor.filemanager` | 2.3.1 | Decent |
| AZ Screen Recorder `com.hecorat.screenrecorder.free` | 5.9.0 | Decent |
