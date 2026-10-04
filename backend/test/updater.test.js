import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createUpdater, RESTART_CODE } from '../src/updater.js';

const b64 = (s) => Buffer.from(s).toString('base64');
function setup(bundles) {
  const root = mkdtempSync(join(tmpdir(), 'pm-upd-'));
  mkdirSync(join(root, 'public')); mkdirSync(join(root, 'src'));
  writeFileSync(join(root, 'build.json'), JSON.stringify({ build: '1', apk: 5 }));
  writeFileSync(join(root, 'public/index.html'), 'old');
  writeFileSync(join(root, 'src/app.js'), 'code');
  const exits = [];
  let n = 0;
  const u = createUpdater({ root, url: 'x', log: () => {}, exit: (c) => exits.push(c),
    fetchImpl: async () => ({ ok: true, json: async () => bundles[Math.min(n++, bundles.length - 1)] }) });
  return { root, u, exits };
}

test('updater: page-only update applies live, code update restarts, bad paths refused', async () => {
  const { root, u, exits } = setup([
    { build: '2', apk: 5, files: { 'public/index.html': b64('new'), 'src/app.js': b64('code') } },
    { build: '2', files: {} },
    { build: '3', apk: 6, files: { 'src/app.js': b64('code v3') } },
    { build: '4', files: { '../evil.js': b64('x') } },
  ]);
  assert.deepEqual(await u.check(), { updated: true, restart: false });
  assert.equal(readFileSync(join(root, 'public/index.html'), 'utf8'), 'new');
  assert.equal(u.info().build, '2');
  assert.deepEqual(exits, []);
  assert.deepEqual(await u.check(), { updated: false });
  await u.check();
  assert.deepEqual(exits, [RESTART_CODE]);
  assert.deepEqual(u.info(), { build: '3', apk: 6 });
  assert.equal(JSON.parse(readFileSync(join(root, 'build.json'), 'utf8')).build, '3');
  const bad = await u.check();
  assert.match(bad.error, /refusing/);
  assert.equal(existsSync(join(root, '..', 'evil.js')), false);
});
