#!/usr/bin/env bash
# Re-enable packages that THIS project disabled on this tablet, read from logs/changes.tsv.
# Never enables a package that was disabled in the original state (manifests/original-disabled.*).
# Dry run unless --apply. Safe to run twice.
# Usage: scripts/rollback.sh [--batch <n> | --package <id>] [--apply] [--yes] [--serial <id>]
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
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done

select_device "$SER"
USER_ID="$(current_user)"
[ -f "$CHANGELOG" ] || { echo "no change log at $CHANGELOG: this project has changed nothing here."; exit 0; }
ORIG="$(ls "$ROOT"/manifests/original-disabled.*.txt 2>/dev/null | head -1)"
[ -n "$ORIG" ] || die "no original-disabled list in manifests/."

# Packages whose latest successful change by us was a disable of an enabled package.
OURS="$(python3 -I - "$CHANGELOG" "$MANIFEST" "$ORIG" "$(serial_tag)" "$BATCH" "$ONE" <<'PY'
import csv, sys
log, manifest, orig, tag, batch, one = sys.argv[1:7]
batches = {r["package"]: r["batch"] for r in csv.DictReader(open(manifest))}
originally_disabled = set(open(orig).read().split())
last = {}
for r in csv.DictReader(open(log), delimiter="\t"):
    if r["device_tag"] != tag or r["result"] != "ok":
        continue
    last[r["package"]] = r
for p, r in sorted(last.items()):
    if r["action"] != "disable" or r["before"] != "enabled" or p in originally_disabled:
        continue
    if batch and batches.get(p) != batch:
        continue
    if one and p != one:
        continue
    print(p)
PY
)"

plan=()
while read -r pkg; do
  [ -n "$pkg" ] || continue
  case "$(pkg_state "$pkg")" in
    disabled) echo "plan  pm enable --user $USER_ID $pkg"; plan+=("$pkg") ;;
    enabled)  echo "skip  $pkg (already enabled)" ;;
    absent)   echo "skip  $pkg (no longer installed; cannot re-enable, reinstall it)" ;;
  esac
done <<< "$OURS"
echo "device: $(device_id), user $USER_ID: ${#plan[@]} package(s) to re-enable"
[ ${#plan[@]} -gt 0 ] || exit 0
if [ $APPLY = 0 ]; then echo "dry run: nothing changed. Re-run with --apply."; exit 0; fi
if [ $YES = 0 ]; then
  read -r -p "Re-enable these ${#plan[@]} package(s)? Type yes: " ans
  [ "$ans" = yes ] || die "not confirmed; nothing changed."
fi

for pkg in "${plan[@]}"; do
  out="$("${ADB[@]}" shell pm enable --user "$USER_ID" "$pkg" </dev/null 2>&1 | tr -d '\r')" || true
  after="$(pkg_state "$pkg")"
  if [ "$after" = enabled ]; then
    log_change enable "$pkg" disabled enabled ok; echo "done  $pkg"
  else
    log_change enable "$pkg" disabled "$after" "fail: $out"
    die "re-enabling $pkg failed: $out"
  fi
done
