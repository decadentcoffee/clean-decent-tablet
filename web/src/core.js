// Everything that talks to the tablet. No page code here, so tests/usb-readonly.mjs can run it from Node against a real tablet.
import { Adb, AdbDaemonTransport } from "@yume-chan/adb";
import { TextDecoderStream } from "@yume-chan/stream-extra";

export const REMOTE = "/data/local/tmp/decent-setup";

export async function connectTablet(device, credentialStore) {
  const connection = await device.connect();
  const transport = await AdbDaemonTransport.authenticate({ serial: device.serial, connection, credentialStore });
  return new Tablet(new Adb(transport));
}

export class Tablet {
  constructor(adb) { this.adb = adb; }

  // Run a command on the tablet. Calls onLine for each output line; resolves with all lines.
  async run(command, onLine = () => {}) {
    const proc = await this.adb.subprocess.noneProtocol.spawn(command);
    const reader = proc.output.pipeThrough(new TextDecoderStream()).getReader();
    const lines = []; let rest = "";
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      rest += value;
      const parts = rest.split(/\r?\n/); rest = parts.pop();
      for (const l of parts) { lines.push(l); onLine(l); }
    }
    if (rest) { lines.push(rest); onLine(rest); }
    return lines;
  }

  async push(path, bytes) {
    const sync = await this.adb.sync();
    try {
      await sync.write({
        filename: path,
        file: new ReadableStream({ start(c) { c.enqueue(bytes); c.close(); } }),
        permission: 0o644,
      });
    } finally { await sync.dispose(); }
  }

  // Put the core script and its lists on the tablet.
  async prepare(files) {
    await this.run(`mkdir -p ${REMOTE}`);
    const enc = new TextEncoder();
    for (const [name, text] of Object.entries(files)) await this.push(`${REMOTE}/${name}`, enc.encode(text));
  }

  setup(args, onLine) { return this.run(`sh ${REMOTE}/decent-setup.sh ${args}`, onLine); }

  close() { return this.adb.close(); }
}

export async function sha256(bytes) {
  const d = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// The newest release of an APK whose URL is GitHub's "latest" download: { version, sha } from GitHub's API, which
// browsers may read (the download itself they may not). Throws when GitHub does not answer or lists no checksum.
export async function latestApk(url, fetchFn = fetch) {
  const m = /^https:\/\/github\.com\/([^/]+\/[^/]+)\/releases\/latest\/download\/([^/]+)$/.exec(url);
  if (!m) throw new Error("not a latest-release address");
  const res = await fetchFn(`https://api.github.com/repos/${m[1]}/releases/latest`, { headers: { Accept: "application/vnd.github+json" } });
  if (!res.ok) throw new Error(`GitHub answered ${res.status}`);
  const rel = await res.json();
  const asset = (rel.assets || []).find((a) => a.name === m[2]);
  const sha = /^sha256:([0-9a-f]{64})$/.exec((asset && asset.digest) || "");
  if (!sha) throw new Error("no checksum listed");
  return { version: String(rel.tag_name || "").replace(/^v/, ""), sha: sha[1] };
}

// STATUS lines into { home, browser, ..., apps: { pkg: state } }.
export function parseStatus(lines) {
  const s = { apps: {} };
  for (const l of lines) {
    let m = l.match(/^STATUS app (\S+) (\S+)$/);
    if (m) { s.apps[m[1]] = m[2]; continue; }
    m = l.match(/^STATUS (\w+)=(.*)$/);
    if (m) s[m[1]] = m[2];
  }
  return s;
}

// PLAN/DONE lines from the core script, as progress: "DONE 12/100 com.x".
export function parseProgress(line) {
  const m = line.match(/^(DONE|SKIP|REFUSED|PLAN) (\d+)\/(\d+) (\S+)/);
  return m ? { kind: m[1], n: +m[2], total: +m[3], pkg: m[4] } : null;
}
