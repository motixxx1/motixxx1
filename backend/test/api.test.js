import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createApp } from '../src/app.js';

test('HTTP flow: request -> offer -> accept -> work -> confirm', async () => {
  const srv = createServer(createApp()).listen(0);
  const base = `http://localhost:${srv.address().port}`;
  const call = (path, body, user, method = body ? 'POST' : 'GET') => fetch(base + path, { method,
    headers: user ? { 'x-user-id': user } : {}, body: body && JSON.stringify(body) })
    .then(async (r) => ({ s: r.status, b: await r.json() }));
  try {
    const loc = { lat: 32.08, lng: 34.78 };
    const pro = (await call('/api/pros', { phone: '1', name: 'טכנאי', categories: ['computers'], location: loc })).b;
    await call(`/api/pros/${pro.id}/availability`, { available: true }, null, 'PUT');
    await call(`/api/pros/${pro.id}/wallet/topup`, { amount: 50 });
    const c = (await call('/api/clients', { phone: '2', name: 'C' })).b;
    const job = (await call('/api/jobs', { categoryId: 'computers.network', mode: 'phone',
      description: 'הראוטר לא עובד' }, c.id)).b;
    assert.equal(job.phone, undefined);
    assert.equal((await call(`/api/pros/${pro.id}/feed`)).b.length, 1);

    const offer = await call(`/api/jobs/${job.id}/offers`, { price: 120, message: 'אפשר עכשיו בטלפון' }, pro.id);
    assert.equal(offer.s, 200);
    assert.equal(offer.b.phone, undefined); // client did not allow calls

    assert.equal((await call(`/api/clients/${c.id}/jobs`, null, pro.id)).s, 403);
    const [mine] = (await call(`/api/clients/${c.id}/jobs`, null, c.id)).b;
    await call(`/api/jobs/${job.id}/offers/${mine.offers[0].id}/accept`, {}, c.id);

    const [assigned] = (await call(`/api/pros/${pro.id}/jobs`, null, pro.id)).b;
    assert.equal(assigned.phone, '2');
    await call(`/api/jobs/${job.id}/status`, { status: 'in_progress' }, pro.id);
    await call(`/api/jobs/${job.id}/log`, { text: 'איפסתי ראוטר' }, pro.id);
    await call(`/api/jobs/${job.id}/status`, { status: 'completed' }, pro.id);
    assert.equal((await call(`/api/jobs/${job.id}/confirm`, {}, c.id)).b.status, 'closed_done');
    assert.equal((await call('/api/nope')).s, 404);
  } finally { srv.close(); }
});

test('licensed category requires admin approval over HTTP', async () => {
  const srv = createServer(createApp()).listen(0);
  const base = `http://localhost:${srv.address().port}`;
  const call = (path, body, user) => fetch(base + path, { method: body ? 'POST' : 'GET',
    headers: user ? { 'x-user-id': user } : {}, body: body && JSON.stringify(body) })
    .then(async (r) => ({ s: r.status, b: await r.json() }));
  try {
    const loc = { lat: 32.08, lng: 34.78 };
    const pro = (await call('/api/pros', { phone: '1', name: 'P', categories: ['locksmith'], location: loc })).b;
    await call(`/api/pros/${pro.id}/wallet/topup`, { amount: 50 });
    const c = (await call('/api/clients', { phone: '2', name: 'C' })).b;
    const job = (await call('/api/jobs', { categoryId: 'locksmith.door', description: 'נעול בחוץ', location: loc }, c.id)).b;
    assert.equal((await call(`/api/jobs/${job.id}/offers`, { price: 200 }, pro.id)).s, 400);
    const doc = (await call(`/api/pros/${pro.id}/documents`, { type: 'criminal_record', url: 'x' })).b;
    assert.equal((await call('/api/admin/pending-documents')).b.length, 1);
    await call(`/api/admin/pros/${pro.id}/documents/${doc.id}/approve`, {});
    assert.equal((await call(`/api/jobs/${job.id}/offers`, { price: 200 }, pro.id)).s, 200);
  } finally { srv.close(); }
});
