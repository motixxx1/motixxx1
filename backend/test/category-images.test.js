import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createApp } from '../src/app.js';
import { Auth } from '../src/auth.js';
import { CATEGORIES } from '../src/categories.js';

test('every top-level category has a served illustration', async () => {
  const srv = createServer(createApp({ auth: new Auth({ secret: 's'.repeat(32), sendSms: async () => {} }), dev: true })).listen(0);
  try {
    const base = `http://localhost:${srv.address().port}`;
    for (const c of CATEGORIES) {
      const r = await fetch(`${base}/img/cat/${c.id}.svg`);
      assert.equal(r.status, 200, c.id);
      assert.equal(r.headers.get('content-type'), 'image/svg+xml');
    }
    assert.equal((await fetch(`${base}/img/cat/nope.svg`)).status, 404);
  } finally { srv.close(); }
});
