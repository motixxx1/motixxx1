import { readFile } from 'node:fs/promises';
import { Marketplace, MarketplaceError, TOPUP_PACKAGES } from './marketplace.js';
import { CATEGORIES, searchCategories } from './categories.js';
import { Auth, normalizePhone } from './auth.js';
import { Catalog } from './catalog.js';
import { Partners } from './partners.js';
import { Media } from './media.js';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const STATUS = { not_found: 404, forbidden: 403, unauthorized: 401, too_soon: 429, too_many_attempts: 429,
  supplier_error: 502, booking_failed: 502, payments_disabled: 501, taken: 409 };
const PAGES = { '/': 'index.html', '/index.html': 'index.html', '/pro': 'pro.html', '/pro.html': 'pro.html', '/admin': 'admin.html' };
// Privacy policy, terms and account deletion: public pages the app stores link to.
const LEGAL = { '/privacy': 'privacy.html', '/terms': 'terms.html', '/delete-account': 'delete-account.html' };
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
// Libraries the pages load from this server (no CDN needed on the local network).
const VENDOR_TYPES = { js: 'text/javascript', css: 'text/css', png: 'image/png', svg: 'image/svg+xml' };

// dev: allows wallet top-up without a payment provider. echoOtp: returns the SMS code in the
// response (only while no SMS provider is configured). Never enable either with real users.
// geocode: address -> {lat,lng} | null. onChange: called after every successful write (persistence).
export function createApp({ market = new Marketplace(), auth, partners = new Partners(),
  catalog = new Catalog({ providers: [partners.provider()] }), geocode = async () => null, reverseGeocode = async () => null, suggestAddress = async () => [], maps = null,
  media = new Media(join(tmpdir(), 'promarket-uploads-' + process.pid)),
  onChange = () => {}, dev = false, echoOtp = dev, version = () => ({ build: 'dev', apk: null }), release = null,
  site = { name: 'זריז', email: '' }, topup = {} } = {}) {
  if (!auth) throw new Error('auth required');
  const routes = [];
  const on = (method, path, role, fn) => routes.push({ method, role, fn,
    re: new RegExp('^' + path.replace(/:\w+/g, '([^/]+)') + '$') });
  const pub = (j) => market.teaser(j);
  const fail = (code, msg) => { throw new MarketplaceError(code, msg); };

  // ---- Auth: one screen, phone + SMS code. New users are created on first verify.
  on('POST', '/api/auth/request', null, async ({ body }) => {
    const { code } = await auth.requestCode(body.phone);
    return echoOtp ? { sent: true, devCode: code } : { sent: true };
  });
  on('POST', '/api/auth/verify', null, ({ body }) => {
    const phone = auth.verifyCode(body.phone, body.code);
    const role = body.role;
    if (role === 'admin') {
      if (!auth.isAdmin(phone)) fail('forbidden', 'Not an admin');
      return { token: auth.issueToken({ sub: phone, role, phone }) };
    }
    if (!['client', 'pro'].includes(role)) fail('bad_role', 'role must be client or pro');
    let user = role === 'pro' ? market.proByPhone(phone) : market.clientByPhone(phone);
    const isNew = !user;
    if (isNew) {
      user = role === 'pro'
        ? market.registerPro({ phone, name: body.name, categories: body.categories, referralCode: body.referralCode })
        : market.registerClient({ phone, name: body.name });
    }
    return { token: auth.issueToken({ sub: user.id, role, phone }), isNew,
      user: role === 'pro' ? market.publicPro(user) : { id: user.id, name: user.name } };
  });

  // Travel is sold with in-app payment only, so it is hidden until payments are connected.
  const visible = (list) => (market.payments ? list : list.filter((c) => c.id !== 'travel' && c.parent !== 'travel'));
  on('GET', '/api/categories', null, ({ query }) => visible(query.q ? searchCategories(query.q) : CATEGORIES));
  // What the pages should show: credit/lead fees, secure in-app payment, support contact.
  on('GET', '/api/config', null, () => ({ leadFees: market.leadFees, payments: market.payments, demo: dev,
    supportEmail: site.email || null,
    topupPackages: TOPUP_PACKAGES, topup: !!topup.url || dev, maps }));
  // "Use my location" -> a street address the customer can check.
  on('GET', '/api/geocode/reverse', ['client', 'pro'], async ({ query }) => {
    const lat = +query.lat, lng = +query.lng;
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) fail('bad_location', 'lat and lng required');
    return { address: await reverseGeocode({ lat, lng }).catch(() => null) };
  });
  // Suggestions while typing an address, from public address data.
  on('GET', '/api/geocode/suggest', ['client', 'pro'], async ({ query }) => {
    const q = String(query.q ?? '').trim();
    return q.length < 3 ? [] : (await suggestAddress(q.slice(0, 80)).catch(() => [])).slice(0, 6);
  });
  on('DELETE', '/api/me', ['client', 'pro'], ({ me, role }) => market.deleteAccount(role, me));
  on('POST', '/api/me/name', ['client', 'pro'], ({ me, role, body }) => market.rename(role, me, body.name));
  on('GET', '/api/client/profile', 'client', ({ me }) => market.clientProfile(me));
  on('POST', '/api/client/addresses', 'client', ({ me, body }) => market.addAddress(me, body));
  on('DELETE', '/api/client/addresses/:id', 'client', ({ me, p }) => market.removeAddress(me, p[0]));
  on('POST', '/api/client/settings', 'client', ({ me, body }) => market.clientSettings(me, body));
  on('POST', '/api/client/jobs/:id/title', 'client', ({ me, p, body }) => market.renameJob(me, p[0], body.title));
  on('GET', '/api/jobs', null, ({ query }) => [...market.jobs.values()]
    .filter((j) => j.status === 'open' && (!query.category || j.categoryId.startsWith(query.category))
      && (!query.mode || j.mode === query.mode))
    .sort((a, b) => b.createdAt - a.createdAt).map(pub));

  // ---- Pro
  on('GET', '/api/pro/me', 'pro', ({ me }) => market.publicPro(market.getPro(me)));
  on('PUT', '/api/pro/me', 'pro', ({ me, body }) => market.publicPro(market.updateProfile(me, body)));
  on('POST', '/api/pro/documents', 'pro', ({ me, body }) => market.uploadDocument(me, body));
  on('PUT', '/api/pro/availability', 'pro', ({ me, body }) => (market.setAvailability(me, body.available), { ok: true }));
  on('PUT', '/api/pro/location', 'pro', ({ me, body }) => (market.updateLocation(me, body), { ok: true }));
  on('GET', '/api/pro/wallet', 'pro', ({ me }) => ({ balance: market.getPro(me).balance, history: market.history(me) }));
  // Production: credit is added only by the payment provider's webhook after a successful charge.
  // Demo: instant. Production: returns the payment link for the chosen package; the credit
  // arrives when the provider calls POST /api/payments/webhook (see topup.url / topup.secret).
  on('POST', '/api/pro/wallet/topup', 'pro', ({ me, body }) => {
    if (!market.leadFees) fail('payments_disabled', 'Credit is not used right now');
    const amount = +body.amount;
    if (!topup.url) return dev ? market.topUp(me, amount, 'demo') : fail('payments_disabled', 'Credit purchase is not set up yet');
    const t = market.startTopup(me, amount);
    onChange();
    return { id: t.id, payUrl: topup.url.replaceAll('{amount}', t.amount).replaceAll('{ref}', t.id).replaceAll('{phone}', encodeURIComponent(market.getPro(me).phone)) };
  });
  on('GET', '/api/pro/wallet/topups/:id', 'pro', ({ p, me }) => {
    const t = market.topups.find((x) => x.id === p[0] && x.proId === me) ?? fail('not_found', 'Unknown payment');
    return { id: t.id, status: t.status, amount: t.amount };
  });
  // Payment provider callback: { ref, status: 'paid' }, authenticated by the shared secret.
  on('POST', '/api/payments/webhook', null, ({ body, query, req }) => {
    const given = req.headers['x-webhook-secret'] ?? query.secret;
    if (!topup.secret || given !== topup.secret) fail('unauthorized', 'Bad secret');
    if (body.status && !['paid', 'success', 'approved'].includes(String(body.status).toLowerCase())) return { ok: true, ignored: true };
    market.confirmTopup(body.ref ?? body.id);
    onChange();
    return { ok: true };
  });
  on('GET', '/api/pro/feed', 'pro', ({ me, query }) => market.feed(me, {
    maxKm: query.maxKm && +query.maxKm, urgency: query.urgency, mode: query.mode }));
  on('GET', '/api/pro/jobs', 'pro', ({ me }) => market.proJobs(me, me));
  on('POST', '/api/jobs/:id/offers', 'pro', async ({ p, me, body }) => {
    const { price, eta, message } = body;
    // Supplier items are re-priced server-side; client-sent prices are ignored.
    const items = body.items?.length ? await catalog.priceItems(body.items) : null;
    return market.sendOffer(p[0], me, { price: items ? null : price ?? null, eta, message, items });
  });
  // Fixed-price request: first pro to accept takes it; later ones get 409 "taken" (missed).
  on('POST', '/api/jobs/:id/take', 'pro', ({ p, me }) => market.takeJob(p[0], me));
  on('POST', '/api/jobs/:id/paid', 'pro', ({ p, me, body }) => market.recordPayment(p[0], me, body));
  on('POST', '/api/jobs/:id/log', 'pro', ({ p, me, body }) => market.addLog(p[0], me, body));
  on('POST', '/api/jobs/:id/status', 'pro', ({ p, me, body }) => pub(market.advance(p[0], me, body.status, body)));

  // ---- Supplier inventory for agents/pros (RateHawk hotels, Duffel flights, our partners, ...)
  on('GET', '/api/catalog/providers', 'pro', () => catalog.list());
  on('POST', '/api/catalog/search', 'pro', ({ body }) => catalog.search(body.provider, body.query ?? {}));

  // ---- Partner (supplier) API: companies publish products with an API key (x-api-key header)
  on('GET', '/api/partner/v1/products', 'partner', ({ me }) => partners.listProducts(me));
  on('POST', '/api/partner/v1/products', 'partner', ({ me, body }) => partners.upsertProduct(me, body));
  on('PUT', '/api/partner/v1/products/:id', 'partner', ({ me, p, body }) => partners.upsertProduct(me, body, p[0]));
  on('DELETE', '/api/partner/v1/products/:id', 'partner', ({ me, p }) => partners.deactivate(me, p[0]));
  on('GET', '/api/partner/v1/bookings', 'partner', ({ me }) => partners.partnerBookings(me));

  // ---- Client
  on('POST', '/api/jobs', 'client', async ({ me, body }) => {
    // Typed address wins; the phone's GPS (myLocation) is the fallback when geocoding fails.
    const locate = async (address, given) =>
      given ?? (address ? await geocode(address).catch(() => null) : null) ?? body.myLocation ?? null;
    const physical = ['onsite', 'delivery'].includes(body.mode ?? 'onsite');
    const location = physical ? await locate(body.address, body.location) : null;
    const dropoff = body.mode === 'delivery' && body.dropoff
      ? { address: body.dropoff.address, location: await locate(body.dropoff.address, body.dropoff.location) } : null;
    const { myLocation, ...rest } = body;
    return pub(market.createJob({ ...rest, location, dropoff, clientId: me, media: media.attach(body.media ?? [], me) }));
  });
  on('GET', '/api/client/jobs', 'client', ({ me }) => market.clientJobs(me, me));
  on('POST', '/api/jobs/:id/offers/:offer/accept', 'client', async ({ p, me, body }) => {
    const { offer } = market.offerForAccept(p[0], me, p[1]);
    if (offer.items) await catalog.requote(offer.items);
    // Production: charge the client's card via the payment provider here, before booking.
    const traveler = body.traveler && { phone: market.clients.get(me).phone, ...body.traveler };
    const job = market.acceptOffer(p[0], me, p[1], { traveler });
    if (offer.items) {
      try { market.bookingConfirmed(job.id, await catalog.book(offer.items, traveler, job.id)); }
      catch (e) { market.bookingFailed(job.id, e.message, e.booked ?? []); }
    }
    return market.clientJobs(me, me).find((j) => j.id === job.id);
  });
  on('POST', '/api/jobs/:id/confirm', 'client', ({ p, me }) => pub(market.confirmCompletion(p[0], me)));
  on('POST', '/api/jobs/:id/rate', ['client', 'pro'], ({ p, me, body }) => market.rate(p[0], me, body.score, body.text));

  // ---- Admin
  on('GET', '/api/admin/pending-documents', 'admin', () => [...market.pros.values()].flatMap((pro) =>
    pro.documents.filter((d) => d.status === 'pending').map((d) => ({ proId: pro.id, proName: pro.name, ...d }))));
  on('POST', '/api/admin/pros/:id/documents/:doc/approve', 'admin', ({ p }) => market.approveDocument(p[0], p[1]));
  on('POST', '/api/admin/partners', 'admin', ({ body }) => partners.create(body));
  // Credit is added only by the payment provider (webhook) or by an admin here, e.g. after a
  // pro paid by bank transfer or Bit.
  on('GET', '/api/admin/pros', 'admin', () => [...market.pros.values()].map((p) => ({
    id: p.id, name: p.name, phone: p.phone, balance: p.balance, categories: p.categories ?? [] })));
  on('POST', '/api/admin/pros/:id/credit', 'admin', ({ p, body, me }) => {
    const amount = Number(body.amount);
    if (!Number.isInteger(amount) || amount === 0 || Math.abs(amount) > 10000) fail('bad_amount', 'Amount must be a whole number up to 10,000');
    const pro = market.getPro(p[0]);
    if (amount < 0 && pro.balance + amount < 0) fail('bad_amount', 'Balance cannot go below zero');
    market.topUp(p[0], amount, `admin:${me}`);
    return { balance: market.getPro(p[0]).balance };
  });

  return async (req, res) => {
    const send = (code, data) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(data)); };
    const url = new URL(req.url, 'http://x');
    if (url.pathname === '/healthz') return send(200, { ok: true });
    // The pages poll this and reload when the server was updated; the apps use `apk` to
    // offer a new APK only when the native shell itself changed.
    if (url.pathname === '/api/version') return send(200, version());
    // The apps' APKs, passed through from the release so the repository can stay private.
    const dl = url.pathname.match(/^\/download\/(ProMarket-(?:client|pro)\.apk)$/);
    if (req.method === 'GET' && dl) {
      if (!release) return send(404, { error: 'not_found' });
      try {
        const r = await release.fetchAsset(dl[1]);
        if (!r.ok) return send(r.status === 404 ? 404 : 502, { error: 'download_failed' });
        res.writeHead(200, { 'content-type': 'application/vnd.android.package-archive',
          'content-disposition': `attachment; filename="${dl[1]}"`, ...(r.headers.get('content-length') ? { 'content-length': r.headers.get('content-length') } : {}) });
        for await (const chunk of r.body) res.write(chunk);
        return res.end();
      } catch (e) { console.warn(`[download] ${dl[1]}: ${e.message}`); if (!res.headersSent) return send(502, { error: 'download_failed' }); return res.end(); }
    }
    const v = url.pathname.match(/^\/vendor\/([\w-]+)\/([\w.-]+)\.(js|css|png|svg)$/);
    if (req.method === 'GET' && v) {
      try {
        const file = await readFile(new URL(`../public/vendor/${v[1]}/${v[2]}.${v[3]}`, import.meta.url));
        res.writeHead(200, { 'content-type': VENDOR_TYPES[v[3]], 'cache-control': 'public, max-age=604800' });
        return res.end(file);
      } catch { return send(404, { error: 'not_found' }); }
    }
    const m = url.pathname.match(/^\/media\/([0-9a-f-]{36})$/);
    if (req.method === 'GET' && m) return media.serve(req, res, m[1]);
    if (req.method === 'POST' && url.pathname === '/api/uploads') {
      try {
        const token = auth.verifyToken((req.headers.authorization ?? '').replace(/^Bearer /, ''));
        if (!token || !['client', 'pro'].includes(token.role)) fail('unauthorized', 'Login required');
        const saved = await media.save(req, token.sub);
        onChange();
        return send(200, saved);
      } catch (e) {
        if (e instanceof MarketplaceError) return send({ too_large: 413, bad_type: 415, unauthorized: 401 }[e.code] ?? 400, { error: e.code, message: e.message });
        console.error(e);
        return send(500, { error: 'internal' });
      }
    }
    // Installable web app (iPhone: Share > Add to Home Screen; Android/desktop Chrome: Install)
    if (req.method === 'GET' && (url.pathname === '/install.js' || url.pathname === '/sw.js')) {
      res.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8', 'cache-control': 'no-cache',
        ...(url.pathname === '/sw.js' ? { 'service-worker-allowed': '/' } : {}) });
      return res.end(await readFile(new URL(`../public${url.pathname}`, import.meta.url)));
    }
    const ico = url.pathname.match(/^\/icons\/(client|pro)-(180|192|512)\.png$/);
    if (req.method === 'GET' && ico) {
      try {
        const file = await readFile(new URL(`../public/icons/${ico[1]}-${ico[2]}.png`, import.meta.url));
        res.writeHead(200, { 'content-type': 'image/png', 'cache-control': 'public, max-age=604800' });
        return res.end(file);
      } catch { return send(404, { error: 'not_found' }); }
    }
    const mf = url.pathname.match(/^\/manifest-(client|pro)\.webmanifest$/);
    if (req.method === 'GET' && mf) {
      const pro = mf[1] === 'pro', name = site.name || 'זריז';
      res.writeHead(200, { 'content-type': 'application/manifest+json; charset=utf-8', 'cache-control': 'no-cache' });
      return res.end(JSON.stringify({
        name: pro ? `${name} מקצוענים` : name, short_name: pro ? `${name} מקצוען` : name,
        description: pro ? 'קריאות ועבודות באזור שלכם' : 'בעלי מקצוע וסידורים בקליק',
        start_url: pro ? '/pro' : '/', scope: pro ? '/pro' : '/', display: 'standalone', dir: 'rtl', lang: 'he',
        background_color: pro ? '#12151f' : '#f4f1ea', theme_color: pro ? '#12151f' : '#ff6a00',
        icons: [192, 512].map((n) => ({ src: `/icons/${mf[1]}-${n}.png`, sizes: `${n}x${n}`, type: 'image/png', purpose: 'any' })),
      }));
    }
    if (req.method === 'GET' && LEGAL[url.pathname]) {
      const html = (await readFile(new URL(`../public/legal/${LEGAL[url.pathname]}`, import.meta.url), 'utf8'))
        .replaceAll('{{NAME}}', esc(site.name || 'זריז'))
        .replaceAll('{{EMAIL}}', esc(site.email || '[כתובת אימייל לפניות – להגדיר SUPPORT_EMAIL]'));
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-cache' });
      return res.end(html);
    }
    if (req.method === 'GET' && PAGES[url.pathname]) {
      // no-cache: phones always get the newest pages, so updates need no new APK.
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-cache' });
      return res.end(await readFile(new URL(`../public/${PAGES[url.pathname]}`, import.meta.url)));
    }
    for (const r of routes) {
      const m = r.method === req.method && url.pathname.match(r.re);
      if (!m) continue;
      try {
        let me = null, role = null;
        if (r.role === 'partner') me = partners.authenticate(req.headers['x-api-key']).id;
        else if (r.role) {
          const token = auth.verifyToken((req.headers.authorization ?? '').replace(/^Bearer /, ''));
          if (!token) fail('unauthorized', 'Login required');
          if (![r.role].flat().includes(token.role)) fail('forbidden', `Requires ${r.role} account`);
          if (token.role !== 'admin' && !market.isActive(token.role, token.sub)) fail('unauthorized', 'Account not found');
          me = token.sub; role = token.role;
        }
        let raw = '';
        for await (const c of req) raw += c;
        const body = raw ? JSON.parse(raw) : {};
        const out = await r.fn({ p: m.slice(1), body, query: Object.fromEntries(url.searchParams), me, role, req });
        if (req.method !== 'GET') onChange();
        return send(200, out);
      } catch (e) {
        if (e instanceof MarketplaceError) return send(STATUS[e.code] ?? 400, { error: e.code, message: e.message });
        if (e instanceof SyntaxError) return send(400, { error: 'bad_json' });
        console.error(e);
        return send(500, { error: 'internal' });
      }
    }
    send(404, { error: 'not_found' });
  };
}

export { normalizePhone };
