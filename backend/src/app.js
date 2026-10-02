import { readFile } from 'node:fs/promises';
import { Marketplace, MarketplaceError } from './marketplace.js';
import { CATEGORIES, searchCategories } from './categories.js';

// Minimal router. Auth (OTP/JWT) is stubbed: callers pass x-user-id.
export function createApp(market = new Marketplace()) {
  const routes = [];
  const on = (method, path, fn) => routes.push({ method, re: new RegExp('^' + path.replace(/:\w+/g, '([^/]+)') + '$'), fn });
  const pub = (j) => market.teaser(j);

  on('GET', '/api/categories', ({ query }) => query.q ? searchCategories(query.q) : CATEGORIES);
  on('POST', '/api/pros', ({ body }) => market.registerPro(body));
  on('POST', '/api/clients', ({ body }) => market.registerClient(body));
  on('POST', '/api/pros/:id/documents', ({ p, body }) => market.uploadDocument(p[0], body));
  on('PUT', '/api/pros/:id/availability', ({ p, body }) => (market.setAvailability(p[0], body.available), { ok: true }));
  on('PUT', '/api/pros/:id/location', ({ p, body }) => (market.updateLocation(p[0], body), { ok: true }));
  on('POST', '/api/pros/:id/wallet/topup', ({ p, body }) => market.topUp(p[0], body.amount, body.method));
  on('GET', '/api/pros/:id/wallet', ({ p }) => ({ balance: market.pros.get(p[0])?.balance, history: market.history(p[0]) }));
  on('GET', '/api/pros/:id/feed', ({ p, query }) => market.feed(p[0], {
    maxKm: query.maxKm && +query.maxKm, urgency: query.urgency, mode: query.mode }));
  on('GET', '/api/pros/:id/jobs', ({ p, user }) => market.proJobs(p[0], user));
  // Client: open a request, get offers, accept one
  on('GET', '/api/jobs', ({ query }) => [...market.jobs.values()]
    .filter((j) => j.status === 'open' && (!query.category || j.categoryId.startsWith(query.category))
      && (!query.mode || j.mode === query.mode))
    .sort((a, b) => b.createdAt - a.createdAt).map(pub));
  on('POST', '/api/jobs', ({ body, user }) => pub(market.createJob({ ...body, clientId: user })));
  on('GET', '/api/clients/:id/jobs', ({ p, user }) => market.clientJobs(p[0], user));
  on('POST', '/api/jobs/:id/offers', ({ p, user, body }) => market.sendOffer(p[0], user, body));
  on('POST', '/api/jobs/:id/offers/:offer/accept', ({ p, user }) => pub(market.acceptOffer(p[0], user, p[1])));
  // Work: documentation + status
  on('POST', '/api/jobs/:id/log', ({ p, user, body }) => market.addLog(p[0], user, body));
  on('POST', '/api/jobs/:id/status', ({ p, user, body }) => pub(market.advance(p[0], user, body.status, body)));
  on('POST', '/api/jobs/:id/confirm', ({ p, user }) => pub(market.confirmCompletion(p[0], user)));
  on('POST', '/api/jobs/:id/rate', ({ p, user, body }) => market.rate(p[0], user, body.score, body.text));
  // Admin
  on('GET', '/api/admin/pending-documents', () => [...market.pros.values()].flatMap((pro) =>
    pro.documents.filter((d) => d.status === 'pending').map((d) => ({ proId: pro.id, proName: pro.name, ...d }))));
  on('POST', '/api/admin/pros/:id/documents/:doc/approve', ({ p }) => market.approveDocument(p[0], p[1]));

  return async (req, res) => {
    const url = new URL(req.url, 'http://x');
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      return res.end(await readFile(new URL('../public/index.html', import.meta.url)));
    }
    const send = (code, data) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(data)); };
    for (const r of routes) {
      const m = r.method === req.method && url.pathname.match(r.re);
      if (!m) continue;
      try {
        let raw = '';
        for await (const c of req) raw += c;
        const body = raw ? JSON.parse(raw) : {};
        const out = r.fn({ p: m.slice(1), body, query: Object.fromEntries(url.searchParams), user: req.headers['x-user-id'] });
        return send(200, out);
      } catch (e) {
        if (e instanceof MarketplaceError) return send({ not_found: 404, forbidden: 403 }[e.code] ?? 400, { error: e.code, message: e.message });
        if (e instanceof SyntaxError) return send(400, { error: 'bad_json' });
        console.error(e);
        return send(500, { error: 'internal' });
      }
    }
    send(404, { error: 'not_found' });
  };
}
