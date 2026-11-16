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
#   wifi-open launcher updates decadent plugin place. wifi-open only opens Wi-Fi settings: the owner joins on the tablet,
#   and no network name or password ever passes through this script or the page.
#   place no-decadent leaves the Decadent icon off Home.
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
        [ "$(role_holder android.app.role.HOME)" = "$p" ] && { say "SKIP $p is still the Home app"; continue; }
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
drag() { # x1 y1 x2 y2. `input draganddrop` holds, then moves (Android 12+). Separate motionevent calls did not
  # make Fossify start a drag on the reference tablet, so they are only the fallback.
  if input draganddrop "$1" "$2" "$3" "$4" 1500 2>/dev/null; then pause; return 0; fi
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
has_webapk() { pm list packages --user "$USER_ID" 2>/dev/null | grep -q 'org.chromium.webapk'; }
is_fossify() { [ "$(role_holder android.app.role.HOME)" = "$FOSSIFY" ]; }
ver_of() { dumpsys package "$1" 2>/dev/null | grep -m 1 versionName | sed 's/.*versionName=//'; }
grid_box() { # Fossify's Home grid, else its largest view
  _l="$(grep 'resource-id="org.fossify.home:id/home_screen_grid"' "$UIN" | head -n 1)"
  if [ -n "$_l" ]; then box "$_l"; return; fi
  grep 'package="org.fossify.home"' "$UIN" | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' |
    awk '{a=($3-$1)*($4-$2)} a>m{m=a; b=$0} END{if(m>0)print b}'
}
home_labels() { grep 'package="org.fossify.home"' "$UIN" | grep -qE '( text|content-desc)="[^"]'; }
home_spot() { # label: centre of its icon on Home (grid or dock), if there is one. Call it on Home.
  _ln="$(ui_line 'text|content-desc' "$1" 'package="org.fossify.home"' 'EditText')"; [ -n "$_ln" ] && mid "$_ln"
}

fin_status() {
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
  wake; go_home
  ui_dump || { say "MANUAL finish icons cannot read the screen"; return 0; }
  home_labels || { say "MANUAL finish icons cannot read the Home screen icons"; return 0; }
  n=0; seen=0; why=""
  for lab in Chrome "Play Store" Camera; do
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
  wake; go_home
  ui_dump || { say "MANUAL finish launcher cannot read the screen"; return 0; }
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

fin_decadent() {
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
fin_place() {
  is_fossify || { say "SKIP finish place home screen option not used"; say "OK finish place"; return 0; }
  wake
  place_one Decaid 2
  # "finish place no-decadent": the owner left Decadent off, so its icon stays off Home even when it is installed.
  case " $ARGS " in *" no-decadent "*) say "SKIP finish place Decadent not wanted" ;; *) place_one Decadent 3 ;; esac
  place_one Settings 4
  go_home; say "OK finish place"
}

# The Decadent plugin for Decaid, through Decaid's own installer: Plugins, the cog, Install plugin, GitHub Release.
# Decaid then keeps it updated. Installing over a copy that is there keeps its settings and its link. Android's Back
# key leaves Decaid's coffee screen for its menu and sends nothing to the espresso machine.
PLUGIN_REPO=decadentcoffee/plugin; DECAID=net.tadel.reaprime
fin_plugin() {
  installed "$DECAID" || { say "SKIP finish plugin Decaid is not installed"; return 0; }
  wifi_up || { say "MANUAL finish plugin needs Wi-Fi"; return 0; }
  wake
  monkey -p "$DECAID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  D="package=\"$DECAID\""; p=""; _k=0
  while [ $_k -le 3 ]; do
    sleep "${UI_PAUSE_S:-3}"; ui_dump
    p="$(ui_find content-desc 'Plugins' "$D")"; [ -n "$p" ] && break
    # Only a full-screen web view (the coffee screen) is left with Back; a first-run screen is the owner's to answer.
    [ -n "$(ui_line class 'android\.webkit\.WebView' "$D")" ] && [ -z "$(ui_line class 'android\.widget\.(Button|EditText)' "$D")" ] && key KEYCODE_BACK
    _k=$((_k+1))
  done
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
  key KEYCODE_BACK
  [ -n "$got" ] && say "DONE finish plugin" || say "MANUAL finish plugin Decaid did not install it"
}

do_finish() {
  step="${ARGS# }"; step="${step%% *}"
  case "$step" in status|wifi-open|account-open|icons|launcher|updates|decadent|plugin|place) ;;
    *) die "unknown finish step '$step'. Steps: status wifi-open account-open icons launcher updates decadent plugin place" ;; esac
  mkdir -p "$DIR" || die "cannot write $DIR"
  if [ "$DRY" = 1 ]; then say "PLAN finish $step"; return 0; fi
  case "$step" in
    status) fin_status ;; wifi-open) fin_wifi_open ;; account-open) fin_account_open ;; icons) fin_icons ;;
    launcher) fin_launcher ;; updates) fin_updates ;; decadent) fin_decadent ;; plugin) fin_plugin ;; place) fin_place ;;
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
