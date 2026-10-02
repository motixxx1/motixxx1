import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createFileStore } from '../src/store.js';
import { Marketplace } from '../src/marketplace.js';
import { Partners } from '../src/partners.js';

test('file store persists and reloads marketplace + partners', async () => {
  const file = join(mkdtempSync(join(tmpdir(), 'pm-')), 'sub', 'state.json');
  const market = new Marketplace();
  const partners = new Partners();
  const store = createFileStore(file, { market, partners });
  const pro = market.registerPro({ phone: '1', name: 'שרה' });
  const { id } = partners.create({ name: 'ספק' });
  store.save();
  await store.flush();

  const market2 = new Marketplace();
  const partners2 = new Partners();
  createFileStore(file, { market: market2, partners: partners2 });
  assert.equal(market2.getPro(pro.id).name, 'שרה');
  assert.equal(partners2.partners.get(id).name, 'ספק');
});
