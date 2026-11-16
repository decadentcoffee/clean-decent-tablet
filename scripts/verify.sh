#!/usr/bin/env bash
# Read-only health check after any change. Prints PASS / FAIL / INFO per check; exits 1 on any FAIL.
# Covers what ADB can see. The manual checks (tap Home, open the drawer, type, wake) are in docs/debloating.md.
# Usage: scripts/verify.sh [--serial <id>]
source "$(dirname "$0")/lib.sh"
SER=""; [ "${1:-}" = --serial ] && SER="$2"
select_device "$SER"
USER_ID="$(current_user)"
fails=0
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; fails=$((fails+1)); }
info() { echo "INFO  $*"; }
must_enabled() { # package label
  local s; s="$(pkg_state "$1")"
  [ "$s" = enabled ] && pass "$2 enabled ($1)" || fail "$2 is $s ($1)"
}

info "device $(device_id), Android $(prop ro.build.version.release), user $USER_ID"
for p in "com.android.systemui:System UI" "com.android.settings:Settings" "com.android.bluetooth:Bluetooth" \
         "com.google.android.webview:WebView" "com.google.android.packageinstaller:Package installer" \
         "com.google.android.permissioncontroller:Permission controller" "com.android.shell:Shell (ADB)" \
         "com.sec.android.app.launcher:One UI Home (fallback)" "com.android.chrome:Chrome" \
         "net.tadel.reaprime:Decaid" "tk.tcl.wish:AndroWish (original Decent app)"; do
  must_enabled "${p%%:*}" "${p#*:}"
done

home="$(home_pkg)"; [ -n "$home" ] && [ "$(pkg_state "$home")" = enabled ] && pass "Home app $home" || fail "no enabled Home app (holder: '$home')"
ime="$(ime_pkg)";   [ -n "$ime" ]  && [ "$(pkg_state "$ime")" = enabled ]  && pass "keyboard $ime"  || fail "default keyboard '$ime' is not enabled"
info "browser role: $(sh_ cmd role get-role-holders --user "$USER_ID" android.app.role.BROWSER | head -1)"
[ "$(sh_ settings get global wifi_on)" != 0 ] && pass "Wi-Fi on" || fail "Wi-Fi off"
[ "$(sh_ settings get global bluetooth_on)" = 1 ] && pass "Bluetooth on" || fail "Bluetooth off"
net="$(sh_ dumpsys connectivity | awk -F': ' '/Active default network/ && !n {print $2; n=1}')" || net=""
[ -n "$net" ] && [ "$net" != none ] && pass "connected to a network (Android reports an active default network)" || fail "no active network: Wi-Fi is on but not connected"

# Decaid's boot receiver starts its process for a few seconds at boot, so a pid alone proves nothing. Ask the port.
# The tablet has no curl: forward the port and test it from this computer. Any HTTP status counts as an answer.
"${ADB[@]}" forward tcp:18080 tcp:8080 >/dev/null
code="$(curl -s -m 4 -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/ || true)"
"${ADB[@]}" forward --remove tcp:18080 >/dev/null 2>&1 || true
if [ "$code" != 000 ] && [ -n "$code" ]; then
  pass "Decaid API port 8080 answers (HTTP $code)"
elif sh_ dumpsys activity services net.tadel.reaprime | grep -q 'flutter_foreground_task'; then
  fail "Decaid service is running but port 8080 does not answer"
else
  info "Decaid not running (start it before testing Decadent)"
fi

# Approved disables are actually disabled.
while IFS=$'\t' read -r pkg batch orig; do
  [ -n "$pkg" ] || continue
  s="$(pkg_state "$pkg")"
  [ "$s" = enabled ] && info "approved for batch $batch but still enabled: $pkg"
done < <(approved_rows)

info "screen timeout $(sh_ settings get system screen_off_timeout) ms, stay-on-while-plugged $(sh_ settings get global stay_on_while_plugged_in), double-tap wake $(sh_ settings get system double_tab_to_wake_up)"
[ $fails = 0 ] && echo "ALL AUTOMATIC CHECKS PASSED" || { echo "$fails CHECK(S) FAILED"; exit 1; }
