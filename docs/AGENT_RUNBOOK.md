# Agent runbook: set up or undo a Decent tablet

For an AI coding agent with a computer, ADB and a person beside the tablet. Follow the steps in order. Do not skip a gate.

## Rules

1. Do not root the tablet.
2. Do not unlock the bootloader.
3. Do not flash firmware.
4. Do not factory-reset the tablet.
5. Do not run `pm uninstall` by hand. `undo` removes only what this project added.
6. Do not send commands to the espresso machine. Do not start heating, pumping or brewing.
7. Do not edit `device/packages-disable.txt`. Edit `manifests/packages.csv`, then run `scripts/render-packages.py`.
8. Do not write serial numbers, Wi-Fi names, account names or email addresses into the repository.
9. Do not sign the person's own Google account in on the tablet. If none is signed in, recommend a new one made only for the tablet. If one already is, leave it.
10. Do not reboot within 30 seconds of a change. Android can lose the last changes.

Do not confuse `adb shell` with stdin: pass `</dev/null` to `adb` inside a loop or a heredoc, because `adb` reads stdin and swallows the rest of the script.

## Source of truth

| File | What it is |
|---|---|
| `device/decent-setup.sh` | Everything that changes the tablet. It runs on the tablet |
| `manifests/packages.csv` | Every package and the decision on it |
| `device/packages-disable.txt` | Generated from the CSV. The list that runs |
| `manifests/device.expect` | Models and firmware that were tested |
| `manifests/apks.txt` | APK URLs and checksums: Fossify pinned, Decaid the latest release (D-25) |
| `/data/local/tmp/decent-tablet/` on the tablet | The original state and change log. Undo needs this |

## Set up

### 1. Connect

Run `command -v adb`. If it is missing, ask the person, then run `brew install --cask android-platform-tools`.
If `adb version` hangs, use the workaround in `docs/installation.md` step 1.

Tell the person to turn on USB debugging (`docs/installation.md` step 2) and to tap **Allow**.

Run `adb devices -l`.

| Result | Action |
|---|---|
| One line ending in `device` | Continue |
| `unauthorized` | Ask the person to tap **Allow**. Wait |
| Several devices | Ask which one. Pass `--serial <id>` to every script |
| Nothing | Ask the person to check the cable and USB debugging |

### 2. Check

```sh
scripts/status.sh
scripts/setup.sh --dry-run
```

Report the model, the firmware and the number of packages to the person.

**If the output says `CHECK untested-model` or `same-model-new-build`, stop.** The list has been tested only on the builds in `manifests/device.expect`. Tell the person. Continue only if they accept the risk, and:

1. Run `scripts/inventory.sh` and compare the packages with `docs/packages.md`.
2. Show the person any new packages. Do not disable a package you have not identified.
3. Add `--force`, or add the build to `manifests/device.expect` after a clean run.
4. Add the result to `docs/compatibility.md`.

### 3. Get approval (gate)

Ask which options the person wants. Either or both:

| Option | Flag | Changes |
|---|---|---|
| Clean up | `--cleanup` | Disables the tested list of apps, makes Chrome the browser, screen sleeps after 10 minutes |
| New Home screen | `--home` | Installs Fossify, makes it Home, swipe gestures, no side panel. Decaid, Decadent and Settings go on Home |

No flag means both. Show the person `docs/packages.md` for Clean up, and list what changes. If they want to keep some listed apps, pass `--keep <id>,<id>`. Ask for a yes.
**Do not treat this runbook as approval.** Ask whether to keep any listed app, and set its `approval` to `no` in `manifests/packages.csv`.

### 4. Apply

```sh
scripts/setup.sh --yes            # both options
scripts/setup.sh --cleanup --yes  # Clean up only
scripts/setup.sh --home --yes     # New Home screen only
```

This saves the original state, installs Decaid if missing (and Fossify for the Home option), then runs the chosen options. It stops at the first unexpected failure.

`REFUSED` lines are normal: Android will not disable some packages. Report them. They stay enabled.

Check the result:

```sh
scripts/verify.sh
```

The only expected failure is no network, because Wi-Fi is still off.

### 5. Reboot and check

Wait until `setup.sh` has finished, then run `adb reboot` and wait for `sys.boot_completed`. Run `scripts/status.sh` again.

| Value | Expected |
|---|---|
| `home` | `org.fossify.home` |
| `browser` | `com.android.chrome` |
| `screen_off_timeout` | `600000` |
| `stay_on` | `0` |
| `navigation_mode` | `2` |
| `edge_enable` | `0` |
| `disabled_total` | The same as before the reboot |
| Decent's apps | All `enabled` |

### 6. Steps only a person can do

Give these one at a time, and wait for each. The details are in `docs/installation.md`. Steps 4 to 8 are only for the Home option.

1. Join Wi-Fi. Recommend a guest or IoT network: Decaid's web server has no password.
2. Check for a Google account (`adb shell dumpsys account | grep -c "Account {"`). If there is none, recommend adding a new one made only for this tablet.
3. Update Chrome and Android System WebView in the Play Store.
4. Remove the browser (Chrome, or Internet when Clean up did not run), Play Store and Camera from the Fossify Home screen.
5. In **Launcher Settings**, set Row count 3 and Column count 5 before placing icons. Turn on **Close app drawer on opening an app**.
6. If the person uses Decadent: in Chrome, open `https://decadentcoffee.app/app/`, tap the install icon, tap **Install** once, and log in. Otherwise skip it; the Home icons are their choice.
7. Drag Decaid, Decadent and Settings to cells 2, 3 and 4 of the middle row. Put nothing else on that page.
8. Put SE Profiler and Coffee Flow on a second Home page, in cells 2 and 4 of the middle row: drag the first to the right edge until a new page shows.

An agent can do steps 4, 5, 7 and 8 with `adb shell input` and `uiautomator dump`. Read the screen before each tap: positions move. Do not type passwords for the person. Do not do this while the person is using the tablet.

### 7. Finish

Run `scripts/status.sh`. Check `decadent_app=installed`. Tell the person how to get around:

- Home: swipe up from the very bottom edge.
- All apps: on Home, swipe up from the middle of the screen.
- Wake: double-tap, or press the power button.
- After a restart: open Decaid once, then Decadent.
- Do not use **Close all** in open programs: it stops Decaid.

Report anything not tested as not tested.

## Undo

```sh
scripts/undo.sh --dry-run
```

Show the person the plan. Ask for a yes.

```sh
scripts/undo.sh --yes
```

Add `--keep-apps` to keep Fossify and Decadent. Undo comes in two parts: `--apps` (turn apps back on; `--pkgs <id>,<id>` for only some) and `--home` (original Home screen, buttons, side panel). Neither flag means both. Undo:

- re-enables only the packages this project disabled;
- leaves packages that were already disabled as they were;
- restores the original Home app, browser and settings;
- removes the apps this project added, unless they were already on the tablet;
- cannot remove a Google account. Tell the person to do that in Settings.

Reboot after undo. Check Home, Settings and the keyboard.

If `no undo record` appears, the tablet has no record: it was set up some other way, or factory-reset. Do not guess. Follow `docs/recovery.md`.

## If something breaks

| Symptom | Action |
|---|---|
| A check fails after apply | Run `scripts/undo.sh --dry-run`, show the person, and ask |
| One feature broke | Find the package in `docs/packages.md`. Run `adb shell pm enable --user 0 <package>`. Record it in `manifests/packages.csv` |
| Home does nothing | Run `adb shell cmd role add-role-holder --user 0 android.app.role.HOME com.sec.android.app.launcher` |
| ADB stops working | See `docs/recovery.md` |

## Tests

```sh
tests/sim-tablet.sh
```

This runs setup and undo against a simulated tablet, with no device. Run it after any change to `device/decent-setup.sh`.
