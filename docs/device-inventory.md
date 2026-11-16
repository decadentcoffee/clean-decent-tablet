# Device inventory

Collected with `scripts/inventory.sh` (read-only) on 3 Nov 2026, run `inventory-20261103T121837Z`.
Raw outputs stay in `logs/` (gitignored). This file holds no serial number, Android ID, MAC address,
account name or user name. Status of every fact here: **Verified** (read from the device), unless marked.

## Device

| Item | Value | Source |
|---|---|---|
| Manufacturer | samsung | `ro.product.manufacturer` |
| Model number | SM-X133 | `ro.product.model` |
| Device / product | gta11wifi / gta11wifidx | `ro.product.device`, `ro.product.name` |
| Android | 16 (SDK 36) | `ro.build.version.release`, `.sdk` |
| One UI | 8.0 (`80000`) | `ro.build.version.oneui` |
| Firmware (PDA) | X133DXS4BZB6 | `ro.build.PDA` |
| Build | BP2A.250605.031.A3.X133DXS4BZB6 | `ro.build.display.id` |
| Fingerprint | samsung/gta11wifidx/gta11wifi:16/BP2A.250605.031.A3/X133DXS4BZB6_OZS4BZB6:user/release-keys | `ro.build.fingerprint` |
| Security patch | 2026-02-05 | `ro.build.version.security_patch` |
| Region code (CSC) | TGY | `ro.csc.sales_code` |
| CPU ABI | arm64-v8a | `ro.product.cpu.abi` |
| Boot state | verified boot green, bootloader locked, user build | `ro.boot.*`, `ro.debuggable=0` |
| Storage (/data) | 45 GB, 34 GB free | `df -h /data` |
| Memory | 3.7 GB total, 1.8 GB available at capture | `/proc/meminfo` |

## Users and management

| Item | Value |
|---|---|
| Android users | one: user 0, running |
| Current (foreground) user | 0 (`am get-current-user`) |
| Device owner / profile owner | none (`dpm list-owners` → "no owners") |
| Already disabled before us | `com.mygalaxy.service`, `com.samsung.android.knox.zt.framework`, `com.google.android.gms.supervision` |

The three packages above were disabled before this project touched the tablet. Rollback must leave them disabled.

## Defaults

| Item | Value |
|---|---|
| Home (launcher) | Samsung One UI Home `com.sec.android.app.launcher`; fallback `com.android.settings/.FallbackHome` |
| Default browser | Samsung Internet `com.sec.android.app.sbrowser` 28.0.5.9 |
| Keyboard | Samsung Keyboard `com.samsung.android.honeyboard` (Google voice input also enabled) |
| Screen timeout | `2147483646` ms, which means "never" |
| Stay awake while charging | `15` (on for AC, USB, wireless and dock) |
| Double-tap to wake | on (`system double_tab_to_wake_up=1`, `secure double_tap_to_wake=1`) |
| Lock screen | none: `CredentialType: NONE`, `IsLockScreenDisabled: true` (`dumpsys lock_settings`) |
| Rotation | auto-rotate off, fixed rotation 3 (landscape) |
| Navigation | 3-button bar (`navigation_mode=0`) |
| Wi-Fi / Bluetooth | both on; Wi-Fi sleep policy `2` (never sleep) |

## Decent and coffee apps

| Package | Version | What it is | Notes |
|---|---|---|---|
| `net.tadel.reaprime` | 0.9.1 (0.9.2 since 16 Nov 2026) | Decaid (Decent's newer app) | Installed by the owner from the APK on 3 Nov 2026, then updated inside Decaid. Grants: Bluetooth scan/connect, notifications, connected-device foreground service, boot completed. Not running at capture. |
| `tk.tcl.wish` | 1.0 | AndroWish, runtime of the original Decent app | Home shortcuts **Decent** and **Update Decent**. Installed 16 Feb 2026 without an installer record. Keep. |
| `hu.kavekalmar.sep` | 2.57.0 | SE Profiler (Smart Espresso Profiler) | Distributed by Decent; Home page 3 |
| `com.pressensor.coffeeflow` | 1.15 | Coffee Flow (Pressensor) | Distributed by Decent; Home page 3 |

## Browsers and PWA runtime

| Package | Version | Notes |
|---|---|---|
| Samsung Internet `com.sec.android.app.sbrowser` | 28.0.5.9 | Default browser; installed as a user-updatable app |
| Chrome `com.android.chrome` | 154.0.8037.92 | Installed and enabled, but did not answer the browser intent query. Not yet explained. |
| Android System WebView `com.google.android.webview` | 153.0.8010.36 | Protect |
| Google Play services `com.google.android.gms` | 26.34.36 | Protect until dependencies are known |

**Decadent: a Chrome pinned shortcut on the home screen**, not an installed WebAPK. Chrome holds one pinned shortcut; no `org.chromium.webapk.*` package exists. (The first pass missed it: `dumpsys shortcut` hides labels.)

## Package counts (user 0)

| List | Count |
|---|---|
| All installed | 368 |
| System | 340 |
| Third-party | 28 |
| Enabled | 365 |
| Disabled | 3 |

Third-party list at capture: Netflix, Outlook, Microsoft 365 (officehubrow), YouTube Music, Google Drive (docs),
Google TV (videos), Spotify, Samsung Shop (ecomm), Samsung Calendar, Samsung Health, Calculator, Clock,
Samsung Members (voc), Galaxy continuity, SmartThings Find, Samsung Notes, Voice Recorder, Samsung Global Goals (sree),
Samsung Free (spage), Game Hub, Kids Home, a screen recorder (`com.hecorat.screenrecorder.free`),
a file manager (`com.alphainventor.filemanager`), Decaid, AndroWish and the two coffee apps above. Owner decisions about these: `docs/decisions.md`.
Names come from the package identifiers. Classification happens in `config/packages.yaml`, not here.

## Limits

- A package inventory is not a backup. It records which apps exist and their state, not app data,
  settings inside apps, accounts or files.
- Facts above describe one tablet on one firmware. They are not a claim about other SM-X133 units or other firmware.
