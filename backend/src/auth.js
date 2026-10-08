import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import { MarketplaceError } from './marketplace.js';

const fail = (code, msg) => { throw new MarketplaceError(code, msg); };
const b64 = (s) => Buffer.from(s).toString('base64url');

// Israeli mobile numbers -> E.164 digits (0501234567 -> 972501234567).
export function normalizePhone(raw = '') {
  let d = String(raw).replace(/\D/g, '');
  if (d.startsWith('0')) d = '972' + d.slice(1);
  if (!/^\d{9,15}$/.test(d)) fail('bad_phone', 'Invalid phone number');
  return d;
}

// SMS OTP login + HMAC-signed bearer tokens (no external deps).
// sendSms: (phone, text) => Promise — plug in an SMS provider (e.g. InforU, 019, Twilio).
export class Auth {
  constructor({ secret, sendSms, codeTtlMs = 5 * 60_000, resendMs = 30_000, maxAttempts = 5,
    tokenTtlMs = 180 * 24 * 3600_000, adminTtlMs = 30 * 24 * 3600_000, adminPhones = [], reviewLogins = {} }) {
    if (!secret || secret.length < 16) throw new Error('Auth secret must be at least 16 chars');
    Object.assign(this, { secret, sendSms, codeTtlMs, resendMs, maxAttempts, tokenTtlMs, adminTtlMs });
    this.adminPhones = new Set(adminPhones.map(normalizePhone));
    this.codes = new Map(); // phone -> { code, exp, sentAt, attempts }
    // App-store reviewers can't receive our SMS: a test number with a fixed code, no SMS sent.
    this.review = new Map(Object.entries(reviewLogins).map(([p, c]) => [normalizePhone(p), String(c)]));
  }

  async requestCode(rawPhone) {
    const phone = normalizePhone(rawPhone);
    const prev = this.codes.get(phone);
    if (prev && Date.now() - prev.sentAt < this.resendMs) fail('too_soon', 'Wait before requesting another code');
    const review = this.review.get(phone);
    const code = review ?? String(randomInt(100000, 1000000));
    this.codes.set(phone, { code, exp: Date.now() + this.codeTtlMs, sentAt: Date.now(), attempts: 0 });
    if (!review) {
      try { await this.sendSms(phone, `קוד הכניסה לזריז: ${code}`); }
      catch (e) {
        this.codes.delete(phone);
        console.warn(`[sms] ${phone}: ${e.message}`);
        fail('sms_failed', 'Could not send the SMS');
      }
    }
    return { phone, code };
  }

  verifyCode(rawPhone, code) {
    const phone = normalizePhone(rawPhone);
    const entry = this.codes.get(phone);
    if (!entry || entry.exp < Date.now()) fail('code_expired', 'Code expired, request a new one');
    if (++entry.attempts > this.maxAttempts) { this.codes.delete(phone); fail('too_many_attempts', 'Too many attempts'); }
    const a = Buffer.from(String(code)), b = Buffer.from(entry.code);
    if (a.length !== b.length || !timingSafeEqual(a, b)) fail('bad_code', 'Wrong code');
    this.codes.delete(phone);
    return phone;
  }

  isAdmin(phone) { return this.adminPhones.has(phone); }

  // Customers and pros stay signed in for 6 months; every week of use renews that (see
  // needsRefresh), so someone who keeps using the app never sees the SMS code again.
  // Admins: 30 days.
  issueToken({ sub, role, phone }) {
    const now = Date.now();
    const body = b64(JSON.stringify({ sub, role, phone, iat: now, exp: now + (role === 'admin' ? this.adminTtlMs : this.tokenTtlMs) }));
    return `${body}.${this.#sign(body)}`;
  }
  needsRefresh(payload) { return !payload.iat || Date.now() - payload.iat > 7 * 24 * 3600_000; }
  ttlMs(role) { return role === 'admin' ? this.adminTtlMs : this.tokenTtlMs; }

  verifyToken(token = '') {
    const [body, sig] = token.split('.');
    if (!body || !sig) return null;
    const expected = Buffer.from(this.#sign(body));
    const given = Buffer.from(sig);
    if (expected.length !== given.length || !timingSafeEqual(expected, given)) return null;
    let payload; try { payload = JSON.parse(Buffer.from(body, 'base64url').toString()); } catch { return null; }
    return payload.exp > Date.now() ? payload : null;
  }

  #sign(body) { return createHmac('sha256', this.secret).update(body).digest('base64url'); }
}
