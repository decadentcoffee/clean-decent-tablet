#!/usr/bin/env bash
# Set up a Decent tablet from a computer. Shows the plan first, and changes nothing until you type yes.
# Usage: scripts/setup.sh [--cleanup] [--home] [--keep <pkg,pkg>] [--dry-run] [--yes] [--force] [--serial <id>]
#   --cleanup  only option 1: switch off the tested list of apps, Chrome as browser, sleep after 10 minutes
#   --home     only option 2: Fossify Launcher as Home with Decaid, Decadent and Settings, swipe gestures
#   --keep     leave these packages on (comma-separated ids from docs/packages.md)
#   Neither flag means both. --force runs on a model or firmware not listed in manifests/device.expect
source "$(dirname "$0")/lib.sh"
DRY=0 YES=0 FORCE="" SER="" CLEAN=0 HOMESCR=0 KEEP=""
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) DRY=1; shift ;; --yes) YES=1; shift ;; --force) FORCE=--force; shift ;; --serial) SER="$2"; shift 2 ;;
  --cleanup) CLEAN=1; shift ;; --keep) KEEP="$2"; shift 2 ;; --home) HOMESCR=1; shift ;;
  -h|--help) sed -n '2,8p' "$0"; exit 0 ;; *) die "unknown option $1" ;; esac; done
[ $CLEAN = 0 ] && [ $HOMESCR = 0 ] && CLEAN=1 HOMESCR=1
select_device "$SER"
R=/data/local/tmp/decent-setup
remote() { "${ADB[@]}" shell "$@" </dev/null | tr -d '\r'; }
python3 "$ROOT/scripts/render-packages.py" >/dev/null
"${ADB[@]}" shell mkdir -p "$R" </dev/null
"${ADB[@]}" push "$ROOT/device/decent-setup.sh" "$ROOT/device/packages-disable.txt" "$ROOT/device/device.expect" "$R/" </dev/null >/dev/null 2>&1
if [ -n "$KEEP" ]; then # the tested list minus the packages to keep
  mkdir -p "$LOGS"; awk -v k=",$KEEP," 'index(k, ","$2",")==0' "$ROOT/device/packages-disable.txt" > "$LOGS/.list"
  echo "Keeping: $KEEP"; "${ADB[@]}" push "$LOGS/.list" "$R/packages-disable.txt" </dev/null >/dev/null 2>&1
fi
remote sh "$R/decent-setup.sh" plan $FORCE | tee "$LOGS/.plan" ; grep -q '^FAIL' "$LOGS/.plan" && exit 1
echo "Options: $([ $CLEAN = 1 ] && echo '1 clean-up ')$([ $HOMESCR = 1 ] && echo '2 home-screen')"
if [ $DRY = 1 ]; then
  [ $CLEAN = 1 ] && remote sh "$R/decent-setup.sh" cleanup --dry-run $FORCE | grep -vE '^(SKIP|INFO|CHECK)'
  [ $HOMESCR = 1 ] && remote sh "$R/decent-setup.sh" home --dry-run $FORCE | grep -vE '^(SKIP|INFO|CHECK)'
  exit 0
fi
if [ $YES = 0 ]; then read -r -p "Change this tablet? scripts/undo.sh reverses it. Type yes: " a; [ "$a" = yes ] || die "not confirmed; nothing changed."; fi

CACHE="$LOGS/apks"; mkdir -p "$CACHE"
grep -v '^#' "$ROOT/manifests/apks.txt" | while read -r name pkg url sha; do
  [ -n "$name" ] || continue
  [ "$name" = fossify ] && [ $HOMESCR = 0 ] && continue
  if remote pm list packages "$pkg" | grep -qx "package:$pkg"; then echo "SKIP $name already installed"; continue; fi
  f="$CACHE/$name.apk"
  case "$sha" in https://*) # a latest release: its checksum list names the file; a cached older file is fetched again
    sha="$(curl -fsSL "$sha" | awk -v n="${url##*/}" '$2==n {print $1}')"; [ -n "$sha" ] || die "could not read the checksum of the latest $name"
    [ -f "$f" ] && [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" != "$sha" ] && rm -f "$f" ;;
  esac
  [ -f "$f" ] || curl -fsSL -o "$f" "$url" || die "could not download $name"
  got="$(shasum -a 256 "$f" | cut -d' ' -f1)"; [ "$got" = "$sha" ] || { rm -f "$f"; die "$name checksum does not match. Nothing installed."; }
  "${ADB[@]}" push "$f" "$R/$name.apk" </dev/null >/dev/null
  remote sh "$R/decent-setup.sh" install "$R/$name.apk" $FORCE | grep -vE '^(INFO|CHECK)'
done
if [ $CLEAN = 1 ]; then remote sh "$R/decent-setup.sh" cleanup $FORCE | grep -vE '^(SKIP|INFO|CHECK)'; fi
if [ $HOMESCR = 1 ]; then remote sh "$R/decent-setup.sh" home $FORCE | grep -vE '^(SKIP|INFO|CHECK)'; fi
echo
echo "Automatic part done. Now finish on the tablet (docs/installation.md has details):"
echo " 1. Reboot it. Join Wi-Fi, on an IoT or guest network if you have one."
echo " 2. If no Google account is signed in, we recommend adding one made only for this tablet (it has no lock). Update Chrome and WebView in Play."
if [ $HOMESCR = 1 ]; then cat <<'T'
 3. Fossify: long-press Chrome, Play Store and Camera on Home, and tap Remove each.
 4. Fossify: long-press empty space, Launcher Settings: Row count 3, Column count 5, Close app drawer on opening an app On.
 5. In Chrome open https://decadentcoffee.app/app/, tap the install icon, tap Install once, and log in.
 6. Swipe up from mid-screen. Drag Decaid, Decadent and Settings to cells 2, 3 and 4 of the middle row.
T
fi
echo "Then run scripts/status.sh to check. To go back: scripts/undo.sh"
