import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createApp } from '../src/app.js';

test('HTTP flow: register, topup, post job, claim', async () => {
  const srv = createServer(createApp()).listen(0);
  const base = `http://localhost:${srv.address().port}`;
  const call = (path, body, user) => fetch(base + path, { method: body ? 'POST' : 'GET',
    headers: user ? { 'x-user-id': user } : {}, body: body && JSON.stringify(body) }).then(async (r) => ({ s: r.status, b: await r.json() }));
  try {
    const loc = { lat: 32.08, lng: 34.78 };
    const pro = (await call('/api/pros', { phone: '1', name: 'P', categories: ['locksmith'], location: loc })).b;
    await fetch(`${base}/api/pros/${pro.id}/availability`, { method: 'PUT', body: '{"available":true}' });
    await call(`/api/pros/${pro.id}/wallet/topup`, { amount: 50 });
    const c = (await call('/api/clients', { phone: '2', name: 'C' })).b;
    const job = (await call('/api/jobs', { clientId: c.id, categoryId: 'locksmith.door', description: 'נעול בחוץ', location: loc, address: 'א', phone: '2' })).b;
    assert.equal(job.phone, undefined);
    // locksmith needs criminal-record approval
    assert.equal((await call(`/api/jobs/${job.id}/claim`, {}, pro.id)).s, 400);
    const doc = (await call(`/api/pros/${pro.id}/documents`, { type: 'criminal_record', url: 'x' })).b;
    await call(`/api/admin/pros/${pro.id}/documents/${doc.id}/approve`, {});
    const claimed = await call(`/api/jobs/${job.id}/claim`, {}, pro.id);
    assert.equal(claimed.s, 200);
    assert.equal(claimed.b.phone, '2');
    assert.equal((await call('/api/nope')).s, 404);
  } finally { srv.close(); }
});
