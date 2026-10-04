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
import { nominatimGeocoder, nominatimReverse, maptilerGeocoder, maptilerReverse, mapTiles } from './geocode.js';
import { twilioSms, httpSms } from './sms.js';
import { Media } from './media.js';
import { createUpdater } from './updater.js';

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
const sms = env.SMS_HTTP_URL
  ? httpSms({ url: env.SMS_HTTP_URL, method: (env.SMS_HTTP_METHOD || 'GET').toUpperCase(), body: env.SMS_HTTP_BODY || '',
    headers: env.SMS_HTTP_HEADERS ? JSON.parse(env.SMS_HTTP_HEADERS) : {} })
  : env.TWILIO_ACCOUNT_SID && env.TWILIO_AUTH_TOKEN && env.TWILIO_FROM
    ? twilioSms({ accountSid: env.TWILIO_ACCOUNT_SID, authToken: env.TWILIO_AUTH_TOKEN, from: env.TWILIO_FROM })
    : null;
if (!sms && !dev) console.warn('!! No SMS provider configured: login codes are only printed here, users cannot sign in.');

const auth = new Auth({
  secret: env.AUTH_SECRET || loadOrCreateSecret(dirname(dataFile)),
  adminPhones: (env.ADMIN_PHONES ?? '').split(',').filter(Boolean),
  // REVIEW_LOGIN=0501234567:246810 - a fixed code for app-store reviewers (no SMS is sent to it).
  reviewLogins: Object.fromEntries((env.REVIEW_LOGIN ?? '').split(',').filter(Boolean).map((x) => x.split(':').map((v) => v.trim()))),
  sendSms: sms ?? (async (phone, text) => console.log(`[sms] ${phone}: ${text}`)),
});
// Launch switches, both off by default:
// LEAD_FEES=1 - each offer costs the pro credit (turn on once pros can buy credit).
// PAYMENTS=1  - secure in-app card payment and travel (turn on once a payment provider is connected).
const leadFees = env.LEAD_FEES === '1';
const payments = env.PAYMENTS === '1';
const market = new Marketplace({ notify: (userId, msg) => console.log('[push]', userId, msg), leadFees, payments });
const partners = new Partners();
const catalog = new Catalog({ providers: [partners.provider(), ...providersFromEnv(env, { dev })] });
const media = new Media(join(dirname(dataFile), 'uploads'));
// Database: SQLite file (data/zariz.db). The older JSON file is imported on first start.
// DB=json keeps the old JSON file store.
let store;
if (env.DB !== 'json') {
  // SQLite is built into Node 22 but still flagged "experimental": hide that one notice.
  const warn = process.emitWarning;
  process.emitWarning = (w, ...rest) => (String(w?.message ?? w).includes('SQLite') ? undefined : warn.call(process, w, ...rest));
  try {
    const { createDbStore } = await import('./db.js');
    store = createDbStore(env.DB_FILE ? resolve(env.DB_FILE) : join(dirname(dataFile), 'zariz.db'), { market, partners, media }, { legacyJson: dataFile });
  } catch (e) {
    console.warn(`[db] SQLite not available (${e.message}); using the JSON file`);
  }
}
store ??= createFileStore(dataFile, { market, partners, media });
// Addresses and map tiles: MapTiler when MAPTILER_KEY is set, otherwise OpenStreetMap.
const ua = env.GEOCODER_USER_AGENT ?? 'Zariz/1.0';
const geocode = env.MAPTILER_KEY ? maptilerGeocoder({ key: env.MAPTILER_KEY }) : nominatimGeocoder({ userAgent: ua });
const reverseGeocode = env.MAPTILER_KEY ? maptilerReverse({ key: env.MAPTILER_KEY }) : nominatimReverse({ userAgent: ua });
const maps = mapTiles(env.MAPTILER_KEY);

// Automatic updates from the GitHub release: on by default for the downloadable package
// (it ships build.json), off for Docker and development. AUTO_UPDATE=0 / 1 forces it.
const updater = createUpdater({ root, beforeRestart: () => store.flush(),
  url: env.UPDATE_URL || 'https://github.com/motixxx1/motixxx1/releases/download/promarket-latest/promarket-update.json' });
// Free fixed address for a home server (https-setup.sh adds the HTTPS certificate):
// DUCKDNS_DOMAIN=zariz-app (or zariz-app.duckdns.org) + DUCKDNS_TOKEN keep the name pointing
// at the home's public IP, which can change.
if (env.DUCKDNS_DOMAIN && env.DUCKDNS_TOKEN) {
  const name = env.DUCKDNS_DOMAIN.replace(/\.duckdns\.org$/, '');
  const refresh = () => fetch(`https://www.duckdns.org/update?domains=${encodeURIComponent(name)}&token=${encodeURIComponent(env.DUCKDNS_TOKEN)}&ip=`)
    .then((r) => r.text()).then((t) => { if (t.trim() !== 'OK') console.warn(`[duckdns] update failed: ${t.trim()}`); })
    .catch((e) => console.warn(`[duckdns] ${e.message}`));
  refresh();
  setInterval(refresh, 5 * 60 * 1000).unref();
  console.log(`[duckdns] keeping ${name}.duckdns.org pointed at this network`);
}

if (env.AUTO_UPDATE === '1' || (existsSync(join(root, 'build.json')) && env.AUTO_UPDATE !== '0')) {
  updater.start();
  console.log(`[update] automatic updates on (build ${updater.info().build})`);
}

const port = env.PORT || 3000;
const server = createServer(createApp({ market, auth, partners, catalog, geocode, reverseGeocode, maps, media, onChange: store.save, dev, echoOtp: dev && !sms,
  version: updater.info, site: { name: env.BUSINESS_NAME || 'זריז', email: env.SUPPORT_EMAIL || '' },
  topup: { url: env.TOPUP_URL || '', secret: env.PAYMENT_WEBHOOK_SECRET || '' } }))
  .listen(port, () => {
    console.log(`Zariz is running on port ${port}${dev ? '  [demo mode]' : ''}`);
    console.log(`  customers: http://<this-computer-ip>:${port}/    pros: http://<this-computer-ip>:${port}/pro`);
    console.log(`  data: ${store.db ? store.db.location?.() ?? 'zariz.db (SQLite)' : dataFile}`);
  });

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, async () => {
    await store.flush();
    store.close?.();
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 2000).unref();
  });
}
