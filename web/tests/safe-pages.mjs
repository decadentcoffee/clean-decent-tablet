#!/usr/bin/env node
// Single screens the safe-mode matrix does not reach: Decadent's start picture, the 20 s Allow hint, the step said in
// words, the share post's words, the written steps after a failed restart, the waits at Decaid and the restart, and a
// browser without WebUSB. Needs the dist server and a CDP helper:
//   BASE=http://127.0.0.1:8498/ CDP_LIB=/path/to/cdp.mjs node web/tests/safe-pages.mjs
const { Browser, sleep } = await import(process.env.CDP_LIB);
const base = process.env.BASE || "http://127.0.0.1:8498/";
const browser = await Browser.launch();
let bad = 0;
const check = (name, ok, got) => { if (!ok) bad++; console.log(`${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : `\n     got ${JSON.stringify(got)}`}`); };
const open = async (q, { width = 1280, height = 820, init } = {}) => {
  const page = await browser.newPage({ width, height });
  if (init) await page.send("Page.addScriptToEvaluateOnNewDocument", { source: init });
  await page.goto(base + q, { settleMs: 600 });
  return page;
};
const until = async (page, expr, ms = 60000) => { const end = Date.now() + ms; while (!(await page.eval(expr))) { if (Date.now() > end) return false; await sleep(100); } return true; };
const visible = `[...document.querySelectorAll('[data-step]')].find((s) => !s.hidden).dataset.step`;
const share = `document.getElementById("share-text").value`;
try {
  // Decadent's way in: the Home picture and its caption, no frame bars, and it stays there.
  for (const q of ["?safe&for=decadent", "?for=decadent"]) {
    const p = await open(q);
    await sleep(6000); // past the 5.2 s the clean-tablet picture takes to switch over
    const got = await p.eval(`(() => { const f = document.querySelector(".device"); return { screen: f.dataset.screen, cap: f.querySelector(".cap-text").textContent, frames: f.querySelector(".frames").hidden, note: f.hasAttribute("data-note") }; })()`);
    check(`Decadent start picture (${q})`, got.screen === "clean" && got.cap === "Decadent, Decaid and Settings on one quiet Home screen, one tap each." && got.frames && got.note && p.consoleErrors.length === 0, got);
    await p.close();
  }
  { const p = await open("?safe"); const cap = await p.eval(`document.querySelector(".cap-text").textContent`); check("clean-tablet start picture unchanged", cap === "Disables around 100 unneeded apps and background services", cap); await p.close(); }

  // The step in words, and nothing off the dotted steps.
  { const p = await open("?safe&to=connect"); await sleep(300); const a = await p.eval(`document.getElementById("step-say").textContent`);
    await p.eval(`document.querySelector('[data-step="connect"] [data-back]').click(); document.querySelector('[data-step="usb"] [data-back]').click()`); await sleep(300);
    const b = await p.eval(`document.getElementById("step-say").textContent`);
    check("step said in words", a === "Step 2 of 6: Connect" && b === "", [a, b]); await p.close(); }

  // A missed Allow: nothing for 20 s, then what to try.
  { const p = await open("?safe&hold=allow&to=connect"); await p.eval(`document.getElementById("connect").click()`);
    await sleep(3000); const early = await p.eval(`[document.getElementById("connect-hint").hidden, document.getElementById("connect-slow").textContent]`);
    await sleep(18500); const late = await p.eval(`document.getElementById("connect-slow").textContent`);
    check("Allow hint after 20 s", early[0] === false && early[1] === "" && late.startsWith("Still waiting. Look at the tablet: if no message shows, unlock it"), { early, late }); await p.close(); }

  // The share post says what this visit did, with the apps really switched off (98: two refused).
  const posts = [
    ["both", "?safe&to=finished", (t) => t.startsWith("I cleaned up the tablet on my Decent espresso machine: 98 unneeded apps and background services switched off, and a quiet Home screen")],
    ["clean-up only", "?safe&on=cleanup&to=finished", (t) => t.startsWith("I cleaned up the tablet on my Decent espresso machine: 98 unneeded apps and background services switched off. Free")],
    ["Home only", "?safe&on=home&to=finished", (t) => t.startsWith("I gave the tablet on my Decent espresso machine a quiet Home screen")],
    ["neither", "?safe=done&decadent=installed&on=plugin&to=finished", (t) => t.startsWith("I set up the tablet on my Decent espresso machine with this page.")],
  ];
  for (const [name, q, ok] of posts) {
    const p = await open(q + "&net=all"); const done = await until(p, `!document.getElementById("fin-after").hidden`);
    const t = await p.eval(share); check(`share post: ${name}`, done && ok(t) && !/\b0 unneeded/.test(t), t); await p.close();
  }

  // A restart that fails: the written steps already name this visit's icons, and the step only points to them.
  { const p = await open("?safe&to=finish&restart=fail&net=all"); await until(p, `${visible} === "finish" && !document.getElementById("fin-you").hidden`);
    await p.eval(`document.getElementById("fin-go").click()`); const ok = await until(p, `!document.getElementById("fin-error").hidden`, 20000);
    const got = await p.eval(`(() => { const li = document.querySelector('#fin-steps [data-k="restart"]'); return { list: [...document.getElementById("fin-byhand-list").children].map((l) => l.textContent), why: li.querySelector(".fin-why").textContent, inline: getComputedStyle(li.querySelector(".by-hand")).display }; })()`);
    const place = got.list.find((t) => t.startsWith("On Home, swipe up")) || "";
    check("written steps after a failed restart", ok && /Decaid and Settings/.test(place) && !/Decadent/.test(place) && got.list.length === 7 && got.why === "Do it by hand: see below." && got.inline === "none", got); await p.close(); }

  // The restart says it is expected and how long it has been.
  { const p = await open("?safe&to=finish&net=all"); await until(p, `${visible} === "finish" && !document.getElementById("fin-you").hidden`);
    await p.eval(`document.getElementById("fin-go").click()`);
    const seen = await until(p, `!document.getElementById("restart-wait").hidden && /usually in under 3 minutes/.test(document.getElementById("restart-wait").textContent) && /^Waited \\d+ s\\.$/.test(document.getElementById("restart-waited").textContent)`, 5000);
    await until(p, `!document.getElementById("fin-after").hidden`);
    const gone = await p.eval(`document.getElementById("restart-wait").hidden`);
    check("restart wait line", seen && gone, { seen, gone }); await p.close(); }

  // Decaid's first questions: how long the page waits, counted.
  { const p = await open("?safe=nodecaid&on=decaid,decadent&decaid=add&to=finished&net=all");
    const asked = await until(p, `!document.getElementById("decaid-ask").hidden`);
    const during = await p.eval(`[document.getElementById("decaid-wait").textContent, document.getElementById("fin-keep").textContent, document.getElementById("decaid-ask").textContent]`);
    await until(p, `!document.getElementById("fin-after").hidden`);
    const after = await p.eval(`document.getElementById("decaid-wait").textContent`);
    check("Decaid wait counted", asked && during[0] === "Waiting 1 of 15 minutes." && /waits up to 15 minutes, then leaves this step to you/.test(during[1]) && /waits up to 15 minutes/.test(during[2]) && after === "", { during, after }); await p.close(); }

  // No WebUSB (any browser but Chrome or Edge): the first screen says so, Get started is off, the preview stays,
  // and the preview's Get started leads back to that first screen.
  { const p = await open("", { init: "delete Navigator.prototype.usb" });
    const got = await p.eval(`[document.getElementById("unsupported-c").hidden, document.getElementById("more").disabled, document.getElementById("preview-start").disabled]`);
    await p.eval(`document.getElementById("preview-start").click()`); await sleep(800);
    for (let i = 0; i < 30 && (await p.eval(visible)) !== "review"; i++) { await p.wheel(700, { step: 140, pauseMs: 30 }); await sleep(450); }
    const inPreview = await p.eval(visible);
    await p.eval(`document.getElementById("preview-exit").click()`); await sleep(400);
    const after = await p.eval(visible);
    check("no WebUSB: start screen and preview exit", got[0] === false && got[1] === true && got[2] === false && inPreview === "review" && after === "start" && p.consoleErrors.length === 0, { got, inPreview, after, errors: p.consoleErrors }); await p.close(); }
} finally { await browser.close(); }
console.log(bad ? `${bad} FAILED` : "ALL SAFE-PAGE CHECKS PASSED");
process.exit(bad ? 1 : 0);
