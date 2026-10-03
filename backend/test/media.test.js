import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp } from '../src/app.js';
import { Auth } from '../src/auth.js';
import { Media } from '../src/media.js';

async function start(mediaOpts) {
  const sms = new Map();
  const auth = new Auth({ secret: 's'.repeat(32), resendMs: 0, sendSms: async (p, t) => sms.set(p, t.match(/\d{6}/)[0]) });
  const media = new Media(mkdtempSync(join(tmpdir(), 'pm-media-')), mediaOpts);
  const srv = createServer(createApp({ auth, media, dev: true })).listen(0);
  const base = `http://localhost:${srv.address().port}`;
  const call = (path, { body, token, method } = {}) => fetch(base + path, { method: method ?? (body ? 'POST' : 'GET'),
    headers: token ? { authorization: `Bearer ${token}` } : {}, body: body && JSON.stringify(body) }).then(async (r) => ({ s: r.status, b: await r.json() }));
  const upload = (token, type, data) => fetch(base + '/api/uploads', { method: 'POST',
    headers: { ...(token && { authorization: `Bearer ${token}` }), 'content-type': type }, body: data }).then(async (r) => ({ s: r.status, b: await r.json() }));
  const login = async (phone, role, extra = {}) => {
    await call('/api/auth/request', { body: { phone } });
    return (await call('/api/auth/verify', { body: { phone, code: sms.get(phone.replace(/^0/, '972')), role, ...extra } })).b;
  };
  return { srv, base, call, upload, login };
}

test('photos and a video attach to a request; only signed-in pros see them', async () => {
  const { srv, base, call, upload, login } = await start();
  try {
    const client = await login('0502222222', 'client', { name: 'דנה' });
    const pro = await login('0521111111', 'pro', { name: 'אינסטלטור', categories: ['plumbing'] });
    await call('/api/pro/me', { method: 'PUT', token: pro.token, body: { location: { lat: 32.08, lng: 34.78 } } });
    await call('/api/pro/availability', { method: 'PUT', token: pro.token, body: { available: true } });

    const png = Buffer.from('89504e470d0a1a0a0000', 'hex');
    const mp4 = Buffer.alloc(5000, 7);
    assert.equal((await upload(null, 'image/png', png)).s, 401);
    assert.equal((await upload(client.token, 'text/html', Buffer.from('<script>'))).s, 415);
    assert.equal((await upload(client.token, 'image/svg+xml', Buffer.from('<svg/>'))).s, 415);
    const img = await upload(client.token, 'image/png', png);
    const vid = await upload(client.token, 'video/mp4', mp4);
    assert.equal(img.s, 200); assert.equal(vid.b.kind, 'video');

    // served back, with Range for video
    const full = await fetch(base + img.b.url);
    assert.equal(full.headers.get('content-type'), 'image/png');
    assert.deepEqual(Buffer.from(await full.arrayBuffer()), png);
    const part = await fetch(base + vid.b.url, { headers: { range: 'bytes=10-19' } });
    assert.equal(part.status, 206);
    assert.equal(part.headers.get('content-range'), 'bytes 10-19/5000');
    assert.equal((await part.arrayBuffer()).byteLength, 10);
    assert.equal((await fetch(base + '/media/00000000-0000-0000-0000-000000000000')).status, 404);

    // a pro cannot attach the client's files; a client cannot attach unknown ids
    const foreign = await call('/api/jobs', { token: pro.token, body: { categoryId: 'plumbing.unclog', description: 'x', media: [img.b.id] } });
    assert.equal(foreign.s, 403);
    const bad = await call('/api/jobs', { token: client.token, body: { categoryId: 'plumbing.unclog', description: 'סתימה', address: 'x', myLocation: { lat: 32.08, lng: 34.78 }, media: ['nope'] } });
    assert.equal(bad.s, 400);

    const job = (await call('/api/jobs', { token: client.token, body: { categoryId: 'plumbing.unclog', description: 'נזילה מתחת לכיור', address: 'x', myLocation: { lat: 32.08, lng: 34.78 }, media: [img.b.id, vid.b.id] } })).b;
    assert.equal((await call('/api/jobs')).b[0].media, undefined);            // public board: no media
    const [card] = (await call('/api/pro/feed', { token: pro.token })).b;
    assert.deepEqual(card.media.map((m) => m.kind), ['image', 'video']);       // eligible pro sees them
    const [mine] = (await call('/api/client/jobs', { token: client.token })).b;
    assert.equal(mine.media.length, 2);
    assert.equal(job.id, mine.id);
  } finally { srv.close(); }
});

test('limits: file size, and number of photos/videos', async () => {
  const { srv, upload, call, login } = await start({ maxImageBytes: 100, maxVideoBytes: 1000 });
  try {
    const client = await login('0502222222', 'client', { name: 'דנה' });
    assert.equal((await upload(client.token, 'image/jpeg', Buffer.alloc(101))).s, 413);
    assert.equal((await upload(client.token, 'image/jpeg', Buffer.alloc(0))).s, 400);
    const ids = [];
    for (let i = 0; i < 9; i++) ids.push((await upload(client.token, 'image/jpeg', Buffer.alloc(10))).b.id);
    const body = (media) => ({ categoryId: 'computers.software', mode: 'remote', description: 'מחשב איטי', media });
    assert.equal((await call('/api/jobs', { token: client.token, body: body(ids) })).s, 400);   // 9 photos
    assert.equal((await call('/api/jobs', { token: client.token, body: body(ids.slice(0, 8)) })).s, 200);
    const v1 = (await upload(client.token, 'video/mp4', Buffer.alloc(10))).b.id, v2 = (await upload(client.token, 'video/webm', Buffer.alloc(10))).b.id;
    assert.equal((await call('/api/jobs', { token: client.token, body: body([v1, v2]) })).s, 400); // 2 videos
  } finally { srv.close(); }
});
