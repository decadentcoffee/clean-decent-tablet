import { AdbDaemonWebUsbDeviceManager } from "@yume-chan/adb-daemon-webusb";
import AdbWebCredentialStore from "@yume-chan/adb-credential-web";
import { connectTablet, parseStatus, parseProgress, sha256, latestApk, REMOTE } from "./core.js";
import { DemoTablet } from "./demo.js";
import APPS from "./apps.json";

const FILES = __DEVICE_FILES__; // decent-setup.sh, packages-disable.txt, device.expect
const APKS = __APKS__; // [{ name, pkg, url, sha }]
const qs = new URLSearchParams(location.search);
// Safe mode (?safe, the older ?demo still works): a pretend tablet for the developer. Every screen looks and
// behaves as in a real run, with Next / Back in a bar; nothing reaches USB. ?safe=done|nodecaid|manual|model|fail|build. &asks=N: Decaid asks its first questions for N checks.
const DEMO = qs.has("safe") || qs.has("demo");
const DEMO_KIND = qs.get("safe") ?? qs.get("demo");

const $ = (id) => document.getElementById(id);
let tablet = null;
let status = null;
const keep = new Set(); // packages the person unticked
let appState = {}; // pkg -> enabled | disabled | absent

// Steps go into the browser history, so its back and forward buttons move between them.
let current = null, busy = false;
const NEEDS_TABLET = ["review", "confirm", "undo", "running", "finish"];
function show(step, push = true) {
  if (push && !previewing) { if (current === "running" || current === null) history.replaceState({ step }, ""); else if (step !== current) history.pushState({ step }, ""); }
  current = step;
  for (const s of document.querySelectorAll("[data-step]")) s.hidden = s.dataset.step !== step;
  // In the preview every control is inert, but details still open (Show details, Choose which apps).
  for (const c of document.querySelectorAll("main > [data-step] :is(button, input, select, textarea, label, .row a)")) c.inert = previewing;
  const h = document.querySelector(`[data-step="${step}"] h2`);
  if (h) { h.tabIndex = -1; h.focus({ preventScroll: true }); }
  window.scrollTo(0, 0);
}
function setError(id, text) { const e = $(id); e.textContent = text || ""; e.hidden = !text; }
function plainError(err) {
  const m = String(err && err.message || err);
  if (/claim|Unable to claim|in use|busy/i.test(m)) return "Another program is using the tablet. Close Android Studio, Samsung software or any other Android tool. If you have used ADB on this computer, run: adb kill-server. Then unplug the tablet, plug it back in and try again.";
  if (/No device selected|NotFoundError|cancel/i.test(m)) return "No tablet was selected. Choose Connect tablet again and pick your tablet in the list. If it isn't listed, check USB debugging is on and the cable carries data.";
  if (/auth|reject|denied/i.test(m)) return "The tablet didn't allow this computer. Unlock it, tap Allow on the USB debugging message, and try again.";
  if (/disconnect|transfer|network|closed/i.test(m)) return "The connection to the tablet dropped. Check the cable, and try again. Anything already done is saved in the record on the tablet, so it's safe to run again.";
  return `Something went wrong: ${m}`;
}

function supported() { return DEMO || ("usb" in navigator && window.isSecureContext); }

async function connect() {
  setError("connect-error"); const btn = $("connect"); btn.disabled = true; btn.textContent = "Connecting…";
  try {
    if (DEMO) tablet = new DemoTablet({ slow: !qs.get("to"), decadent: qs.get("decadent") === "installed", done: DEMO_KIND === "done", noDecaid: DEMO_KIND === "nodecaid", manual: DEMO_KIND === "manual", net: qs.get("net") || (qs.get("to") === "finished" ? "all" : null), hold: qs.get("to") === "running", asks: qs.get("asks") ? +qs.get("asks") : DEMO_KIND === "nodecaid" && qs.get("decaid") === "add" ? 4 : 0, fail: { model: "model", fail: "run", build: "build" }[DEMO_KIND] });
    else {
      const device = await AdbDaemonWebUsbDeviceManager.BROWSER.requestDevice();
      if (!device) throw new Error("No device selected");
      $("connect-hint").hidden = false;
      tablet = await connectTablet(device, new AdbWebCredentialStore("Decent tablet setup"));
    }
    checking();
    working("Getting the tablet ready…");
    await tablet.prepare(FILES);
    await review();
  } catch (e) { if (current === "review") show("connect"); setError("connect-error", plainError(e)); }
  finally { btn.disabled = false; btn.textContent = "Connect tablet"; $("connect-hint").hidden = true; }
}

let FORCE = ""; // " --force" once the person accepts an untested firmware on the tested model

// The Tablet setup screen opens as soon as the tablet allows the connection. The status box says it is checking until the
// model and firmware are known, and the line under it names what is being read until the options are ready.
function working(what) { $("check-what").textContent = what || ""; $("check-progress").hidden = !what; }
function checking() {
  $("device-name").dataset.state = "checking";
  $("device-name").replaceChildren(
    el("span", { className: "found-mark found-spin", ariaHidden: "true" }),
    el("span", { className: "found-what" }, el("small", { textContent: "Connected" }), el("b", { textContent: "Checking the tablet…" }),
      el("span", { textContent: "Its model, firmware and what has been changed before." })));
  for (const id of ["unsupported-model", "new-firmware", "already", "setup-part", "do-setup"]) $(id).hidden = true;
  show("review");
}

async function review() {
  if (current !== "review") checking();
  working("Reading the model and firmware…");
  const check = await tablet.setup("check");
  const info = (check.find((l) => l.startsWith("INFO model=")) || "").match(/model=(\S+) build=(\S+)/);
  const verdict = (check.find((l) => l.startsWith("CHECK ")) || "").split(" ")[1];
  status = parseStatus(await tablet.setup("status"));
  $("their-model").textContent = info ? info[1] : "unknown";
  $("their-build").textContent = info ? info[2] : "unknown";
  const tested = verdict === "tested", newBuild = verdict === "same-model-new-build";
  // What the tablet reports, then whether that pairing has been tested: never the tested values themselves.
  const ok = tested, word = tested ? "Tested" : newBuild ? "Firmware not tested" : "Not tested";
  $("device-name").dataset.state = ok ? "ok" : "warn";
  $("device-name").replaceChildren(
    el("span", { className: "found-mark", ariaHidden: "true", textContent: ok ? "✓" : "!" }),
    el("span", { className: "found-what" }, el("small", { textContent: "Detected" }),
      el("b", { textContent: info ? `Samsung ${info[1]}` : "Unknown tablet" }),
      el("span", { textContent: info ? `Firmware ${info[2]}` : "It didn't report its model." })),
    el("span", { className: "found-chip", textContent: word }));
  FORCE = ""; $("accept-build").checked = false; $("accept-model").checked = false;
  doAllowed = tested; appState = {};
  working(tested ? "Looking for earlier changes and counting the apps…" : "Looking for earlier changes…");
  try { await Promise.all([loadUndo(), tested && loadPlan()]); } finally { working(""); }
  $("unsupported-model").hidden = tested || newBuild;
  $("new-firmware").hidden = !newBuild;
  choiceDefaults();
  if (DEMO && qs.get("opts")) { const o = qs.get("opts"); $("opt-cleanup").checked = o !== "home"; $("opt-home").checked = o !== "clean"; }
  syncChoices();
  if (current !== "review") show("review");
}

// The options mirror the tablet: Clean up and New Home screen while there is something to do, Turn apps back on
// and Put the original Home screen back once the record on the tablet says this page changed them. Clean up and
// New Home screen show only on a tested tablet, or once the owner accepts an untested one; undo never needs that.
let doAllowed = false;
const FOSSIFY = "org.fossify.home";
function shown() {
  const avail = APPS.filter((a) => appState[a.pkg] === "enabled").length;
  return {
    cleanup: doAllowed && avail > 0,
    home: doAllowed && status && status.home !== FOSSIFY,
    undoApps: undoPlan.apps.length + undoPlan.appSettings.length > 0,
    undoHome: undoPlan.home.length > 0,
  };
}
function choiceDefaults() {
  const v = shown();
  $("opt-cleanup").checked = v.cleanup; $("opt-home").checked = v.home;
  $("opt-undo-apps").checked = false; $("opt-undo-home").checked = false; $("keep-apps").checked = false;
}
// What the person has chosen, counting only the options on screen.
function chosen() {
  const v = shown();
  return { cleanup: v.cleanup && $("opt-cleanup").checked, home: v.home && $("opt-home").checked,
    undoApps: v.undoApps && $("opt-undo-apps").checked, undoHome: v.undoHome && $("opt-undo-home").checked };
}
function syncChoices() {
  const v = shown(), c = chosen();
  $("row-cleanup").hidden = !v.cleanup; $("pick").hidden = !c.cleanup;
  $("row-home").hidden = !v.home;
  $("row-undo-apps").hidden = !v.undoApps; $("undo-pick").hidden = !c.undoApps || undoPlan.apps.length === 0;
  $("row-undo-home").hidden = !v.undoHome; $("row-keep-apps").hidden = !c.undoHome;
  const any = v.cleanup || v.home || v.undoApps || v.undoHome;
  $("setup-part").hidden = !any; $("do-setup").hidden = !any;
  $("already").hidden = !(doAllowed && !v.cleanup && Object.keys(appState).length);
  syncUndo();
}

// Debug only (?demo&to=<screen>): walks the real flow with the pretend tablet up to one screen, so every screen
// can be opened in the state a real run would leave it in. opts=both|clean|home, decaid=add|skip, net=none|wifi|all.
async function demoGoTo(to) {
  const ORDER = ["usb", "connect", "review", "confirm", "running", "finish", "finished", "undo", "undone"];
  const upTo = (s) => ORDER.indexOf(to) >= ORDER.indexOf(s);
  const until = async (fn, ms = 30000) => { const end = Date.now() + ms; while (!fn()) { if (Date.now() > end) throw new Error(`demo: stuck before ${to}`); await wait(150); } };
  if (!upTo("usb")) return; show("usb"); if (to === "usb") return;
  show("connect"); if (to === "connect") return;
  await connect(); if (to === "review" || current !== "review") return;
  if (to === "undo" || to === "undone") {
    for (const [id, on] of [["opt-cleanup", false], ["opt-home", false], ["opt-undo-apps", true], ["opt-undo-home", true]]) $(id).checked = on;
    syncChoices(); await $("do-setup").onclick(); if (to === "undone") await runUndo(); return;
  }
  await $("do-setup").onclick(); if (to === "confirm" || current !== "confirm") return;
  if (!decaidHave) { const d = qs.get("decaid") || "skip"; $(d === "add" ? "decaid-add" : "decaid-skip").checked = true; $("decaid-get").hidden = d !== "add"; }
  const go = runSetup(); if (to === "running") return;
  await go; if (to === "finish") return;
  await until(() => $("fin-go") && !$("fin-you").hidden);
  await runFinish(); await until(() => !$("fin-after").hidden, 60000);
}


async function loadPlan() {
  const plan = (await tablet.setup(`plan${FORCE}`)).find((l) => l.startsWith("PLAN disable="));
  const n = plan ? plan.match(/disable=(\d+)/)[1] : "?";
  $("count").textContent = n;
  const pkgs = async (flag) => new Set((await tablet.run(`pm list packages ${flag}`)).map((l) => l.replace(/^package:/, "").trim()).filter(Boolean));
  const [all, off] = await Promise.all([pkgs(""), pkgs("-d")]);
  appState = Object.fromEntries(APPS.map((a) => [a.pkg, !all.has(a.pkg) ? "absent" : off.has(a.pkg) ? "disabled" : "enabled"]));
  renderApps();
}

// Plan lines from the core script, in plain words.
const LABEL = { "org.fossify.home": "Fossify Launcher", "com.sec.android.app.launcher": "Samsung's One UI Home", "com.android.chrome": "Chrome",
  "com.sec.android.app.sbrowser": "Samsung Internet", "app.olauncher": "Olauncher" };
const SETTING = { screen_off_timeout: "Screen sleeps after", stay_on_while_plugged_in: "Stay awake while charging", edge_enable: "Samsung side panel",
  navigation_bar_gesture_hint: "Gesture hint line", navigation_bar_gesture_while_hidden: "Gestures while bar hidden" };
const nameOf = (p) => LABEL[p] || (p.startsWith("org.chromium.webapk") ? "Decadent" : (APPS.find((a) => a.pkg === p) || {}).name || p);
const valueOf = (k, v) => k === "screen_off_timeout" ? (+v >= 2147483646 ? "never" : `${Math.round(v / 60000)} min`) : v === "0" ? "off" : v === "null" ? "default" : "on";
function plain(l) {
  let m;
  if ((m = l.match(/^android\.app\.role\.(HOME|BROWSER) -> (\S+)/))) return `${m[1] === "HOME" ? "Home screen" : "Browser"}: ${nameOf(m[2])}`;
  if ((m = l.match(/^(disable|enable|uninstall) (\S+)/))) return `${{ disable: "Switch off", enable: "Turn back on", uninstall: "Remove" }[m[1]]} ${nameOf(m[2])}`;
  if ((m = l.match(/^navigation -> (\w+)/))) return m[1] === "gestural" ? "Swipe gestures instead of buttons" : "Bottom buttons back";
  if ((m = l.match(/^\w+\/(\w+): (\S+) -> (\S+)/))) return `${SETTING[m[1]] || m[1]}: ${valueOf(m[1], m[2])} → ${valueOf(m[1], m[3])}`;
  if ((m = l.match(/^delete \w+\/(\w+)/))) return `${SETTING[m[1]] || m[1]}: back to default`;
  return l;
}

const el = (tag, props = {}, ...kids) => { const e = Object.assign(document.createElement(tag), props); e.append(...kids); return e; };

function renderApps() {
  const box = $("app-groups"); box.textContent = "";
  const groups = [...new Set(APPS.map((a) => a.group))];
  for (const g of groups) {
    const items = APPS.filter((a) => a.group === g);
    const gbox = el("input", { type: "checkbox", className: "group-box" });
    gbox.dataset.group = g;
    const fs = el("fieldset", { className: "app-group" }, el("legend", {}, el("label", {}, gbox, ` ${g} (${items.length})`)));
    for (const a of items) {
      const st = appState[a.pkg];
      const cb = el("input", { type: "checkbox", checked: !keep.has(a.pkg), disabled: st !== "enabled" });
      cb.dataset.pkg = a.pkg;
      const tag = st === "disabled" ? el("span", { className: "tag" }, "already off") : st === "absent" ? el("span", { className: "tag" }, "not on this tablet") : "";
      fs.append(el("label", { className: "app" }, cb, el("span", {}, el("b", {}, a.name), " ", tag, el("br"), el("span", { className: "muted" }, a.why))));
    }
    box.append(fs);
  }
  syncApps();
}

// Selected apps that this run would switch off.
function toSwitchOff() { return APPS.filter((a) => appState[a.pkg] === "enabled" && !keep.has(a.pkg)); }

function syncApps() {
  for (const g of document.querySelectorAll(".group-box")) {
    const boxes = [...document.querySelectorAll(`#app-groups input[data-pkg]`)].filter((b) => APPS.find((a) => a.pkg === b.dataset.pkg).group === g.dataset.group && !b.disabled);
    const on = boxes.filter((b) => b.checked).length;
    g.checked = boxes.length > 0 && on === boxes.length; g.indeterminate = on > 0 && on < boxes.length; g.disabled = boxes.length === 0;
  }
  const n = toSwitchOff().length, avail = APPS.filter((a) => appState[a.pkg] === "enabled").length;
  $("count").textContent = n;
  $("picked").textContent = `(${n} of ${avail} ticked)`;
}

// The list the core script runs, minus anything the person unticked. The script still refuses protected packages.
function chosenList() {
  return FILES["packages-disable.txt"].split("\n").filter((l) => { const p = l.split(" ")[1]; return l.startsWith("#") || !p || !keep.has(p); }).join("\n");
}

function progress(line, bar, label, log) {
  const p = parseProgress(line);
  if (p) { bar.max = p.total; bar.value = p.n; label.textContent = `${p.n} of ${p.total}`; }
  if (/^(DONE|REFUSED|FAIL|OK|MANUAL)/.test(line)) { log.textContent += line + "\n"; log.scrollTop = log.scrollHeight; }
}

async function installApk(a, bytes, onLine) {
  const path = `${REMOTE}/${a.name}.apk`;
  await tablet.push(path, bytes);
  const out = await tablet.setup(`install ${path}${FORCE}`, onLine);
  if (out.some((l) => l.startsWith("FAIL"))) throw new Error(out.find((l) => l.startsWith("FAIL")).slice(5));
}

let decaidHave = true;
async function isInstalled(pkg) { return (await tablet.run(`pm list packages ${pkg}`)).includes(`package:${pkg}`); }

async function runSetup() {
  show("running"); busy = true; setError("run-error"); $("run-back").hidden = true;
  const bar = $("bar"), label = $("bar-label"), log = $("log"); log.textContent = "";
  const on = (l) => progress(l, bar, label, log);
  try {
    const wantClean = $("opt-cleanup").checked, wantHome = $("opt-home").checked;
    // Decaid is checked before anything is installed: the chosen file must be Decent's latest release.
    const decaid = APKS.find((a) => a.name === "decaid");
    let decaidBytes = null;
    if (!decaidHave && $("decaid-add").checked && $("decaid-file").files[0]) {
      $("run-title").textContent = "Checking the Decaid file…";
      decaidBytes = new Uint8Array(await $("decaid-file").files[0].arrayBuffer());
      if (!DEMO) {
        const latest = await latestApk(decaid.url).catch(() => { throw new Error("The Decaid file could not be checked with GitHub. Check this computer's internet connection and try again. Nothing was installed."); });
        if ((await sha256(decaidBytes)) !== latest.sha) throw new Error(`That file isn't the latest Decaid${latest.version ? ` (${latest.version})` : ""}. Download it again with the link on the Decaid step. Nothing was installed.`);
      }
    }
    $("run-title").textContent = "Installing the launcher…";
    const fossify = APKS.find((a) => a.name === "fossify");
    if (wantHome && !(await isInstalled(fossify.pkg))) {
      const bytes = DEMO ? new Uint8Array(1) : new Uint8Array(await (await fetch("fossify.apk")).arrayBuffer());
      if (!DEMO && (await sha256(bytes)) !== fossify.sha) throw new Error("The launcher download failed its checksum. Nothing was installed.");
      await installApk(fossify, bytes, on);
    }
    if (decaidBytes) {
      $("run-title").textContent = "Installing Decaid…";
      await installApk(decaid, decaidBytes, on);
    }
    const stopped = (out) => !out.some((l) => l.startsWith("OK ") && !l.includes("dry run"));
    const why = (out) => (out.find((l) => l.startsWith("FAIL")) || "FAIL The tablet stopped partway.").slice(5);
    let out = [];
    if (wantClean) {
      $("run-title").textContent = "Switching off apps…";
      await tablet.prepare({ "packages-disable.txt": chosenList() });
      out = await tablet.setup(`cleanup${FORCE}`, on);
      if (stopped(out)) throw new Error(why(out));
    }
    if (wantHome) {
      $("run-title").textContent = "Setting up the Home screen…";
      const h = await tablet.setup(`home${FORCE}`, on);
      if (stopped(h)) throw new Error(why(h));
    }
    for (const el of document.querySelectorAll("[data-home]")) el.hidden = !wantHome;
    for (const el of document.querySelectorAll("[data-decaid]")) el.hidden = !decaidHave && !$("decaid-add").checked;
    const refused = (out.join("\n").match(/Refused by Android: (\d+)/) || [])[1];
    $("refused").textContent = refused && refused !== "0" ? `Android wouldn't switch off ${refused} of them, which is expected on some firmware.` : "";
    $("fin-done").textContent = wantClean ? "The clean-up is done." : "The new Home screen is in.";
    busy = false; wantHomeDone = wantHome; show("finish"); startFinish();
  } catch (e) { busy = false; setError("run-error", plainError(e)); $("run-title").textContent = "Stopped"; $("run-back").hidden = false; }
}

// Last steps. The owner joins Wi-Fi and signs in to Google; the core script's `finish` steps drive the rest
// through the tablet's screen. Decaid's first questions are a pause for the owner (decaidReady). The written instructions
// are always on the screen as the second way; a step the tablet doesn't allow also lists its own under Left for you.
let wantHomeDone = true, finWifi = false, finAcct = null, finPoll = null, decadentHad = false;
const FIN = (s) => $("fin-steps").querySelector(`[data-k="${s}"]`);
function finState(k, state, why) {
  const li = FIN(k); if (!li) return;
  li.dataset.state = state;
  li.querySelector(".st").textContent = { run: "…", done: "✓", skip: "–", manual: "!", you: "?" }[state] || "";
  li.title = why || "";
}
async function finStatus() {
  const st = parseStatus(await tablet.setup("finish status"));
  finWifi = st.wifi === "connected";
  decadentHad = st.decadent_app === "installed";
  $("fin-decadent-h").textContent = decadentHad ? "Put Decadent on Home" : "Install Decadent on the tablet";
  $("fin-decadent-p").textContent = decadentHad ? "Decadent is already on this tablet. Leave this off to keep its icon off Home." : "Our app for the DE1, as one icon on Home. Leave this off if you don't use it.";
  if (finAcct !== "skip") finAcct = st.google_account === "yes" ? "yes" : "no";
  $("fin-wifi-state").textContent = finWifi ? "Connected ✓" : "Not connected";
  $("wifi-form").hidden = finWifi;
  $("fin-acct-state").textContent = finAcct === "yes" ? "Signed in ✓" : finAcct === "skip" ? "Going on without one" : "Not signed in";
  $("acct-form").hidden = finAcct !== "no";
  $("fin-nowifi").hidden = finWifi;
  const ready = finWifi && finAcct !== "no";
  $("fin-lead").textContent = ready ? "The tablet is on Wi-Fi and ready. Choose Finish for me and this page does the rest." : `${finWifi || finAcct !== "no" ? "One thing needs" : "Two things need"} you. This page does the rest.`;
  $("fin-you-h").textContent = ready ? "Ready" : "Only you can do these";
  if (finWifi && finAcct !== "no") stopPoll();
  return st;
}
function stopPoll() { clearInterval(finPoll); finPoll = null; }
async function startFinish() {
  $("fin-you").hidden = false; $("fin-run").hidden = true; $("fin-after").hidden = true; shareBox(false);
  for (const li of $("fin-steps").children) { delete li.dataset.state; li.querySelector(".st").textContent = ""; }
  try { await finStatus(); } catch (e) { setError("fin-error", plainError(e)); }
  stopPoll();
  finPoll = setInterval(() => { if (current !== "finish" || !$("fin-run").hidden || !tablet) return stopPoll(); finStatus().catch(() => {}); }, 4000);
}
function shareBox(on) { document.querySelector('[data-step="finish"] .share').hidden = !on; }
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
// The tablet drops off USB while it restarts. Find it again: the browser keeps the permission, and the tablet
// remembers this computer if "Always allow" was ticked.
async function restartTablet() {
  if (DEMO) { await wait(1500); return; }
  tablet.run("reboot").catch(() => {});
  await wait(4000);
  try { await tablet.close(); } catch {}
  tablet = null;
  const until = Date.now() + 180000;
  while (Date.now() < until) {
    await wait(3000);
    try {
      const [device] = await AdbDaemonWebUsbDeviceManager.BROWSER.getDevices();
      if (!device) continue;
      tablet = await connectTablet(device, new AdbWebCredentialStore("Decent tablet setup"));
      for (let i = 0; i < 40; i++) { if ((await tablet.run("getprop sys.boot_completed")).join("").trim() === "1") break; await wait(3000); }
      await wait(15000); // let Home and Play services settle
      await tablet.prepare(FILES);
      return;
    } catch { tablet = null; }
  }
  throw new Error("reconnect");
}
async function reconnectByHand() {
  setError("fin-error"); $("fin-reconnect-row").hidden = true;
  try {
    const device = await AdbDaemonWebUsbDeviceManager.BROWSER.requestDevice();
    if (!device) throw new Error("No device selected");
    tablet = await connectTablet(device, new AdbWebCredentialStore("Decent tablet setup"));
    await tablet.prepare(FILES);
    finState("restart", "done");
    await runFinish(true);
  } catch (e) { setError("fin-error", plainError(e)); $("fin-reconnect-row").hidden = false; }
}
// A Decaid that has never been opened asks its first questions (account, permissions, old data). They are the
// owner's to answer: the page opens Decaid, says so, asks the tablet again every few seconds, and carries on by itself
// once Decaid's menu shows. True when Decaid is ready for the plugin step.
let decaidPass = false;
async function decaidReady() {
  const ask = $("decaid-ask"), keep = $("fin-keep"), was = keep.textContent, until = Date.now() + 15 * 60000;
  decaidPass = false;
  try {
    for (let first = true; Date.now() < until && !decaidPass; first = false) {
      const st = parseStatus(await tablet.setup(`finish decaid${first ? " open" : ""}`));
      if (st.decaid !== "asking") return st.decaid === "ready";
      if (ask.hidden) { ask.hidden = false; finState("plugin", "you"); keep.textContent = "Keep the cable plugged in. Decaid is waiting for you on the tablet."; }
      await wait(2000);
    }
    return false;
  } catch { return false; }
  finally { ask.hidden = true; keep.textContent = was; }
}
function outcome(lines, k) {
  const mine = lines.filter((l) => / finish /.test(` ${l} `) || l.startsWith("FAIL"));
  if (mine.some((l) => l.startsWith("MANUAL") || l.startsWith("FAIL"))) return "manual";
  if (mine.some((l) => l.startsWith("DONE"))) return "done";
  if (mine.some((l) => l.startsWith("SKIP"))) return "skip";
  return k === "updates" && lines.some((l) => l.startsWith("OK finish")) ? "skip" : "manual";
}
async function runFinish(afterRestart = false) {
  stopPoll(); busy = true;
  $("fin-you").hidden = true; $("fin-run").hidden = false; $("fin-after").hidden = true; setError("fin-error");
  $("fin-run-h").textContent = "Finishing the tablet…"; $("fin-keep").hidden = false;
  const home = wantHomeDone, onHome = home && $("fin-decadent").checked, decadent = onHome && !decadentHad;
  // The Decadent plugin goes into Decaid through Decaid's own installer, whenever Decadent is wanted and Decaid is there.
  const plugin = onHome && (decaidHave || $("decaid-add").checked);
  // The plugin goes first: it is the one step that may need the owner (Decaid's first questions), so they are free after it.
  const plan = ["restart", ...(plugin ? ["plugin"] : []), ...(home ? ["icons", "launcher"] : []), "updates", ...(decadent ? ["decadent"] : []), ...(home ? ["place"] : []), "open"];
  // Name only the icons this tablet will get: Decaid if it is there, Decadent if wanted.
  const icons = [...(decaidHave || $("decaid-add").checked ? ["Decaid"] : []), ...(onHome ? ["Decadent"] : []), "Settings"];
  const said = (b) => icons.map((n) => (b ? `<b>${n}</b>` : n)).join(", ").replace(/, ([^,]*)$/, " and $1");
  const [w, h] = FIN("place").querySelectorAll(".place-list"); w.textContent = said(false); h.innerHTML = said(true);
  for (const li of $("fin-steps").children) li.hidden = !plan.includes(li.dataset.k);
  try {
    if (!afterRestart) {
      finState("restart", "run");
      try { await restartTablet(); finState("restart", "done"); }
      catch { finState("restart", "manual"); busy = false; setError("fin-error", "The tablet didn't come back on its own. Unplug it and plug it back in, unlock it, tap Allow if it asks, then choose Reconnect the tablet."); $("fin-reconnect-row").hidden = false; return; }
    }
    for (const k of plan.slice(1)) {
      finState(k, "run");
      if (k === "updates" && (!finWifi || finAcct !== "yes")) { finState(k, "manual", finWifi ? "needs a Google account" : "needs Wi-Fi"); continue; }
      if (k === "decadent" && !finWifi) { finState(k, "manual", "needs Wi-Fi"); continue; }
      if (k === "open") { await openApps(); finState(k, "done"); continue; }
      if (k === "plugin" && !(await decaidReady())) { finState(k, "manual", decaidPass ? "skipped" : "Decaid's first questions were not answered"); continue; }
      if (k === "plugin") finState(k, "run");
      let lines;
      try { lines = await tablet.setup(`finish ${k}${k === "place" && !onHome ? " no-decadent" : ""}`); } catch (e) { lines = [`MANUAL finish ${k} ${e.message}`]; }
      finState(k, outcome(lines, k), (lines.find((l) => /^(MANUAL|FAIL)/.test(l)) || "").replace(/^\S+ (finish \S+ )?/, ""));
    }
  } finally { busy = false; }
  finishLeft();
}
async function openApps() {
  const pkgs = (await tablet.run("pm list packages")).map((l) => l.replace(/^package:/, "").trim());
  if (pkgs.includes("net.tadel.reaprime")) { await tablet.run("monkey -p net.tadel.reaprime -c android.intent.category.LAUNCHER 1"); await wait(6000); }
  const webapk = pkgs.find((p) => p.startsWith("org.chromium.webapk"));
  if (webapk) await tablet.run(`monkey -p ${webapk} -c android.intent.category.LAUNCHER 1`);
}
function finishLeft() {
  const left = $("fin-left"); left.textContent = "";
  for (const li of $("fin-steps").children) {
    if (li.hidden || li.dataset.state !== "manual") continue;
    const item = document.createElement("li"); item.innerHTML = li.querySelector(".by-hand").innerHTML; left.append(item);
  }
  const decadentIn = FIN("decadent") && !FIN("decadent").hidden && FIN("decadent").dataset.state !== "manual";
  if (decadentIn) { const item = document.createElement("li"); item.innerHTML = "<b>Log in to Decadent</b> on the tablet. It's open and waiting."; left.append(item); }
  const none = left.children.length === 0;
  $("fin-left-h").textContent = none ? "All done" : "Left for you";
  if (none) { const item = document.createElement("li"); item.textContent = "Nothing. The tablet is ready."; left.append(item); }
  $("fin-run-h").textContent = "Finished"; $("fin-keep").hidden = true;
  $("fin-lead").textContent = none ? "The tablet is ready." : "Nearly ready: a few things are left for you, below.";
  $("fin-after").hidden = false; shareBox(true);
}

const undoOff = new Set(); // apps the person chose to leave off
let undoPlan = { apps: [], appSettings: [], home: [] };

// Read during the check, only when the tablet has a record of this page's changes, so the options are ready at once.
async function loadUndo() {
  undoOff.clear(); undoPlan = { apps: [], appSettings: [], home: [] };
  if (!status || status.undo_record !== "present") return;
  const planOf = async (args) => (await tablet.setup(`undo ${args} --dry-run`));
  const [a, h] = await Promise.all([planOf("--apps"), planOf("--home")]);
  const plans = (lines) => lines.filter((l) => l.startsWith("PLAN")).map((l) => l.slice(5));
  const ap = plans(a);
  undoPlan = { apps: ap.filter((l) => l.startsWith("enable ")).map((l) => l.split(" ")[1]), appSettings: ap.filter((l) => !l.startsWith("enable ")), home: plans(h) };
  const list = $("undo-app-list"); list.textContent = "";
  for (const p of undoPlan.apps) {
    const cb = el("input", { type: "checkbox", checked: true }); cb.dataset.undoPkg = p;
    list.append(el("label", { className: "app" }, cb, el("span", {}, el("b", {}, nameOf(p)))));
  }
  const n = undoPlan.apps.length;
  $("undo-apps-text").textContent = n ? `The ${n} app${n === 1 ? "" : "s"} Clean up switched off, and the original screen sleep time and browser.` : "The original screen sleep time and browser.";
}

function undoItems() {
  const c = chosen(), keepApps = $("keep-apps").checked;
  const picked = undoPlan.apps.filter((p) => !undoOff.has(p));
  const home = c.undoHome ? undoPlan.home.filter((l) => !(keepApps && l.startsWith("uninstall "))) : [];
  const apps = c.undoApps ? [...picked.map((p) => `enable ${p}`), ...undoPlan.appSettings] : [];
  return { picked, home, apps };
}
function syncUndo() {
  const { picked, home, apps } = undoItems(), c = chosen();
  $("undo-picked").textContent = `(${picked.length} of ${undoPlan.apps.length} ticked)`;
  $("undo-list").textContent = [...home, ...apps].map(plain).join("\n") || "Nothing to undo.";
  const sum = $("undo-summary"); sum.textContent = "";
  if (c.undoApps) sum.append(el("li", { textContent: picked.length ? `Turn ${picked.length} app${picked.length === 1 ? "" : "s"} back on, with the original screen sleep time and browser.` : "Put the original screen sleep time and browser back." }));
  if (c.undoHome) sum.append(el("li", { textContent: $("keep-apps").checked ? "Put Samsung's Home screen back, keeping Fossify Launcher and Decadent installed." : "Put Samsung's Home screen back, and remove Fossify Launcher and Decadent." }));
  const then = c.cleanup || c.home;
  $("undo-then").hidden = !then;
  $("undo-go").textContent = then ? "Put these back, then continue" : "Put these back";
}

async function runUndo() {
  const c = chosen(), wantH = c.undoHome, wantA = c.undoApps;
  if (!wantH && !wantA) return;
  show("running"); busy = true; setError("run-error"); $("run-back").hidden = true;
  $("run-title").textContent = "Putting things back…";
  const bar = $("bar"), label = $("bar-label"), log = $("log"); log.textContent = ""; bar.removeAttribute("value"); label.textContent = "";
  const on = (l) => progress(l, bar, label, log);
  const check = (out) => { if (!out.some((l) => l.startsWith("OK undo"))) throw new Error((out.find((l) => l.startsWith("FAIL")) || "FAIL Undo stopped partway. It is safe to run again.").slice(5)); };
  try {
    if (wantH) check(await tablet.setup(`undo --home${$("keep-apps").checked ? " --keep-apps" : ""}`, on));
    if (wantA) {
      const picked = undoPlan.apps.filter((p) => !undoOff.has(p));
      const pkgs = picked.length === undoPlan.apps.length ? "" : ` --pkgs=${picked.join(",") || "none"}`;
      check(await tablet.setup(`undo --apps${pkgs}`, on));
    }
    busy = false;
    // Undo first, then any new change chosen with it (say, the original Home screen back and Clean up).
    if (c.cleanup || c.home) { $("opt-undo-apps").checked = false; $("opt-undo-home").checked = false; await toConfirm(); return; }
    show("undone");
  } catch (e) { busy = false; setError("run-error", plainError(e)); $("run-title").textContent = "Stopped"; $("run-back").hidden = false; }
}

// Preview mode, on the plain page only (safe mode keeps its own bar). Until a tablet is connected, scrolling on
// past the bottom of a screen moves to the next one and scrolling up past its top goes back, so the whole flow can
// be looked through without pressing anything. Past Connect it is a preview: a pretend tablet fills the screens,
// nothing in them can be pressed, and the tablet picture moves with the scroll instead of playing by itself.
// Real work starts only from Connect tablet. Each move waits for the scroll that made it to settle.
let previewing = false;
const FLOW = ["start", "about", "usb", "connect", "review", "confirm", "running", "finish", "next"];
const FLOW_NAME = { about: "Before you start", usb: "USB debugging", connect: "Connect", review: "Preview: choose", confirm: "Preview: Decaid", running: "Preview: working", finish: "Preview: finish", next: "Preview: what to do next" };
const LONG = { start: 1100, running: 1100 }; // these screens play their picture as the scroll goes on
let prog = 0, pull = 0, quietUntil = 0, moving = false, navStep = null, settle = false, lastNudge = 0;
const hintEl = el("div", { className: "scroll-hint", ariaHidden: "true" });
const scrubTo = (step, p) => {
  document.dispatchEvent(new CustomEvent("scrub", { detail: { step, p } }));
  if (previewing && step === "running") previewLog(p);
};
// The preview's Show details lists the default load-out: every app the clean-up would switch off with nothing
// changed on Choose, ticked off as the scroll goes on.
function previewLog(p) {
  const plan = toSwitchOff(), t = plan.length, n = Math.round(p * t), log = $("log");
  $("bar").max = t; $("bar").value = n; $("bar-label").textContent = `${n} of ${t}`;
  log.textContent = plan.map((a, i) => `${i < n ? "DONE " : "TO DO"} ${String(i + 1).padStart(String(t).length)}/${t} ${a.name}`).join("\n");
  const row = log.scrollHeight / Math.max(t, 1); log.scrollTop = Math.max(0, row * n - log.clientHeight / 2);
}
const navOn = () => !DEMO && !busy && !moving && (previewing || !tablet) && FLOW.includes(current);
const atEnd = () => scrollY + innerHeight >= document.documentElement.scrollHeight - 2;
const atTop = () => scrollY <= 0;
function hint() {
  const next = FLOW[FLOW.indexOf(current) + 1];
  const on = navOn() && next && atEnd();
  hintEl.toggleAttribute("data-on", !!on); if (!on) return;
  const r = document.querySelector("main").getBoundingClientRect();
  hintEl.style.left = `${r.left + r.width / 2}px`;
  hintEl.innerHTML = `Keep scrolling: ${FLOW_NAME[next]} ↓<i></i>`;
  hintEl.style.setProperty("--p", Math.min(1, prog / (LONG[current] || 160)));
}
async function move(d) {
  const to = FLOW[FLOW.indexOf(current) + d]; if (!to) return;
  moving = true; quietUntil = performance.now() + 500; prog = 0; pull = 0; settle = true;
  try {
    if (to === "review" && !previewing) await enterPreview();
    else if (to === "connect" && previewing) exitPreview();
    else if (previewing) await previewShow(to);
    else show(to);
  } catch (e) { console.error(e); exitPreview(); }
  finally { moving = false; }
  navStep = current;
  if (d < 0 && LONG[current]) prog = LONG[current] - 1; // back into a picture screen: at its end
  scrubTo(current, prog / (LONG[current] || 160)); hint();
}
function nudge(dy) {
  // After a move, the gesture that made it has to stop (a 250 ms gap) before the next one counts.
  const t = performance.now(), gap = t - lastNudge; lastNudge = t;
  if (settle) { if (gap < 250 || t < quietUntil) return; settle = false; }
  if (!navOn()) return;
  const need = LONG[current] || 160;
  if (dy > 0) {
    if (!atEnd()) return;
    pull = 0; prog = Math.min(need, prog + dy); scrubTo(current, prog / need); hint();
    if (prog >= need) move(1);
  } else {
    if (prog > 0 && atEnd()) { prog = Math.max(0, prog + dy); scrubTo(current, prog / need); hint(); return; }
    if (!atTop()) return;
    pull -= dy; if (pull >= 160) move(-1);
  }
}
async function enterPreview() {
  previewing = true; document.body.dataset.preview = "";
  tablet = new DemoTablet({}); await tablet.prepare(FILES);
  await review();
}
function exitPreview() {
  previewing = false; delete document.body.dataset.preview;
  tablet = null; status = null; keep.clear(); FORCE = ""; appState = {};
  $("bar").removeAttribute("value"); $("bar-label").textContent = ""; $("log").textContent = "";
  scrubTo(null, 0); show("connect", false);
}
async function previewShow(to) {
  if (to === "review") { show("review"); return; }
  if (to === "next") { show("next"); return; }
  if (to === "confirm") {
    decaidHave = await isInstalled(APKS.find((a) => a.name === "decaid").pkg);
    $("decaid-have").hidden = !decaidHave; $("decaid-choice").hidden = decaidHave; $("decaid-missing").hidden = true;
    show("confirm"); return;
  }
  if (to === "running") {
    show("running"); setError("run-error"); $("run-back").hidden = true;
    $("run-title").textContent = "Switching off apps…"; previewLog(0);
    return;
  }
  if (to === "finish") {
    for (const e of document.querySelectorAll("[data-home]")) e.hidden = false;
    for (const e of document.querySelectorAll("[data-decaid]")) e.hidden = false;
    $("refused").textContent = ""; wantHomeDone = true; setError("fin-error");
    show("finish");
    $("fin-you").hidden = true; $("fin-run").hidden = false;
    for (const li of $("fin-steps").children) { li.hidden = false; finState(li.dataset.k, "done"); }
    finishLeft();
  }
}
function scrollNav() {
  if (DEMO) return;
  document.body.append(hintEl);
  addEventListener("wheel", (e) => nudge(e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY), { passive: true });
  let ty = null;
  addEventListener("touchstart", (e) => { ty = e.touches[0].clientY; }, { passive: true });
  addEventListener("touchmove", (e) => { if (ty == null) return; const y = e.touches[0].clientY; nudge((ty - y) * 2.5); ty = y; }, { passive: true });
  addEventListener("keydown", (e) => {
    if (e.target.closest("input, textarea, select, [contenteditable]")) return;
    const d = { PageDown: 1, ArrowDown: 1, " ": e.shiftKey ? -1 : 1, PageUp: -1, ArrowUp: -1 }[e.key];
    if (d && (d > 0 ? atEnd() : atTop())) nudge(d * 220);
  });
  addEventListener("scroll", hint, { passive: true }); addEventListener("resize", hint);
  document.addEventListener("scrub-to", (e) => { if (!navOn() || !LONG[current]) return; prog = e.detail * LONG[current]; scrubTo(current, e.detail); hint(); });
  // Get started in the preview box: leave the preview and begin for real, where the start page's button goes.
  $("preview-exit").onclick = () => { if (!previewing) return; exitPreview(); show("usb"); navStep = current; scrubTo(current, 0); hint(); };
  // A button press moves on for real: start the new screen's picture from the beginning.
  new MutationObserver(() => { if (moving || current === navStep) return; navStep = current; if (!navOn()) { hint(); return; } prog = 0; scrubTo(current, 0); hint(); }).observe(document.querySelector("main"), { subtree: true, attributes: true, attributeFilter: ["hidden"] });
  navStep = current; scrubTo(current, 0); hint();
}

// Names the release in the download link the first time the Decaid choice shows. The link works without it.
let decaidNamed = false;
function nameDecaid() {
  if (decaidHave || decaidNamed || DEMO) return;
  decaidNamed = true;
  latestApk(APKS.find((a) => a.name === "decaid").url).then((l) => { if (l.version) $("decaid-link").textContent = `download the latest Decaid (${l.version})`; }).catch(() => { decaidNamed = false; });
}

async function toConfirm() {
  decaidHave = await isInstalled(APKS.find((a) => a.name === "decaid").pkg);
  $("decaid-have").hidden = !decaidHave; $("decaid-choice").hidden = decaidHave; $("decaid-missing").hidden = true;
  nameDecaid();
  show("confirm");
}

function init() {
  if (!supported()) { $("unsupported").hidden = false; $("start").disabled = true; }
  $("more").onclick = () => show("about");
  $("start").onclick = () => show("usb");
  $("usb-next").onclick = () => show("connect");
  $("connect").onclick = connect;
  $("do-setup").onclick = async () => {
    const c = chosen(), none = !c.cleanup && !c.home && !c.undoApps && !c.undoHome;
    $("opt-none").hidden = !none;
    if (none) return;
    if (c.undoApps || c.undoHome) { syncUndo(); show("undo"); return; }
    await toConfirm();
  };
  for (const id of ["decaid-add", "decaid-skip"]) $(id).addEventListener("change", () => { $("decaid-get").hidden = !$("decaid-add").checked; $("decaid-missing").hidden = true; });
  $("decaid-file").addEventListener("change", () => { $("decaid-missing").hidden = true; });
  // Finish: a ready-made post for anyone who wants to pass it on. Nothing is sent anywhere unless they choose to.
  // In production the tool runs at tablet.decadentcoffee.app inside the page at the public address; share that page.
  const pageUrl = location.hostname.endsWith("decadentcoffee.app") || location.hostname.endsWith(".pages.dev")
    ? "https://decadentcoffee.app/clean-decent-tablet/" : location.origin + location.pathname;
  $("share-text").value = `I cleaned up the tablet on my Decent espresso machine: about 100 unneeded apps and background services switched off, and a quiet Home screen with just what the DE1 needs. Free, open source and fully undoable: ${pageUrl}`;
  $("share-copy").onclick = async () => {
    try { await navigator.clipboard.writeText($("share-text").value); $("share-done").textContent = "Copied."; }
    catch { $("share-text").select(); $("share-done").textContent = "Selected: press Ctrl+C or Cmd+C to copy."; }
  };
  if (navigator.share) {
    $("share-send").hidden = false;
    $("share-send").onclick = () => navigator.share({ title: "Clean theme for Decent Espresso Tablet", text: $("share-text").value }).catch(() => {});
  }
  $("confirm-go").onclick = () => {
    if (!decaidHave && $("decaid-add").checked && !$("decaid-file").files[0] && !(DEMO && qs.get("decaid") === "add")) { $("decaid-missing").hidden = false; $("decaid-file").focus(); return; }
    runSetup();
  };
  $("wifi-open").onclick = () => tablet && tablet.setup("finish wifi-open").catch(() => {});
  $("acct-open").onclick = () => tablet && tablet.setup("finish account-open").catch(() => {});
  $("acct-skip").onclick = () => { finAcct = "skip"; finStatus().catch(() => {}); };
  $("fin-go").onclick = () => runFinish();
  $("decaid-pass").onclick = () => { decaidPass = true; };
  for (const li of $("fin-steps").children) { const item = document.createElement("li"); item.innerHTML = li.querySelector(".by-hand").innerHTML; $("fin-byhand-list").append(item); }
  $("to-next").onclick = () => show("next");
  $("fin-reconnect").onclick = reconnectByHand;
  $("app-groups").addEventListener("change", (e) => {
    const t = e.target;
    if (t.dataset.pkg) { if (t.checked) keep.delete(t.dataset.pkg); else keep.add(t.dataset.pkg); }
    if (t.dataset.group) for (const a of APPS.filter((a) => a.group === t.dataset.group && appState[a.pkg] === "enabled")) { if (t.checked) keep.delete(a.pkg); else keep.add(a.pkg); }
    if (t.dataset.group) for (const b of document.querySelectorAll("#app-groups input[data-pkg]")) if (!b.disabled) b.checked = !keep.has(b.dataset.pkg);
    syncApps();
  });
  $("pick-reset").onclick = () => { keep.clear(); for (const b of document.querySelectorAll("#app-groups input[data-pkg]")) if (!b.disabled) b.checked = true; syncApps(); };
  // Each area has one direction at a time: switching apps off or turning them back on, the new Home screen or the original.
  const OTHER = { "opt-cleanup": "opt-undo-apps", "opt-undo-apps": "opt-cleanup", "opt-home": "opt-undo-home", "opt-undo-home": "opt-home" };
  for (const id of [...Object.keys(OTHER), "keep-apps"]) $(id).addEventListener("change", () => {
    if ($(id).checked) { $("opt-none").hidden = true; if (OTHER[id]) $(OTHER[id]).checked = false; }
    syncChoices();
  });
  $("undo-go").onclick = runUndo;
  // Untested firmware or model: the options appear only once the owner accepts, and every change then runs with --force.
  for (const id of ["accept-build", "accept-model"]) $(id).addEventListener("change", async (e) => {
    FORCE = e.target.checked ? " --force" : "";
    doAllowed = e.target.checked;
    if (doAllowed) { working("Counting the apps…"); try { await loadPlan(); } finally { working(""); } }
    const v = shown(); $("opt-cleanup").checked = v.cleanup; $("opt-home").checked = v.home;
    syncChoices();
  });
  $("undo-app-list").addEventListener("change", (e) => { const p = e.target.dataset.undoPkg; if (p) { if (e.target.checked) undoOff.delete(p); else undoOff.add(p); syncUndo(); } });
  window.addEventListener("popstate", (e) => {
    if (previewing) exitPreview();
    const step = e.state && e.state.step;
    if (busy) { history.pushState({ step: "running" }, ""); return; } // never leave a running change
    if (!step) return;
    if (step === "running") { history.back(); return; }
    if (NEEDS_TABLET.includes(step) && !tablet) { show("connect", false); history.replaceState({ step: "connect" }, ""); return; }
    show(step, false);
  });
  for (const b of document.querySelectorAll("[data-back]")) b.onclick = () => show(b.dataset.back);
  $("decaid-link").href = APKS.find((a) => a.name === "decaid").url;
  show(qs.get("step") || "start");
  scrollNav();
  if (DEMO && qs.get("to")) demoGoTo(qs.get("to")).catch((e) => console.error(e));
}
init();
