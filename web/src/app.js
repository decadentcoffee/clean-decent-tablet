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
// The way in. ?for=decadent comes from Decadent's sign-up: the same page, with Decadent ticked from the start.
const FOR_DECADENT = qs.get("for") === "decadent";

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
  // Windows answers "Access denied" (a SecurityError) when another program or driver already holds the tablet, not the tablet's Allow.
  if ((err && err.name === "SecurityError") || /SecurityError|Access denied/i.test(m)) return "Windows didn't let the browser use the tablet. Another program or driver has it: close Android Studio, Samsung Smart Switch and any other Android tool. If you have used ADB on this computer, run: adb kill-server. Then unplug the tablet, plug it back in and try again.";
  if (/auth|reject|denied/i.test(m)) return "The tablet didn't allow this computer. Unlock it, tap Allow on the USB debugging message, and try again.";
  if (/disconnect|transfer|network|closed/i.test(m)) return "The connection to the tablet dropped. Check the cable, and try again. Anything already done is saved in the record on the tablet, so it's safe to run again.";
  return `Something went wrong: ${m}`;
}
// An error this page words itself (a download, a checksum): shown as it is, never as a script failure.
const said = (text) => Object.assign(new Error(text), { plain: true });
// A stopped run says what happened in plain words; the script's own line goes under Show details. Its one action
// reads the tablet again, so the choices on the next screen (undo included) come from the record on the tablet.
function stopRun(e) {
  busy = false; $("run-title").textContent = "Stopped"; $("run-lead").hidden = true; $("run-back").hidden = false;
  const text = e && e.plain ? e.message : plainError(e);
  setError("run-error", text.startsWith("Something went wrong") ? "The tablet stopped partway. What it changed so far is kept and recorded on the tablet. Check the tablet again, then run the setup again or put things back." : text);
  const raw = String(e && e.message || e), log = $("log"); if (!log.textContent.includes(raw)) log.textContent += `${log.textContent ? "\n" : ""}${raw}`;
}

function supported() { return DEMO || ("usb" in navigator && window.isSecureContext); }

async function connect() {
  setError("connect-error"); const btn = $("connect"); btn.disabled = true; btn.textContent = "Connecting…";
  try {
    if (DEMO) tablet = new DemoTablet({ slow: !qs.get("to"), decadent: qs.get("decadent") === "installed", done: DEMO_KIND === "done", noDecaid: DEMO_KIND === "nodecaid", original: qs.get("original") === "1", manual: DEMO_KIND === "manual", net: qs.get("net") || (qs.get("to") === "finished" ? "all" : null), hold: qs.get("to") === "running", asks: qs.get("asks") ? +qs.get("asks") : DEMO_KIND === "nodecaid" && qs.get("decaid") === "add" ? 4 : 0, fail: { model: "model", fail: "run", build: "build" }[DEMO_KIND] });
    else {
      // A second Connect in one visit (after Back to start): let go of the first connection, or the tablet never answers.
      if (tablet) { const old = tablet; tablet = null; try { await old.close(); } catch {} }
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
      el("span", { textContent: "Its model, firmware and what has been changed before. This can take a minute." })));
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
  // In the preview the pretend tablet never reads as a real connection.
  if (previewing) $("device-name").replaceChildren(
    el("span", { className: "found-mark", ariaHidden: "true", textContent: "✓" }),
    el("span", { className: "found-what" }, el("small", { textContent: "Preview" }), el("b", { textContent: "Example tablet" }),
      el("span", { textContent: "Your tablet's model and firmware show here once it is connected." })));
  else $("device-name").replaceChildren(
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
  decaidHave = await isInstalled(APKS.find((a) => a.name === "decaid").pkg);
  choiceDefaults();
  // Safe mode: on=decaid,decadent,cleanup,home,plugin sets exactly those ticks.
  if (DEMO && qs.get("on") !== null) { const on = qs.get("on").split(","); for (const k of ["decaid", "decadent", "plugin", "cleanup", "home"]) $(`opt-${k}`).checked = on.includes(k); }
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
    decaid: doAllowed && !decaidHave,
    decadent: doAllowed && !!status && status.decadent_app !== "installed",
    plugin: doAllowed && !!status && status.decadent_app === "installed",
    cleanup: doAllowed && avail > 0,
    home: doAllowed && status && status.home !== FOSSIFY,
    undoApps: undoPlan.apps.length + undoPlan.appSettings.length > 0,
    undoHome: undoPlan.home.length > 0,
  };
}
function choiceDefaults() {
  const v = shown();
  $("opt-cleanup").checked = v.cleanup; $("opt-home").checked = v.home;
  $("opt-decaid").checked = v.decaid; $("opt-decadent").checked = v.decadent && FOR_DECADENT; $("opt-plugin").checked = v.plugin && FOR_DECADENT;
  $("opt-undo-apps").checked = false; $("opt-undo-home").checked = false; $("keep-apps").checked = false;
}
// What the person has chosen, counting only the options on screen.
function chosen() {
  const v = shown();
  const decaid = v.decaid && $("opt-decaid").checked;
  return { decaid, decadent: v.decadent && $("opt-decadent").checked && (decaidHave || decaid), plugin: v.plugin && $("opt-plugin").checked && (decaidHave || decaid),
    cleanup: v.cleanup && $("opt-cleanup").checked, home: v.home && $("opt-home").checked,
    undoApps: v.undoApps && $("opt-undo-apps").checked, undoHome: v.undoHome && $("opt-undo-home").checked };
}
function syncChoices() {
  const v = shown();
  // Decadent reaches the machine through Decaid: without Decaid on the tablet or ticked, its tick is off and says why.
  const noDecaid = !FOR_DECADENT && v.decadent && !decaidHave && !(v.decaid && $("opt-decaid").checked);
  if (FOR_DECADENT) { // Decaid, the plugin and the app are what this way in is for: they are not choices
    $("opt-decaid").checked = v.decaid; $("opt-decadent").checked = v.decadent; $("opt-plugin").checked = v.plugin;
    const fixed = $("row-decadent-fixed"); fixed.hidden = !(v.decaid || v.decadent || v.plugin);
    fixed.innerHTML = `<b>Decadent.</b> ${v.decaid ? "Decaid, Decent's app for the machine, goes on first. " : ""}${v.decadent ? "Then the Decadent plugin and the app." : "The Decadent plugin is checked, and added if it is missing."}`;
  }
  if (noDecaid && !FOR_DECADENT) $("opt-decadent").checked = false;
  $("opt-decadent").disabled = noDecaid; $("decadent-needs").hidden = !noDecaid;
  const c = chosen();
  $("row-decaid").hidden = !v.decaid || FOR_DECADENT; $("row-decadent").hidden = !v.decadent || FOR_DECADENT; $("row-plugin").hidden = !v.plugin || FOR_DECADENT;
  $("row-cleanup").hidden = !v.cleanup; $("pick").hidden = !c.cleanup;
  $("row-home").hidden = !v.home;
  $("row-undo-apps").hidden = !v.undoApps; $("undo-pick").hidden = !c.undoApps || undoPlan.apps.length === 0;
  $("row-undo-home").hidden = !v.undoHome; $("row-keep-apps").hidden = !c.undoHome;
  const any = v.decaid || v.decadent || v.plugin || v.cleanup || v.home || v.undoApps || v.undoHome;
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
  await $("do-setup").onclick();
  if (FOR_DECADENT) { if (to === "finished") await until(() => !$("fin-after").hidden || !$("opt-none").hidden, 60000); return; } // no Decaid screen, and the end runs by itself
  if (to === "confirm" || current !== "confirm") return;
  if (!decaidHave) { const d = qs.get("decaid") || (want.decaid ? "add" : "skip"); $(d === "add" ? "decaid-add" : "decaid-skip").checked = true; $("decaid-get").hidden = d !== "add"; }
  const go = runSetup(); if (to === "running") return;
  await go; if (to === "finish") return;
  await until(() => $("fin-go") && !$("fin-you").hidden);
  await runFinish(); await until(() => !$("fin-after").hidden, 60000);
}


async function loadPlan() {
  const plan = (await tablet.setup(`plan${FORCE}`)).find((l) => l.startsWith("PLAN disable="));
  const n = plan ? plan.match(/disable=(\d+)/)[1] : "?";
  $("count").textContent = n; $("count-apps").textContent = +n === 1 ? "app" : "apps";
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
  $("count").textContent = n; $("count-apps").textContent = +n === 1 ? "app" : "apps";
  $("picked").textContent = `(${n} of ${avail} ticked)`;
}

// The list the core script runs, minus anything the person unticked. The script still refuses protected packages.
function chosenList() {
  return FILES["packages-disable.txt"].split("\n").filter((l) => { const p = l.split(" ")[1]; return l.startsWith("#") || !p || !keep.has(p); }).join("\n");
}

function progress(line, bar, label, log) {
  const p = parseProgress(line);
  if (p) { bar.max = p.total; bar.value = p.n; label.textContent = `${p.n} of ${p.total}`; }
  // After the last app the tablet waits 30 seconds for Android to save the changes: say so, or the full bar looks stuck.
  if (/^INFO waiting/.test(line)) label.textContent = "All switched off. Saving the changes takes about 30 seconds…";
  if (/^(DONE|REFUSED|FAIL|OK|MANUAL)/.test(line)) { log.textContent += line + "\n"; log.scrollTop = log.scrollHeight; }
}

async function installApk(a, bytes, onLine) {
  const path = `${REMOTE}/${a.name}.apk`;
  await tablet.push(path, bytes);
  const out = await tablet.setup(`install ${path}${FORCE}`, onLine);
  if (out.some((l) => l.startsWith("FAIL"))) throw new Error(out.find((l) => l.startsWith("FAIL")).slice(5));
}

let decaidHave = true;
let changedAt = 0; // when the last change on the tablet finished: Android saves app states a little late
async function isInstalled(pkg) { return (await tablet.run(`pm list packages ${pkg}`)).includes(`package:${pkg}`); }

async function runSetup() {
  show("running"); busy = true; setError("run-error"); $("run-back").hidden = true; $("run-lead").hidden = false;
  const bar = $("bar"), label = $("bar-label"), log = $("log"); log.textContent = "";
  const on = (l) => progress(l, bar, label, log);
  try {
    const wantClean = want.cleanup, wantHome = want.home;
    // Decaid is checked before anything is installed: the chosen file must be Decent's latest release.
    const decaid = APKS.find((a) => a.name === "decaid");
    let decaidBytes = null;
    const decaidFile = $("decaid-file").files[0];
    if (!decaidHave && $("decaid-add").checked && (decaidFile || !DEMO)) {
      // The page fetches Decent's latest release itself (this site passes it on unchanged), unless the person chose
      // a file of their own; either way the bytes are checked against the checksum GitHub lists before anything is installed.
      $("run-title").textContent = decaidFile ? "Checking the Decaid file…" : "Downloading Decaid…";
      if (decaidFile) decaidBytes = new Uint8Array(await decaidFile.arrayBuffer());
      else {
        const res = await fetch("decaid-latest.apk").catch(() => null);
        if (!res || !res.ok) throw said("Decaid could not be downloaded. Check this computer's internet connection and try again. Nothing was installed.");
        decaidBytes = new Uint8Array(await res.arrayBuffer());
      }
      if (!DEMO) {
        const latest = await latestApk(decaid.url).catch(() => { throw said("The Decaid file could not be checked with GitHub. Check this computer's internet connection and try again. Nothing was installed."); });
        if ((await sha256(decaidBytes)) !== latest.sha) throw said(decaidFile ? `That file isn't the latest Decaid${latest.version ? ` (${latest.version})` : ""}. Download it again with the link on the Decaid step, or let this page get it. Nothing was installed.` : "The Decaid download did not match Decent's checksum. Try again. Nothing was installed.");
      }
    }
    $("run-title").textContent = "Installing the launcher…";
    const fossify = APKS.find((a) => a.name === "fossify");
    if (wantHome && !(await isInstalled(fossify.pkg))) {
      const bytes = DEMO ? new Uint8Array(1) : new Uint8Array(await (await fetch("fossify.apk")).arrayBuffer());
      if (!DEMO && (await sha256(bytes)) !== fossify.sha) throw said("The launcher download failed its checksum. Nothing was installed.");
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
    $("fin-done").textContent = wantClean ? "The clean-up is done." : wantHome ? "The new Home screen is in." : decaidBytes ? "Decaid is installed." : "";
    if (wantClean || wantHome) changedAt = Date.now();
    busy = false; wantHomeDone = wantHome; ranChange = wantClean || wantHome || undid; show("finish"); startFinish();
  } catch (e) { stopRun(e); }
}

// Last steps. The owner joins Wi-Fi and signs in to Google; the core script's `finish` steps drive the rest
// through the tablet's screen. Decaid's first questions are a pause for the owner (decaidReady). The written instructions
// are always on the screen as the second way; a step the tablet doesn't allow also lists its own under Left for you.
let wantHomeDone = true, ranChange = true, finWifi = false, finAcct = null, finPoll = null, decadentHad = false, finHome = "", finOriginal = false;
const FIN = (s) => $("fin-steps").querySelector(`[data-k="${s}"]`);
function finState(k, state, why) {
  const li = FIN(k); if (!li) return;
  li.dataset.state = state;
  li.querySelector(".st").textContent = { run: "…", done: "✓", skip: "–", manual: "!", you: "?" }[state] || "";
  // The glyph is only a picture: the state is also said in words, and a step left for you says why on screen.
  let word = li.querySelector(".what + .vh"), line = li.querySelector(".fin-why");
  if (!word) li.querySelector(".what").after(word = el("span", { className: "vh" }), line = el("p", { className: "fin-why" }));
  word.textContent = `: ${{ run: "working on it", done: "done", skip: "not needed", manual: "left for you", you: "waiting for you" }[state] || ""}`;
  line.textContent = state === "manual" && why ? `Not done here: ${why}.` : ""; line.hidden = !line.textContent;
  const shown = [...$("fin-steps").children].filter((s) => !s.hidden), n = (st) => shown.filter((s) => s.dataset.state === st).length;
  $("fin-sum").textContent = `${n("done") + n("skip")} of ${shown.length} steps done${n("manual") ? `, ${n("manual")} left for you` : ""}.`;
}
async function finStatus() {
  const st = parseStatus(await tablet.setup("finish status"));
  finWifi = st.wifi === "connected";
  decadentHad = st.decadent_app === "installed"; finHome = st.home || ""; finOriginal = st.original_app === "yes";
  if (finAcct !== "skip") finAcct = st.google_account === "yes" ? "yes" : "no";
  $("fin-wifi-state").textContent = finWifi ? "Connected ✓" : "Not connected";
  $("wifi-form").hidden = finWifi;
  $("fin-acct-state").textContent = finAcct === "yes" ? "Signed in ✓" : finAcct === "skip" ? "Going on without one" : "Not signed in";
  $("acct-form").hidden = finAcct !== "no";
  $("fin-nowifi").hidden = finWifi;
  const ready = finWifi && finAcct !== "no";
  $("fin-lead").textContent = ready ? (FOR_DECADENT ? "The tablet is on Wi-Fi and ready. This page does the rest." : "The tablet is on Wi-Fi and ready. Choose Finish for me and this page does the rest.") : `${finWifi || finAcct !== "no" ? "One thing needs" : "Two things need"} you. This page does the rest.`;
  $("fin-you-h").textContent = ready ? "Ready" : "Only you can do these";
  if (finWifi && finAcct !== "no") stopPoll();
  return st;
}
function stopPoll() { clearInterval(finPoll); finPoll = null; }
async function startFinish() {
  $("fin-you").hidden = FOR_DECADENT; $("fin-run").hidden = true; $("fin-after").hidden = true; shareBox(false);
  for (const li of $("fin-steps").children) { delete li.dataset.state; li.querySelector(".st").textContent = ""; for (const x of li.querySelectorAll(".what + .vh, .fin-why")) x.remove(); }
  $("fin-sum").textContent = ""; $("fin-back").hidden = false;
  try { await finStatus(); } catch (e) { setError("fin-error", plainError(e)); }
  stopPoll();
  if (autoFinish()) return;
  finPoll = setInterval(() => { if (current !== "finish" || !$("fin-run").hidden || !tablet) return stopPoll(); finStatus().then(autoFinish).catch(() => {}); }, 4000);
}
// From Decadent's way in nobody presses Finish for me: with Wi-Fi the last steps start by themselves. A Google
// account is used when the tablet has one and never asked for. Without Wi-Fi the page waits and says so.
function autoFinish() {
  if (!FOR_DECADENT || current !== "finish" || !$("fin-run").hidden || busy) return false;
  if (!finWifi) { $("fin-you").hidden = false; $("fin-lead").textContent = "The tablet needs Wi-Fi for the next part. Join a network on the tablet, and this page carries on."; $("fin-you-h").textContent = "One thing first"; return false; }
  if (finAcct !== "yes") finAcct = "skip";
  runFinish(); return true;
}
function shareBox(on) { document.querySelector('[data-step="finish"] .share').hidden = !on; }
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
// The tablet drops off USB while it restarts. Find it again: the browser keeps the permission, and the tablet
// remembers this computer if "Always allow" was ticked.
async function restartTablet() {
  if (DEMO) {
    if (qs.get("allow")) { $("allow-ask").hidden = false; finState("restart", "you"); await wait(+qs.get("allow") || 3000); $("allow-ask").hidden = true; finState("restart", "run"); }
    await wait(1500); return;
  }
  // A restart within 30 seconds of switching apps off brought some of them back (docs/compatibility.md), so wait it out.
  const early = 30000 - (Date.now() - changedAt); if (early > 0) await wait(early);
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
      // No answer within a few seconds means the tablet is asking to allow this computer again ("Always allow" was not
      // ticked): say so, and wait for the tap however long it takes.
      const ask = setTimeout(() => { $("allow-ask").hidden = false; finState("restart", "you"); }, 6000);
      try { tablet = await connectTablet(device, new AdbWebCredentialStore("Decent tablet setup")); }
      finally { clearTimeout(ask); $("allow-ask").hidden = true; finState("restart", "run"); }
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
  // Updates with nothing to update are done, not left out: a dash there read as a step that did not run.
  if (k === "updates" && mine.length && mine.every((l) => /^SKIP .* up to date$/.test(l))) return "done";
  if (mine.some((l) => l.startsWith("SKIP"))) return "skip";
  return k === "updates" && lines.some((l) => l.startsWith("OK finish")) ? "skip" : "manual";
}
async function runFinish(afterRestart = false) {
  stopPoll(); busy = true; $("fin-back").hidden = true; // no leaving while the tablet is being driven (D-22)
  $("fin-you").hidden = true; $("fin-run").hidden = false; $("fin-after").hidden = true; setError("fin-error");
  $("fin-run-h").textContent = "Finishing the tablet…"; $("fin-keep").hidden = false;
  try { await finStatus(); } catch { /* keep the last reading */ }
  // The steps for this visit. Read from the tablet as it is now (an undo may have run since the choose screen):
  // the launcher steps arrange a launcher this visit installed, and never one the person has already arranged.
  const newHome = wantHomeDone, ours = finHome === FOSSIFY, samsung = finHome === "com.sec.android.app.launcher";
  const decaidThere = decaidHave || ($("decaid-add").checked && !!want.decaid);
  // From Decadent's way in the app is always wanted, also when an undo in this visit has just removed it.
  const wantD = (FOR_DECADENT || want.decadent) && decaidThere, decadent = wantD && !decadentHad;
  const onHome = wantD || decadentHad; // Decadent's icon belongs on Home
  const plugin = (wantD || want.plugin) && decaidThere;
  const plan = [...(ranChange ? ["restart"] : []), ...(plugin ? ["plugin"] : []), ...(newHome && ours ? ["icons", "launcher"] : []),
    ...(ranChange || (decadent && finAcct === "yes") ? ["updates"] : []), ...(decadent ? ["decadent"] : []),
    // On Samsung's own Home a Decadent that was already installed gets its icon only when Home shows none (place if-missing).
    ...((ours && (newHome || wantD)) || (samsung && wantD) ? ["place"] : []), ...(newHome && ours ? ["more"] : []), ...(decaidThere || onHome ? ["open"] : [])];
  // Name only the icons this tablet will get: Decaid if it is there, Decadent if wanted.
  // A tablet that stays on the original Decent app (no Decaid): Home leads with it and Decent's two other apps, and
  // Settings goes to the second page (D-38). The Decent icon is a shortcut only the tablet step can add.
  const original = ours && finOriginal && !decaidThere;
  const icons = original ? ["Decent", "Coffee Flow", "SE Profiler"] : ours ? [...(decaidThere ? ["Decaid"] : []), ...(onHome ? ["Decadent"] : []), "Settings"] : ["Decadent"];
  FIN("place").querySelector(".place-note").hidden = !original;
  FIN("more").querySelector(".what").textContent = original ? "Put Settings on a second Home page" : "Put Decent's other apps on a second Home page";
  for (const n of FIN("more").querySelectorAll("[data-more]")) n.hidden = (n.dataset.more === "original") !== original;
  const said = (b) => icons.map((n) => (b ? `<b>${n}</b>` : n)).join(", ").replace(/, ([^,]*)$/, " and $1");
  const [w, h] = FIN("place").querySelectorAll(".place-list"); w.textContent = said(false); h.innerHTML = said(true);
  // The last step names only the apps it opens: Decadent when it is, or will be, on the tablet.
  const opens = [...(decaidThere ? ["Decaid"] : []), ...(onHome ? ["Decadent"] : [])];
  FIN("open").querySelector(".what").textContent = "Open " + opens.join(", then ");
  FIN("open").querySelector(".by-hand").innerHTML = "Open " + opens.map((n) => `<b>${n}</b>`).join(" once, then ") + ".";
  for (const li of $("fin-steps").children) li.hidden = !plan.includes(li.dataset.k);
  try {
    if (plan[0] === "restart" && !afterRestart) {
      finState("restart", "run");
      try { await restartTablet(); finState("restart", "done"); }
      catch { finState("restart", "manual"); busy = false; $("fin-back").hidden = false; setError("fin-error", "The tablet didn't come back on its own. Unplug it and plug it back in, unlock it, tap Allow if it asks, then choose Reconnect the tablet."); $("fin-reconnect-row").hidden = false; return; }
    }
    for (const k of plan) {
      if (k === "restart") continue; // done above, or by hand before Reconnect
      finState(k, "run");
      // From Decadent's way in an account is never asked for (D-36): without one the updates are skipped, not left for the person.
      if (k === "updates" && FOR_DECADENT && finWifi && finAcct !== "yes") { finState(k, "skip"); continue; }
      if (k === "updates" && (!finWifi || finAcct !== "yes")) { finState(k, "manual", finWifi ? "needs a Google account" : "needs Wi-Fi"); continue; }
      if (k === "decadent" && !finWifi) { finState(k, "manual", "needs Wi-Fi"); continue; }
      if (k === "open") { await openApps(); finState(k, "done"); continue; }
      if (k === "plugin" && !(await decaidReady())) { finState(k, "manual", decaidPass ? "skipped for now" : "Decaid's first questions were not answered"); continue; }
      if (k === "plugin") finState(k, "run");
      let lines;
      try { lines = await tablet.setup(`finish ${k}${k === "place" && !onHome ? " no-decadent" : ""}${k === "place" && samsung && decadentHad ? " if-missing" : ""}`); } catch (e) { lines = [`MANUAL finish ${k} ${e.message}`]; }
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
  if (decadentIn) { const item = document.createElement("li"); item.innerHTML = "<b>Log in to Decadent</b> on the tablet. It's open and waiting: type your email and password, or tap <b>Show a QR code</b> there and scan it with your phone."; left.append(item); }
  // Samsung's own Home puts a new app in its app list only, and its menus cannot be driven from here.
  if (decadentIn && finHome !== FOSSIFY && FIN("place").dataset.state !== "done") { const item = document.createElement("li"); item.innerHTML = "<b>Put Decadent on Home.</b> It is in the tablet's app list: on Home, swipe up, hold <b>Decadent</b> and tap <b>Add to Home</b>."; left.append(item); }
  const none = left.children.length === 0;
  $("fin-left-h").textContent = none ? "All done" : FOR_DECADENT && left.children.length === 1 ? "One thing left" : "Left for you";
  if (none) { const item = document.createElement("li"); item.textContent = "Nothing. The tablet is ready."; left.append(item); }
  $("fin-run-h").textContent = "Finished"; $("fin-keep").hidden = true;
  // D-36 (5): logging in to Decadent is the one thing that may be left when the machine is Decadent.
  const loginOnly = decadentIn && left.children.length === 1;
  if (FOR_DECADENT) { $("fin-h").textContent = none || loginOnly ? "Your machine is Decadent" : "Nearly there"; $("fin-done").textContent = ""; $("refused").textContent = ""; }
  $("fin-lead").textContent = none ? "The tablet is ready." : FOR_DECADENT && left.children.length === 1 ? "One thing is left for you, below." : "Nearly ready: a few things are left for you, below.";
  $("fin-after").hidden = false; $("fin-back").hidden = false; shareBox(!FOR_DECADENT);
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
  const then = c.cleanup || c.home || c.decaid || c.decadent || c.plugin;
  $("undo-then").hidden = !then;
  $("undo-go").textContent = then ? "Put these back, then continue" : "Put these back";
}

async function runUndo() {
  const c = chosen(), wantH = c.undoHome, wantA = c.undoApps;
  if (!wantH && !wantA) return;
  show("running"); busy = true; setError("run-error"); $("run-back").hidden = true; $("run-lead").hidden = false;
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
    busy = false; undid = true; changedAt = Date.now();
    // Undo first, then any new change chosen with it (say, the original Home screen back and Clean up).
    if (want.decaid || want.decadent || want.plugin || want.cleanup || want.home) { $("opt-undo-apps").checked = false; $("opt-undo-home").checked = false; await toConfirm(); return; }
    show("undone");
  } catch (e) { stopRun(e); }
}

// Preview mode, on the plain page only (safe mode keeps its own bar). It starts only from Preview the steps on the
// first screen. Then, until a tablet is connected, scrolling on past the bottom of a screen (or Space, Page Down or
// the down arrow there) moves to the next one and scrolling up past its top goes back, so the whole flow can be
// looked through. Past Connect a pretend tablet fills the screens, nothing in them can be pressed, and the tablet
// picture moves with the scroll instead of playing by itself. Without it a scroll only plays the first screen's
// picture and never changes the screen. Real work starts only from Connect tablet. Each move waits for the scroll
// that made it to settle.
let previewing = false, touring = false;
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
const moves = () => navOn() && touring; // the screen changes with the scroll only once the preview was asked for
const atEnd = () => scrollY + innerHeight >= document.documentElement.scrollHeight - 2;
const atTop = () => scrollY <= 0;
function hint() {
  const next = FLOW[FLOW.indexOf(current) + 1];
  const on = moves() && next && atEnd();
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
  if (!navOn() || (!touring && !LONG[current])) return;
  const need = LONG[current] || 160;
  if (dy > 0) {
    if (!atEnd()) return;
    pull = 0; prog = Math.min(need, prog + dy); scrubTo(current, prog / need); hint();
    if (prog >= need && touring) move(1);
  } else {
    if (prog > 0 && atEnd()) { prog = Math.max(0, prog + dy); scrubTo(current, prog / need); hint(); return; }
    if (!atTop() || !touring) return;
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
    $("decaid-have").hidden = !decaidHave; $("decaid-choice").hidden = decaidHave;
    show("confirm"); return;
  }
  if (to === "running") {
    show("running"); setError("run-error"); $("run-back").hidden = true; $("run-lead").hidden = false;
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
  if (DEMO) { $("preview-start").hidden = true; return; } // safe mode has its own Next / Back bar
  document.body.append(hintEl);
  addEventListener("wheel", (e) => nudge(e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY), { passive: true });
  let ty = null;
  addEventListener("touchstart", (e) => { ty = e.touches[0].clientY; }, { passive: true });
  addEventListener("touchmove", (e) => { if (ty == null) return; const y = e.touches[0].clientY; nudge((ty - y) * 2.5); ty = y; }, { passive: true });
  addEventListener("keydown", (e) => {
    if (!touring || e.target.closest("input, textarea, select, [contenteditable]")) return;
    const d = { PageDown: 1, ArrowDown: 1, " ": e.shiftKey ? -1 : 1, PageUp: -1, ArrowUp: -1 }[e.key];
    if (d && (d > 0 ? atEnd() : atTop())) nudge(d * 220);
  });
  addEventListener("scroll", hint, { passive: true }); addEventListener("resize", hint);
  document.addEventListener("scrub-to", (e) => { if (!navOn() || !LONG[current]) return; prog = e.detail * LONG[current]; scrubTo(current, e.detail); hint(); });
  // Get started in the preview box: leave the preview and begin for real, where the start page's button goes.
  $("preview-start").onclick = () => { touring = true; move(1); };
  $("preview-exit").onclick = () => { if (!previewing) return; touring = false; exitPreview(); show("usb"); navStep = current; scrubTo(current, 0); hint(); };
  // A button press moves on for real: start the new screen's picture from the beginning.
  new MutationObserver(() => { if (moving || current === navStep) return; navStep = current; if (!navOn()) { hint(); return; } prog = 0; scrubTo(current, 0); hint(); }).observe(document.querySelector("main"), { subtree: true, attributes: true, attributeFilter: ["hidden"] });
  navStep = current; scrubTo(current, 0); hint();
}

// Names the release in the download link the first time the Decaid choice shows. The link works without it.
let decaidNamed = false;
function nameDecaid() {
  if (decaidHave || decaidNamed || DEMO) return;
  decaidNamed = true;
  latestApk(APKS.find((a) => a.name === "decaid").url).then((l) => { if (l.version) $("decaid-link").textContent = `Download the latest Decaid (${l.version})`; }).catch(() => { decaidNamed = false; });
}

// What this visit adds, fixed when the person leaves the choose screen: an undo that runs first must not change it.
let want = { decaid: false, decadent: false, plugin: false, cleanup: false, home: false };
let undid = false; // an undo ran in this visit: the tablet restarts before the last steps, as after any change
async function toConfirm() {
  decaidHave = await isInstalled(APKS.find((a) => a.name === "decaid").pkg);
  $("decaid-add").checked = want.decaid; $("decaid-skip").checked = !want.decaid; $("decaid-get").hidden = !want.decaid;
  if (FOR_DECADENT) { runSetup(); return; }
  $("decaid-have").hidden = !decaidHave; $("decaid-choice").hidden = decaidHave;
  $("confirm-h").textContent = decaidHave ? "Ready to start" : "Decaid installation";
  nameDecaid();
  show("confirm");
}

function init() {
  if (!supported()) { $("unsupported").hidden = false; $("start").disabled = true; }
  if (FOR_DECADENT) {
    // The way in from Decadent: one short first screen, then straight to the cable. The by-hand way stays on offer.
    $("start-decadent").hidden = false; $("start-clean").hidden = true;
    $("byhand-d").append(document.querySelector('[data-step="about"] details.byhand'));
    document.querySelector('[data-step="usb"] [data-back]').dataset.back = "start";
    $("start-d").onclick = () => show("usb");
    if (!supported()) { $("unsupported-d").hidden = false; $("start-d").disabled = true; }
    // The Home screen comes before the clean-up here, and Wi-Fi is the only thing asked of the person at the end.
    $("row-cleanup").before($("row-home")); $("fin-acct").hidden = true; $("fin-go").hidden = true; $("fin-h").textContent = "Setting up";
    document.querySelector("#setup-part legend").textContent = "What happens";
    document.querySelector("header .mark").textContent = "Tablet setup for Decadent";
    // Shorter words for the two choices: the details are one click away under each.
    $("row-home").querySelector("span").innerHTML = "<b>The Home screen</b><br>Decadent, Decaid and Settings as three large icons, and swipes in place of the bottom buttons.";
    const cu = $("row-cleanup").querySelector("span"); cu.innerHTML = `<b>The clean-up</b><br>Switches off <b id="count">0</b> bundled <span id="count-apps">apps</span>. Nothing is deleted, and any can be turned back on.`;
    document.querySelector('[data-step="connect"] .reassure').hidden = true;
  }
  $("more").onclick = () => show("about");
  $("start").onclick = () => show("usb");
  // One press: the Connect screen opens with the browser's device list already up. Its own button is the second try.
  $("usb-next").onclick = () => { show("connect"); connect(); };
  $("connect").onclick = connect;
  $("do-setup").onclick = async () => {
    const c = chosen(), none = !c.decaid && !c.decadent && !c.plugin && !c.cleanup && !c.home && !c.undoApps && !c.undoHome;
    $("opt-none").hidden = !none;
    if (none) return;
    want = { decaid: c.decaid, decadent: c.decadent, plugin: c.plugin, cleanup: c.cleanup, home: c.home };
    if (c.undoApps || c.undoHome) { syncUndo(); show("undo"); return; }
    await toConfirm();
  };
  for (const id of ["decaid-add", "decaid-skip"]) $(id).addEventListener("change", () => { $("decaid-get").hidden = !$("decaid-add").checked; });
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
  $("confirm-go").onclick = () => runSetup();
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
  for (const id of [...Object.keys(OTHER), "keep-apps", "opt-decaid", "opt-decadent", "opt-plugin"]) $(id).addEventListener("change", () => {
    if ($(id).checked) { $("opt-none").hidden = true; if (OTHER[id]) $(OTHER[id]).checked = false; }
    syncChoices();
  });
  $("undo-go").onclick = runUndo;
  $("run-again").onclick = () => review().catch((e) => { show("connect"); setError("connect-error", plainError(e)); });
  // Untested firmware or model: the options appear only once the owner accepts, and every change then runs with --force.
  for (const id of ["accept-build", "accept-model"]) $(id).addEventListener("change", async (e) => {
    FORCE = e.target.checked ? " --force" : "";
    doAllowed = e.target.checked;
    if (doAllowed) { working("Counting the apps…"); try { await loadPlan(); } finally { working(""); } }
    choiceDefaults();
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
