#!/usr/bin/env bash
# Show the tablet's state. Read-only.
# Usage: scripts/status.sh [--serial <id>]
source "$(dirname "$0")/lib.sh"
SER=""; [ "${1:-}" = --serial ] && SER="$2"
select_device "$SER"
R=/data/local/tmp/decent-setup
"${ADB[@]}" shell mkdir -p "$R" </dev/null
"${ADB[@]}" push "$ROOT/device/decent-setup.sh" "$ROOT/device/packages-disable.txt" "$ROOT/device/device.expect" "$R/" </dev/null >/dev/null 2>&1
"${ADB[@]}" shell sh "$R/decent-setup.sh" status </dev/null | tr -d '\r'
