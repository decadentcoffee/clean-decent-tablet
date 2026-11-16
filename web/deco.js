// Presentation only. Watches which [data-step] is visible and switches the tablet
// screen drawn over the photo, its caption, the step dots and the slide direction.
// It also lays that screen onto the photo's tablet glass with a perspective warp.
// It never reads or changes anything app.js depends on.
(() => {
  const fig = document.querySelector(".device");
  const main = document.querySelector("main");
  if (!fig || !main) return;
  const cap = fig.querySelector(".device-cap");
  // The caption holds its words and, on the start step, two bars that pick the frame of the animation.
  let capText = cap, frames = [];
  if (cap) {
    capText = document.createElement("span"); capText.className = "cap-text"; capText.textContent = cap.textContent;
    const nav = document.createElement("span"); nav.className = "frames"; nav.setAttribute("role", "group"); nav.setAttribute("aria-label", "Animation frame");
    nav.innerHTML = '<button type="button" data-frame="off" aria-label="Apps switching off"><i></i></button><button type="button" data-frame="home" aria-label="The new Home screen"><i></i></button>';
    cap.replaceChildren(nav, capText);
    frames = [...nav.querySelectorAll("button")];
  }
  const root = document.documentElement;
  // On the plain page the picture never plays by itself: app.js sends "scrub" events ({step, p} with p 0..1)
  // as the visitor scrolls, and the start and running pictures follow them. Safe mode keeps the timed animations.
  const SCRUB = !/[?&](safe|demo)\b/.test(location.search);
  let scrub = { step: null, p: 0 };

  const ORDER = ["start", "about", "usb", "connect", "review", "confirm", "running", "finish", "next", "undo", "undone"];
  const DOT = { usb: 0, connect: 1, review: 2, confirm: 3, running: 4, finish: 5 };
  const CABLE = new Set(["usb", "connect", "review", "confirm", "running", "undo"]);
  const SCREEN = { start: "run", usb: "settings", connect: "allow", review: "list", confirm: "list", finish: "clean", next: "clean", undo: "off", undone: "busy" };
  const CAPTION = {
    busy: "As it ships: about 100 apps and services.",
    pitch: "Disables around 100 unneeded apps and background services",
    home: "Then a quiet Home: Decaid, Decadent* and Settings",
    settings: "Developer options, then USB debugging.",
    allow: "Tap Allow on the tablet.",
    list: "Chosen apps switch off. Nothing is deleted.",
    run: "Switching off, one at a time.",
    clean: "After: three large icons on a quiet Home.",
    off: "Switched off, still installed.",
    restore: "Turning apps back on.",
    undone: "As it shipped.",
    halt: "Stopped partway.",
    idle: "Nothing changed on the tablet.",
  };


  // Warp the drawn screen (570 x 364 including its bezel) onto the glass in the photo.
  // Corners are the outer edge of the glass in the 2528 x 1684 photo: TL, TR, BR, BL.
  const photo = fig.querySelector(".photo");
  const art = fig.querySelector(".device-art");
  const GLASS = [[946, 49], [1639, 81], [1578, 513], [891, 450]];
  const PW = 2528, AW = 570, AH = 364;
  function homography(q) {
    // Unit square to quad (Heckbert), returned as a CSS matrix3d for a AW x AH box.
    const [[x0, y0], [x1, y1], [x2, y2], [x3, y3]] = q;
    const dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
    const dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
    const den = dx1 * dy2 - dx2 * dy1;
    const g = (dx3 * dy2 - dx2 * dy3) / den, h = (dx1 * dy3 - dx3 * dy1) / den;
    const a = x1 - x0 + g * x1, b = x3 - x0 + h * x3, d = y1 - y0 + g * y1, e = y3 - y0 + h * y3;
    const m = [a / AW, d / AW, 0, g / AW, b / AH, e / AH, 0, h / AH, 0, 0, 1, 0, x0, y0, 0, 1];
    return `matrix3d(${m.map((v) => +v.toFixed(9)).join(",")})`;
  }
  function warp() {
    const w = photo.offsetWidth;
    if (!w) return;
    const k = w / PW;
    art.style.transform = homography(GLASS.map(([x, y]) => [x * k, y * k]));
    fig.classList.add("warped");
  }
  if (photo && art) {
    if ("ResizeObserver" in window) new ResizeObserver(warp).observe(photo); else addEventListener("resize", warp);
    warp();
  }

  let last = null, before = null, rawLast = null;
  const visible = () => [...document.querySelectorAll("[data-step]")].find((s) => !s.hidden);

  function update() {
    const sec = visible();
    if (!sec) return;
    const raw = sec.dataset.step;
    if (raw !== rawLast) { if (rawLast) root.dataset.dir = ORDER.indexOf(raw) < ORDER.indexOf(rawLast) && rawLast !== "running" ? "back" : "forward"; rawLast = raw; }
    const step = raw === "about" ? "start" : raw; // the second start page keeps the start picture
    if (step !== last) { before = last; last = step; }
    let screen = SCREEN[step];
    if (step === "start" && atHome) screen = "clean";
    if (step === "running") screen = before === "undo" ? "restore" : "run";
    const part = document.getElementById("setup-part");
    const idle = step === "review" && part && part.hidden;
    if (idle) screen = "busy";
    const err = document.getElementById("run-error");
    const halted = step === "running" && err && !err.hidden;
    // The start picture always follows the scroll on the plain page; running only in the preview (app.js sends it).
    const sp = !SCRUB ? null : raw === "start" ? (scrub.step === "start" ? scrub.p : 0) : raw === "running" && scrub.step === "running" ? scrub.p : null;
    if (SCRUB && raw === "about") { atHome = true; screen = "clean"; }
    const rowsX = [...fig.querySelectorAll(".s-list .row.x")].sort((a, b) => parseFloat(a.style.getPropertyValue("--i")) - parseFloat(b.style.getPropertyValue("--i")));
    const fillBar = fig.querySelector(".onbar-fill");
    if (sp != null) {
      const split = step === "start" ? 0.6 : 1, q = Math.min(1, sp / split);
      if (step === "start") atHome = sp >= split;
      screen = step === "start" && atHome ? "clean" : "run";
      const k = Math.round(q * rowsX.length);
      rowsX.forEach((r, i) => r.toggleAttribute("data-on", i >= k));
      if (fillBar) fillBar.style.transform = `scaleX(${q})`;
      fig.setAttribute("data-scrub", "");
    } else if (fig.hasAttribute("data-scrub")) {
      fig.removeAttribute("data-scrub"); for (const r of rowsX) r.removeAttribute("data-on"); if (fillBar) fillBar.style.transform = "";
    }
    if (fig.dataset.screen !== screen) fig.dataset.screen = screen;
    fig.toggleAttribute("data-cable", CABLE.has(step));
    fig.toggleAttribute("data-halt", halted);
    const text = halted ? CAPTION.halt : idle ? CAPTION.idle : step === "undone" ? CAPTION.undone : step === "start" ? (atHome ? CAPTION.home : CAPTION.pitch) : CAPTION[screen];
    fig.dataset.view = step;
    if (capText && capText.textContent !== text) capText.textContent = text;
    for (const b of frames) b.setAttribute("aria-pressed", String((b.dataset.frame === "home") === atHome));
    fig.toggleAttribute("data-note", step === "start" && atHome);
    if (step in DOT && screen !== "restore") main.dataset.at = DOT[step]; else delete main.dataset.at;
  }

  // Fine print under the Home caption.
  if (cap) { const n = document.createElement("p"); n.className = "device-note"; n.textContent = "* Decadent is a Chrome link. It can be easily removed, or swapped for icons you prefer."; cap.after(n); }

  // Start step: the tablet first switches apps off, then shows the new Home. It moves on by itself
  // once the switch-off has played (pages short enough not to scroll), or sooner when the visitor scrolls.
  // A click on the tablet plays it again.
  let atHome = false, auto = null, seen = null;
  // Loops: switch-off (5.2 s), Home (8 s), again. With reduced motion it stops on Home.
  const still = matchMedia("(prefers-reduced-motion: reduce)");
  function rest() { clearTimeout(auto); if (SCRUB) return; if (!still.matches) auto = setTimeout(() => { if (last === "start") { atHome = false; update(); arm(); } }, 8000); }
  function arm() { clearTimeout(auto); if (SCRUB) return; auto = setTimeout(() => { if (last === "start" && !atHome) { atHome = true; update(); rest(); } }, 5200); }
  let picked = false, holding = false;
  function onScroll() { if (SCRUB) return; if (last === "start" && !atHome && !picked && scrollY > innerHeight * 0.15) { atHome = true; update(); rest(); } }
  addEventListener("scroll", onScroll, { passive: true });
  fig.addEventListener("click", () => { if (SCRUB || last !== "start") return; atHome = false; update(); arm(); });
  // The bars pick a frame. The loop waits while the pointer or keyboard focus is on them,
  // then carries on from the chosen frame at the usual pace.
  const resume = () => { if (last === "start") (atHome ? rest : arm)(); };
  for (const b of frames) b.addEventListener("click", (e) => {
    e.stopPropagation();
    if (last !== "start") return;
    if (SCRUB) { document.dispatchEvent(new CustomEvent("scrub-to", { detail: b.dataset.frame === "home" ? 0.6 : 0 })); return; }
    picked = true; atHome = b.dataset.frame === "home"; update();
    if (holding) clearTimeout(auto); else resume();
  });
  const nav = frames[0]?.parentElement;
  if (nav) {
    nav.addEventListener("pointerenter", () => { holding = true; clearTimeout(auto); });
    nav.addEventListener("pointerleave", () => { holding = false; resume(); });
    nav.addEventListener("focusin", (e) => { if (e.target.matches(":focus-visible")) { holding = true; clearTimeout(auto); } });
    nav.addEventListener("focusout", (e) => { if (!nav.contains(e.relatedTarget) && holding && !nav.matches(":hover")) { holding = false; resume(); } });
  }
  document.addEventListener("scrub", (e) => { scrub = e.detail || { step: null, p: 0 }; update(); });
  new MutationObserver(() => { update(); if (last === "start" && seen !== "start") { atHome = false; arm(); update(); } seen = last; }).observe(main, { subtree: true, attributes: true, attributeFilter: ["hidden"] });


  // A sticky button row gets its fade only while content runs on beneath it.
  const rows = [...document.querySelectorAll('[data-step="start"] > .row, [data-step="about"] > .row')];
  const stuck = () => { for (const r of rows) { const b = r.getBoundingClientRect(); r.toggleAttribute("data-stuck", b.height > 0 && getComputedStyle(r).position === "sticky" && b.bottom >= innerHeight - 1 && document.documentElement.scrollHeight - scrollY - innerHeight > 2); } };
  addEventListener("scroll", stuck, { passive: true }); addEventListener("resize", stuck);
  new MutationObserver(() => requestAnimationFrame(stuck)).observe(main, { subtree: true, attributes: true, attributeFilter: ["hidden", "open"] });
  update();
  if (last === "start") arm();
  requestAnimationFrame(stuck);
  seen = last;
})();


// Safe mode (?safe, or the older ?demo&tour). A Next / Back bar that walks every screen with the pretend tablet.
// Next presses the screen's own forward button, so each screen fills in as it would for real; nothing reaches a tablet.
if (/[?&]safe\b/.test(location.search) || (/[?&]tour/.test(location.search) && /[?&]demo/.test(location.search))) {
  const ORDER = ["start", "about", "usb", "connect", "review", "confirm", "running", "finish", "next", "undo", "undone"];
  const NAMES = { start: "Start", about: "Before you start", usb: "USB debugging", connect: "Connect", review: "Choose", confirm: "Decaid installation", running: "Working", finish: "Finish", next: "What to do next", undo: "Undo", undone: "Put back" };
  const FORWARD = { start: "#more", about: "#start", usb: "#usb-next", connect: "#connect", review: "#do-setup", confirm: "#confirm-go", finish: "#to-next", next: "#do-undo", undo: "#undo-go", undone: '[data-step="undone"] [data-back="start"]' };
  const bar = document.createElement("div");
  bar.className = "tour";
  bar.innerHTML = '<button type="button" data-go="back">‹ Back</button><span class="tour-at" aria-live="polite"></span><button type="button" data-go="next">Next ›</button>';
  document.body.append(bar);
  const at = bar.querySelector(".tour-at"), nextB = bar.querySelector('[data-go="next"]'), backB = bar.querySelector('[data-go="back"]');
  const now = () => ([...document.querySelectorAll("[data-step]")].find((s) => !s.hidden) || {}).dataset?.step;
  const paint = () => {
    const s = now(); if (!s) return;
    at.textContent = `Safe mode · ${ORDER.indexOf(s) + 1} of ${ORDER.length} · ${NAMES[s] || s}`;
    const finRunning = s === "finish" && document.getElementById("fin-run") && !document.getElementById("fin-run").hidden && document.getElementById("fin-after").hidden;
    const finYou = s === "finish" && document.getElementById("fin-you") && !document.getElementById("fin-you").hidden;
    nextB.disabled = s === "running" || finRunning;
    nextB.textContent = s === "running" || finRunning ? "Working…" : finYou ? "Finish for me ›" : s === "undone" ? "Start again ›" : "Next ›";
    backB.disabled = s === "start" || s === "running";
  };
  bar.addEventListener("click", (e) => {
    const go = e.target.closest("button")?.dataset.go; if (!go) return;
    if (go === "back") { history.back(); return; }
    const s = now();
    if (s === "finish") { // last steps: Finish for me first, then on to Undo once they are done
      const you = document.getElementById("fin-you"), after = document.getElementById("fin-after");
      const b = you && !you.hidden ? document.getElementById("fin-go") : after && !after.hidden ? document.querySelector(FORWARD.finish) : null;
      if (b) b.click(); return;
    }
    const b = document.querySelector(FORWARD[s]); if (b) b.click();
  });
  new MutationObserver(paint).observe(document.querySelector("main"), { subtree: true, attributes: true, attributeFilter: ["hidden", "data-state"] });
  paint();
}
