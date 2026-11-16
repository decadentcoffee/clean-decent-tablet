#!/usr/bin/env bash
# Reverse the setup, using the record kept on the tablet. Works from any computer. Shows the plan first.
# Usage: scripts/undo.sh [--apps] [--home] [--pkgs a,b] [--dry-run] [--yes] [--keep-apps] [--serial <id>]
#   --apps: turn apps back on (--pkgs: only these). --home: original Home screen. Neither: both
source "$(dirname "$0")/lib.sh"
DRY=0 YES=0 KEEP="" SER="" PART=""
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) DRY=1; shift ;; --yes) YES=1; shift ;; --keep-apps) KEEP=--keep-apps; shift ;; --apps) PART="$PART --apps"; shift ;; --home) PART="$PART --home"; shift ;; --pkgs) PART="$PART --pkgs=$2"; shift 2 ;; --serial) SER="$2"; shift 2 ;;
  -h|--help) sed -n '2,4p' "$0"; exit 0 ;; *) die "unknown option $1" ;; esac; done
select_device "$SER"
R=/data/local/tmp/decent-setup
remote() { "${ADB[@]}" shell "$@" </dev/null | tr -d '\r'; }
"${ADB[@]}" shell mkdir -p "$R" </dev/null
"${ADB[@]}" push "$ROOT/device/decent-setup.sh" "$ROOT/device/packages-disable.txt" "$ROOT/device/device.expect" "$R/" </dev/null >/dev/null 2>&1
remote sh "$R/decent-setup.sh" undo --dry-run $PART $KEEP | grep -v '^SKIP'
[ $DRY = 1 ] && exit 0
if [ $YES = 0 ]; then read -r -p "Undo all of this? Type yes: " a; [ "$a" = yes ] || die "not confirmed; nothing changed."; fi
remote sh "$R/decent-setup.sh" undo $PART $KEEP | grep -v '^SKIP'
