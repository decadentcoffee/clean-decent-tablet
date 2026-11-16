#!/usr/bin/env bash
# Read-only inventory of a connected Android tablet.
# Writes logs/inventory-<UTC stamp>/ and changes nothing on the device.
# Usage: scripts/inventory.sh [--serial <id>]
source "$(dirname "$0")/lib.sh"

SER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --serial) SER="$2"; shift 2 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done
select_device "$SER"

OUT="$LOGS/inventory-$(stamp)"
mkdir -p "$OUT"
cap() { local f="$1"; shift; sh_ "$@" 2>&1 | redact > "$OUT/$f" || true; }

USER_ID="$(current_user)"

# Identity of the build (no unique identifiers).
{
  for p in ro.product.manufacturer ro.product.brand ro.product.model ro.product.name ro.product.device \
           ro.build.version.release ro.build.version.sdk ro.build.version.security_patch \
           ro.build.fingerprint ro.build.display.id ro.build.PDA ro.build.version.oneui \
           ro.build.version.sem_platform_int ro.csc.sales_code ro.product.cpu.abi \
           ro.config.knox ro.boot.verifiedbootstate ro.boot.flash.locked ro.debuggable; do
    echo "$p=$(prop "$p")"
  done
  echo "current_user=$USER_ID"
} | redact > "$OUT/device.txt"

# Users: keep ids and flags only, drop the names people gave them.
sh_ pm list users | sed -E 's/UserInfo\{([0-9]+):[^:]*:([0-9a-fx]+)\}/UserInfo{\1:<name>:\2}/' > "$OUT/users.txt"

# Package state (the baseline that debloat/rollback compare against).
cap packages-all-paths.txt   pm list packages -f --user "$USER_ID"
cap packages-third-party.txt pm list packages -3 --user "$USER_ID"
cap packages-system.txt      pm list packages -s --user "$USER_ID"
cap packages-disabled.txt    pm list packages -d --user "$USER_ID"
cap packages-enabled.txt     pm list packages -e --user "$USER_ID"
cap packages-uninstalled-for-user.txt pm list packages -u --user "$USER_ID"
cap packages-versions.txt    pm list packages --show-versioncode --user "$USER_ID"

# Defaults that matter for this project.
{
  echo "home=$(sh_ cmd package resolve-activity --brief --user "$USER_ID" -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1)"
  echo "browser=$(sh_ cmd package resolve-activity --brief --user "$USER_ID" -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d https://example.com | tail -1)"
  echo "default_input_method=$(sh_ settings get secure default_input_method)"
  echo "screen_off_timeout_ms=$(sh_ settings get system screen_off_timeout)"
  echo "stay_on_while_plugged_in=$(sh_ settings get global stay_on_while_plugged_in)"
  echo "screen_brightness_mode=$(sh_ settings get system screen_brightness_mode)"
  echo "accelerometer_rotation=$(sh_ settings get system accelerometer_rotation)"
  echo "user_rotation=$(sh_ settings get system user_rotation)"
  echo "double_tap_to_wake(system double_tab_to_wake_up)=$(sh_ settings get system double_tab_to_wake_up)"
  echo "double_tap_to_wake(secure double_tap_to_wake)=$(sh_ settings get secure double_tap_to_wake)"
  echo "lockscreen_disabled=$(sh_ settings get secure lockscreen.disabled)"
  echo "wifi_sleep_policy=$(sh_ settings get global wifi_sleep_policy)"
  echo "bluetooth_on=$(sh_ settings get global bluetooth_on)"
  echo "wifi_on=$(sh_ settings get global wifi_on)"
  echo "adaptive_battery=$(sh_ settings get global adaptive_battery_management_enabled)"
  echo "navigation_mode=$(sh_ settings get secure navigation_mode)"
} | redact > "$OUT/defaults.txt"
cap browsers.txt   cmd package query-activities --brief --user "$USER_ID" -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d https://example.com
cap launchers.txt  cmd package query-activities --brief --user "$USER_ID" -a android.intent.action.MAIN -c android.intent.category.HOME
cap keyboards.txt  ime list -a -s
cap deviceidle-whitelist.txt dumpsys deviceidle whitelist

# Device management: owners only, not the full policy dump.
cap device-owners.txt dpm list-owners

# Resources.
cap storage.txt df -h /data
sh_ head -3 /proc/meminfo > "$OUT/memory.txt"

# Raw settings tables, redacted. Kept in logs/ only (gitignored).
cap settings-system.txt settings list system
cap settings-secure.txt settings list secure
cap settings-global.txt settings list global

echo "$OUT"
