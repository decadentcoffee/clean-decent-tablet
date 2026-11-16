#!/usr/bin/env node
// The README's twelve screens, each 1280 × 820 of the viewport, from the local dist server in safe mode.
//   node web/readme-shots.mjs            (after node web/build.mjs; the dist server on 8498 serves it)
// Writes docs/img/web-<name>.png. Needs a headless-Chrome (CDP) helper module that exports { Browser, sleep }:
//   CDP_LIB=/path/to/cdp.mjs node web/readme-shots.mjs
if (!process.env.CDP_LIB) { console.error("Set CDP_LIB to a CDP helper module that exports Browser and sleep."); process.exit(2); }
const { Browser, sleep } = await import(process.env.CDP_LIB);
const base = process.env.BASE || "http://127.0.0.1:8498/";
const out = new URL("../docs/img/", import.meta.url).pathname;
const click = (id) => `document.getElementById(${JSON.stringify(id)}).click()`;
const untick = (names) => `[...document.querySelectorAll('#pick label.app')].filter(l => ${JSON.stringify(names)}.includes(l.querySelector('b').textContent)).forEach(l => l.querySelector('input').click())`;
const settled = (step) => `!document.querySelector('[data-step="${step}"]').hidden`;
const flow = [
  ["start", "?safe", []],
  ["about", "?safe", [click("more")]],
  ["usb", "?safe&to=usb", []],
  ["connect", "?safe&to=connect", []],
  ["review", "?safe&to=review", []],
  ["choose-apps", "?safe&to=review", ["document.getElementById('pick').open = true", untick(["Gmail", "Google Meet"]), "document.getElementById('pick').scrollIntoView({block: 'start'}); scrollBy(0, -110)"]],
  ["confirm", "?safe&to=confirm", []],
  ["running", "?safe&to=running", ["@wait:2500", "const d = document.querySelector('[data-step=running] details'); d.open = true; d.querySelector('pre').scrollTop = 1e6"]],
  ["finish", "?safe&to=finish", []],
  ["next", "?safe&to=finished", ["@until:fin-after", click("to-next")]],
  ["undo", "?safe=done&to=undo", []],
  ["undone", "?safe=done&to=undone", []],
];
const browser = await Browser.launch();
const errors = [];
try {
  for (const [name, q, steps] of flow) {
    const page = await browser.newPage({ width: 1280, height: 820 });
    await page.goto(base + q, { settleMs: 800 });
    const until = async (expr, ms = 20000) => { const end = Date.now() + ms; while (!(await page.eval(expr))) { if (Date.now() > end) throw new Error(`${name}: stuck waiting for ${expr}`); await sleep(150); } };
    const target = q.match(/to=(\w+)/)?.[1];
    if (target && target !== "finished") await until(settled(target));
    for (const s of steps) {
      if (s.startsWith("@wait:")) { await sleep(+s.slice(6)); continue; }
      if (s.startsWith("@until:")) { await until(`!document.getElementById(${JSON.stringify(s.slice(7))}).hidden`, 60000); continue; }
      await page.eval(s); await sleep(700);
    }
    await sleep(600);
    await page.screenshot({ path: `${out}web-${name}.png`, format: "png" });
    const vis = await page.eval(`[...document.querySelectorAll('[data-step]')].filter(s=>!s.hidden).map(s=>s.dataset.step).join(',')`);
    console.log(`web-${name}: visible=${vis}`);
    for (const e of page.consoleErrors) errors.push(`${name}: ${e}`);
    await page.close();
  }
} finally { await browser.close(); }
if (errors.length) console.log("errors:\n" + errors.join("\n"));
