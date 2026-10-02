import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Marketplace } from '../src/marketplace.js';
import { Catalog } from '../src/catalog.js';
import { mockProvider } from '../src/providers/mock.js';
import { makeFx } from '../src/fx.js';

function setup() {
  const hotels = mockProvider({ id: 'h', kind: 'hotel' });
  const flights = mockProvider({ id: 'f', kind: 'flight' });
  const catalog = new Catalog({ providers: [hotels, flights], fx: makeFx({ ILS: 1, USD: 4 }, 0) });
  const m = new Marketplace({ welcomeCredit: 50 });
  const client = m.registerClient({ phone: '050', name: 'נועה' });
  const agent = m.registerPro({ phone: '052', name: 'סוכנת נסיעות', categories: ['travel'] });
  m.setAvailability(agent.id, true);
  const job = m.createJob({ clientId: client.id, categoryId: 'travel.package', mode: 'remote',
    description: 'אתונה, 2 מבוגרים, סוף שבוע' });
  return { hotels, flights, catalog, m, client, agent, job };
}

test('travel jobs are forced to in-app payment and reach agents nationwide', () => {
  const { job, agent } = setup();
  assert.equal(job.paymentMode, 'in_app');
  assert.deepEqual(job.dispatchedTo, [agent.id]);
});

test('agent sees base price (net + platform markup) but never the supplier net', async () => {
  const { catalog } = setup();
  const [hotel] = await catalog.search('h', {});
  assert.equal(hotel.basePrice, 518.4); // 120 USD * 4 = 480 + 8%
  assert.equal(hotel.netPrice, undefined);
  const [priced] = await catalog.priceItems([{ provider: 'h', ref: 'hotel-a', agentMarkup: 100 }]);
  assert.deepEqual([priced.netILS, priced.platformFee, priced.agentFee, priced.price], [480, 38.4, 100, 618.4]);
});

test('package offer -> accept -> supplier booking -> escrow split', async () => {
  const { catalog, m, client, agent, job } = setup();
  const items = await catalog.priceItems([
    { provider: 'f', ref: 'flight-a', agentMarkup: 50 },   // 310 USD = 1240 + 4% = 1289.6 + 50
    { provider: 'h', ref: 'hotel-a', agentMarkup: 100 },   // 618.4
  ]);
  const sent = m.sendOffer(job.id, agent.id, { items, message: 'טיסה ישירה + מלון על הים' });
  assert.equal(sent.myOffer.price, 1958);
  assert.equal(sent.myOffer.items[0].netILS, undefined);
  const offer = m.jobs.get(job.id).offers[0];
  assert.throws(() => m.acceptOffer(job.id, client.id, offer.id), /Traveler/);
  const traveler = { firstName: 'Noa', lastName: 'Levi', email: 'n@x.com', phone: '972500000000' };
  await catalog.requote(offer.items);
  m.acceptOffer(job.id, client.id, offer.id, { traveler });
  assert.deepEqual(m.jobs.get(job.id).escrow.breakdown, { supplier: 1720, platformFee: 88, agentFee: 150 });
  assert.throws(() => m.advance(job.id, agent.id, 'in_progress'), /not confirmed/);
  m.bookingConfirmed(job.id, await catalog.book(offer.items, traveler, job.id));
  m.advance(job.id, agent.id, 'in_progress');
  m.advance(job.id, agent.id, 'completed');
  const done = m.confirmCompletion(job.id, client.id);
  // platform: 88 markup + 12% of 150 = 106; agent: 150 - 18 = 132
  assert.equal(done.escrow.fee, 106);
  assert.equal(done.escrow.payout, 132);
  const [view] = m.clientJobs(client.id, client.id);
  assert.equal(view.offers[0].items[0].netILS, undefined);
  assert.equal(view.escrow.breakdown, undefined);
});

test('supplier price rise blocks the sale; failed booking refunds the client', async () => {
  const { catalog, hotels, m, client, agent, job } = setup();
  const items = await catalog.priceItems([{ provider: 'h', ref: 'hotel-b' }]);
  m.sendOffer(job.id, agent.id, { items });
  hotels.setPrice('hotel-b', 130);
  await assert.rejects(catalog.requote(items), /עלה/);
  hotels.setPrice('hotel-b', 95);
  await catalog.requote(items);
  const offer = m.jobs.get(job.id).offers[0];
  m.acceptOffer(job.id, client.id, offer.id, { traveler: { firstName: 'a', lastName: 'b', email: 'c' } });
  const failed = m.bookingFailed(job.id, 'sold out');
  assert.equal(failed.escrow.status, 'refunded');
  assert.equal(failed.status, 'booking_failed');
});

test('RateHawk adapter maps search, prebook and booking calls', async () => {
  const { rateHawkProvider } = await import('../src/providers/ratehawk.js');
  const calls = [];
  const rate = { book_hash: 'bh1', room_name: 'Double', meal: 'breakfast',
    payment_options: { payment_types: [{ amount: '200.00', currency_code: 'EUR', type: 'deposit',
      cancellation_penalties: { free_cancellation_before: '2026-11-01T00:00:00' } }] } };
  const responses = {
    '/search/serp/region/': { status: 'ok', data: { hotels: [{ id: 'grand_hotel_athens', rates: [rate] }] } },
    '/hotel/prebook': { status: 'ok', data: { hotels: [{ rates: [rate] }] } },
    '/hotel/order/booking/form/': { status: 'ok', data: { order_id: 777, payment_types: [{ type: 'deposit', amount: '200.00', currency_code: 'EUR' }] } },
    '/hotel/order/booking/finish/': { status: 'ok', data: null },
    '/hotel/order/booking/finish/status/': { status: 'ok', data: { percent: 100 } },
  };
  const fetchImpl = async (url, init) => {
    const path = url.replace('https://api.worldota.net/api/b2b/v3', '');
    calls.push({ path, body: JSON.parse(init.body), auth: init.headers.authorization });
    return { json: async () => responses[path] };
  };
  const rh = rateHawkProvider({ keyId: '1', apiKey: 'k', fetchImpl, pollMs: 0 });
  const [h] = await rh.search({ regionId: 2563, checkin: '2026-11-10', checkout: '2026-11-12', adults: 2 });
  assert.equal(h.netPrice, 200);
  assert.equal(h.currency, 'EUR');
  assert.equal(calls[0].body.region_id, 2563);
  assert.equal(calls[0].auth, 'Basic ' + Buffer.from('1:k').toString('base64'));
  const res = await rh.book(h.ref, { traveler: { firstName: 'A', lastName: 'B', email: 'e', phone: 'p' }, partnerOrderId: 'job-0' });
  assert.equal(res.supplierRef, '777');
  assert.equal(calls.find((c) => c.path === '/hotel/order/booking/form/').body.book_hash, 'bh1');
});

test('catalog items cannot be sold on a direct-payment job', async () => {
  const { catalog, m, client, agent } = setup();
  m.updateProfile(agent.id, { categories: ['travel', 'computers'] });
  const job = m.createJob({ clientId: client.id, categoryId: 'computers.network', mode: 'remote', description: 'ראוטר חדש' });
  const items = await catalog.priceItems([{ provider: 'h', ref: 'hotel-a' }]);
  assert.throws(() => m.sendOffer(job.id, agent.id, { items }), /in-app/);
});
