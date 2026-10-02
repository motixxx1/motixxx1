import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createApp } from '../src/app.js';
import { Auth } from '../src/auth.js';
import { Marketplace } from '../src/marketplace.js';
import { Catalog } from '../src/catalog.js';
import { mockProvider } from '../src/providers/mock.js';

async function start() {
  const sms = new Map();
  const auth = new Auth({ secret: 's'.repeat(32), resendMs: 0, adminPhones: ['0509999999'],
    sendSms: async (p, t) => sms.set(p, t.match(/\d{6}/)[0]) });
  const catalog = new Catalog({ providers: [mockProvider({ id: 'mock-hotels', kind: 'hotel' })] });
  const srv = createServer(createApp({ market: new Marketplace(), auth, catalog, dev: true })).listen(0);
  const base = `http://localhost:${srv.address().port}`;
  const call = (path, { body, token, method } = {}) => fetch(base + path, { method: method ?? (body ? 'POST' : 'GET'),
    headers: token ? { authorization: `Bearer ${token}` } : {}, body: body && JSON.stringify(body) })
    .then(async (r) => ({ s: r.status, b: await r.json() }));
  const login = async (phone, role, extra = {}) => {
    await call('/api/auth/request', { body: { phone } });
    const code = sms.get(phone.replace(/^0/, '972'));
    return (await call('/api/auth/verify', { body: { phone, code, role, ...extra } })).b;
  };
  return { srv, call, login };
}

test('HTTP: sign up in one step, offer, accept, work, confirm', async () => {
  const { srv, call, login } = await start();
  try {
    const loc = { lat: 32.08, lng: 34.78 };
    const pro = await login('0521111111', 'pro', { name: 'טכנאי', categories: ['computers'] });
    assert.equal(pro.isNew, true);
    assert.equal(pro.user.balance, 30); // welcome credit
    await call('/api/pro/me', { method: 'PUT', token: pro.token, body: { location: loc } });
    await call('/api/pro/availability', { method: 'PUT', token: pro.token, body: { available: true } });
    const client = await login('0502222222', 'client', { name: 'דנה' });
    assert.equal((await call('/api/jobs', { body: { categoryId: 'computers.network', description: 'x' } })).s, 401);
    assert.equal((await call('/api/jobs', { token: pro.token, body: { categoryId: 'computers.network', description: 'x' } })).s, 403);
    const job = (await call('/api/jobs', { token: client.token, body: { categoryId: 'computers.network', mode: 'phone', description: 'הראוטר לא עובד' } })).b;
    assert.equal((await call('/api/pro/feed', { token: pro.token })).b.length, 1);
    const offer = await call(`/api/jobs/${job.id}/offers`, { token: pro.token, body: { price: 120, message: 'אפשר עכשיו' } });
    assert.equal(offer.s, 200);
    assert.equal(offer.b.phone, undefined);
    const [mine] = (await call('/api/client/jobs', { token: client.token })).b;
    await call(`/api/jobs/${job.id}/offers/${mine.offers[0].id}/accept`, { token: client.token, body: {} });
    const [assigned] = (await call('/api/pro/jobs', { token: pro.token })).b;
    assert.equal(assigned.phone, '972502222222');
    await call(`/api/jobs/${job.id}/status`, { token: pro.token, body: { status: 'in_progress' } });
    await call(`/api/jobs/${job.id}/log`, { token: pro.token, body: { text: 'איפסתי ראוטר' } });
    await call(`/api/jobs/${job.id}/status`, { token: pro.token, body: { status: 'completed' } });
    assert.equal((await call(`/api/jobs/${job.id}/confirm`, { token: client.token, body: {} })).b.status, 'closed_done');
    // logging in again returns the same account
    assert.equal((await login('0521111111', 'pro')).isNew, false);
  } finally { srv.close(); }
});

test('HTTP: travel agent sells a hotel from the supplier API', async () => {
  const { srv, call, login } = await start();
  try {
    const agent = await login('0523333333', 'pro', { name: 'סוכן', categories: ['travel'] });
    await call('/api/pro/availability', { method: 'PUT', token: agent.token, body: { available: true } });
    const client = await login('0504444444', 'client', { name: 'נועה' });
    const job = (await call('/api/jobs', { token: client.token, body: { categoryId: 'travel.hotel', mode: 'remote', description: 'מלון ברודוס' } })).b;
    const results = (await call('/api/catalog/search', { token: agent.token, body: { provider: 'mock-hotels', query: {} } })).b;
    assert.ok(results[0].basePrice > 0);
    // a forged price from the client side is ignored; server re-prices from the supplier
    const sent = await call(`/api/jobs/${job.id}/offers`, { token: agent.token,
      body: { price: 1, items: [{ provider: 'mock-hotels', ref: results[0].ref, agentMarkup: 50 }] } });
    assert.equal(sent.b.myOffer.price, results[0].basePrice + 50);
    const [mine] = (await call('/api/client/jobs', { token: client.token })).b;
    const accepted = await call(`/api/jobs/${job.id}/offers/${mine.offers[0].id}/accept`, { token: client.token,
      body: { traveler: { firstName: 'Noa', lastName: 'Levi', email: 'n@x.com' } } });
    assert.equal(accepted.b.booking.status, 'confirmed');
  } finally { srv.close(); }
});

test('HTTP: admin routes need an admin phone', async () => {
  const { srv, call, login } = await start();
  try {
    const pro = await login('0525555555', 'pro', { name: 'מנעולן', categories: ['locksmith'] });
    assert.equal((await call('/api/admin/pending-documents', { token: pro.token })).s, 403);
    const doc = (await call('/api/pro/documents', { token: pro.token, body: { type: 'criminal_record', url: 'x' } })).b;
    assert.equal((await login('0525555555', 'admin')).token, undefined);
    const admin = await login('0509999999', 'admin');
    assert.equal((await call('/api/admin/pending-documents', { token: admin.token })).b.length, 1);
    await call(`/api/admin/pros/${pro.user.id}/documents/${doc.id}/approve`, { token: admin.token, body: {} });
    assert.deepEqual((await call('/api/pro/me', { token: pro.token })).b.approvedRequirements, ['criminal_record']);
  } finally { srv.close(); }
});

test('HTTP: a company publishes products via the partner API and an agent resells them', async () => {
  const sms = new Map();
  const auth = new Auth({ secret: 's'.repeat(32), resendMs: 0, adminPhones: ['0509999999'],
    sendSms: async (p, t) => sms.set(p, t.match(/\d{6}/)[0]) });
  const srv = createServer(createApp({ auth, dev: true })).listen(0); // default: partners provider only
  const base = `http://localhost:${srv.address().port}`;
  const call = (path, { body, token, key, method } = {}) => fetch(base + path, { method: method ?? (body ? 'POST' : 'GET'),
    headers: { ...(token && { authorization: `Bearer ${token}` }), ...(key && { 'x-api-key': key }) }, body: body && JSON.stringify(body) })
    .then(async (r) => ({ s: r.status, b: await r.json() }));
  const login = async (phone, role, extra = {}) => {
    await call('/api/auth/request', { body: { phone } });
    return (await call('/api/auth/verify', { body: { phone, code: sms.get(phone.replace(/^0/, '972')), role, ...extra } })).b;
  };
  try {
    const admin = await login('0509999999', 'admin');
    const partner = (await call('/api/admin/partners', { token: admin.token, body: { name: 'צימרים בגליל' } })).b;
    assert.match(partner.apiKey, /^pk_/);
    assert.equal((await call('/api/partner/v1/products', { key: 'pk_wrong' })).s, 401);
    const bad = await call('/api/partner/v1/products', { key: partner.apiKey, body: { kind: 'hotel', title: 'x', netPrice: -1, currency: 'ILS' } });
    assert.equal(bad.s, 400);
    const product = (await call('/api/partner/v1/products', { key: partner.apiKey,
      body: { kind: 'hotel', title: 'צימר עם ג׳קוזי', location: 'ראש פינה', netPrice: 600, currency: 'ILS', stock: 1 } })).b;

    const agent = await login('0521111111', 'pro', { name: 'סוכן', categories: ['travel'] });
    await call('/api/pro/availability', { method: 'PUT', token: agent.token, body: { available: true } });
    const client = await login('0502222222', 'client', { name: 'רון' });
    const job = (await call('/api/jobs', { token: client.token, body: { categoryId: 'travel.hotel', mode: 'remote', description: 'צימר בצפון לזוג' } })).b;
    const [found] = (await call('/api/catalog/search', { token: agent.token, body: { provider: 'partners', query: { q: 'ג׳קוזי' } } })).b;
    assert.equal(found.basePrice, 648); // 600 + 8%
    await call(`/api/jobs/${job.id}/offers`, { token: agent.token, body: { items: [{ provider: 'partners', ref: found.ref, agentMarkup: 100 }] } });
    const [mine] = (await call('/api/client/jobs', { token: client.token })).b;
    const done = (await call(`/api/jobs/${job.id}/offers/${mine.offers[0].id}/accept`, { token: client.token,
      body: { traveler: { firstName: 'Ron', lastName: 'Cohen', email: 'r@x.com' } } })).b;
    assert.equal(done.booking.status, 'confirmed');
    const bookings = (await call('/api/partner/v1/bookings', { key: partner.apiKey })).b;
    assert.equal(bookings[0].net.amount, 600);
    assert.equal(bookings[0].customer.phone, '972502222222');
    // sold out after stock hits 0
    assert.equal((await call('/api/catalog/search', { token: agent.token, body: { provider: 'partners', query: {} } })).b.length, 0);
    assert.equal((await call(`/api/partner/v1/products/${product.id}`, { key: partner.apiKey, method: 'PUT', body: { stock: 3 } })).b.stock, 3);
  } finally { srv.close(); }
});

test('HTTP: delivery request geocodes typed addresses, falls back to phone GPS', async () => {
  const sms = new Map();
  const auth = new Auth({ secret: 's'.repeat(32), resendMs: 0, sendSms: async (p, t) => sms.set(p, t.match(/\d{6}/)[0]) });
  const known = { 'דיזנגוף 100 תל אביב': { lat: 32.077, lng: 34.774 } };
  let saves = 0;
  const srv = createServer(createApp({ auth, dev: true, geocode: async (a) => known[a] ?? null, onChange: () => saves++ })).listen(0);
  const base = `http://localhost:${srv.address().port}`;
  const call = (path, { body, token, method } = {}) => fetch(base + path, { method: method ?? (body ? 'POST' : 'GET'),
    headers: token ? { authorization: `Bearer ${token}` } : {}, body: body && JSON.stringify(body) }).then(async (r) => ({ s: r.status, b: await r.json() }));
  const login = async (phone, role, extra = {}) => {
    await call('/api/auth/request', { body: { phone } });
    return (await call('/api/auth/verify', { body: { phone, code: sms.get(phone.replace(/^0/, '972')), role, ...extra } })).b;
  };
  try {
    assert.equal((await call('/healthz')).s, 200);
    const courier = await login('0521111111', 'pro', { name: 'שליח', categories: ['delivery'] });
    await call('/api/pro/me', { method: 'PUT', token: courier.token, body: { location: { lat: 32.078, lng: 34.775 } } });
    await call('/api/pro/availability', { method: 'PUT', token: courier.token, body: { available: true } });
    const client = await login('0502222222', 'client', { name: 'דן' });
    const job = await call('/api/jobs', { token: client.token, body: { categoryId: 'delivery.food', mode: 'delivery',
      description: 'פיצה', address: 'דיזנגוף 100 תל אביב', dropoff: { address: 'כתובת שלא קיימת' },
      myLocation: { lat: 32.1, lng: 34.8 }, itemsCost: 70 } });
    assert.equal(job.s, 200);
    assert.deepEqual(job.b.location, { lat: 32.08, lng: 34.77 });     // geocoded pickup (rounded)
    assert.deepEqual(job.b.dropoff.location, { lat: 32.1, lng: 34.8 }); // GPS fallback
    const [card] = (await call('/api/pro/feed', { token: courier.token })).b;
    assert.equal(card.distanceKm, 0.1);
    assert.ok(saves >= 4);
  } finally { srv.close(); }
});
