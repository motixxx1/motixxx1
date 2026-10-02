import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { createApp } from './app.js';
import { Marketplace } from './marketplace.js';
import { Auth } from './auth.js';
import { Catalog } from './catalog.js';
import { Partners } from './partners.js';
import { providersFromEnv } from './providers/index.js';

const dev = process.env.NODE_ENV !== 'production';
if (!dev && !process.env.AUTH_SECRET) throw new Error('AUTH_SECRET is required in production');

const auth = new Auth({
  secret: process.env.AUTH_SECRET ?? randomBytes(32).toString('hex'),
  adminPhones: (process.env.ADMIN_PHONES ?? '').split(',').filter(Boolean),
  // TODO: real SMS provider. In dev the code is printed and echoed to the login screen.
  sendSms: async (phone, text) => console.log(`[sms] ${phone}: ${text}`),
});
const market = new Marketplace({ notify: (userId, msg) => console.log('[push]', userId, msg) });
const partners = new Partners();
const catalog = new Catalog({ providers: [partners.provider(), ...providersFromEnv(process.env, { dev })] });

const port = process.env.PORT || 3000;
createServer(createApp({ market, auth, partners, catalog, dev })).listen(port, () =>
  console.log(`API on http://localhost:${port}  (client: /  ·  pros: /pro)${dev ? '  [dev mode]' : ''}`));
