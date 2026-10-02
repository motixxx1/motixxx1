import { MarketplaceError } from './marketplace.js';
import { makeFx } from './fx.js';

const fail = (code, msg) => { throw new MarketplaceError(code, msg); };
const money = (n) => Math.round(n * 100) / 100;

// Platform margin on top of the supplier's net price (hotels carry more margin than flights).
export const PLATFORM_MARKUP = { hotel: 0.08, flight: 0.04, activity: 0.1, product: 0.1 };

// Sells supplier inventory (RateHawk, Duffel, our own partner API, ...) through agents and pros:
//   client price = net (in ILS) + platform markup + agent markup
// Agents see only the base price (net + platform markup), never the supplier net.
export class Catalog {
  constructor({ providers = [], fx = makeFx(), markup = PLATFORM_MARKUP, priceTolerance = 0.02 } = {}) {
    this.providers = new Map(providers.map((p) => [p.id, p]));
    Object.assign(this, { fx, markup, priceTolerance });
  }

  list() { return [...this.providers.values()].map(({ id, kind }) => ({ id, kind })); }
  #provider(id) { return this.providers.get(id) ?? fail('bad_provider', `Unknown supplier ${id}`); }

  #price(kind, q) {
    const netILS = this.fx(q.netPrice, q.currency);
    const platformFee = money(netILS * (this.markup[kind] ?? 0.1));
    return { netILS, platformFee, basePrice: money(netILS + platformFee) };
  }

  // For the agent's search screen.
  async search(providerId, query) {
    const p = this.#provider(providerId);
    const results = await p.search(query).catch((e) => fail('supplier_error', e.message));
    return results.map((r) => ({ provider: p.id, kind: r.kind ?? p.kind, ref: r.ref, title: r.title, details: r.details,
      basePrice: this.#price(r.kind ?? p.kind, r).basePrice, freeCancellationBefore: r.freeCancellationBefore ?? null }));
  }

  // Re-quotes every item live from the supplier (never trust client-sent prices).
  async priceItems(items = []) {
    if (!Array.isArray(items) || !items.length) fail('bad_items', 'Items required');
    return Promise.all(items.map(async ({ provider, ref, agentMarkup = 0 }) => {
      const p = this.#provider(provider);
      if (!(agentMarkup >= 0)) fail('bad_markup', 'Markup must be 0 or more');
      const q = await p.quote(ref).catch((e) => fail('supplier_error', e.message));
      const kind = q.kind ?? p.kind;
      const { netILS, platformFee, basePrice } = this.#price(kind, q);
      const agentFee = money(agentMarkup);
      return { provider: p.id, kind, ref, title: q.title, details: q.details,
        net: { amount: q.netPrice, currency: q.currency }, netILS, platformFee, agentFee, basePrice,
        price: money(basePrice + agentFee), freeCancellationBefore: q.freeCancellationBefore ?? null };
    }));
  }

  // Before taking the client's money: the supplier price must not have risen past tolerance.
  async requote(items) {
    const fresh = await this.priceItems(items.map(({ provider, ref, agentFee }) => ({ provider, ref, agentMarkup: agentFee })));
    fresh.forEach((f, i) => {
      if (f.netILS > items[i].netILS * (1 + this.priceTolerance)) {
        fail('price_changed', `המחיר של "${f.title}" עלה אצל הספק – צריך לשלוח הצעה מעודכנת`);
      }
    });
  }

  async book(items, traveler, orderId) {
    const out = [];
    try {
      for (const [i, it] of items.entries()) {
        const res = await this.#provider(it.provider).book(it.ref, { traveler, partnerOrderId: `${orderId}-${i}` });
        out.push({ provider: it.provider, ref: it.ref, title: it.title, ...res });
      }
    } catch (e) {
      // Partial bookings (e.g. flight booked, hotel failed) need manual cancel/refund by support.
      throw Object.assign(new MarketplaceError('booking_failed', e.message), { booked: out });
    }
    return out;
  }
}
