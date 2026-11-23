#!/system/bin/sh
# Runs ON the tablet, through `adb shell`. Every front end (scripts/setup.sh, an agent, the webpage) calls this,
# so all of them do the same thing. It keeps its record on the tablet, so undo works from any computer.
#
# sh decent-setup.sh check | status | plan | snapshot
# sh decent-setup.sh cleanup [--dry-run]    option 1: switch off the listed apps; Chrome as browser; sleep after 10 min
# sh decent-setup.sh home [--dry-run]       option 2: Fossify Launcher as Home; swipe gestures; no edge panel
# sh decent-setup.sh apply [--dry-run]      both options
# sh decent-setup.sh install <apk>...       install pushed APKs and remember that we installed them
# sh decent-setup.sh undo [--apps] [--home] [--pkgs=a,b] [--dry-run] [--keep-apps]
#   --apps: turn back on what cleanup switched off (--pkgs= limits it) and restore sleep and browser
#   --home: original Home app, buttons and side panel; removes Fossify unless --keep-apps. Neither: both
# sh decent-setup.sh finish <step> [--dry-run]  last steps, done on the screen: status wifi account-open icons
#   wifi-open launcher updates decadent decaid plugin place. wifi-open only opens Wi-Fi settings: the owner joins on the tablet,
#   and no network name or password ever passes through this script or the page.
#   place no-decadent leaves the Decadent icon off Home.
#   place if-missing (Samsung's Home) adds the Decadent icon only when Home shows none.
#   decaid [open] reports STATUS decaid=ready|asking|absent: asking means Decaid shows its first questions, which
#   only the owner answers. The front end waits and asks again; plugin runs once it is ready.
#   A step it cannot do prints MANUAL; the front end then shows the written instructions for it
#
# Add --force to run on a model or build not listed in device.expect. Output lines start with a word a front end can parse:
# CHECK INFO PLAN DONE SKIP REFUSED FAIL OK STATUS MANUAL

DIR="${DECENT_DIR:-/data/local/tmp/decent-tablet}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LIST="$HERE/packages-disable.txt"
EXPECT="$HERE/device.expect"
LOG="$DIR/changes.tsv"
USER_ID=""
FOSSIFY=org.fossify.home
ONEUI=com.sec.android.app.launcher
CHROME=com.android.chrome

# Never disabled, whatever the list says.
PROTECTED="android com.android.systemui com.android.settings com.android.bluetooth com.sec.android.app.bluetoothagent
com.google.android.webview com.google.android.packageinstaller com.google.android.permissioncontroller com.android.shell
com.android.providers.settings com.google.android.gms com.google.android.gsf com.android.vending com.android.chrome
com.sec.android.app.launcher com.samsung.android.honeyboard net.tadel.reaprime tk.tcl.wish hu.kavekalmar.sep
com.pressensor.coffeeflow com.alphainventor.filemanager com.hecorat.screenrecorder.free com.wssyncmldm com.sec.android.soagent
com.android.phone com.google.android.networkstack com.samsung.android.networkstack com.android.wifi.resources
com.samsung.android.wifi.resources org.fossify.home app.olauncher"

say() { echo "$*"; }
die() { echo "FAIL $*"; exit 1; }
stamp() { date -u +%Y%m%dT%H%M%SZ; }
model() { getprop ro.product.model; }
build() { getprop ro.build.PDA; }

is_protected() { for w in $PROTECTED; do [ "$w" = "$1" ] && return 0; done; return 1; }
installed() { pm list packages --user "$USER_ID" 2>/dev/null | grep -qx "package:$1"; }
# usable <package>: on the tablet and able to open. Samsung switches off apps nobody has opened for a while
# ("auto_disabler": the app reads as disabled, state 4, disabled until used) and the app comes back on when it is
# opened (reference tablet, 21 Nov 2026: AZ Screen Recorder and seven preloaded apps). Such an app is still there.
usable() {
  case "$(state_of "$1")" in enabled) return 0 ;; disabled) dumpsys package "$1" 2>/dev/null | grep -q "User $USER_ID:.* enabled=4 " ;; *) return 1 ;; esac
}
state_of() {
  installed "$1" || { echo absent; return; }
  if pm list packages -d --user "$USER_ID" 2>/dev/null | grep -qx "package:$1"; then echo disabled; else echo enabled; fi
}
role_holder() { cmd role get-role-holders --user "$USER_ID" "$1" 2>/dev/null | head -n 1; }
log_change() { printf '%s\t%s\t%s\t%s\t%s\n' "$(stamp)" "$1" "$2" "$3" "$4" >> "$LOG"; }

init_user() { USER_ID="$(am get-current-user 2>/dev/null)"; [ -n "$USER_ID" ] || die "could not read the Android user"; }

do_check() {
  m="$(model)"; b="$(build)"
  say "INFO model=$m build=$b android=$(getprop ro.build.version.release) oneui=$(getprop ro.build.version.oneui) user=$USER_ID"
  if grep -v '^#' "$EXPECT" 2>/dev/null | grep -qxF "$m $b"; then say "CHECK tested"; return 0; fi
  if grep -v '^#' "$EXPECT" 2>/dev/null | grep -q "^$m "; then say "CHECK same-model-new-build"; else say "CHECK untested-model"; fi
  [ "$FORCE" = 1 ] && { say "INFO continuing because of --force"; return 0; }
  die "this tablet is $m $b, which has not been tested. Nothing changed. Review docs/packages.md, then re-run with --force."
}

# Save the original state once, before the first change. Never overwritten.
do_snapshot() {
  mkdir -p "$DIR" || die "cannot write $DIR"
  [ -f "$DIR/original.done" ] && { say "INFO original state already saved"; return 0; }
  pm list packages -d --user "$USER_ID" | sed 's/^package://' | sort > "$DIR/original-disabled.txt"
  pm list packages --user "$USER_ID" | sed 's/^package://' | sort > "$DIR/original-installed.txt"
  {
    echo "system_screen_off_timeout=$(settings get system screen_off_timeout)"
    echo "global_stay_on_while_plugged_in=$(settings get global stay_on_while_plugged_in)"
    echo "global_navigation_bar_gesture_hint=$(settings get global navigation_bar_gesture_hint)"
    echo "global_navigation_bar_gesture_while_hidden=$(settings get global navigation_bar_gesture_while_hidden)"
    echo "secure_navigation_mode=$(settings get secure navigation_mode)"
    echo "secure_edge_enable=$(settings get secure edge_enable)"
    echo "role_browser=$(role_holder android.app.role.BROWSER)"
    echo "role_home=$(role_holder android.app.role.HOME)"
  } > "$DIR/original-settings.txt"
  printf 'utc\taction\ttarget\tbefore\tresult\n' > "$LOG"
  : > "$DIR/original.done"
  say "OK original state saved on the tablet in $DIR"
}
orig() { grep "^$1=" "$DIR/original-settings.txt" | head -n 1 | cut -d= -f2-; }

set_setting() { # namespace key value
  before="$(settings get "$1" "$2")"
  [ "$before" = "$3" ] && { say "SKIP $1/$2 already $3"; return 0; }
  if [ "$DRY" = 1 ]; then say "PLAN $1/$2: $before -> $3"; return 0; fi
  settings put "$1" "$2" "$3"
  now="$(settings get "$1" "$2")"
  if [ "$now" = "$3" ]; then log_change setting "$1/$2" "$before" ok; say "DONE $1/$2 = $3"
  else log_change setting "$1/$2" "$before" fail; say "FAIL $1/$2 stayed $now"; return 1; fi
}
restore_setting() { # namespace key value; "null" means it was never set
  if [ "$3" = null ] || [ -z "$3" ]; then
    [ "$(settings get "$1" "$2")" = null ] && { say "SKIP $1/$2 already unset"; return 0; }
    if [ "$DRY" = 1 ]; then say "PLAN delete $1/$2"; return 0; fi
    settings delete "$1" "$2" >/dev/null; log_change restore "$1/$2" - ok; say "DONE $1/$2 unset"
  else set_setting "$1" "$2" "$3"; fi
}
set_role() { # role package
  [ "$(role_holder "$1")" = "$2" ] && { say "SKIP $1 already $2"; return 0; }
  if [ "$DRY" = 1 ]; then say "PLAN $1 -> $2"; return 0; fi
  installed "$2" || { say "FAIL $2 is not installed"; return 1; }
  before="$(role_holder "$1")"
  cmd role add-role-holder --user "$USER_ID" "$1" "$2" >/dev/null 2>&1
  if [ "$(role_holder "$1")" = "$2" ]; then log_change role "$1" "$before" ok; say "DONE $1 = $2"
  else log_change role "$1" "$before" fail; say "FAIL could not set $1 to $2"; return 1; fi
}
set_nav() { # gestural | threebutton
  if [ "$1" = gestural ]; then mode=2; hidden=1; else mode=0; hidden=0; fi
  [ "$(settings get secure navigation_mode)" = "$mode" ] && { say "SKIP navigation already $1"; return 0; }
  if [ "$DRY" = 1 ]; then say "PLAN navigation -> $1"; return 0; fi
  before="$(settings get secure navigation_mode)"
  cmd overlay enable-exclusive --category "com.android.internal.systemui.navbar.$1" >/dev/null 2>&1
  settings put global navigation_bar_gesture_while_hidden "$hidden"
  settings put secure navigation_mode "$mode"
  log_change setting secure/navigation_mode "$before" ok
  say "DONE navigation = $1"
}

cleanup_settings() {
  set_setting system screen_off_timeout 600000 &&
  set_setting global stay_on_while_plugged_in 0 &&
  set_role android.app.role.BROWSER "$CHROME"
}
home_settings() {
  set_setting secure edge_enable 0 &&
  set_nav gestural &&
  set_setting global navigation_bar_gesture_hint 0
}

do_plan() {
  n=0; skip=0
  while read -r batch pkg; do
    case "$batch" in ''|'#'*) continue ;; esac
    is_protected "$pkg" && die "$pkg is protected but listed for disabling. Fix packages-disable.txt."
    case "$(state_of "$pkg")" in enabled) n=$((n+1)) ;; *) skip=$((skip+1)) ;; esac
  done < "$LIST"
  say "PLAN disable=$n already-off-or-absent=$skip"
}

do_cleanup() {
  [ -f "$LIST" ] || die "missing $LIST"
  # Check the whole list before changing anything.
  while read -r batch pkg; do
    case "$batch" in ''|'#'*) continue ;; esac
    is_protected "$pkg" && die "$pkg is protected but listed for disabling. Fix packages-disable.txt. Nothing changed."
  done < "$LIST"
  [ "$DRY" = 1 ] || do_snapshot
  cleanup_settings || die "a setting failed. Stopped before disabling anything."
  disabled_now="$(pm list packages -d --user "$USER_ID")"
  all_now="$(pm list packages --user "$USER_ID")"
  total=$(grep -cv '^#' "$LIST"); i=0; refused=0
  while read -r batch pkg; do
    case "$batch" in ''|'#'*) continue ;; esac
    i=$((i+1))
    is_protected "$pkg" && die "$pkg is protected but listed for disabling. Fix packages-disable.txt."
    # Android may change the current Home app and keyboard; never disable those.
    [ "$pkg" = "$(role_holder android.app.role.HOME)" ] && { say "SKIP $pkg is the Home app"; continue; }
    [ "$pkg" = "$(settings get secure default_input_method | cut -d/ -f1)" ] && { say "SKIP $pkg is the keyboard"; continue; }
    echo "$all_now" | grep -qx "package:$pkg" || { say "SKIP $i/$total $pkg not installed"; continue; }
    echo "$disabled_now" | grep -qx "package:$pkg" && { say "SKIP $i/$total $pkg already disabled"; continue; }
    if [ "$DRY" = 1 ]; then say "PLAN $i/$total disable $pkg"; continue; fi
    out="$(pm disable-user --user "$USER_ID" "$pkg" 2>&1)"
    if [ "$(state_of "$pkg")" = disabled ]; then log_change disable "$pkg" enabled ok; say "DONE $i/$total $pkg"
    elif echo "$out" | grep -q 'Failed to change state'; then log_change disable "$pkg" enabled refused; say "REFUSED $i/$total $pkg"; refused=$((refused+1))
    else log_change disable "$pkg" enabled fail; sleep 30; die "$pkg: $out. Stopped. Run undo to go back."; fi
  done < "$LIST"
  if [ "$DRY" = 1 ]; then say "OK dry run: nothing changed"; return 0; fi
  say "INFO waiting 30 seconds for Android to save the changes. Do not reboot yet."
  sleep "${SETTLE_S:-30}"
  say "OK cleanup finished. Refused by Android: $refused"
}

do_install() {
  do_snapshot
  for apk in "$@"; do
    [ -f "$apk" ] || die "missing $apk"
    out="$(pm install -r --user "$USER_ID" "$apk" 2>&1)"
    case "$out" in *Success*) log_change install "$apk" - ok; say "DONE installed $(basename "$apk")" ;;
      *) log_change install "$apk" - fail; die "$(basename "$apk"): $out" ;; esac
  done
}

do_home() {
  [ "$DRY" = 1 ] || do_snapshot
  if [ "$DRY" != 1 ] && ! installed "$FOSSIFY"; then die "Fossify Launcher is not installed. Install it first. Nothing changed."; fi
  set_role android.app.role.HOME "$FOSSIFY" || die "could not make Fossify the Home app."
  home_settings || die "a Home screen setting failed."
  [ "$DRY" = 1 ] && { say "OK dry run: nothing changed"; return 0; }
  say "OK home screen finished"
}

do_status() {
  say "STATUS model=$(model) build=$(build) oneui=$(getprop ro.build.version.oneui)"
  say "STATUS home=$(role_holder android.app.role.HOME)"
  say "STATUS browser=$(role_holder android.app.role.BROWSER)"
  say "STATUS keyboard=$(settings get secure default_input_method | cut -d/ -f1)"
  say "STATUS screen_off_timeout=$(settings get system screen_off_timeout)"
  say "STATUS stay_on=$(settings get global stay_on_while_plugged_in)"
  say "STATUS navigation_mode=$(settings get secure navigation_mode)"
  say "STATUS edge_enable=$(settings get secure edge_enable)"
  say "STATUS double_tap_wake=$(settings get system double_tab_to_wake_up)"
  say "STATUS disabled_total=$(pm list packages -d --user "$USER_ID" | grep -c .)"
  # "present" only once something was changed: a saved original state alone has nothing to undo.
  say "STATUS undo_record=$([ -f "$DIR/original.done" ] && [ "$(grep -c . "$LOG" 2>/dev/null)" -gt 1 ] && echo present || echo none)"
  for p in net.tadel.reaprime tk.tcl.wish hu.kavekalmar.sep com.pressensor.coffeeflow com.alphainventor.filemanager com.hecorat.screenrecorder.free "$FOSSIFY" "$CHROME" com.android.settings com.android.bluetooth "$ONEUI"; do
    say "STATUS app $p $(state_of "$p")"
  done
  pm list packages --user "$USER_ID" | grep -q 'org.chromium.webapk' && say "STATUS decadent_app=installed" || say "STATUS decadent_app=none"
  if has_original; then say "STATUS original_app=yes"; else say "STATUS original_app=no"; fi
}

do_undo() {
  [ -f "$DIR/original.done" ] || die "no undo record on this tablet. Nothing to undo."
  [ -f "$LOG" ] || die "undo record is incomplete: $LOG is missing"
  [ "$UNDO_APPS" = 0 ] && [ "$UNDO_HOME" = 0 ] && { UNDO_APPS=1; UNDO_HOME=1; }
  if [ "$UNDO_HOME" = 1 ]; then
    # Back to the original Home first, so the tablet always has a working launcher.
    h="$(orig role_home)"; [ -n "$h" ] && set_role android.app.role.HOME "$h"
    restore_setting secure edge_enable "$(orig secure_edge_enable)"
    if [ "$(orig secure_navigation_mode)" = 2 ]; then set_nav gestural; else set_nav threebutton; fi
    restore_setting global navigation_bar_gesture_hint "$(orig global_navigation_bar_gesture_hint)"
    # Apps this project added; never an app that was already here.
    if [ "$KEEP_APPS" != 1 ]; then
      pm list packages --user "$USER_ID" | sed 's/^package://' | while read -r p; do
        case "$p" in "$FOSSIFY"|app.olauncher|org.chromium.webapk.*) ;; *) continue ;; esac
        if grep -qx "$p" "$DIR/original-installed.txt"; then say "SKIP $p was here before this project"; continue; fi
        # A preview has not handed Home back yet, so the launcher is still Home there: list it all the same.
        [ "$DRY" != 1 ] && [ "$(role_holder android.app.role.HOME)" = "$p" ] && { say "SKIP $p is still the Home app"; continue; }
        if [ "$DRY" = 1 ]; then say "PLAN uninstall $p"; continue; fi
        pm uninstall --user "$USER_ID" "$p" >/dev/null 2>&1; log_change uninstall "$p" - ok; say "DONE uninstalled $p"
      done
    fi
  fi
  if [ "$UNDO_APPS" = 1 ]; then
    # Packages this project disabled; never one that was already disabled. --pkgs limits it to some of them.
    awk -F'\t' '$2=="disable" && $5=="ok" {print $3}' "$LOG" | sort -u | while read -r pkg; do
      [ -n "$pkg" ] || continue
      if [ -n "$PKGS" ]; then case ",$PKGS," in *",$pkg,"*) ;; *) continue ;; esac; fi
      if grep -qx "$pkg" "$DIR/original-disabled.txt"; then say "SKIP $pkg was disabled before this project"; continue; fi
      case "$(state_of "$pkg")" in
        disabled)
          if [ "$DRY" = 1 ]; then say "PLAN enable $pkg"; continue; fi
          pm enable --user "$USER_ID" "$pkg" >/dev/null 2>&1
          if [ "$(state_of "$pkg")" = enabled ]; then log_change enable "$pkg" disabled ok; say "DONE enabled $pkg"; else log_change enable "$pkg" disabled fail; say "FAIL could not enable $pkg"; fi ;;
        enabled) say "SKIP $pkg already enabled" ;;
        absent) say "SKIP $pkg no longer on this tablet" ;;
      esac
    done
    restore_setting system screen_off_timeout "$(orig system_screen_off_timeout)"
    restore_setting global stay_on_while_plugged_in "$(orig global_stay_on_while_plugged_in)"
    b="$(orig role_browser)"
    if [ -n "$b" ]; then
      if [ "$DRY" = 1 ] || [ "$(state_of "$b")" = enabled ]; then set_role android.app.role.BROWSER "$b"
      else say "SKIP browser stays $(role_holder android.app.role.BROWSER): $b is still off"; fi
    fi
  fi
  [ "$DRY" = 1 ] && { say "OK dry run: nothing changed"; return 0; }
  say "MANUAL Remove the Google account you added, if any: Settings > Accounts and backup > Manage accounts."
  say "OK undo finished. Reboot, then check Home and Settings."
}

# ---- finish: the last steps, done by reading the screen (uiautomator dump) and touching it (input). No root.
# Every wait ends. UI_WAIT_S replaces each timeout and UI_PAUSE_S the pause after a touch (the tests set both).
UIX="$DIR/ui.xml"; UIN="$DIR/ui.txt"
URL=https://decadentcoffee.app/app/
WEBVIEW=com.google.android.webview
pause() { sleep "${UI_PAUSE_S:-1}"; }
tmo() { echo "${UI_WAIT_S:-$1}"; }
# One node per line in $UIN. uiautomator fails while the screen animates, so try three times.
ui_dump() {
  _n=0
  while [ $_n -lt 3 ]; do
    rm -f "$UIX"; uiautomator dump "$UIX" >/dev/null 2>&1
    if [ -s "$UIX" ]; then tr '<' '\n' < "$UIX" | grep '^node ' > "$UIN"; return 0; fi
    _n=$((_n+1)); pause
  done
  : > "$UIN"; return 1
}
# ui_line <attrs> <regex> [must match] [must not match]: first node whose attribute is exactly the regex, any case.
ui_line() { grep -iE "(^| )($1)=\"($2)\"" "$UIN" | grep -iE "${3:-.}" | grep -viE "${4:-^\$}" | head -n 1; }
box() { echo "$1" | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p'; }
mid() { box "$1" | awk '{print int(($1+$3)/2), int(($2+$4)/2)}'; }
attr_of() { echo "$1" | sed -n "s/.* $2=\"\([^\"]*\)\".*/\1/p"; }
ui_find() { _l="$(ui_line "$@")"; [ -n "$_l" ] && mid "$_l"; }
# ui_wait <attrs> <regex> <seconds> [must] [not]: dump until the node shows; prints its centre.
ui_wait() {
  _end=$(( $(date +%s) + $(tmo "$3") ))
  while :; do
    ui_dump; _p="$(ui_find "$1" "$2" "${4:-.}" "${5:-^\$}")"
    [ -n "$_p" ] && { echo "$_p"; return 0; }
    [ "$(date +%s)" -ge "$_end" ] && return 1
    pause
  done
}
# A labelled node under the point x y, if any.
node_at() {
  awk -v x="$1" -v y="$2" 'match($0, /bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"/) {
    b = substr($0, RSTART + 8, RLENGTH - 9); gsub(/\[|\]|,/, " ", b); split(b, a, " ")
    if (x >= a[1] && x < a[3] && y >= a[2] && y < a[4] && ($0 ~ / text="[^"]/ || $0 ~ /content-desc="[^"]/)) { print; exit } }' "$UIN"
}
in_box() { [ "$1" -ge "$3" ] && [ "$1" -lt "$5" ] && [ "$2" -ge "$4" ] && [ "$2" -lt "$6" ]; }
screen_wh() {
  _wh="$(sed -n 's/.*bounds="\[[0-9]*,[0-9]*\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2/p' "$UIN" | awk '$1>w{w=$1} $2>h{h=$2} END{if(w>0)print w, h}')"
  [ -n "$_wh" ] || _wh="$(wm size | sed -n 's/.*size: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -n 1)"
  echo "$_wh"
}
tap() { input tap "$1" "$2"; pause; }
long_press() { input swipe "$1" "$2" "$1" "$2" 900; pause; }
key() { input keyevent "$@"; pause; }
go_home() { key KEYCODE_HOME; }
wake() { input keyevent KEYCODE_WAKEUP; wm dismiss-keyguard >/dev/null 2>&1; pause; }
drag() { # x1 y1 x2 y2 [milliseconds]. `input draganddrop` holds, then moves (Android 12+). Separate motionevent calls did not
  # make Fossify start a drag on the reference tablet, so they are only the fallback.
  if input draganddrop "$1" "$2" "$3" "$4" "${5:-1500}" 2>/dev/null; then pause; return 0; fi
  input motionevent DOWN "$1" "$2"; sleep "${UI_HOLD_S:-1.0}"
  _i=1
  while [ $_i -le 8 ]; do
    input motionevent MOVE $(( $1 + ($3 - $1) * _i / 8 )) $(( $2 + ($4 - $2) * _i / 8 )); sleep "${UI_STEP_S:-0.1}"; _i=$((_i+1))
  done
  sleep "${UI_STEP_S:-0.3}"; input motionevent UP "$3" "$4"; pause
}
# seek <regex> [attrs]: the node with this text (or other attributes), scrolling down up to 4 times, then back up
# up to 4 times. Sets SEEK.
seek() {
  _s=0; _a="${2:-text|content-desc}"
  while :; do
    ui_dump; SEEK="$(ui_line "$_a" "$1" . 'EditText')"
    [ -n "$SEEK" ] && return 0
    [ $_s -ge 8 ] && return 1
    _wh="$(screen_wh)"; _w="${_wh% *}"; _h="${_wh#* }"; [ -n "$_h" ] || return 1
    if [ $_s -lt 4 ]; then input swipe $((_w/2)) $((_h*3/4)) $((_w/2)) $((_h*3/10)) 300
    else input swipe $((_w/2)) $((_h*3/10)) $((_w/2)) $((_h*3/4)) 300; fi
    pause; _s=$((_s+1))
  done
}

wifi_up() { cmd wifi status 2>/dev/null | grep -qi 'is connected to'; }
# Decadent as an installed web app: a Chrome WebAPK whose package report names Decadent's address. Another site's
# WebAPK does not count.
has_webapk() {
  for _w in $(pm list packages --user "$USER_ID" 2>/dev/null | sed -n 's/^package:\(org\.chromium\.webapk\..*\)$/\1/p'); do
    dumpsys package "$_w" 2>/dev/null | grep -q 'decadentcoffee\.app' && return 0
  done
  return 1
}
is_fossify() { [ "$(role_holder android.app.role.HOME)" = "$FOSSIFY" ]; }
ver_of() { dumpsys package "$1" 2>/dev/null | grep -m 1 versionName | sed 's/.*versionName=//'; }
grid_box() { # Fossify's Home grid, else its largest view
  _l="$(grep 'resource-id="org.fossify.home:id/home_screen_grid"' "$UIN" | head -n 1)"
  if [ -n "$_l" ]; then box "$_l"; return; fi
  grep 'package="org.fossify.home"' "$UIN" | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' |
    awk '{a=($3-$1)*($4-$2)} a>m{m=a; b=$0} END{if(m>0)print b}'
}
home_labels() { grep 'package="org.fossify.home"' "$UIN" | grep -qE '( text|content-desc)="[^"]'; }
# home_wait [labels]: press Home until Fossify's own screen can be read (with its icon labels, when asked). A tablet
# that has just restarted needs a while: straight after the restart the first read found no Home at all.
# The Home role can name Fossify while the Home key still opens the tablet's own Home (reference tablet, 21 Nov 2026:
# a restart straight after the role was set; every Home step then read "cannot find the Home screen"). Asking for the
# role again cures it.
home_mend() {
  is_fossify || return 0
  cmd package resolve-activity --brief --user "$USER_ID" -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1 | grep -q "^$FOSSIFY/" && return 0
  cmd role add-role-holder --user "$USER_ID" android.app.role.HOME "$FOSSIFY" >/dev/null 2>&1; sleep 1
}
home_wait() {
  home_mend
  _hend=$(( $(date +%s) + $(tmo 60) ))
  while :; do
    wake; go_home
    if ui_dump && grep -q 'package="org.fossify.home"' "$UIN"; then
      [ "$1" = labels ] || return 0
      home_labels && return 0
    fi
    [ "$(date +%s)" -ge "$_hend" ] && return 1
    sleep 2
  done
}
home_spot() { # label: centre of its icon on Home (grid or dock), if there is one. Call it on Home.
  _ln="$(ui_line 'text|content-desc' "$1" 'package="org.fossify.home"' 'EditText')"; [ -n "$_ln" ] && mid "$_ln"
}

# The original Decent app is not an app of its own: it is a script that AndroWish runs, and its Home icon is a shortcut
# that AndroWish pinned to Samsung's Home. A pinned shortcut stays with the Home app it was pinned to, so Fossify starts
# without it. "Original mode" is a tablet that has that app and no Decaid: Home then leads with it (owner, 20 Nov 2026).
DE1PLUS="${DE1PLUS_DIR:-/sdcard/de1plus}"; WISH=tk.tcl.wish
has_original() { [ -f "$DE1PLUS/de1plus.tcl" ] && usable "$WISH"; }
original_mode() { has_original && ! installed net.tadel.reaprime; }
# AndroWish pins the shortcut again, to the Home app now in charge, when a script asks it to. The script here asks for
# that and nothing else: it loads none of the Decent app, so nothing reaches the machine. Fossify takes the icon without
# a question and puts it in the first free cell of the page that is showing (reference tablet, 20 Nov 2026).
pin_ask() { # label script icon: AndroWish asks the Home app for one shortcut of the Decent app. pin_end follows it.
  # AndroWish names a new shortcut "pinned-<how many it has>". Two things can make that name one that is taken, and
  # Android then pins the older shortcut again, under its own label, so the wanted icon never comes.
  # 1. Dead records. After Undo and a new set-up, a restart brings back the records of the removed Home's icons:
  #    counted, pinned by nothing (reference tablet, 21 Nov 2026: a count of 4 with two pinned, and Update Decent
  #    refused on a clean set-up). Android drops them whenever it tidies any package's shortcuts, so it is asked to
  #    tidy a package that does not exist: nothing else changes, and the count is true again.
  # 2. An icon removed by hand. The count then names an icon that is still there. No request is made: 2 when the
  #    icon in the way is on this Home (Undo and a new set-up cure it), 3 when it is on the tablet's own Home.
  cmd shortcut clear-shortcuts --user "$USER_ID" decent.setup.none >/dev/null 2>&1
  _n="$(cmd shortcut get-shortcuts --user "$USER_ID" --flags 15 "$WISH" 2>/dev/null | grep -c 'ShortcutInfo {')"
  _own="$(dumpsys shortcut 2>/dev/null | awk -v id="pinned-$_n" '/Launcher: /{l=$2} $1=="Pinned:" && $2==id {print l; exit}')"
  say "INFO pin $1: AndroWish has $_n shortcuts"
  case "$_own" in "") ;; org.fossify.home) return 2 ;; *) return 3 ;; esac
  _t="${PIN_DIR:-/sdcard/Download}/decent-setup-pin.tcl"
  cat > "$_t" <<PIN_EOF || return 1
catch {
  package require base64
  set f [open "$DE1PLUS/$3" rb]; set d [read \$f]; close \$f
  borg shortcut add "$1" "file://$DE1PLUS/$2" [::base64::encode -maxlen 0 \$d]
}
after 3000 exit
PIN_EOF
  am force-stop "$WISH" >/dev/null 2>&1
  am start -a android.intent.action.VIEW -t application/x-tcl -d "file://$_t" -n "$WISH/.AndroWishLauncher" >/dev/null 2>&1
  sleep "${PIN_WAIT_S:-6}" # Android takes the request only while AndroWish is on the screen: no Home press before it has asked
}
pin_end() { am force-stop "$WISH" >/dev/null 2>&1; rm -f "${PIN_DIR:-/sdcard/Download}/decent-setup-pin.tcl"; }
pin_original() {
  go_home; ui_dump
  [ -n "$(home_spot Decent)" ] && return 0
  # Fossify 1.10.0 crashes when a shortcut arrives on a Home with no icon at all, and Android then forgets which Home
  # app was chosen (reference tablet, 20 Nov 2026). So the other icons go first, and an empty Home is left alone.
  home_labels || return 1
  pin_ask Decent de1plus.tcl de1plus_icon_v2.png || return $?
  # With one Home page Fossify puts the new icon on a second page it makes for it; with two it lands on the first.
  # From the second page, a slow drag to the left edge turns the page and drops it in the first column.
  _pe=$(( $(date +%s) + $(tmo 20) )); _ok=1
  while :; do
    pause; go_home
    if ui_dump && [ -n "$(home_spot Decent)" ]; then _ok=0; break; fi
    _one="$(home_sig)"; page_two; _q="$(home_spot Decent)"
    if [ -n "$_q" ] && [ "$_one" != "$(home_sig)" ]; then
      _gb="$(grid_box)"
      if [ -n "$_gb" ]; then
        set -- $_gb; drag $_q $(( $1 + 3 )) $(( ($2 + $4) / 2 )) 6000
        go_home; ui_dump && [ -n "$(home_spot Decent)" ] && _ok=0
      fi
      break
    fi
    [ "$(date +%s)" -ge "$_pe" ] && break
  done
  pin_end
  return $_ok
}
# pin_two <label> <script> <icon> <column>: a shortcut of the Decent app on the second Home page, in the middle row.
# With one Home page Fossify makes the second page for the new icon; with two it lands on the first, and one slow
# drag to the right edge carries it over. An icon already on Home, on either page, is left where the person has it.
# "Update Decent" is the Decent app's own updater: a second shortcut, to appupdate.tcl (install_update_app_icon in the
# app's gui.tcl). It goes on the second page, where Settings joins it (owner, 20 Nov 2026).
PIN_TAKEN="its icon was removed from Home by hand before. Choose Undo to put the Home screen back, then set it up again"
PIN_GONE="an icon of the Decent app was removed from the tablet's own Home screen before, and Android cannot make this one"
pin_two() {
  lab="$1"; _ps="$2"; _pi="$3"; _pc="$4"
  [ -f "$DE1PLUS/$_ps" ] && [ -f "$DE1PLUS/$_pi" ] || { say "SKIP finish more $lab not on this tablet"; return 0; }
  go_home; ui_dump
  home_labels || { say "MANUAL finish more $lab Home has no icons yet"; return 0; }
  _u="$(home_spot "$lab")"; _one="$(home_sig)"
  if [ -z "$_u" ]; then page_two; [ "$_one" != "$(home_sig)" ] && _u="$(home_spot "$lab")"; fi
  [ -n "$_u" ] && { go_home; say "SKIP finish more $lab already on Home"; return 0; }
  pin_ask "$lab" "$_ps" "$_pi"
  case $? in 0) ;; 2) say "MANUAL finish more $lab $PIN_TAKEN"; return 0 ;; 3) say "MANUAL finish more $lab $PIN_GONE"; return 0 ;; *) say "MANUAL finish more $lab could not add its icon"; return 0 ;; esac
  _pe=$(( $(date +%s) + $(tmo 20) )); _on=0; _q=""
  while :; do
    pause; go_home
    if ui_dump && [ -n "$(home_spot "$lab")" ]; then _on=1; break; fi
    _one="$(home_sig)"; page_two; _q="$(home_spot "$lab")"
    if [ -n "$_q" ] && [ "$_one" != "$(home_sig)" ]; then _on=2; break; fi
    [ "$(date +%s)" -ge "$_pe" ] && break
  done
  pin_end
  [ "$_on" = 0 ] && { go_home; say "MANUAL finish more $lab could not add its icon"; return 0; }
  if [ "$_on" = 1 ]; then
    # It landed on the first page. Two moves carry it over: to the last column of its own row, then a short hold
    # at the right edge. The hold grows until the page turns once: 1.2 s did it on the reference tablet, and 4 s
    # turned two pages (21 Nov 2026). A cell that holds an icon is never dropped on: that would make a folder.
    _away="MANUAL finish more $lab is on Home: drag it to the second Home page"
    go_home; ui_dump; _q="$(home_spot "$lab")"; gb="$(grid_box)"
    [ -n "$_q" ] && [ -n "$gb" ] || { say "$_away"; return 0; }
    set -- $gb; cw=$(( ($3 - $1) / 5 )); _qy="${_q#* }"; _lx=$(( $1 + cw * 4 + cw / 2 )); _ex=$(( $3 - 3 ))
    if ! in_box $_q $(( $1 + cw * 4 )) $2 $3 $4; then
      [ -z "$(node_at $_lx $_qy)" ] || { say "$_away"; return 0; }
      drag $_q $_lx $_qy
    fi
    for _t in ${PIN_EDGE_MS:-1200 1800 2400}; do
      go_home; ui_dump; _q="$(home_spot "$lab")"; [ -n "$_q" ] || break
      drag $_q $_ex $_qy $_t
    done
    _one=""; go_home; ui_dump && _one="$(home_sig)"; page_two; _q="$(home_spot "$lab")"
    { [ -n "$_q" ] && [ "$_one" != "$(home_sig)" ]; } || { go_home; say "$_away"; return 0; }
  fi
  gb="$(grid_box)"
  if [ -n "$gb" ]; then
    set -- $gb; cw=$(( ($3 - $1) / 5 )); rh=$(( ($4 - $2) / 3 ))
    cell="$(( $1 + cw * (_pc - 1) )) $(( $2 + rh )) $(( $1 + cw * _pc )) $(( $2 + 2 * rh ))"
    _tx=$(( $1 + cw * (_pc - 1) + cw / 2 )); _ty=$(( $2 + rh + rh / 2 ))
    # Its cell, unless the person keeps something there: then it stays where it landed.
    in_box $_q $cell || [ -n "$(node_at $_tx $_ty)" ] || { drag $_q $_tx $_ty; pause; }
  fi
  go_home; log_change finish "more:$lab" - ok; say "DONE finish more $lab"
}
pin_update() { pin_two "Update Decent" appupdate.tcl cloud_download_icon.png 2; }

fin_status() {
  if has_original; then say "STATUS original_app=yes"; else say "STATUS original_app=no"; fi
  if wifi_up; then say "STATUS wifi=connected"; else say "STATUS wifi=disconnected"; fi
  if [ "$(dumpsys account 2>/dev/null | grep -c 'type=com\.google}')" -gt 0 ]; then say "STATUS google_account=yes"; else say "STATUS google_account=no"; fi
  say "STATUS home=$(role_holder android.app.role.HOME)"
  if has_webapk; then say "STATUS decadent_app=installed"; else say "STATUS decadent_app=none"; fi
  say "OK finish status"
}

# Wi-Fi is joined by the owner on the tablet's own screen, like the Google sign-in: nothing here asks for or sees
# the network name or password. Status only reports connected or not.
fin_wifi_open() {
  wake
  out="$(am start -a android.settings.WIFI_SETTINGS 2>&1)"
  case "$out" in *Error*|*Exception*) say "MANUAL finish wifi-open cannot open Wi-Fi settings" ;;
    *) say "DONE finish wifi-open" ;; esac
}

fin_account_open() {
  wake
  out="$(am start -a android.settings.ADD_ACCOUNT_SETTINGS --esa account_types com.google 2>&1)"
  case "$out" in *Error*|*Exception*) out="$(am start -a android.settings.SYNC_SETTINGS 2>&1)" ;; esac
  case "$out" in *Error*|*Exception*) say "MANUAL finish account-open cannot open the accounts screen" ;;
    *) say "DONE finish account-open" ;; esac
}

fin_icons() {
  is_fossify || { say "SKIP finish icons home screen option not used"; return 0; }
  home_wait labels || { say "MANUAL finish icons cannot read the Home screen icons"; return 0; }
  n=0; seen=0; why=""
  # Fossify fills Home with the browser, Play Store and Camera. Without Clean up the browser is Samsung Internet.
  for lab in Chrome "Internet|Samsung Internet" "Play Store" Camera; do
    p="$(home_spot "$lab")"; [ -n "$p" ] || continue
    seen=$((seen+1))
    long_press $p
    r="$(ui_wait 'text|content-desc' 'remove' 5)" || { why="no Remove option appeared for $lab"; key KEYCODE_BACK; go_home; break; }
    tap $r; ui_dump
    if [ -n "$(home_spot "$lab")" ]; then why="$lab is still on Home"; break; fi
    n=$((n+1))
  done
  [ $n -gt 0 ] && log_change finish icons - "removed=$n"
  if [ -n "$why" ]; then say "MANUAL finish icons $why"
  elif [ $seen = 0 ]; then say "SKIP finish icons none on Home"
  else say "DONE finish icons removed=$n"; fi
}

# pick_count <label regex> <value>: open the setting, choose the value unless it is already chosen.
# Fossify Home's settings, found by their view ids (stable across languages). Seen on Fossify Launcher 1.10.0:
# settings_home_screen_row_count / _column_count show the value; tapping opens a list of "3 rows", "5 columns".
FSET=org.fossify.home:id/settings_
# pick_count <row|column> <n>
pick_count() {
  seek "${FSET}home_screen_$1_count" resource-id || { WHY="cannot find the Home screen $1 count"; return 1; }
  [ "$(attr_of "$SEEK" text)" = "$2" ] && return 0
  _lb="$(ui_line resource-id "${FSET}home_screen_$1_count_label")"; [ -n "$_lb" ] || _lb="$SEEK"
  tap $(mid "$_lb")
  o="$(ui_wait text "$2( $1s)?" 5 'checkable="true"')" || { WHY="no $2 in the $1 count list"; key KEYCODE_BACK; return 1; }
  tap $o; CH=$((CH+1))
  ui_dump; ok="$(ui_find text 'ok' 'Button')"; [ -n "$ok" ] && tap $ok
  seek "${FSET}home_screen_$1_count" resource-id && [ "$(attr_of "$SEEK" text)" = "$2" ] || { WHY="the Home screen $1 count did not change"; return 1; }
  return 0
}
fin_launcher() {
  is_fossify || { say "SKIP finish launcher home screen option not used"; return 0; }
  home_wait || { say "MANUAL finish launcher cannot find the Home screen"; return 0; }
  gb="$(grid_box)"; [ -n "$gb" ] || { say "MANUAL finish launcher cannot find the Home screen"; return 0; }
  set -- $gb; w=$(($3-$1)); h=$(($4-$2)); spot=""
  for f in "5 6" "5 2" "1 6" "9 6" "5 10"; do # tenths across, twelfths down: upper middle first
    x=$(( $1 + w * ${f% *} / 10 )); y=$(( $2 + h * ${f#* } / 12 ))
    [ -z "$(node_at $x $y)" ] && { spot="$x $y"; break; }
  done
  [ -n "$spot" ] || { say "MANUAL finish launcher no empty space on Home"; return 0; }
  long_press $spot
  p="$(ui_wait 'text|content-desc' 'launcher settings' 5)" || { key KEYCODE_BACK; say "MANUAL finish launcher no Launcher settings option"; return 0; }
  tap $p
  CH=0; WHY=""
  pick_count row 3 && pick_count column 5 && {
    sw="${FSET}close_app_drawer_on_other_app"
    if ! seek "$sw" resource-id; then WHY="cannot find Close app drawer on opening an app"
    elif [ "$(attr_of "$SEEK" checked)" = false ]; then
      tap $(mid "$SEEK"); seek "$sw" resource-id
      if [ "$(attr_of "$SEEK" checked)" = true ]; then CH=$((CH+1)); else WHY="Close app drawer on opening an app stayed off"; fi
    fi
  }
  key KEYCODE_BACK; go_home
  [ $CH -gt 0 ] && log_change finish launcher - "changed=$CH"
  if [ -n "$WHY" ]; then say "MANUAL finish launcher $WHY"
  elif [ $CH = 0 ]; then say "SKIP finish launcher already set"
  else say "DONE finish launcher"; fi
}

fin_update_one() {
  pkg="$1"
  wifi_up || { say "MANUAL finish update $pkg no network"; return 0; }
  v0="$(ver_of "$pkg")"
  out="$(am start -a android.intent.action.VIEW -d "market://details?id=$pkg" -p com.android.vending 2>&1)"
  case "$out" in *Error*|*Exception*) say "MANUAL finish update $pkg cannot open the Play Store"; return 0 ;; esac
  # Up to date shows Open/Uninstall for Chrome and only "Remove updates" for WebView (Play, Nov 2026). Never tap that one.
  ui_wait 'text|content-desc' 'update|open|uninstall|remove updates|deactivate|disable|sign in' 20 'package="com.android.vending"' >/dev/null ||
    { say "MANUAL finish update $pkg the Play Store page did not load"; return 0; }
  [ -n "$(ui_line 'text|content-desc' 'sign in')" ] && { say "MANUAL finish update $pkg needs a Google account"; return 0; }
  p="$(ui_find 'text|content-desc' 'update' 'package="com.android.vending"')"
  [ -n "$p" ] || { say "SKIP finish update $pkg up to date"; return 0; }
  tap $p
  end=$(( $(date +%s) + $(tmo 240) ))
  while :; do
    ui_dump
    if [ -z "$(ui_find 'text|content-desc' 'update' 'package="com.android.vending"')" ] && [ "$(ver_of "$pkg")" != "$v0" ]; then
      log_change finish "update:$pkg" "$v0" ok; say "DONE finish update $pkg"; return 0
    fi
    [ "$(date +%s)" -ge "$end" ] && break
    pause
  done
  say "MANUAL finish update $pkg the update did not finish in 4 minutes"
}
fin_updates() {
  wake
  for pkg in "$CHROME" "$WEBVIEW"; do fin_update_one "$pkg"; done
  go_home; say "OK finish updates"
}

# Chrome sometimes shows no Install button the first time (seen once on the reference tablet, straight after an undo;
# the second try installed it). So one failed try is followed by one more.
fin_decadent() {
  _o="$(fin_decadent_once)"
  case "$_o" in MANUAL*) has_webapk || { go_home; _o="$(fin_decadent_once)"; } ;; esac
  echo "$_o"
}
fin_decadent_once() {
  has_webapk && { say "SKIP finish decadent already installed"; return 0; }
  wake
  out="$(am start -a android.intent.action.VIEW -d "$URL" -p "$CHROME" 2>&1)"
  case "$out" in *Error*|*Exception*) say "MANUAL finish decadent cannot open Chrome"; return 0 ;; esac
  C='package="com.android.chrome"'; page=""
  end=$(( $(date +%s) + $(tmo 30) ))
  while :; do # Chrome's first-run screens come before the page on a new tablet
    ui_dump
    fre="$(ui_find text 'accept (&amp;|&) continue|use without an account|no thanks|no, thanks' "$C")"
    if [ -n "$fre" ]; then tap $fre
    elif [ -n "$(ui_line 'text|content-desc' '[^"]*decadentcoffee\.app[^"]*' "$C")" ]; then page=1; break; fi
    [ "$(date +%s)" -ge "$end" ] && break
    pause
  done
  [ -n "$page" ] || { say "MANUAL finish decadent the page did not open"; return 0; }
  how=install
  p="$(ui_find 'text|content-desc' 'install( app)?' "$C" 'EditText')"
  if [ -n "$p" ]; then tap $p
  else
    m="$(ui_find content-desc 'more options|customize and control google chrome' "$C")"
    [ -n "$m" ] || { say "MANUAL finish decadent cannot find Chrome's menu"; return 0; }
    tap $m
    # The menu is longer than a landscape screen: scroll its list (app_menu_list) until the item shows.
    IA='install app|install and create shortcut|add to home ?screen'; i=""; _k=0
    while [ $_k -le 4 ]; do
      ui_dump; i="$(ui_find 'text|content-desc' "$IA" "$C")"; [ -n "$i" ] && break
      ml="$(ui_line resource-id 'com.android.chrome:id/app_menu_list')"; [ -n "$ml" ] || break
      set -- $(box "$ml"); input swipe $(( ($1+$3)/2 )) $(( $4 - 40 )) $(( ($1+$3)/2 )) $(( $2 + 40 )) 400; pause
      _k=$((_k+1))
    done
    [ -n "$i" ] || { key KEYCODE_BACK; say "MANUAL finish decadent Chrome offers no Install app"; return 0; }
    case "$(attr_of "$(ui_line 'text|content-desc' "$IA" "$C")" text)" in [Aa]dd*) how=add ;; esac
    tap $i
  fi
  d="$(ui_wait text 'install|add' 10 'class="android.widget.Button"')" && tap $d
  end=$(( $(date +%s) + $(tmo 60) ))
  while :; do
    has_webapk && { log_change finish decadent - webapk; say "DONE finish decadent"; go_home; return 0; }
    [ "$(date +%s)" -ge "$end" ] && break
    pause
  done
  go_home
  if [ -z "$d" ]; then say "MANUAL finish decadent no Install button in the dialog"
  elif [ "$how" = add ] || dumpsys shortcut 2>/dev/null | grep -q 'decadentcoffee\.app'; then
    log_change finish decadent - shortcut; say "DONE finish decadent shortcut"
  else say "MANUAL finish decadent Chrome did not install the app"; fi
}

# place_one <label> <column>: the middle row of a 5 x 3 grid.
place_one() {
  lab="$1"; col="$2"
  case "$lab" in
    Decaid) installed net.tadel.reaprime || { say "SKIP finish place $lab not installed"; return 0; } ;;
    Decadent) has_webapk || { say "SKIP finish place $lab not installed"; return 0; } ;;
    "Coffee Flow") usable com.pressensor.coffeeflow || { say "SKIP finish place $lab not on this tablet"; return 0; } ;;
    "SE Profiler") usable hu.kavekalmar.sep || { say "SKIP finish place $lab not on this tablet"; return 0; } ;;
    Decent) pin_original; case $? in 0) ;; 2) say "MANUAL finish place $lab $PIN_TAKEN"; return 0 ;; 3) say "MANUAL finish place $lab $PIN_GONE"; return 0 ;; *) say "MANUAL finish place $lab could not add its icon"; return 0 ;; esac ;;
  esac
  go_home; ui_dump
  gb="$(grid_box)"; [ -n "$gb" ] || { say "MANUAL finish place $lab cannot find the Home screen"; return 0; }
  set -- $gb; cw=$(( ($3 - $1) / 5 )); rh=$(( ($4 - $2) / 3 ))
  cell="$(( $1 + cw * (col - 1) )) $(( $2 + rh )) $(( $1 + cw * col )) $(( $2 + 2 * rh ))"
  tx=$(( $1 + cw * (col - 1) + cw / 2 )); ty=$(( $2 + rh + rh / 2 ))
  p="$(home_spot "$lab")"
  if [ -n "$p" ] && in_box $p $cell; then say "SKIP finish place $lab already there"; return 0; fi
  if [ -z "$p" ]; then # from the app list: swipe up from the middle of the grid
    gx=$(( ($1 + $3) / 2 ))
    input swipe $gx $(( $2 + ($4 - $2) * 3 / 4 )) $gx $(( $2 + ($4 - $2) / 4 )) 300; pause
    F='package="org.fossify.home"'
    ui_wait 'text|content-desc|class' "$lab|android.widget.EditText" 5 "$F" >/dev/null ||
      { go_home; say "MANUAL finish place $lab the app list did not open"; return 0; }
    p="$(ui_find 'text|content-desc' "$lab" "$F" 'EditText')"
    if [ -z "$p" ]; then
      s="$(ui_find class 'android.widget.EditText' "$F")"
      [ -n "$s" ] || { go_home; say "MANUAL finish place $lab could not find it in the app list"; return 0; }
      tap $s
      dels=""; _i=0; while [ $_i -lt 30 ]; do dels="$dels KEYCODE_DEL"; _i=$((_i+1)); done
      key KEYCODE_MOVE_END $dels
      input text "$(echo "$lab" | sed 's/ /%s/g')"; pause
      p="$(ui_wait 'text|content-desc' "$lab" 5 "$F" 'EditText')" ||
        { go_home; say "MANUAL finish place $lab could not find it in the app list"; return 0; }
    fi
  fi
  drag $p $tx $ty
  go_home; ui_dump
  if home_labels; then
    q="$(home_spot "$lab")"
    if [ -z "$q" ]; then say "MANUAL finish place $lab not on Home after the drag"; return 0; fi
    in_box $q $cell || { say "MANUAL finish place $lab landed in another cell"; return 0; }
  fi
  log_change finish "place:$lab" - ok; say "DONE finish place $lab"
}
# Decent ships a few more apps a person opens by hand. They go on a second Home page, in the same middle cells.
# (AndroWish is not one of them: it only runs the original Decent app. Nor is the screen recorder: owner, 19 Nov 2026.) Fossify makes the second page when an icon is
# held at the right edge, and one slow drag does that: the icon then sits in the last column of the new page.
MORE_APPS="hu.kavekalmar.sep:SE Profiler
com.pressensor.coffeeflow:Coffee Flow"
home_sig() { grep 'package="org.fossify.home"' "$UIN" | grep -oE '(text|content-desc)="[^"]+"' | tr -d '\n'; }
page_two() { go_home; _wh="$(screen_wh)"; _w="${_wh% *}"; _h="${_wh#* }"; input swipe $((_w*3/4)) $((_h*4/5)) $((_w/4)) $((_h*4/5)) 150; pause; ui_dump; }
# drawer_spot <label>: open the app list and print where the app's icon is. Call it on Home.
drawer_spot() {
  _gb="$(grid_box)"; [ -n "$_gb" ] || return 1
  set -- $_gb; _gx=$(( ($1 + $3) / 2 ))
  input swipe $_gx $(( $2 + ($4 - $2) * 3 / 4 )) $_gx $(( $2 + ($4 - $2) / 4 )) 300; pause
  F='package="org.fossify.home"'
  ui_wait 'text|content-desc|class' "$lab|android.widget.EditText" 5 "$F" >/dev/null || return 1
  _p="$(ui_find 'text|content-desc' "$lab" "$F" 'EditText')"
  if [ -z "$_p" ]; then
    _s="$(ui_find class 'android.widget.EditText' "$F")"; [ -n "$_s" ] || return 1
    tap $_s
    _d=""; _i=0; while [ $_i -lt 30 ]; do _d="$_d KEYCODE_DEL"; _i=$((_i+1)); done
    key KEYCODE_MOVE_END $_d
    input text "$(echo "$lab" | sed 's/ /%s/g')"; pause
    _p="$(ui_wait 'text|content-desc' "$lab" 5 "$F" 'EditText')" || return 1
  fi
  echo "$_p"
}
place_two() { # package label column
  lab="$2"; col="$3"
  usable "$1" || { say "SKIP finish more $lab not on this tablet"; return 0; }
  go_home; ui_dump
  gb="$(grid_box)"; [ -n "$gb" ] || { say "MANUAL finish more $lab cannot find the Home screen"; return 0; }
  set -- $gb; cw=$(( ($3 - $1) / 5 )); rh=$(( ($4 - $2) / 3 ))
  cell="$(( $1 + cw * (col - 1) )) $(( $2 + rh )) $(( $1 + cw * col )) $(( $2 + 2 * rh ))"
  tx=$(( $1 + cw * (col - 1) + cw / 2 )); ty=$(( $2 + rh + rh / 2 ))
  sx=$(( $1 + cw * 4 + cw / 2 )); ex=$(( $3 - 3 ))
  # Is there a second page yet? Without one a swipe shows the first page again.
  one="$(home_sig)"; page_two; two="$(home_sig)"
  if [ "$one" != "$two" ]; then
    q="$(home_spot "$lab")"
    if [ -n "$q" ] && in_box $q $cell; then say "SKIP finish more $lab already there"; return 0; fi
    if [ -z "$q" ]; then # the app list opens over the page that is showing, so the icon drops on this page
      q="$(drawer_spot)" || { go_home; say "MANUAL finish more $lab could not find it in the app list"; return 0; }
    fi
    drag $q $tx $ty
  else
    go_home; ui_dump; p="$(home_spot "$lab")"
    if [ -z "$p" ]; then # from the app list onto the first page's last column, which the standard Home leaves empty
      [ -z "$(node_at $sx $ty)" ] || { say "MANUAL finish more $lab no empty space on Home"; return 0; }
      p="$(drawer_spot)" || { go_home; say "MANUAL finish more $lab could not find it in the app list"; return 0; }
      drag $p $sx $ty
      go_home; ui_dump; p="$(home_spot "$lab")"
      [ -n "$p" ] || { say "MANUAL finish more $lab not on Home after the drag"; return 0; }
    fi
    # Slowly to the right edge: Fossify makes the second page and the icon drops in its last column. Only the first
    # icon goes this way: with a second page already there, the same hold turns two pages.
    drag $p $ex $ty 6000
    page_two; q="$(home_spot "$lab")"
    [ -n "$q" ] || { go_home; say "MANUAL finish more $lab did not reach the second page"; return 0; }
    in_box $q $cell || drag $q $tx $ty
  fi
  page_two; q="$(home_spot "$lab")"
  { [ -n "$q" ] && in_box $q $cell; } || { go_home; say "MANUAL finish more $lab landed in another cell"; return 0; }
  log_change finish "more:$lab" - ok; say "DONE finish more $lab"
}
fin_more() {
  is_fossify || { say "SKIP finish more home screen option not used"; say "OK finish more"; return 0; }
  home_wait || :
  if original_mode; then pin_update; place_two com.android.settings Settings 4; go_home; say "OK finish more"; return 0; fi
  # With Decaid in charge the original Decent app keeps one icon, in the middle of the second page: opened from the
  # app list AndroWish runs nothing, so without it the app could not be opened at all (owner, 21 Nov 2026). It goes
  # first: on a Home with one page Fossify makes the second page for it.
  has_original && pin_two Decent de1plus.tcl de1plus_icon_v2.png 3
  _c=2
  echo "$MORE_APPS" > "$DIR/more.tmp"
  while IFS=: read -r _pk _lb <&3; do place_two "$_pk" "$_lb" $_c; _c=$((_c+2)); done 3< "$DIR/more.tmp" # two apps: cells 2 and 4, either side of the middle
  rm -f "$DIR/more.tmp"
  go_home; say "OK finish more"
}

# Samsung's own Home puts a new app in its app list only. Its long-press menu cannot be read from here, but an icon
# dragged from the app list to the bottom edge of the screen lands on Home (reference tablet, One UI 8.5, 19 Nov 2026).
# Decadent's own icon is told from an older Chrome shortcut of the same name by counting: one more after the drag.
SAMSUNG=com.sec.android.app.launcher
sam_count() { grep "package=\"$SAMSUNG\"" "$UIN" | grep -cE "(text|content-desc)=\"$1\""; }
place_samsung() { # label
  lab="$1"
  has_webapk || { say "SKIP finish place $lab not installed"; return 0; }
  wake; go_home; ui_dump || { say "MANUAL finish place $lab cannot read the screen"; return 0; }
  _wh="$(screen_wh)"; _w="${_wh% *}"; _h="${_wh#* }"; [ -n "$_h" ] || { say "MANUAL finish place $lab cannot read the screen"; return 0; }
  before="$(sam_count "$lab")"
  # "finish place if-missing": the app was here before this visit, so an icon already on Home is left alone.
  case " $ARGS " in *" if-missing "*) [ "$before" -gt 0 ] && { say "SKIP finish place $lab already on Home"; return 0; } ;; esac
  input swipe $((_w/2)) $((_h*3/4)) $((_w/2)) $((_h/4)) 300; pause
  F="package=\"$SAMSUNG\""; p=""; _n=0
  while [ $_n -lt 5 ]; do # the app list is pages side by side
    ui_dump; p="$(ui_find 'text|content-desc' "$lab" "$F")"
    [ -n "$p" ] && break
    input swipe $((_w*3/4)) $((_h/2)) $((_w/4)) $((_h/2)) 200; pause; _n=$((_n+1))
  done
  [ -n "$p" ] || { go_home; say "MANUAL finish place $lab could not find it in the app list"; return 0; }
  drag $p $((_w/2)) $((_h-5)) 5000
  go_home; ui_dump
  [ "$(sam_count "$lab")" -gt "$before" ] || { say "MANUAL finish place $lab not on Home after the drag"; return 0; }
  log_change finish "place:$lab" - samsung; say "DONE finish place $lab"
}
fin_place() {
  if [ "$(role_holder android.app.role.HOME)" = "$SAMSUNG" ]; then
    case " $ARGS " in *" no-decadent "*) say "SKIP finish place Decadent not wanted" ;; *) place_samsung Decadent ;; esac
    go_home; say "OK finish place"; return 0
  fi
  is_fossify || { say "SKIP finish place home screen option not used"; say "OK finish place"; return 0; }
  home_wait || :
  if original_mode; then # no Decaid: the original Decent app leads, with Decent's two other apps; Settings goes to page two (fin_more)
    place_one "Coffee Flow" 3; place_one "SE Profiler" 4; place_one Decent 2 # Decent last: see pin_original
    go_home; say "OK finish place"; return 0
  fi
  place_one Decaid 2
  # "finish place no-decadent": the owner left Decadent off, so its icon stays off Home even when it is installed.
  case " $ARGS " in *" no-decadent "*) say "SKIP finish place Decadent not wanted" ;; *) place_one Decadent 3 ;; esac
  place_one Settings 4
  go_home; say "OK finish place"
}

# The Decadent plugin for Decaid, through Decaid's own installer: Plugins, the cog, Install plugin, GitHub Release.
# Decaid then keeps it updated. Installing over a copy that is there keeps its settings and its link. Android's Back
# key leaves Decaid's coffee screen for its menu and sends nothing to the espresso machine.
PLUGIN_REPO=decadentcoffee/decadent-plugin; DECAID=net.tadel.reaprime
# Where Decaid is, from the last screen read: dashboard (its menu shows), skin (the full-screen coffee screen, a web
# view; a skin's own buttons show in the screen read, so buttons do not make it a question), scan (it is looking for
# the machine), or asking (anything else: its first questions, or an Android dialog over it).
decaid_where() {
  if [ -n "$(ui_line content-desc 'Plugins[^"]*' "$D")" ]; then echo dashboard
  elif [ -n "$(ui_line class 'android\.webkit\.WebView' "$D")" ]; then echo skin
  elif [ -n "$(ui_line 'content-desc|text' '(Continue to )?Dashboard' "$D")" ]; then echo scan
  else echo asking; fi
}
# decaid_answer: answer one of a new Decaid's first questions the way a person in a hurry does (D-44). Get Started;
# Skip for now on the Decent account and on the old-data import (both stay on Decaid's Dashboard, under Account and
# Data); Continue offline when Decaid finds no internet; Allow on Android's own questions for Decaid (Bluetooth,
# notifications, running in the background). An Android question is answered only when it names Decaid. True when it
# tapped something. Anything it does not know is left on the screen for the person.
ALLOW_PKGS='com\.android\.permissioncontroller|com\.google\.android\.permissioncontroller|com\.android\.settings'
decaid_answer() {
  for _q in 'Get Started' 'Skip for now' 'Continue offline'; do
    _p="$(ui_find 'content-desc|text' "$_q" "$D")"
    [ -n "$_p" ] && { tap $_p; return 0; }
  done
  if grep -E "package=\"($ALLOW_PKGS)\"" "$UIN" | grep -qE '(text|content-desc)="[^"]*Decaid[^"]*"'; then
    _p="$(ui_find 'text' 'Allow' "package=\"($ALLOW_PKGS)\"")"
    [ -n "$_p" ] && { tap $_p; return 0; }
  fi
  return 1
}
# decaid_menu <seconds>: bring Decaid to its menu. Prints dashboard, or what Decaid still shows when the time is up.
# It answers a new Decaid's first questions (decaid_answer), leaves the coffee screen with Back, and leaves "looking
# for the machine" by Decaid's own Dashboard button once Decaid has had time to find one. None of these sends
# anything to the espresso machine. ANSWERED counts the questions it answered.
decaid_menu() {
  _end=$(( $(date +%s) + $(tmo "$1") )); _scan=""; _w=asking; _acts=0; ANSWERED=0
  while :; do
    ui_dump; _w="$(decaid_where)"
    case "$_w" in
      dashboard) break ;;
      skin) [ $_acts -lt 6 ] && { _acts=$((_acts+1)); key KEYCODE_BACK; continue; } ;;
      scan) [ -n "$_scan" ] || _scan=$(( $(date +%s) + $(tmo 12) ))
        if [ "$(date +%s)" -ge "$_scan" ] && [ $_acts -lt 6 ]; then
          _p="$(ui_find 'content-desc|text' '(Continue to )?Dashboard' "$D")"
          [ -n "$_p" ] && { _acts=$((_acts+1)); tap $_p; continue; }
        fi ;;
      asking) [ $ANSWERED -lt 12 ] && decaid_answer && { ANSWERED=$((ANSWERED+1)); _end=$(( _end + $(tmo 15) )); continue; } ;;
    esac
    [ "$(date +%s)" -ge "$_end" ] && break
    pause
  done
  echo "$_w"
}
# finish decaid [open]: say whether Decaid is at its menu (ready), on its way there with its first questions being
# answered by this script (answering), or showing something this script does not answer (asking). The front end
# calls it until ready, so a Decaid that has never been opened is a short wait, not a failure.
fin_decaid() {
  installed "$DECAID" || { say "STATUS decaid=absent"; say "OK finish decaid"; return 0; }
  D="package=\"$DECAID\""
  case "$ARGS " in *" open "*) wake; monkey -p "$DECAID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep "${UI_PAUSE_S:-3}" ;; esac
  _dm="$(decaid_menu 20; echo " $ANSWERED")"
  case "$_dm" in dashboard*) say "STATUS decaid=ready" ;; asking*" 0") say "STATUS decaid=asking" ;; *) say "STATUS decaid=answering" ;; esac
  say "OK finish decaid"
}

# The plugin's card in Decaid's Plugins list, once all of it is on screen (the list is scrolled down to it).
PLUGIN_CARD='Decadent&#10;by Decadent[^"]*'
plugin_card() {
  _i=0
  while [ $_i -lt 12 ]; do
    ui_dump; _c="$(ui_line 'content-desc|text' "$PLUGIN_CARD" "$D")"
    set -- $(box "$(head -n 1 "$UIN")"); _W=${3:-0}; _H=${4:-0}
    if [ -n "$_c" ]; then set -- $(box "$_c"); [ "${4:-$_H}" -lt $((_H - 4)) ] && { echo "$_c"; return 0; }; fi
    input swipe $((_W/2)) $((_H*3/4)) $((_W/2)) $((_H*2/5)) 300; pause
    _i=$((_i+1))
  done
  return 1
}
# Switch the plugin on from the Plugins list: Load in its menu starts it now, and the card's own switch (Auto-load
# on startup) starts it with Decaid from then on. A plugin that is already on is left as it is.
plugin_on() {
  plugin_card >/dev/null || return 1
  _m="$(awk '/="Decadent&#10;by Decadent/ {f=1; next} f && /content-desc="Show menu"/ {print; exit}' "$UIN")"
  [ -n "$_m" ] || return 1
  tap $(mid "$_m")
  ui_wait 'content-desc|text' 'Load|Unload' 5 "$D" >/dev/null || return 1
  _p="$(ui_find 'content-desc|text' 'Load' "$D")"
  if [ -n "$_p" ]; then tap $_p; sleep "${UI_PAUSE_S:-2}"; else key KEYCODE_BACK; fi
  _c="$(plugin_card)" || return 1
  if [ "$(attr_of "$_c" checked)" != true ]; then
    _d="$(wm density 2>/dev/null | awk '{print $NF}' | tail -n 1)"; case "$_d" in ''|*[!0-9]*) _d=213 ;; esac
    set -- $(box "$_c"); tap $(( $1 + 42 * _d / 160 )) $(( $4 - 32 * _d / 160 ))
    _c="$(plugin_card)" || return 1
    [ "$(attr_of "$_c" checked)" = true ] || return 1
  fi
  return 0
}

# With Android's bottom buttons showing, Decaid draws the end of its Plugins list under the button bar, and the last
# card's Auto-load switch cannot be tapped (reference tablet, Decaid 0.9.2, 19 Nov 2026). So the step runs with swipe
# gestures and puts the buttons back when it ends. This is not recorded as a change: undo has nothing to do with it.
nav_overlay() { cmd overlay enable-exclusive --category "com.android.internal.systemui.navbar.$1" >/dev/null 2>&1; settings put secure navigation_mode "$2"; sleep "${UI_PAUSE_S:-3}"; }
fin_plugin() {
  _nav="$(settings get secure navigation_mode 2>/dev/null)"
  case "$_nav" in 2|'') fin_plugin_do; return 0 ;; esac
  nav_overlay gestural 2
  fin_plugin_do
  nav_overlay threebutton "$_nav"
}
fin_plugin_do() {
  installed "$DECAID" || { say "SKIP finish plugin Decaid is not installed"; return 0; }
  # Straight after a restart Wi-Fi can take a moment.
  _n=0; while ! wifi_up && [ $_n -lt "$(tmo 30)" ]; do sleep 1; _n=$((_n+1)); done
  wifi_up || { say "MANUAL finish plugin needs Wi-Fi"; return 0; }
  wake
  monkey -p "$DECAID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  D="package=\"$DECAID\""; sleep "${UI_PAUSE_S:-3}"
  case "$(decaid_menu 30)" in
    dashboard) ;;
    asking) say "MANUAL finish plugin Decaid is asking its first questions"; return 0 ;;
    *) say "MANUAL finish plugin Decaid's menu did not show"; return 0 ;;
  esac
  ui_dump; p="$(ui_find content-desc 'Plugins[^"]*' "$D")"
  [ -n "$p" ] || { say "MANUAL finish plugin Decaid's menu did not show"; return 0; }
  tap $p
  for want in 'Plugin actions' 'Install plugin' 'GitHub Release'; do
    p="$(ui_wait content-desc "$want" 8 "$D")" || { key KEYCODE_BACK; say "MANUAL finish plugin cannot find $want in Decaid"; return 0; }
    tap $p
  done
  p="$(ui_wait class 'android\.widget\.EditText' 8 "$D")" || { key KEYCODE_BACK; say "MANUAL finish plugin Decaid's install form did not open"; return 0; }
  tap $p; input text "$PLUGIN_REPO"; pause
  ui_dump
  [ -n "$(ui_line text "$PLUGIN_REPO" "$D")" ] || { key KEYCODE_BACK; key KEYCODE_BACK; say "MANUAL finish plugin could not type the plugin's name"; return 0; }
  p="$(ui_find content-desc 'Install' "$D")"
  [ -n "$p" ] || { key KEYCODE_BACK; key KEYCODE_BACK; say "MANUAL finish plugin cannot find Install in Decaid"; return 0; }
  tap $p
  # Done when Decaid says "Plugin installed". Its message shows for a few seconds after the form closes.
  end=$(( $(date +%s) + $(tmo 45) )); got=""
  while :; do
    ui_dump
    [ -n "$(ui_line 'content-desc|text' 'Plugin installed[^"]*' "$D")" ] && { got=1; break; }
    [ "$(date +%s)" -ge "$end" ] && break
  done
  [ -n "$(ui_line content-desc 'Install from GitHub Release' "$D")" ] && key KEYCODE_BACK
  [ -n "$got" ] || { key KEYCODE_BACK; say "MANUAL finish plugin Decaid did not install it"; return 0; }
  # Decaid adds a plugin switched off and not set to start with it (seen on a real tablet, 18 Nov 2026).
  if plugin_on; then key KEYCODE_BACK; say "DONE finish plugin"
  else key KEYCODE_BACK; say "MANUAL finish plugin it is installed but switched off"; fi
}

do_finish() {
  step="${ARGS# }"; step="${step%% *}"
  case "$step" in status|wifi-open|account-open|icons|launcher|updates|decadent|decaid|plugin|place|more) ;;
    *) die "unknown finish step '$step'. Steps: status wifi-open account-open icons launcher updates decadent decaid plugin place more" ;; esac
  mkdir -p "$DIR" || die "cannot write $DIR"
  if [ "$DRY" = 1 ]; then say "PLAN finish $step"; return 0; fi
  case "$step" in
    status) fin_status ;; wifi-open) fin_wifi_open ;; account-open) fin_account_open ;; icons) fin_icons ;;
    launcher) fin_launcher ;; updates) fin_updates ;; decadent) fin_decadent ;; decaid) fin_decaid ;; plugin) fin_plugin ;; place) fin_place ;; more) fin_more ;;
  esac
  rm -f "$UIX" "$UIN" # screen dumps can hold names and addresses
}

DRY=0; FORCE=0; KEEP_APPS=0; UNDO_APPS=0; UNDO_HOME=0; PKGS=""; ARGS=""
CMD="$1"; [ $# -gt 0 ] && shift
for a in "$@"; do case "$a" in
  --dry-run) DRY=1 ;; --force) FORCE=1 ;; --keep-apps) KEEP_APPS=1 ;;
  --apps) UNDO_APPS=1 ;; --home) UNDO_HOME=1 ;; --pkgs=*) PKGS="${a#--pkgs=}" ;;
  *) ARGS="$ARGS $a" ;;
esac; done
init_user
case "$CMD" in
  check) do_check ;;
  status) do_status ;;
  plan) do_check && do_plan ;;
  snapshot) do_check && do_snapshot ;;
  cleanup) do_check && do_cleanup ;;
  apply) do_check && do_cleanup && do_home ;;
  install) do_check && do_install $ARGS ;;
  home) do_check && do_home ;;
  undo) do_undo ;;
  finish) do_finish ;;
  *) sed -n '2,16p' "$0"; exit 2 ;;
esac
