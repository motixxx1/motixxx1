import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { createApp } from './app.js';
import { Marketplace } from './marketplace.js';
import { Auth } from './auth.js';
import { Catalog } from './catalog.js';
import { Partners } from './partners.js';
import { providersFromEnv } from './providers/index.js';
import { createFileStore } from './store.js';
import { nominatimGeocoder } from './geocode.js';
import { twilioSms } from './sms.js';

// DEMO_MODE=1 keeps the dev conveniences (test top-ups, mock suppliers, and — while no SMS
// provider is configured — the login code shown on screen) on a public server.
// Without an SMS provider anyone can log in as any phone number: demo data only!
const env = process.env;
const dev = env.NODE_ENV !== 'production' || env.DEMO_MODE === '1';
if (env.NODE_ENV === 'production' && !env.AUTH_SECRET) throw new Error('AUTH_SECRET is required in production');
const sms = env.TWILIO_ACCOUNT_SID && env.TWILIO_AUTH_TOKEN && env.TWILIO_FROM
  ? twilioSms({ accountSid: env.TWILIO_ACCOUNT_SID, authToken: env.TWILIO_AUTH_TOKEN, from: env.TWILIO_FROM })
  : null;

const auth = new Auth({
  secret: env.AUTH_SECRET ?? randomBytes(32).toString('hex'),
  adminPhones: (env.ADMIN_PHONES ?? '').split(',').filter(Boolean),
  sendSms: sms ?? (async (phone, text) => console.log(`[sms] ${phone}: ${text}`)),
});
const market = new Marketplace({ notify: (userId, msg) => console.log('[push]', userId, msg) });
const partners = new Partners();
const catalog = new Catalog({ providers: [partners.provider(), ...providersFromEnv(env, { dev })] });
const store = createFileStore(env.DATA_FILE ?? './data/state.json', { market, partners });
const geocode = nominatimGeocoder({ userAgent: env.GEOCODER_USER_AGENT ?? 'ProMarket/0.1' });

const port = env.PORT || 3000;
const server = createServer(createApp({ market, auth, partners, catalog, geocode, onChange: store.save, dev, echoOtp: dev && !sms }))
  .listen(port, () => console.log(`API on http://localhost:${port}  (client: /  ·  pros: /pro)${dev ? '  [demo mode]' : ''}`));

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, async () => { await store.flush(); server.close(() => process.exit(0)); });
}
