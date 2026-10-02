import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { MarketplaceError } from './marketplace.js';

const fail = (code, msg) => { throw new MarketplaceError(code, msg); };
const sha = (s) => createHash('sha256').update(String(s)).digest('hex');
export const PRODUCT_KINDS = ['hotel', 'flight', 'activity', 'product'];

// Our own supplier API (the "RateHawk" of this platform): hotels, B&Bs, tour operators,
// attraction sites and shops publish net-priced products; agents and pros resell them
// with their own markup. Exposed to the Catalog as the 'partners' provider.
export class Partners {
  constructor() {
    this.partners = new Map();
    this.products = new Map();
    this.bookings = [];
  }

  // Admin creates the partner; the API key is shown once and stored only as a hash.
  create({ name, webhookUrl = null }) {
    if (!name) fail('bad_name', 'Partner name required');
    const apiKey = 'pk_' + randomBytes(24).toString('hex');
    const partner = { id: randomUUID(), name, webhookUrl, keyHash: sha(apiKey), createdAt: Date.now() };
    this.partners.set(partner.id, partner);
    return { id: partner.id, name, apiKey };
  }
  authenticate(apiKey) {
    const h = sha(apiKey ?? '');
    return [...this.partners.values()].find((p) => p.keyHash === h) ?? fail('unauthorized', 'Invalid API key');
  }

  upsertProduct(partnerId, data, productId = null) {
    const existing = productId && this.products.get(productId);
    if (productId && existing?.partnerId !== partnerId) fail('not_found', 'Product not found');
    const p = { ...(existing ?? { id: randomUUID(), partnerId, createdAt: Date.now() }), ...pick(data) };
    if (!PRODUCT_KINDS.includes(p.kind)) fail('bad_kind', `kind must be one of ${PRODUCT_KINDS.join(', ')}`);
    if (!p.title) fail('bad_title', 'title required');
    if (!(p.netPrice > 0)) fail('bad_price', 'netPrice must be positive');
    if (!/^[A-Z]{3}$/.test(p.currency ?? '')) fail('bad_currency', 'currency must be ISO code, e.g. ILS');
    if (p.stock != null && !(Number.isInteger(p.stock) && p.stock >= 0)) fail('bad_stock', 'stock must be a whole number');
    p.active = p.active ?? true;
    this.products.set(p.id, p);
    return p;
  }
  listProducts(partnerId) { return [...this.products.values()].filter((p) => p.partnerId === partnerId); }
  deactivate(partnerId, productId) { return this.upsertProduct(partnerId, { active: false }, productId); }
  partnerBookings(partnerId) { return this.bookings.filter((b) => b.partnerId === partnerId); }

  provider() {
    const self = this;
    const view = (p) => ({ ref: p.id, kind: p.kind, title: p.title,
      details: [self.partners.get(p.partnerId)?.name, p.details, p.location].filter(Boolean).join(' · '),
      netPrice: p.netPrice, currency: p.currency });
    const live = (id) => {
      const p = self.products.get(id);
      if (!p?.active || p.stock === 0) throw new Error('המוצר כבר לא זמין');
      return p;
    };
    return {
      id: 'partners', kind: 'mixed',
      async search({ kind, q = '' } = {}) {
        return [...self.products.values()]
          .filter((p) => p.active && p.stock !== 0 && (!kind || p.kind === kind)
            && (!q || `${p.title} ${p.details ?? ''} ${p.location ?? ''}`.includes(q)))
          .map(view);
      },
      async quote(ref) { return view(live(ref)); },
      // Stock is reserved synchronously; the partner is paid its net price at settlement.
      async book(ref, { partnerOrderId, traveler }) {
        const p = live(ref);
        if (p.stock != null) p.stock -= 1;
        const booking = { id: randomUUID(), partnerId: p.partnerId, productId: p.id, title: p.title, partnerOrderId,
          customer: traveler && { firstName: traveler.firstName, lastName: traveler.lastName, email: traveler.email, phone: traveler.phone },
          net: { amount: p.netPrice, currency: p.currency }, status: 'confirmed', at: Date.now() };
        self.bookings.push(booking);
        // TODO: POST booking to partner.webhookUrl (signed), retry with backoff.
        return { supplierRef: booking.id, status: 'confirmed' };
      },
    };
  }
}

const FIELDS = ['kind', 'title', 'details', 'location', 'netPrice', 'currency', 'stock', 'availableFrom', 'availableTo', 'imageUrl', 'active'];
function pick(data = {}) {
  const out = {};
  for (const f of FIELDS) if (data[f] !== undefined) out[f] = data[f];
  if (out.netPrice !== undefined) out.netPrice = Number(out.netPrice);
  return out;
}
