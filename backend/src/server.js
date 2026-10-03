import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApp } from './app.js';
import { Marketplace } from './marketplace.js';
import { Auth } from './auth.js';
import { Catalog } from './catalog.js';
import { Partners } from './partners.js';
import { providersFromEnv } from './providers/index.js';
import { createFileStore } from './store.js';
import { nominatimGeocoder } from './geocode.js';
import { twilioSms } from './sms.js';
import { Media } from './media.js';

// Settings come from environment variables, or from config.env next to package.json
// (the downloadable server package ships one; real env vars win).
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
if (existsSync(join(root, 'config.env'))) process.loadEnvFile(join(root, 'config.env'));

// DEMO_MODE=1 keeps the dev conveniences (test top-ups, mock suppliers, and — while no SMS
// provider is configured — the login code shown on screen) on a public server.
// Without an SMS provider anyone can log in as any phone number: demo data only!
const env = process.env;
const dev = env.NODE_ENV !== 'production' || env.DEMO_MODE === '1';
const dataFile = env.DATA_FILE ? resolve(env.DATA_FILE) : join(root, 'data', 'state.json');

// Token signing key: AUTH_SECRET, or one generated on first start and kept next to the data,
// so logins survive restarts.
function loadOrCreateSecret(dir) {
  const file = join(dir, '.auth_secret');
  if (existsSync(file)) return readFileSync(file, 'utf8').trim();
  mkdirSync(dir, { recursive: true });
  const secret = randomBytes(32).toString('hex');
  writeFileSync(file, secret, { mode: 0o600 });
  return secret;
}
const sms = env.TWILIO_ACCOUNT_SID && env.TWILIO_AUTH_TOKEN && env.TWILIO_FROM
  ? twilioSms({ accountSid: env.TWILIO_ACCOUNT_SID, authToken: env.TWILIO_AUTH_TOKEN, from: env.TWILIO_FROM })
  : null;

// A real (non-demo) server must be able to text login codes; otherwise nobody could sign in.
if (!dev && !sms) {
  console.error('Production mode needs SMS: set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_FROM (or DEMO_MODE=1 for a demo).');
  process.exit(1);
}
if (env.DEMO_MODE === '1' && env.NODE_ENV === 'production') {
  console.warn('WARNING: DEMO_MODE is on — anyone can log in as any phone number. Do not use with real users.');
}

const auth = new Auth({
  secret: env.AUTH_SECRET || loadOrCreateSecret(dirname(dataFile)),
  adminPhones: (env.ADMIN_PHONES ?? '').split(',').filter(Boolean),
  sendSms: sms ?? (async (phone, text) => console.log(`[sms] ${phone}: ${text}`)),
});
const market = new Marketplace({ notify: (userId, msg) => console.log('[push]', userId, msg) });
const partners = new Partners();
const catalog = new Catalog({ providers: [partners.provider(), ...providersFromEnv(env, { dev })] });
const media = new Media(join(dirname(dataFile), 'uploads'));
const store = createFileStore(dataFile, { market, partners, media });
const geocode = nominatimGeocoder({ userAgent: env.GEOCODER_USER_AGENT ?? 'ProMarket/0.1' });

const port = env.PORT || 3000;
const server = createServer(createApp({ market, auth, partners, catalog, geocode, media, onChange: store.save, dev, echoOtp: dev && !sms }))
  .listen(port, () => {
    console.log(`ProMarket is running on port ${port}${dev ? '  [demo mode]' : ''}`);
    console.log(`  customers: http://<this-computer-ip>:${port}/    pros: http://<this-computer-ip>:${port}/pro`);
    console.log(`  data: ${dataFile}`);
  });

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, async () => { await store.flush(); server.close(() => process.exit(0)); });
}
