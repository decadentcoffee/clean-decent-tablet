#!/bin/sh
# Publish the setup page to Cloudflare Pages (project clean-decent-tablet). Its one public address is
# https://decadentcoffee.app/clean-decent-tablet/: a site page with the site's menu, framing this deploy at its own
# origin https://tablet.decadentcoffee.app/ (custom domain on this project, 11 Nov 2026). Its own origin keeps this
# code away from the Decadent app's storage and sign-in (Decadent security audit, lead 5). Opened anywhere outside
# that frame (tablet.decadentcoffee.app or pages.dev directly) the page sends the visitor to the address. Ships only what the page needs: no candidates
# (rc-*), no debug page. Test locally on the dist server instead (README: Run the webpage).
# Usage: scripts/deploy-site.sh            (needs a wrangler login with Pages access)
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/web/deploy"
node "$here/web/build.mjs"
rm -rf "$out"; mkdir -p "$out/img"
cd "$here/web/dist"
cp app.js deco.js style.css fossify.apk LICENSE.txt NOTICE.txt "$out/"
cp img/de1-1600.jpg img/de1-2528.jpg img/decadent-lockup.svg "$out/img/"
python3 - "$here/web/dist/index.html" "$out/index.html" <<'EOF'
import sys
s = open(sys.argv[1]).read()
go = ('<script>if(self===top)'
      'location.replace("https://decadentcoffee.app/clean-decent-tablet/"+location.search+location.hash)</script>\n')
assert s.count("<head>") == 1, "no <head>"
open(sys.argv[2], "w").write(s.replace("<head>", "<head>\n" + go, 1))
EOF
cat > "$out/_headers" <<'EOF'
/*
  X-Robots-Tag: noindex
  Content-Security-Policy: frame-ancestors https://decadentcoffee.app https://decadent.pages.dev
  X-Content-Type-Options: nosniff
EOF
cd "$here/web"
npx --yes wrangler@4 pages deploy deploy --project-name clean-decent-tablet --branch main --commit-dirty=true
