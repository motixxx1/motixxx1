import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Auth, normalizePhone } from '../src/auth.js';

const mk = (opts = {}) => {
  const sms = [];
  const auth = new Auth({ secret: 'x'.repeat(32), sendSms: async (p, t) => sms.push({ p, t }), resendMs: 0, ...opts });
  return { auth, sms };
};

test('normalizes Israeli numbers', () => {
  assert.equal(normalizePhone('050-123-4567'), '972501234567');
  assert.throws(() => normalizePhone('12'), /Invalid/);
});

test('OTP: correct code works once; wrong codes are limited', async () => {
  const { auth, sms } = mk({ maxAttempts: 2 });
  const { code } = await auth.requestCode('0501234567');
  assert.match(sms[0].t, new RegExp(code));
  assert.equal(auth.verifyCode('0501234567', code), '972501234567');
  assert.throws(() => auth.verifyCode('0501234567', code), /expired/);
  await auth.requestCode('0501234567');
  assert.throws(() => auth.verifyCode('0501234567', '000000'), /Wrong/);
  assert.throws(() => auth.verifyCode('0501234567', '000000'), /Wrong/);
  assert.throws(() => auth.verifyCode('0501234567', '000000'), /Too many/);
});

test('tokens: valid, tampered, expired', () => {
  const { auth } = mk();
  const t = auth.issueToken({ sub: 'u1', role: 'pro', phone: '972' });
  assert.equal(auth.verifyToken(t).sub, 'u1');
  const [body, sig] = t.split('.');
  const forged = Buffer.from(JSON.stringify({ sub: 'u1', role: 'admin', exp: Date.now() + 1e6 })).toString('base64url');
  assert.equal(auth.verifyToken(`${forged}.${sig}`), null);
  assert.equal(auth.verifyToken(`${body}.x`), null);
  const { auth: shortLived } = mk({ tokenTtlMs: -1 });
  assert.equal(shortLived.verifyToken(shortLived.issueToken({ sub: 'u' })), null);
});

test('store-review login: fixed code, no SMS sent', async () => {
  const sent = [];
  const { Auth } = await import('../src/auth.js');
  const a = new Auth({ secret: 's'.repeat(32), sendSms: async (p) => sent.push(p), reviewLogins: { '0500000000': '246810' } });
  await a.requestCode('0500000000');
  assert.equal(sent.length, 0);
  assert.equal(a.verifyCode('0500000000', '246810'), '972500000000');
});
