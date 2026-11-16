// A pretend tablet for checking the page without one: open with ?safe (safe mode). It never touches USB.
// Its logs name the real packages from apps.json, so safe-mode screens read like a real run.
import APPS from "./apps.json";
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const PKG = (i) => APPS[(i - 1) % APPS.length].pkg; // the i-th package, 1-based
export class DemoTablet {
  constructor(opts = {}) { this.done = !!opts.done; this.noDecaid = !!opts.noDecaid; this.fail = opts.fail; this.manual = !!opts.manual; this.hold = !!opts.hold; this.pushed = []; this.wifi = opts.net === "wifi" || opts.net === "all"; this.account = opts.net === "all"; this.webapk = !!opts.decadent; this.slow = !!opts.slow; }
  async prepare() {}
  async push(p) { this.pushed.push(p); }
  async run(c, onLine = () => {}) {
    (globalThis.safeModeLog ||= []).push(c); // what the page asked the tablet to do, for checking safe-mode runs
    if (c.includes("pm list packages net.tadel")) { if (this.noDecaid) return []; const l = "package:net.tadel.reaprime"; onLine(l); return [l]; }
    const pk = (list) => list.map((p) => `package:${p}`);
    if (c === "pm list packages -d") return pk(this.done ? APPS.map((a) => a.pkg) : ["com.samsung.android.app.contacts"]);
    if (c === "pm list packages ") return pk(APPS.map((a) => a.pkg).filter((p) => p !== "com.sec.android.autodoodle.service"));
    return [];
  }
  async setup(args, onLine = () => {}) {
    (globalThis.safeModeLog ||= []).push(`setup ${args}`);
    const out = [];
    const say = async (l, ms = 0) => { out.push(l); onLine(l); if (ms) await wait(ms); };
    const a = args.split(" ")[0];
    const dry = args.includes("--dry-run");
    if (this.slow && (a === "plan" || (a === "undo" && dry))) await wait(1200); // like a real tablet: the line under the box shows
    if (a === "check") {
      if (this.slow) await wait(1500); // a real tablet takes a moment; shows the checking box
      const m = this.fail === "model" ? "SM-T220" : "SM-X133", b = this.fail === "model" ? "T220XXU1AUB2" : this.fail === "build" ? "X133DXU9CZZ1" : "X133DXS5BZI3";
      await say(`INFO model=${m} build=${b} android=16 oneui=80500 user=0`);
      await say(this.fail === "model" ? "CHECK untested-model" : this.fail === "build" ? "CHECK same-model-new-build" : "CHECK tested");
      if (this.fail === "model" || this.fail === "build") await say(`FAIL this tablet is ${m} ${b}, which has not been tested. Nothing changed.`);
    }
    if (a === "plan") await say(this.done ? "PLAN disable=0 already-off-or-absent=100" : "PLAN disable=97 already-off-or-absent=3");
    if (a === "status") { for (const l of [`STATUS model=SM-X133`, `STATUS build=X133DXS5BZI3`, `STATUS undo_record=${this.done ? "present" : "none"}`, `STATUS home=${this.done ? "org.fossify.home" : "com.sec.android.app.launcher"}`, "STATUS app net.tadel.reaprime enabled"]) await say(l); }
    if (this.hold && !dry && (a === "cleanup" || a === "home")) { for (let i = 1; i <= 41; i++) await say(`DONE ${i}/100 ${PKG(i)}`, 0); await new Promise(() => {}); } // debug: stay on the running screen
    if (a === "cleanup" && !dry && this.fail === "run") { await say(`DONE 1/100 ${PKG(1)}`, 300); await say(`FAIL ${PKG(2)}: Unknown error. Stopped. Run undo to go back.`); return out; }
    if (a === "cleanup" && !dry) { for (let i = 1; i <= 100; i += 9) await say(`DONE ${i}/100 ${PKG(i)}`, 60); await say("OK cleanup finished. Refused by Android: 2"); this.done = true; }
    if (a === "cleanup" && dry) { await say("PLAN system/screen_off_timeout: 2147483646 -> 600000"); await say("PLAN 1/100 disable com.netflix.mediaclient"); await say("PLAN 2/100 disable com.spotify.music"); await say("OK dry run: nothing changed"); }
    if (a === "finish") {
      const k = args.split(" ")[1];
      if (k === "status") { await say(`STATUS wifi=${this.wifi ? "connected" : "disconnected"}`); await say(`STATUS google_account=${this.account ? "yes" : "no"}`); await say("STATUS home=org.fossify.home"); await say(`STATUS decadent_app=${this.webapk ? "installed" : "none"}`); await say("OK finish status"); }
      if (k === "wifi-open") { await say("DONE finish wifi-open"); setTimeout(() => { this.wifi = true; }, 5000); }
      if (k === "account-open") { await say("DONE finish account-open"); setTimeout(() => { this.account = true; }, 5000); }
      if (k === "icons") await say(this.manual ? "MANUAL finish icons no Remove option appeared" : "DONE finish icons removed=3", 900);
      if (k === "launcher") await say("DONE finish launcher", 900);
      if (k === "updates") { await say("DONE finish update com.android.chrome", 1200); await say("SKIP finish update com.google.android.webview up to date", 300); await say("OK finish updates"); }
      if (k === "decadent") { this.webapk = true; await say("DONE finish decadent", 1200); }
      if (k === "place") {
        for (const l of ["Decaid", "Decadent", "Settings"]) {
          if (l === "Decaid" && this.noDecaid && !this.pushed.some((p) => p.endsWith("decaid.apk"))) { await say("SKIP finish place Decaid not installed", 200); continue; }
          if (l === "Decadent" && / no-decadent\b/.test(args)) { await say("SKIP finish place Decadent not wanted", 200); continue; }
          await say(this.manual && l === "Decadent" ? `MANUAL finish place ${l} could not find it in the app list` : `DONE finish place ${l}`, 500);
        }
        await say("OK finish place");
      }
      return out;
    }
    if (a === "install") await say("DONE installed fossify.apk", 300);
    if (a === "home" && dry) { await say("PLAN android.app.role.HOME -> org.fossify.home"); await say("PLAN navigation -> gestural"); await say("OK dry run: nothing changed"); }
    if (a === "home" && !dry) { await say("DONE android.app.role.HOME = org.fossify.home"); await say("OK home screen finished"); }
    if (a === "undo" && dry && !this.done) { await say("FAIL no undo record on this tablet. Nothing to undo."); return out; }
    if (a === "undo" && dry && args.includes("--apps")) { for (const p of ["com.netflix.mediaclient", "com.spotify.music", "com.google.android.gm", "com.sec.android.app.sbrowser"]) await say(`PLAN enable ${p}`); await say("PLAN system/screen_off_timeout: 600000 -> 2147483646"); await say("PLAN android.app.role.BROWSER -> com.sec.android.app.sbrowser"); await say("OK dry run: nothing changed"); }
    if (a === "undo" && dry && args.includes("--home")) { await say("PLAN android.app.role.HOME -> com.sec.android.app.launcher"); await say("PLAN secure/edge_enable: 0 -> 1"); await say("PLAN navigation -> threebutton"); await say("PLAN uninstall org.fossify.home"); await say("PLAN uninstall org.chromium.webapk.a45977050c6c6f69b_v2"); await say("OK dry run: nothing changed"); }
    if (a === "undo" && !dry) { for (let i = 1; i <= 100; i += 19) await say(`DONE enabled ${PKG(i)}`, 60); await say("MANUAL Remove the Google account you added, if any."); await say("OK undo finished. Reboot, then check Home and Settings."); this.done = false; }
    return out;
  }
  close() {}
}
