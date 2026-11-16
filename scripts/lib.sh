# Shared helpers for clean-decent-tablet scripts. Source, do not run.
# shellcheck shell=bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS="$ROOT/logs"

die() { echo "error: $*" >&2; exit 1; }

# Pick exactly one authorised device. Honour ANDROID_SERIAL or --serial.
# Sets ADB=(adb -s <serial>) and SERIAL.
select_device() {
  command -v adb >/dev/null || die "adb not found. Install Android platform tools first (docs/installation.md)."
  local want="${1:-${ANDROID_SERIAL:-}}"
  local lines
  lines="$(adb devices | awk 'NR>1 && NF>=2 {print $1" "$2}')"
  [ -n "$lines" ] || die "no device found. Check the USB cable and that USB debugging is on."
  if [ -n "$want" ]; then
    echo "$lines" | grep -q "^$want " || die "device $want is not connected."
    SERIAL="$want"
  else
    local n
    n="$(echo "$lines" | wc -l | tr -d ' ')"
    [ "$n" = 1 ] || die "$n devices connected. Pick one with --serial <id> or ANDROID_SERIAL."
    SERIAL="${lines%% *}"
  fi
  local state
  state="$(echo "$lines" | awk -v s="$SERIAL" '$1==s {print $2}')"
  case "$state" in
    device) ;;
    unauthorized) die "the tablet has not authorised this computer. Unlock it and tap Allow on the USB debugging prompt." ;;
    *) die "device state is '$state', expected 'device'." ;;
  esac
  ADB=(adb -s "$SERIAL")
}

sh_() { "${ADB[@]}" shell "$@" </dev/null | tr -d '\r'; }
prop() { sh_ getprop "$1"; }

# The foreground Android user. Never assume 0.
current_user() { sh_ am get-current-user; }

# Strip values that identify one physical device or person.
redact() {
  sed -E \
    -e "s/${SERIAL:-__no_serial__}/<serial>/g" \
    -e 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g' \
    -e 's/(android_id|bluetooth_address|bluetooth_name|device_name|ro\.serialno|ro\.boot\.serialno)([=: ]+).*/\1\2<redacted>/I'
}

stamp() { date -u +%Y%m%dT%H%M%SZ; }

MANIFEST="${DT_MANIFEST:-$ROOT/manifests/packages.csv}"
CHANGELOG="$LOGS/changes.tsv"   # append-only; private (logs/ is gitignored)
EXPECT_FILE="$ROOT/manifests/device.expect"

# Packages the scripts never disable, whatever the manifest says.
PROTECTED="android com.android.systemui com.android.settings com.android.bluetooth
com.sec.android.app.bluetoothagent com.google.android.webview com.google.android.packageinstaller
com.google.android.permissioncontroller com.android.shell com.android.providers.settings
com.google.android.gms com.google.android.gsf com.android.vending com.android.chrome
com.sec.android.app.launcher com.samsung.android.honeyboard net.tadel.reaprime tk.tcl.wish
hu.kavekalmar.sep com.pressensor.coffeeflow com.alphainventor.filemanager com.hecorat.screenrecorder.free
com.wssyncmldm com.android.phone com.google.android.networkstack
com.samsung.android.networkstack com.android.wifi.resources com.samsung.android.wifi.resources"

is_protected() {
  local p="$1" w
  for w in $PROTECTED; do [ "$w" = "$p" ] && return 0; done
  # The live Home app and keyboard are protected too, whatever they are now.
  [ "$p" = "$(home_pkg)" ] && return 0
  [ "$p" = "$(ime_pkg)" ] && return 0
  return 1
}
home_pkg() { sh_ cmd role get-role-holders --user "$USER_ID" android.app.role.HOME | head -1; }
ime_pkg()  { sh_ settings get secure default_input_method | cut -d/ -f1; }

# enabled | disabled | absent, for the current user.
pkg_state() {
  local p="$1"
  if ! sh_ pm list packages --user "$USER_ID" | grep -qx "package:$p"; then echo absent; return; fi
  if sh_ pm list packages -d --user "$USER_ID" | grep -qx "package:$p"; then echo disabled; else echo enabled; fi
}

device_id() { echo "$(prop ro.product.model) $(prop ro.build.PDA)"; }

# Refuse to change a device whose model/build differs from manifests/device.expect.
check_expected_device() {
  local want have
  [ -f "$EXPECT_FILE" ] || die "missing $EXPECT_FILE"
  have="$(device_id)"
  grep -v '^#' "$EXPECT_FILE" | grep -qxF "$have" || die "device is '$have', which manifests/device.expect does not list. Review the manifest for this build first."
  want="$have"
}

# Short, non-reversible tag for the device in private logs (never the raw serial).
serial_tag() { printf '%s' "$SERIAL" | shasum -a 256 | cut -c1-8; }

log_change() { # action package before after result
  [ -f "$CHANGELOG" ] || printf 'utc\tdevice_tag\tmodel_build\tuser\taction\tpackage\tbefore\tafter\tresult\n' > "$CHANGELOG"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(stamp)" "$(serial_tag)" "$(device_id)" "$USER_ID" "$1" "$2" "$3" "$4" "$5" >> "$CHANGELOG"
}

# Print "package<TAB>batch<TAB>original_state" for approved disable rows.
approved_rows() {
  python3 -I - "$MANIFEST" <<'PY'
import csv, sys
for r in csv.DictReader(open(sys.argv[1])):
    if r["proposed_action"] == "disable" and r["approval"] == "approved":
        print(r["package"], r["batch"], r["original_state"], sep="\t")
PY
}
