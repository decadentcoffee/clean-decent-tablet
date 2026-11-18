// Decent's latest Decaid release, passed on unchanged. A browser may not read the file from GitHub's download
// address (no cross-origin permission), so the page on Decadent's way in fetches it here and checks it against the
// checksum GitHub lists for that release before it installs anything (latestApk in src/core.js).
const LATEST = "https://github.com/decentespresso/decaid/releases/latest/download/decaid-android-latest.apk";
export async function onRequestGet() {
  const res = await fetch(LATEST, { redirect: "follow" });
  if (!res.ok || !res.body) return new Response("Decaid could not be fetched.", { status: 502 });
  const headers = { "content-type": "application/vnd.android.package-archive", "cache-control": "no-store" };
  const len = res.headers.get("content-length"); if (len) headers["content-length"] = len;
  return new Response(res.body, { headers });
}
