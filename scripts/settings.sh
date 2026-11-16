#!/usr/bin/env bash
# Apply or revert this project's device settings. Dry run unless --apply or --revert is given.
# Values: screen sleeps after 10 min, no stay-awake-on-charge, Chrome is the browser.
# Original values: manifests/original-settings.*.txt. Every change goes to logs/changes.tsv.
# Usage: scripts/settings.sh [--apply | --revert] [--serial <id>]
source "$(dirname "$0")/lib.sh"
MODE=dry SER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) MODE=apply; shift ;;
    --revert) MODE=revert; shift ;;
    --serial) SER="$2"; shift 2 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done
select_device "$SER"
USER_ID="$(current_user)"
check_expected_device
ORIG="$(ls "$ROOT"/manifests/original-settings.*.txt 2>/dev/null | head -1)"
[ -n "$ORIG" ] || die "no original-settings list in manifests/."
orig_of() { awk -F= -v k="$1" '$1==k {print $2}' "$ORIG"; }

read_key() { # namespace/key or role/<role>
  case "$1" in
    role/*) sh_ cmd role get-role-holders --user "$USER_ID" "${1#role/}" | head -1 ;;
    *) sh_ settings get "${1%%/*}" "${1#*/}" ;;
  esac
}
write_key() {
  case "$1" in
    role/*) sh_ cmd role add-role-holder --user "$USER_ID" "${1#role/}" "$2" >/dev/null ;;
    *) sh_ settings put "${1%%/*}" "${1#*/}" "$2" >/dev/null ;;
  esac
}
change() { # key target
  local key="$1" want="$2" before after
  before="$(read_key "$key")"
  if [ "$before" = "$want" ]; then echo "skip  $key already $want"; return; fi
  echo "plan  $key: $before -> $want"
  [ "$MODE" = dry ] && return
  write_key "$key" "$want"
  after="$(read_key "$key")"
  if [ "$after" = "$want" ]; then
    log_change "setting-$MODE" "$key" "$before" "$after" ok; echo "done  $key"
  else
    log_change "setting-$MODE" "$key" "$before" "$after" fail
    die "$key did not change: still $after"
  fi
}

if [ "$MODE" = revert ]; then
  change system/screen_off_timeout "$(orig_of system/screen_off_timeout)"
  change global/stay_on_while_plugged_in "$(orig_of global/stay_on_while_plugged_in)"
  change role/android.app.role.BROWSER "$(orig_of role/android.app.role.BROWSER)"
  change global/navigation_bar_gesture_hint "$(orig_of global/navigation_bar_gesture_hint)"
  change secure/edge_enable "$(orig_of secure/edge_enable)"
else
  [ "$(pkg_state com.android.chrome)" = enabled ] || die "Chrome is not enabled."
  change system/screen_off_timeout 600000
  change global/stay_on_while_plugged_in 0
  change role/android.app.role.BROWSER com.android.chrome
  # Hides the gesture line. Choose Swipe gestures by hand first: docs/startup.md.
  change global/navigation_bar_gesture_hint 0
  # Removes Samsung's Edge panel handle from the side of the screen.
  change secure/edge_enable 0
fi
[ "$MODE" = dry ] && echo "dry run: nothing changed. Use --apply or --revert."
exit 0
