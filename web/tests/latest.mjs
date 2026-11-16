// node --test web/tests/latest.mjs : the page's read of Decaid's latest release.
import test from "node:test";
import assert from "node:assert/strict";
import { latestApk } from "../src/core.js";

const URL_OK = "https://github.com/decentespresso/decaid/releases/latest/download/decaid-android-latest.apk";
const sha = "9".repeat(64);
const answer = (body, ok = true, status = 200) => async (url) => { answer.asked = url; return { ok, status, json: async () => body }; };

test("reads the version and checksum of the named file", async () => {
  const got = await latestApk(URL_OK, answer({ tag_name: "v0.9.2", assets: [{ name: "other.apk", digest: "sha256:" + "1".repeat(64) }, { name: "decaid-android-latest.apk", digest: "sha256:" + sha }] }));
  assert.deepEqual(got, { version: "0.9.2", sha });
  assert.equal(answer.asked, "https://api.github.com/repos/decentespresso/decaid/releases/latest");
});
test("fails closed: no answer, no file, no checksum, another address", async () => {
  await assert.rejects(latestApk(URL_OK, answer({}, false, 403)), /403/);
  await assert.rejects(latestApk(URL_OK, answer({ tag_name: "v1", assets: [] })), /no checksum/);
  await assert.rejects(latestApk(URL_OK, answer({ assets: [{ name: "decaid-android-latest.apk", digest: "md5:abc" }] })), /no checksum/);
  await assert.rejects(latestApk("https://example.test/decaid.apk", answer({})), /not a latest-release/);
});
