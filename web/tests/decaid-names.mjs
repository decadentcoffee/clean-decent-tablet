// node --test web/tests/decaid-names.mjs : every Decaid control this project names is one Decaid has (D-43).
// web/tests/decaid-ui.json is a copy of the Decadent repo's pwa/tests/unit/fixtures/decaid-ui.json, which
// scripts/decaid-labels.mjs there reads from Decaid's own source. Never write a Decaid control's name from memory.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (p) => readFileSync(new URL(p, import.meta.url), "utf8");
const ui = JSON.parse(read("./decaid-ui.json"));
const names = new Set(ui.facts.filter((f) => f.kind !== "fact").map((f) => f.name));
const labels = new Set(ui.facts.filter((f) => f.kind === "label").map((f) => f.name));

test("the written steps on the page name only Decaid's controls, from the Dashboard", () => {
  const html = read("../index.html");
  const list = html.slice(html.indexOf('<ol id="byhand-plugin">'), html.indexOf("</ol>", html.indexOf('<ol id="byhand-plugin">')));
  const bold = [...list.matchAll(/<b>([^<]+)<\/b>/g)].map((m) => m[1]);
  assert.ok(bold.length >= 8, "the steps mark Decaid's controls in bold");
  for (const b of bold) assert.ok(labels.has(b), `"${b}" is not a control in Decaid ${ui.decaid}`);
  assert.ok(list.indexOf("Dashboard") < list.indexOf("Plugins"), "Plugins is on the Dashboard, not in the coffee screen");
  const steps = [...list.matchAll(/<li>(.*?)<\/li>/g)].map((m) => m[1].replace(/<[^>]+>/g, ""));
  for (const step of steps) for (const sentence of step.split(/(?<=\.)\s+/)) {
    assert.ok(sentence.split(/\s+/).length <= 20, `more than 20 words: ${sentence}`);
    assert.ok(!/, then |\band tap\b|[→⋮]/.test(sentence), `two instructions or a symbol in one sentence: ${sentence}`);
  }
});

test("the setup script taps the controls Decaid has", () => {
  const sh = read("../../device/decent-setup.sh");
  const body = sh.slice(sh.indexOf("fin_plugin_do() {"), sh.indexOf("\n}\n", sh.indexOf("fin_plugin_do() {")));
  const loop = body.match(/for want in ((?:'[^']+' ?)+);/);
  assert.ok(loop, "the tap list of fin_plugin_do");
  const taps = [...loop[1].matchAll(/'([^']+)'/g)].map((m) => m[1]);
  assert.deepEqual(taps, ["Plugin actions", "Install plugin", "GitHub Release"]);
  for (const t of [...taps, "Plugins", "Install", "Load"]) assert.ok(names.has(t), `"${t}" is not in Decaid ${ui.decaid}`);
  assert.match(body, /ui_find content-desc 'Plugins\[\^"\]\*'/);
  assert.match(body, /ui_find content-desc 'Install'/);
});
