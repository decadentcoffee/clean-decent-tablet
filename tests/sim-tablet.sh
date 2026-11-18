#!/bin/bash
# Full setup and undo against a simulated tablet: stub pm, settings, cmd, am, getprop. Touches no real device.
# Usage: tests/sim-tablet.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/db" "$T/dev"
cp "$ROOT/device/decent-setup.sh" "$ROOT/device/packages-disable.txt" "$T/dev/"
printf 'SM-X133 X133DXS5BZI3\n' > "$T/dev/device.expect"
export SIM="$T/db" DECENT_DIR="$T/state" SETTLE_S=0 PATH="$T/bin:$PATH"

# Starting state: everything listed, plus Decent's apps and system apps; three already disabled by the vendor.
{ awk '!/^#/ {print $2}' "$T/dev/packages-disable.txt"
  printf '%s\n' com.mygalaxy.service com.google.android.gms.supervision com.samsung.android.knox.zt.framework tk.tcl.wish hu.kavekalmar.sep \
    com.pressensor.coffeeflow com.alphainventor.filemanager com.hecorat.screenrecorder.free net.tadel.reaprime com.android.chrome \
    com.sec.android.app.sbrowser com.sec.android.app.launcher com.samsung.android.honeyboard com.android.settings com.android.bluetooth \
    com.samsung.android.fmm org.fossify.home app.olauncher; } | sort -u > "$SIM/installed"
sed -i.b '/^com.sec.android.autodoodle.service$/d' "$SIM/installed" # one listed package is absent
printf '%s\n' com.mygalaxy.service com.google.android.gms.supervision com.samsung.android.knox.zt.framework > "$SIM/disabled"
cat > "$SIM/settings" <<S
system.screen_off_timeout=2147483646
global.stay_on_while_plugged_in=15
global.navigation_bar_gesture_hint=1
global.navigation_bar_gesture_while_hidden=0
secure.navigation_mode=0
secure.edge_enable=1
secure.default_input_method=com.samsung.android.honeyboard/.service.HoneyBoardService
S
printf 'com.sec.android.app.sbrowser\n' > "$SIM/role.browser"; printf 'com.sec.android.app.launcher\n' > "$SIM/role.home"
cp "$SIM/installed" "$SIM/installed.start"; cp "$SIM/disabled" "$SIM/disabled.start"; cp "$SIM/settings" "$SIM/settings.start"

cat > "$T/bin/getprop" <<'S'
#!/bin/bash
case "$1" in ro.product.model) echo SM-X133;; ro.build.PDA) echo "${SIM_BUILD:-X133DXS5BZI3}";; *) echo x;; esac
S
cat > "$T/bin/am" <<'S'
#!/bin/bash
[ "$1" = start ] || { echo 0; exit 0; }
a=""; d=""; while [ $# -gt 0 ]; do case "$1" in -a) a="$2"; shift ;; -d) d="$2"; shift ;; esac; shift; done
echo "am $a $d" >> "$SIM/events"; . "$(dirname "$0")/_simui"; go am "${d:-$a}"; echo "Starting: Intent { act=$a }"
S
# The screen: a fixture file per screen; input and am move between them by transitions.tsv. Home also drops
# removed icons and shows dropped ones. uiautomator writes the screen on one line, like the real one.
cat > "$T/bin/_simui" <<'S'
scr() { cat "$SIM/screen" 2>/dev/null || echo home; }
render() {
  s="$(scr)"; f="$FX/$s.xml"
  if [ "$s" = home ]; then
    grep -v '</hierarchy>' "$f" | if [ -s "$SIM/removed" ]; then grep -vF -f "$SIM/removed"; else cat; fi
    cat "$SIM/added" 2>/dev/null; echo '</hierarchy>'
  else sed -e "s/@ROWS@/$(cat "$SIM/fossify.rows" 2>/dev/null || echo 4)/" -e "s/@COLS@/$(cat "$SIM/fossify.cols" 2>/dev/null || echo 4)/" \
    -e "s/@CLOSE@/$([ "$(cat "$SIM/fossify.close" 2>/dev/null)" = on ] && echo true || echo false)/" "$f"; fi
}
hit() { # label of the smallest labelled node under x y, or -
  render | awk -v x="$1" -v y="$2" 'match($0, /bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"/) {
    b = substr($0, RSTART + 8, RLENGTH - 9); gsub(/\[|\]|,/, " ", b); split(b, a, " ")
    t = ""; if (match($0, / text="[^"]+"/)) t = substr($0, RSTART + 7, RLENGTH - 8)
    else if (match($0, /content-desc="[^"]+"/)) t = substr($0, RSTART + 14, RLENGTH - 15)
    if (t != "" && x >= a[1] && x < a[3] && y >= a[2] && y < a[4]) { ar = (a[3]-a[1]) * (a[4]-a[2]); if (best == "" || ar < bar) { best = t; bar = ar } } }
    END { print (best == "" ? "-" : best) }'
}
effect() { case "$1" in
  mark) echo "$2" > "$SIM/marked" ;;
  remove) echo "=\"$(cat "$SIM/marked")\"" >> "$SIM/removed" ;;
  set:*) kv="${1#set:}"; echo "${kv#*=}" > "$SIM/fossify.${kv%%=*}" ;;
  ver:*) kv="${1#ver:}"; echo "${kv#*=}" > "$SIM/ver.${kv%%=*}" ;;
  webapk) echo org.chromium.webapk.a5c1d2 >> "$SIM/installed" ;;
  plugin) echo installed > "$SIM/decaid.plugin" ;;
  pluginload) echo loaded >> "$SIM/decaid.plugin" ;;
  pluginauto) echo autoload >> "$SIM/decaid.plugin" ;;
esac; }
go() { # event label
  s="$(scr)"; lab="$(echo "$2" | tr 'A-Z' 'a-z')"
  while IFS=$'\t' read -r ps pe pl next eff; do
    [[ -z "$ps" || "$ps" == '#'* ]] && continue
    # shellcheck disable=SC2053
    [[ $s == $ps ]] && [ "$pe" = "$1" ] || continue
    [ "$pl" = '*' ] || [ "$(echo "$pl" | tr 'A-Z' 'a-z')" = "$lab" ] || continue
    effect "$eff" "$2"; echo "$next" > "$SIM/screen"; return 0
  done < "$SIM/transitions"
}
S
cat > "$T/bin/uiautomator" <<'S'
#!/bin/bash
. "$(dirname "$0")/_simui"; [ "$1" = dump ] && { render | tr -d '\n' > "$2"; echo "UI hierchary dumped to: $2"; }
S
cat > "$T/bin/input" <<'S'
#!/bin/bash
. "$(dirname "$0")/_simui"; echo "input $*" >> "$SIM/events"
case "$1" in
 keyevent) shift; for k in "$@"; do case "$k" in KEYCODE_HOME) echo home > "$SIM/screen" ;; KEYCODE_WAKEUP) ;; *) go "key:$k" - ;; esac; done ;;
 tap) go tap "$(hit "$2" "$3")" ;;
 swipe) if [ "$2" = "$4" ] && [ "$3" = "$5" ]; then go long "$(hit "$2" "$3")"
   elif [ $(( $5 - $3 )) -lt -100 ]; then go swipe-up -; elif [ $(( $5 - $3 )) -gt 100 ]; then go swipe-down -; fi ;;
 text) go text "${2//%s/ }" ;;
 draganddrop) l="$(hit "$2" "$3")"; [ "$l" != - ] && { case "$(scr)" in drawer*) echo home > "$SIM/screen" ;; esac; x=$4 y=$5
   echo "<node index=\"9\" text=\"\" resource-id=\"\" class=\"android.view.View\" package=\"org.fossify.home\" content-desc=\"$l\" checkable=\"false\" checked=\"false\" bounds=\"[$((x-90)),$((y-90))][$((x+90)),$((y+90))]\"/>" >> "$SIM/added"; } ;;
 motionevent) case "$2" in
   DOWN) l="$(hit "$3" "$4")"; [ "$l" != - ] && { echo "$l" > "$SIM/dragging"; case "$(scr)" in drawer*) echo home > "$SIM/screen" ;; esac; } ;;
   UP) [ -s "$SIM/dragging" ] && { l="$(cat "$SIM/dragging")"; rm -f "$SIM/dragging"; x=$3 y=$4
     echo "<node index=\"9\" text=\"\" resource-id=\"\" class=\"android.view.View\" package=\"org.fossify.home\" content-desc=\"$l\" checkable=\"false\" checked=\"false\" bounds=\"[$((x-90)),$((y-90))][$((x+90)),$((y+90))]\"/>" >> "$SIM/added"; } ;;
 esac ;;
esac
exit 0
S
cat > "$T/bin/wm" <<'S'
#!/bin/bash
[ "$1" = size ] && echo "Physical size: 1200x1920"; exit 0
S
cat > "$T/bin/dumpsys" <<'S'
#!/bin/bash
case "$1" in
 account) echo "Accounts: $(grep -c . "$SIM/accounts")"; while read -r a; do echo "    Account {name=$a, type=com.google}"; done < "$SIM/accounts" ;;
 package) echo "Packages:"; echo "  Package [$2]"; echo "    versionName=$(cat "$SIM/ver.$2" 2>/dev/null || echo 1.0)"; echo "    versionName=0.9-factory" ;;
esac
exit 0
S
cat > "$T/bin/pm" <<'S'
#!/bin/bash
case "$1" in
 list) if [ "$3" = -d ] || [ "${2:-}" = -d ]; then sed 's/^/package:/' "$SIM/disabled"; else sed 's/^/package:/' "$SIM/installed"; fi ;;
 disable-user) p="$4"; if [ "$p" = com.samsung.android.smartsuggestions ]; then echo "Failed to change state of package: $p"; exit 1; fi; echo "$p" >> "$SIM/disabled"; sort -u -o "$SIM/disabled" "$SIM/disabled" ;;
 enable) grep -vx "$4" "$SIM/disabled" > "$SIM/d2"; mv "$SIM/d2" "$SIM/disabled" ;;
 uninstall) grep -vx "$4" "$SIM/installed" > "$SIM/i2"; mv "$SIM/i2" "$SIM/installed"; echo "$4" >> "$SIM/uninstalled" ;;
 install) echo Success ;;
esac
S
cat > "$T/bin/settings" <<'S'
#!/bin/bash
k="$2.$3"
case "$1" in
 get) v="$(grep -E "^$k=" "$SIM/settings" | cut -d= -f2-)"; echo "${v:-null}" ;;
 put) grep -vE "^$k=" "$SIM/settings" > "$SIM/s2"; mv "$SIM/s2" "$SIM/settings"; echo "$k=$4" >> "$SIM/settings" ;;
 delete) grep -vE "^$k=" "$SIM/settings" > "$SIM/s2"; mv "$SIM/s2" "$SIM/settings" ;;
esac
S
cat > "$T/bin/cmd" <<'S'
#!/bin/bash
if [ "$1" = wifi ]; then case "$2" in # like Android, status names the network
  status) echo "Wifi is enabled"; if [ -s "$SIM/wifi" ]; then echo "Wifi is connected to \"$(cat "$SIM/wifi")\""; else echo "Wifi is not connected"; fi ;;
  set-wifi-enabled) echo "$3" > "$SIM/wifi.enabled" ;;
  connect-network) printf '%s|%s|%s\n' "$3" "$4" "${5:-}" > "$SIM/wifi.args"; [ "${SIM_WIFI_FAIL:-0}" = 1 ] || echo "$3" > "$SIM/wifi"; echo "Connection initiated" ;;
esac; exit 0; fi
if [ "$1" = role ]; then r="${5##*.}"; r="$(echo "$r" | tr 'A-Z' 'a-z')"
  case "$2" in get-role-holders) cat "$SIM/role.$r" ;; add-role-holder) echo "$6" > "$SIM/role.$r" ;; esac
fi
exit 0
S
# monkey opens an app. Decaid opens on the screen in $SIM/decaid.start; one that is already showing stays where it is.
cat > "$T/bin/monkey" <<'S'
#!/bin/bash
. "$(dirname "$0")/_simui"; echo "monkey $*" >> "$SIM/events"
[ "$2" = net.tadel.reaprime ] && [ -s "$SIM/decaid.start" ] && case "$(scr)" in decaid_*) ;; *) cat "$SIM/decaid.start" > "$SIM/screen" ;; esac
exit 0
S
chmod +x "$T/bin/"*
run() { /bin/sh "$T/dev/decent-setup.sh" "$@"; }
fails=0
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fails=$((fails+1)); }
sameset() { sort "$1" > "$T/a"; sort "$2" > "$T/b"; cmp -s "$T/a" "$T/b"; }
get() { grep -E "^$1=" "$SIM/settings" | cut -d= -f2-; }

# 1. A build not listed refuses, and changes nothing.
SIM_BUILD=OTHER run apply > "$T/o" 2>&1; [ $? -ne 0 ] && grep -q 'Nothing changed' "$T/o" && [ ! -d "$DECENT_DIR" ] && ok "refuses an untested build" || bad "untested build"
SIM_BUILD=OTHER run cleanup --dry-run --force > "$T/o" 2>&1; [ $? = 0 ] && grep -q 'CHECK same-model-new-build' "$T/o" && grep -q 'continuing because of --force' "$T/o" && ok "new firmware on the tested model runs with --force" || bad "force on new build"
rm -rf "$DECENT_DIR"
# 2. Dry run changes nothing.
run apply --dry-run > "$T/o" 2>&1; sameset "$SIM/disabled" "$SIM/disabled.start" && sameset "$SIM/settings" "$SIM/settings.start" && ok "dry run changes nothing" || bad "dry run"
[ ! -f "$DECENT_DIR/original.done" ] && ok "dry run saves no record" || bad "dry run wrote a record"
run snapshot >/dev/null 2>&1; run status | grep -q 'undo_record=none' && ok "a saved original alone reports nothing to undo" || bad "status after snapshot"
# 3. Apply.
run apply > "$T/o" 2>&1; rc=$?; [ $rc = 0 ] && ok "apply exits 0" || { bad "apply rc=$rc"; tail -5 "$T/o"; }
for p in tk.tcl.wish hu.kavekalmar.sep com.pressensor.coffeeflow com.alphainventor.filemanager com.hecorat.screenrecorder.free net.tadel.reaprime com.android.chrome com.android.settings com.sec.android.app.launcher; do
  grep -qx "$p" "$SIM/disabled" && bad "$p got disabled"; done; ok "protected apps untouched"
grep -qx com.sec.android.app.sbrowser "$SIM/disabled" && ok "Samsung Internet disabled" || bad "sbrowser"
grep -q 'REFUSED .*smartsuggestions' "$T/o" && ! grep -qx com.samsung.android.smartsuggestions "$SIM/disabled" && ok "a refusal is recorded and survived" || bad "refusal"
grep -q 'SKIP .*autodoodle.*not installed' "$T/o" && ok "absent package skipped" || bad "absent"
[ "$(cat "$SIM/role.browser")" = com.android.chrome ] && [ "$(get system.screen_off_timeout)" = 600000 ] && [ "$(get global.stay_on_while_plugged_in)" = 0 ] && [ "$(get secure.edge_enable)" = 0 ] && [ "$(get secure.navigation_mode)" = 2 ] && ok "settings applied" || bad "settings"
# 4. Home.
run home > "$T/o" 2>&1; [ "$(cat "$SIM/role.home")" = org.fossify.home ] && ok "Fossify is Home" || bad "home"
# 5. Apply twice changes nothing new; the original record is not overwritten.
cp "$DECENT_DIR/original-settings.txt" "$T/os"; cp "$SIM/disabled" "$T/d1"; run apply > "$T/o" 2>&1; sameset "$SIM/disabled" "$T/d1" && cmp -s "$T/os" "$DECENT_DIR/original-settings.txt" && ! grep -q '^DONE' "$T/o" && ok "second apply is a no-op" || bad "idempotent"
# 6. Undo dry run changes nothing.
cp "$SIM/settings" "$T/s1"; run undo --dry-run > "$T/o" 2>&1; sameset "$SIM/disabled" "$T/d1" && sameset "$SIM/settings" "$T/s1" && ok "undo dry run changes nothing" || bad "undo dry"
# 7. Undo restores everything, leaves the vendor's three disabled, and keeps apps that were already there.
run undo > "$T/o" 2>&1; rc=$?; [ $rc = 0 ] && ok "undo exits 0" || bad "undo rc=$rc"
sameset "$SIM/disabled" "$SIM/disabled.start" && ok "disabled list matches the original exactly" || { bad "disabled differs"; diff "$T/a" "$T/b" | head; }
sameset "$SIM/settings" "$SIM/settings.start" && ok "settings match the original exactly" || { bad "settings differ"; diff "$T/a" "$T/b" | head; }
[ "$(cat "$SIM/role.home")" = com.sec.android.app.launcher ] && [ "$(cat "$SIM/role.browser")" = com.sec.android.app.sbrowser ] && ok "Home and browser restored" || bad "roles"
sameset "$SIM/installed" "$SIM/installed.start" && ok "apps already there were not uninstalled" || bad "installed"
# 8. Undo twice is safe.
run undo > "$T/o" 2>&1; [ $? = 0 ] && ! grep -q '^FAIL' "$T/o" && sameset "$SIM/disabled" "$SIM/disabled.start" && ok "second undo is safe" || bad "undo twice"
# 9. An app the project added is removed on undo; one kept with --keep-apps stays.
grep -vx org.fossify.home "$SIM/installed" > "$T/i"; cp "$T/i" "$SIM/installed"; rm -rf "$DECENT_DIR"; run snapshot >/dev/null 2>&1; echo org.fossify.home >> "$SIM/installed"
run undo --keep-apps >/dev/null 2>&1; grep -qx org.fossify.home "$SIM/installed" && ok "--keep-apps keeps added apps" || bad "keep-apps"
run undo >/dev/null 2>&1; grep -qx org.fossify.home "$SIM/installed" && bad "added app left behind" || ok "added app removed on undo"
# 10. Each option alone touches only its own part, and undo reverses it.
reset() { rm -rf "$DECENT_DIR"; cp "$SIM/installed.start" "$SIM/installed"; cp "$SIM/disabled.start" "$SIM/disabled"; cp "$SIM/settings.start" "$SIM/settings"
  printf 'com.sec.android.app.sbrowser\n' > "$SIM/role.browser"; printf 'com.sec.android.app.launcher\n' > "$SIM/role.home"; }
reset; run cleanup > "$T/o" 2>&1
grep -qx com.sec.android.app.sbrowser "$SIM/disabled" && [ "$(cat "$SIM/role.home")" = com.sec.android.app.launcher ] && [ "$(get secure.navigation_mode)" = 0 ] && [ "$(get secure.edge_enable)" = 1 ] && [ "$(get system.screen_off_timeout)" = 600000 ] && ok "cleanup alone leaves Home, navigation and edge panel" || bad "cleanup alone"
run undo >/dev/null 2>&1; sameset "$SIM/disabled" "$SIM/disabled.start" && sameset "$SIM/settings" "$SIM/settings.start" && ok "undo after cleanup alone" || bad "undo cleanup alone"
reset; run home --dry-run > "$T/o" 2>&1; [ "$(cat "$SIM/role.home")" = com.sec.android.app.launcher ] && grep -q '^PLAN' "$T/o" && ok "home dry run changes nothing" || bad "home dry"
run home > "$T/o" 2>&1
sameset "$SIM/disabled" "$SIM/disabled.start" && [ "$(cat "$SIM/role.home")" = org.fossify.home ] && [ "$(get secure.navigation_mode)" = 2 ] && [ "$(get secure.edge_enable)" = 0 ] && [ "$(cat "$SIM/role.browser")" = com.sec.android.app.sbrowser ] && ok "home alone disables nothing and keeps the browser" || bad "home alone"
run undo --keep-apps >/dev/null 2>&1; [ "$(cat "$SIM/role.home")" = com.sec.android.app.launcher ] && sameset "$SIM/settings" "$SIM/settings.start" && ok "undo after home alone" || bad "undo home alone"
grep -vx org.fossify.home "$SIM/installed" > "$T/i"; cp "$T/i" "$SIM/installed"; rm -rf "$DECENT_DIR"
run home > "$T/o" 2>&1; [ $? -ne 0 ] && grep -q 'not installed' "$T/o" && ok "home refuses without Fossify" || bad "home without fossify"
# 11. Undo in parts: apps only, Home only, and a few apps only.
reset; run apply >/dev/null 2>&1
run undo --apps --pkgs=com.netflix.mediaclient,com.sec.android.app.sbrowser > "$T/o" 2>&1
! grep -qx com.netflix.mediaclient "$SIM/disabled" && ! grep -qx com.sec.android.app.sbrowser "$SIM/disabled" && grep -qx com.spotify.music "$SIM/disabled" && [ "$(cat "$SIM/role.home")" = org.fossify.home ] && [ "$(cat "$SIM/role.browser")" = com.sec.android.app.sbrowser ] && ok "undo --apps --pkgs re-enables only those, keeps Home" || { bad "undo pkgs"; tail -5 "$T/o"; }
run undo --home > "$T/o" 2>&1
[ "$(cat "$SIM/role.home")" = com.sec.android.app.launcher ] && [ "$(get secure.navigation_mode)" = 0 ] && grep -qx com.spotify.music "$SIM/disabled" && ok "undo --home restores Home, leaves apps off" || bad "undo home part"
run undo --apps > "$T/o" 2>&1
sameset "$SIM/disabled" "$SIM/disabled.start" && sameset "$SIM/settings" "$SIM/settings.start" && ok "undo in parts ends at the original state" || { bad "undo parts end"; diff "$T/a" "$T/b" | head; }
reset; run apply >/dev/null 2>&1; run undo --apps --pkgs=com.netflix.mediaclient >/dev/null 2>&1
[ "$(cat "$SIM/role.browser")" = com.android.chrome ] && ok "browser stays Chrome while Samsung Internet is still off" || bad "browser with sbrowser off"
reset
# 12. A protected package in the list stops before any change.
echo "1 com.android.settings" >> "$T/dev/packages-disable.txt"; cp "$SIM/disabled" "$T/d2"; run apply > "$T/o" 2>&1; [ $? -ne 0 ] && sameset "$SIM/disabled" "$T/d2" || true
grep -q 'protected' "$T/o" && ok "protected package in the list is refused" || bad "protected list"

# 13. finish: the last steps, driven on a simulated screen (tests/fixtures/finish). Short timeouts.
export FX="$ROOT/tests/fixtures/finish" UI_WAIT_S=1 UI_PAUSE_S=0 UI_HOLD_S=0 UI_STEP_S=0
reset; : > "$SIM/accounts"; rm -f "$SIM/wifi" "$SIM/events"; cp "$FX/transitions.tsv" "$SIM/transitions"; echo home > "$SIM/screen"
printf 'org.fossify.home\n' > "$SIM/role.home"
fin() { run finish "$@" > "$T/o" 2>&1; cat "$T/o" >> "$T/all"; }
: > "$T/all"
fin status
grep -qx 'STATUS wifi=disconnected' "$T/o" && grep -qx 'STATUS google_account=no' "$T/o" && grep -qx 'STATUS home=org.fossify.home' "$T/o" && grep -qx 'STATUS decadent_app=none' "$T/o" && tail -n 1 "$T/o" | grep -qx 'OK finish status' && ok "finish status reports wifi, account, Home and app" || { bad "finish status"; cat "$T/o"; }
SSID='Cafe Guest 5G'
run finish wifi > "$T/o" 2>&1; [ $? -ne 0 ] && grep -q 'unknown finish step' "$T/o" && ok "no finish step takes Wi-Fi details" || bad "old wifi step still there"
run finish wifi-open --dry-run > "$T/o" 2>&1; grep -qx 'PLAN finish wifi-open' "$T/o" && ! grep -q 'WIFI_SETTINGS' "$SIM/events" 2>/dev/null && ok "finish --dry-run plans and opens nothing" || bad "finish dry run"
fin wifi-open; grep -qx 'DONE finish wifi-open' "$T/o" && grep -q 'WIFI_SETTINGS' "$SIM/events" && ok "finish wifi-open opens Wi-Fi settings on the tablet" || { bad "wifi-open"; cat "$T/o"; }
echo "$SSID" > "$SIM/wifi"; fin status   # the owner joins on the tablet
grep -qx 'STATUS wifi=connected' "$T/o" && ! grep -qF "$SSID" "$T/o" && ok "status sees the tablet joined, without naming the network" || { bad "wifi status"; cat "$T/o"; }
fin account-open; grep -qx 'DONE finish account-open' "$T/o" && grep -q 'ADD_ACCOUNT_SETTINGS' "$SIM/events" && ok "finish account-open opens the add-account screen" || bad "account-open"
# Fallback: Chrome's long-press menu never shows Remove. The step gives up quickly with MANUAL.
grep -v $'^home\tlong\t\\*' "$FX/transitions.tsv" > "$SIM/transitions"; t0=$(date +%s)
fin icons; t1=$(date +%s)
grep -q '^MANUAL finish icons no Remove option appeared for Chrome' "$T/o" && [ $((t1-t0)) -lt 15 ] && [ ! -s "$SIM/removed" ] && ok "a missing button ends MANUAL in $((t1-t0)) s and removes nothing" || { bad "icons fallback"; cat "$T/o"; }
cp "$FX/transitions.tsv" "$SIM/transitions"; echo home > "$SIM/screen"
fin icons; grep -qx 'DONE finish icons removed=3' "$T/o" && [ "$(grep -c . "$SIM/removed")" = 3 ] && ok "finish icons removes Chrome, Play Store and Camera" || { bad "icons"; cat "$T/o"; }
fin icons; grep -qx 'SKIP finish icons none on Home' "$T/o" && ok "finish icons again: none on Home" || { bad "icons again"; cat "$T/o"; }
fin launcher
grep -qx 'DONE finish launcher' "$T/o" && [ "$(cat "$SIM/fossify.rows" 2>/dev/null)" = 3 ] && [ "$(cat "$SIM/fossify.cols" 2>/dev/null)" = 5 ] && [ "$(cat "$SIM/fossify.close" 2>/dev/null)" = on ] && [ "$(cat "$SIM/screen")" = home ] && ok "finish launcher sets 3 rows, 5 columns, closes the drawer, ends on Home" || { bad "launcher"; cat "$T/o"; }
echo 130.0.6723.102 > "$SIM/ver.com.android.chrome"; fin updates
grep -qx 'DONE finish update com.android.chrome' "$T/o" && grep -qx 'SKIP finish update com.google.android.webview up to date' "$T/o" && tail -n 1 "$T/o" | grep -qx 'OK finish updates' && [ "$(cat "$SIM/screen")" = home ] && ok "finish updates: Chrome updated, WebView up to date" || { bad "updates"; cat "$T/o"; }
fin decadent; grep -qx 'DONE finish decadent' "$T/o" && grep -q '^org.chromium.webapk' "$SIM/installed" && ok "finish decadent installs the app from Chrome's menu" || { bad "decadent"; cat "$T/o"; }
fin decadent; grep -qx 'SKIP finish decadent already installed' "$T/o" && ok "finish decadent again: already installed" || bad "decadent again"
# The plugin step drives Decaid's own installer, on screens labelled as Decaid 0.9.2's source labels them.
cp "$SIM/installed" "$T/installed.keep"; grep -v '^net.tadel.reaprime$' "$T/installed.keep" > "$SIM/installed"
fin plugin; grep -qx 'SKIP finish plugin Decaid is not installed' "$T/o" && ok "finish plugin without Decaid: skipped" || { bad "plugin no decaid"; cat "$T/o"; }
fin decaid open; grep -qx 'STATUS decaid=absent' "$T/o" && ok "finish decaid without Decaid: absent" || { bad "decaid absent"; cat "$T/o"; }
{ cat "$T/installed.keep"; echo net.tadel.reaprime; } | sort -u > "$SIM/installed"
# A Decaid that has never been opened asks its first questions. Those are the owner's: nothing is tapped, the step says asking.
echo decaid_welcome > "$SIM/decaid.start"; echo home > "$SIM/screen"; : > "$SIM/events"
fin decaid open; grep -qx 'STATUS decaid=asking' "$T/o" && tail -n 1 "$T/o" | grep -qx 'OK finish decaid' && [ "$(cat "$SIM/screen")" = decaid_welcome ] && ! grep -q '^input tap' "$SIM/events" && ok "a new Decaid's first questions: asking, and nothing tapped for the owner" || { bad "decaid asking"; cat "$T/o" "$SIM/events"; }
echo decaid_import > "$SIM/screen"; : > "$SIM/events"   # the owner tapped Get Started
fin decaid; grep -qx 'STATUS decaid=asking' "$T/o" && [ "$(cat "$SIM/screen")" = decaid_import ] && ! grep -q '^monkey' "$SIM/events" && ! grep -q '^input tap' "$SIM/events" && ok "asked again without open: still asking, Decaid not relaunched" || { bad "decaid asking again"; cat "$T/o" "$SIM/events"; }
t0=$(date +%s); fin plugin; t1=$(date +%s)
grep -qx 'MANUAL finish plugin Decaid is asking its first questions' "$T/o" && [ $((t1-t0)) -lt 20 ] && [ ! -s "$SIM/decaid.plugin" ] && ok "finish plugin while Decaid is asking ends MANUAL in $((t1-t0)) s" || { bad "plugin while asking"; cat "$T/o"; }
echo decaid_scan > "$SIM/screen"   # the owner answered the import question; Decaid now looks for the machine
fin decaid; grep -qx 'STATUS decaid=ready' "$T/o" && [ "$(cat "$SIM/screen")" = decaid_dash ] && ok "after the questions: past the machine search and the coffee screen, ready at Decaid's menu" || { bad "decaid ready"; cat "$T/o"; }
fin plugin; grep -qx 'DONE finish plugin' "$T/o" && [ "$(tr '\n' ' ' < "$SIM/decaid.plugin" 2>/dev/null)" = "installed loaded autoload " ] && grep -q '^input text decadentcoffee/decadent-plugin' "$SIM/events" && [ "$(cat "$SIM/screen")" = decaid_dash ] && ok "finish plugin installs decadentcoffee/decadent-plugin through Decaid's installer, loads it and sets it to start with Decaid" || { bad "plugin install"; cat "$T/o"; }
# A Decaid already set up opens on the coffee screen; one start does the whole step.
rm -f "$SIM/decaid.plugin"; echo decaid_skin > "$SIM/decaid.start"; echo home > "$SIM/screen"
fin plugin; grep -qx 'DONE finish plugin' "$T/o" && [ -s "$SIM/decaid.plugin" ] && ok "finish plugin from the coffee screen" || { bad "plugin from skin"; cat "$T/o"; }
rm -f "$SIM/decaid.start"; echo home > "$SIM/screen"
cp "$T/installed.keep" "$SIM/installed"
fin place
grep -qx 'DONE finish place Decaid' "$T/o" && grep -qx 'DONE finish place Decadent' "$T/o" && grep -qx 'SKIP finish place Settings already there' "$T/o" && tail -n 1 "$T/o" | grep -qx 'OK finish place' && ok "finish place drags Decaid and Decadent, leaves Settings" || { bad "place"; cat "$T/o"; }
grep -q 'content-desc="Decaid".*bounds="\[486,519\]\[666,699\]"' "$SIM/added" && grep -q 'content-desc="Decadent".*bounds="\[870,519\]\[1050,699\]"' "$SIM/added" && grep -q '^input text Decadent' "$SIM/events" && ok "dropped in middle-row cells 2 and 3; Decadent found through search" || { bad "place cells"; cat "$SIM/added"; }
echo owner@example.test > "$SIM/accounts"; fin status
grep -qx 'STATUS wifi=connected' "$T/o" && grep -qx 'STATUS google_account=yes' "$T/o" && grep -qx 'STATUS decadent_app=installed' "$T/o" && ok "finish status after the steps" || { bad "status after"; cat "$T/o"; }
! grep -rqF -e "$SSID" -e 'owner@example.test' "$T/all" "$DECENT_DIR" && ok "no network name or account name in any output, log or file" || bad "a secret leaked"
printf 'com.sec.android.app.launcher\n' > "$SIM/role.home"; fin icons; grep -qx 'SKIP finish icons home screen option not used' "$T/o" && ok "finish icons skips without Fossify" || bad "icons no fossify"
# Owner's choices at the end: Decadent left off Home, and a tablet without Decaid (they skipped installing it).
printf 'org.fossify.home\n' > "$SIM/role.home"; : > "$SIM/added"; echo home > "$SIM/screen"
fin place no-decadent
grep -qx 'SKIP finish place Decadent not wanted' "$T/o" && ! grep -q 'content-desc="Decadent"' "$SIM/added" && tail -n 1 "$T/o" | grep -qx 'OK finish place' && ok "finish place no-decadent leaves Decadent off Home" || { bad "place no-decadent"; cat "$T/o"; }
grep -vx net.tadel.reaprime "$SIM/installed" > "$T/i"; cp "$T/i" "$SIM/installed"; : > "$SIM/added"; echo home > "$SIM/screen"
fin place
grep -qx 'SKIP finish place Decaid not installed' "$T/o" && ! grep -q 'content-desc="Decaid"' "$SIM/added" && tail -n 1 "$T/o" | grep -qx 'OK finish place' && ok "finish place without Decaid skips its icon" || { bad "place no decaid"; cat "$T/o"; }
# Decent's other apps. The simulated app list does not show them, so each ends MANUAL and nothing lands on Home;
# a tablet without them skips both.
printf 'org.fossify.home\n' > "$SIM/role.home"; : > "$SIM/added"; echo home > "$SIM/screen"
fin more
[ "$(grep -c '^MANUAL finish more .* could not find it in the app list$' "$T/o")" = 2 ] && [ ! -s "$SIM/added" ] && tail -n 1 "$T/o" | grep -qx 'OK finish more' && ok "finish more ends MANUAL for an app the app list does not show" || { bad "more"; cat "$T/o"; }
grep -vxE 'hu.kavekalmar.sep|com.pressensor.coffeeflow|com.hecorat.screenrecorder.free' "$SIM/installed" > "$T/i"; cp "$T/i" "$SIM/installed"; echo home > "$SIM/screen"
fin more
[ "$(grep -c '^SKIP finish more .* not on this tablet$' "$T/o")" = 2 ] && tail -n 1 "$T/o" | grep -qx 'OK finish more' && ok "finish more skips apps the tablet does not have" || { bad "more absent"; cat "$T/o"; }
printf 'com.sec.android.app.launcher\n' > "$SIM/role.home"; fin more; grep -qx 'SKIP finish more home screen option not used' "$T/o" && ok "finish more skips without the Home option" || bad "more without home"
echo; [ $fails = 0 ] && echo "ALL SIM CHECKS PASSED" || { echo "$fails SIM CHECK(S) FAILED"; exit 1; }
