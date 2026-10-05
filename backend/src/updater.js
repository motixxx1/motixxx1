import { existsSync, readFileSync } from 'node:fs';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, join, normalize, sep } from 'node:path';

// Self-update for the downloadable server package. Every release publishes
// promarket-update.json = { build, apk, files: { "src/app.js": "<base64>", "public/...": ... } }.
// The server checks it now and then; when the build changed it writes the new files.
// Web pages take effect at once (they are read from disk per request) and open apps reload
// themselves; code changes need a restart, so the process exits with RESTART_CODE and the
// start script (start.sh / start.bat / systemd) starts it again. Phones never need a new APK
// for this - only when the native shell itself changes (`apk` goes up).
export const RESTART_CODE = 42;
const ALLOWED = /^(src|public)\/[\w./-]+$|^package\.json$/;

export function readBuild(root) {
  try { return JSON.parse(readFileSync(join(root, 'build.json'), 'utf8')); } catch { return { build: 'dev', apk: null }; }
}

export function createUpdater({ root, url, source = null, intervalMs = 30 * 60_000, log = console.log, beforeRestart = async () => {},
  exit = (code) => process.exit(code), fetchImpl = fetch } = {}) {
  let info = readBuild(root);
  let timer = null;
  let busy = false;

  async function check() {
    if (busy) return { updated: false };
    busy = true;
    try {
      const r = source && !url ? await source.fetchAsset('promarket-update.json')
        : await fetchImpl(url, { headers: { 'user-agent': 'ProMarket-updater' }, redirect: 'follow' });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const next = await r.json();
      if (!next?.build || next.build === info.build) return { updated: false };
      let codeChanged = false;
      for (const [path, b64] of Object.entries(next.files ?? {})) {
        const clean = normalize(path).split(sep).join('/');
        if (!ALLOWED.test(clean) || clean.includes('..')) throw new Error(`refusing path ${path}`);
        const target = join(root, clean);
        const data = Buffer.from(b64, 'base64');
        const old = existsSync(target) ? await readFile(target) : null;
        if (old && old.equals(data)) continue;
        await mkdir(dirname(target), { recursive: true });
        await writeFile(target + '.new', data);
        await rename(target + '.new', target);
        if (!clean.startsWith('public/')) codeChanged = true;
      }
      info = { build: next.build, apk: next.apk ?? info.apk };
      await writeFile(join(root, 'build.json'), JSON.stringify(info));
      log(`[update] now on build ${info.build}${codeChanged ? ' - restarting' : ''}`);
      if (codeChanged) { await beforeRestart(); exit(RESTART_CODE); }
      return { updated: true, restart: codeChanged };
    } catch (e) {
      log(`[update] check failed: ${e.message}`);
      return { updated: false, error: e.message };
    } finally { busy = false; }
  }

  return {
    info: () => info,
    check,
    start() { setTimeout(check, 10_000); timer = setInterval(check, intervalMs); timer.unref?.(); return this; },
    stop() { clearInterval(timer); },
  };
}
