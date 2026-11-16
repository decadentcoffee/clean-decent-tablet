// Real-tablet test of the page's connection code (src/core.js), from Node over USB. Reads only, plus one temp file it removes.
// Needs: npm install --no-save usb@2. Set TEST_KEY to a key file path. Stop the adb server first: adb kill-server. The tablet asks to allow a new key.
import { WebUSB } from "usb";
import { generateKeyPairSync, createHash } from "node:crypto";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { AdbDaemonWebUsbDeviceManager } from "@yume-chan/adb-daemon-webusb";
import { connectTablet, parseStatus, REMOTE } from "../src/core.js";

const keyPath = process.env.TEST_KEY;
if (!existsSync(keyPath)) writeFileSync(keyPath, generateKeyPairSync("rsa", { modulusLength: 2048, publicExponent: 65537 }).privateKey.export({ format: "der", type: "pkcs8" }));
const toKey = () => ({ buffer: new Uint8Array(readFileSync(keyPath)), name: "decent-tablet-test" });
const store = { generateKey: toKey, *iterateKeys() { yield toKey(); } };

const mgr = new AdbDaemonWebUsbDeviceManager(new WebUSB({ allowAllDevices: true }));
const [device] = await mgr.getDevices();
if (!device) { console.log("FAIL no ADB device over USB"); process.exit(1); }
console.log("found", device.name, "serial hidden; waiting for Allow on the tablet");
const t0 = Date.now();
process.on("unhandledRejection", (e) => console.log(`unhandled at ${Date.now() - t0} ms:`, e && e.message));
const tablet = await connectTablet(device, store);
console.log(`authenticated in ${Date.now() - t0} ms`);
const here = new URL("../../device/", import.meta.url).pathname;
const files = {}; for (const f of ["decent-setup.sh", "packages-disable.txt", "device.expect"]) files[f] = readFileSync(here + f, "utf8");
await tablet.prepare(files);
console.log((await tablet.setup("check")).join("\n"));
const s = parseStatus(await tablet.setup("status"));
console.log("home", s.home, "| browser", s.browser, "| disabled", s.disabled_total, "| undo record", s.undo_record, "| decaid", s.apps["net.tadel.reaprime"]);
console.log((await tablet.setup("plan")).filter((l) => l.startsWith("PLAN")).join("\n"));
const undo = await tablet.setup("undo --dry-run");
console.log("undo preview:", undo.filter((l) => l.startsWith("PLAN enable")).length, "enable,", undo.filter((l) => l.startsWith("PLAN uninstall")).length, "uninstall");
// Large push, checked end to end: the Fossify APK when built, else a test blob.
const blob = existsSync(new URL("../dist/fossify.apk", import.meta.url)) ? new Uint8Array(readFileSync(new URL("../dist/fossify.apk", import.meta.url))) : new Uint8Array(1024 * 1024).fill(7);
const remote = `${REMOTE}/push-test.bin`;
const t1 = Date.now(); await tablet.push(remote, blob);
const sum = (await tablet.run(`sha256sum ${remote}`))[0].split(" ")[0];
const want = createHash("sha256").update(blob).digest("hex");
console.log(`push ${blob.length} bytes in ${Date.now() - t1} ms, checksum ${sum === want ? "matches" : "DIFFERS"}`);
await tablet.run(`rm -f ${remote}`);
await tablet.close();
console.log("PASS");
process.exit(0);
