#!/usr/bin/env bash
# Disable the approved packages of one batch from manifests/packages.csv.
# Dry run unless --apply. Only rows with proposed_action=disable and approval=approved are touched.
# Usage: scripts/disable.sh --batch <n> [--package <id>] [--apply] [--yes] [--serial <id>]
source "$(dirname "$0")/lib.sh"

BATCH="" ONE="" APPLY=0 YES=0 SER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --batch) BATCH="$2"; shift 2 ;;
    --package) ONE="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --dry-run) APPLY=0; shift ;;
    --yes) YES=1; shift ;;
    --serial) SER="$2"; shift 2 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done
[ -n "$BATCH" ] || die "pick a batch with --batch <n>. Small batches only."

select_device "$SER"
USER_ID="$(current_user)"
check_expected_device

plan=()
while IFS=$'\t' read -r pkg batch orig; do
  [ "$batch" = "$BATCH" ] || continue
  [ -z "$ONE" ] || [ "$pkg" = "$ONE" ] || continue
  is_protected "$pkg" && die "$pkg is protected but marked for disabling. Fix the manifest."
  state="$(pkg_state "$pkg")"
  case "$state" in
    absent)   echo "skip  $pkg (not installed for user $USER_ID)" ;;
    disabled) echo "skip  $pkg (already disabled; original state: $orig)" ;;
    enabled)  echo "plan  pm disable-user --user $USER_ID $pkg"; plan+=("$pkg") ;;
  esac
done < <(approved_rows)

echo "device: $(device_id), user $USER_ID, batch $BATCH: ${#plan[@]} package(s) to disable"
[ ${#plan[@]} -gt 0 ] || exit 0
if [ $APPLY = 0 ]; then echo "dry run: nothing changed. Re-run with --apply."; exit 0; fi

if [ $YES = 0 ]; then
  read -r -p "Disable these ${#plan[@]} package(s)? Type yes: " ans
  [ "$ans" = yes ] || die "not confirmed; nothing changed."
fi

# Snapshot the full state before the first change.
"$ROOT/scripts/inventory.sh" --serial "$SERIAL" >/dev/null

refused=0
for pkg in "${plan[@]}"; do
  before="$(pkg_state "$pkg")"
  out="$("${ADB[@]}" shell pm disable-user --user "$USER_ID" "$pkg" </dev/null 2>&1 | tr -d '\r')" || true
  after="$(pkg_state "$pkg")"
  if [ "$after" = disabled ]; then
    log_change disable "$pkg" "$before" "$after" ok
    echo "done  $pkg"
  elif [ "$after" = enabled ] && echo "$out" | grep -q 'Failed to change state'; then
    # Android refused and nothing changed. Record it and carry on.
    log_change disable "$pkg" "$before" "$after" "refused: $out"
    echo "refused  $pkg (Android will not disable it; still enabled)"
    refused=$((refused+1))
  else
    log_change disable "$pkg" "$before" "$after" "fail: $out"
    echo "waiting ${SETTLE_S:-30}s so earlier changes are saved." >&2
    sleep "${SETTLE_S:-30}"
    die "disabling $pkg failed: $out. Stopped. Earlier packages in this batch stay disabled; see scripts/rollback.sh."
  fi
done
# Android writes package state to disk a few seconds later. A reboot before that loses the last changes
# (seen 3 Nov 2026: the last 5 of 24 came back after an immediate reboot).
echo "waiting ${SETTLE_S:-30}s for Android to save the changes. Do not reboot yet."
sleep "${SETTLE_S:-30}"
[ "$refused" = 0 ] || echo "$refused package(s) refused by Android. Set them to keep in the manifest."
echo "batch $BATCH applied. Now run scripts/verify.sh and the manual checks in docs/debloating.md."
