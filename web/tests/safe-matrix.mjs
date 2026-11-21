#!/usr/bin/env node
// Every way through the choose screen, in safe mode: the ticks shown, and the finish steps the page sends to the
// (pretend) tablet when Finish for me runs. Needs the dist server on 8498 and a CDP helper:
//   CDP_LIB=/path/to/cdp.mjs node web/tests/safe-matrix.mjs
const { Browser, sleep } = await import(process.env.CDP_LIB);
const base = process.env.BASE || "http://127.0.0.1:8498/";
const CASES = [
  // [name, query, ticks shown on the choose screen, finish steps in order, or null when the page must refuse]
  ["clean-tablet way in, defaults", "?safe", "decadent,cleanup,home", ["icons", "launcher", "updates", "place no-decadent", "more"]],
  ["sign-up way in, defaults", "?safe&for=decadent", "cleanup,home", ["decaid open", "plugin", "icons", "launcher", "updates", "decadent", "place", "more"]],
  ["Decadent only, Samsung's Home", "?safe&on=decadent", "decadent,cleanup,home", ["decaid open", "plugin", "updates", "decadent", "place"]],
  ["Clean up only", "?safe&on=cleanup", "decadent,cleanup,home", ["updates"]],
  ["Home only, with Decadent", "?safe&on=home,decadent", "decadent,cleanup,home", ["decaid open", "plugin", "icons", "launcher", "updates", "decadent", "place", "more"]],
  ["no Decaid: Decaid and Decadent", "?safe=nodecaid&on=decaid,decadent&decaid=add", "decaid,decadent,cleanup,home", ["decaid open", "plugin", "updates", "decadent", "place"]],
  ["no Decaid: Decadent without Decaid is refused", "?safe=nodecaid&on=decadent", "decaid,decadent,cleanup,home", null],
  ["nothing ticked is refused", "?safe&on=", "decadent,cleanup,home", null],
  ["set-up tablet: add Decadent later", "?safe=done&on=decadent", "decadent,undo-apps,undo-home", ["decaid open", "plugin", "updates", "decadent", "place"]],
  ["sign-up way in, app already there: the plugin check is ticked", "?safe=done&decadent=installed&for=decadent", "undo-apps,undo-home", ["decaid open", "plugin", "place"]],
  ["sign-up way in, no Decaid, Home and Clean up unticked", "?safe=nodecaid&for=decadent&on=", "cleanup,home", ["decaid open", "plugin", "updates", "decadent", "place"]],
  ["sign-up way in, Clean up unticked", "?safe&for=decadent&on=home", "cleanup,home", ["decaid open", "plugin", "icons", "launcher", "updates", "decadent", "place", "more"]],
  ["sign-up way in, app there but no Decaid: Decaid, then the plugin", "?safe=nodecaid&decadent=installed&for=decadent&on=", "cleanup,home", ["decaid open", "plugin", "place if-missing"]],
  ["Decadent already there: check the plugin", "?safe=done&decadent=installed&on=plugin", "plugin,undo-apps,undo-home", ["decaid open", "plugin"]],
  ["only the plugin (D-43): nothing else is ticked", "?safe&do=plugin", "plugin,cleanup,home", ["decaid open", "plugin"]],
  ["only the plugin, app already there", "?safe=done&decadent=installed&do=plugin", "plugin,undo-apps,undo-home", ["decaid open", "plugin"]],
  ["only the plugin, from the sign-up way in", "?safe&for=decadent&do=plugin", "cleanup,home", ["decaid open", "plugin"]],
];
const browser = await Browser.launch();
let bad = 0;
try {
  for (const [name, q, wantRows, wantSteps] of CASES) {
    const page = await browser.newPage({ width: 1280, height: 820 });
    await page.goto(base + q + "&to=finished&net=all", { settleMs: 500 });
    const end = Date.now() + 60000; let state = "";
    for (;;) {
      state = await page.eval(`(() => { const vis = [...document.querySelectorAll('[data-step]')].filter((s) => !s.hidden).map((s) => s.dataset.step)[0];
        return vis === "finish" && !document.getElementById("fin-after").hidden ? "finished" : vis === "review" && !document.getElementById("opt-none").hidden ? "refused" : ""; })()`);
      if (state || Date.now() > end) break; await sleep(200);
    }
    const rows = await page.eval(`["decaid","decadent","plugin","cleanup","home","undo-apps","undo-home"].filter((k) => !document.getElementById("row-" + k).hidden).join(",")`);
    const steps = await page.eval(`(globalThis.safeModeLog || []).filter((c) => c.startsWith("setup finish ") && !/finish status/.test(c)).map((c) => c.slice(13)).filter((c) => c !== "decaid")`);
    const shown = await page.eval(`[...document.getElementById("fin-steps").children].filter((l) => !l.hidden).map((l) => l.dataset.k).join(",")`);
    const okRows = rows === wantRows;
    const okSteps = wantSteps === null ? state === "refused" && steps.length === 0 : state === "finished" && JSON.stringify(steps) === JSON.stringify(wantSteps);
    // the visible list names the same steps the tablet got (restart and open are the page's own)
    const listed = shown.split(",").filter((k) => k && k !== "restart" && k !== "open").join(",");
    const sent = (wantSteps || []).filter((s) => s !== "decaid open").map((s) => s.split(" ")[0]).join(",");
    const okList = wantSteps === null || listed === sent;
    const ok = okRows && okSteps && okList && page.consoleErrors.length === 0;
    if (!ok) bad++;
    console.log(`${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : `\n     rows ${rows} (want ${wantRows})\n     state ${state || "stuck"} steps ${JSON.stringify(steps)}\n     want ${JSON.stringify(wantSteps)}\n     listed ${listed}\n     errors ${page.consoleErrors.join(" | ")}`}`);
    await page.close();
  }
} finally { await browser.close(); }
console.log(bad ? `${bad} FAILED` : "ALL SAFE-MODE CASES PASSED");
process.exit(bad ? 1 : 0);
