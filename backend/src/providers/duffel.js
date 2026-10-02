// Duffel flights API (v2). Flow: offer request -> fresh offer (price check) -> order.
// Payment type 'balance' draws from the platform's prepaid Duffel balance.
// NOTE: verify against Duffel test mode ("duffel_test_..." token) before going live.
export function duffelProvider({ token, baseUrl = 'https://api.duffel.com', fetchImpl = fetch }) {
  const call = async (method, path, body) => {
    const r = await fetchImpl(baseUrl + path, { method, headers: {
      authorization: `Bearer ${token}`, 'duffel-version': 'v2', accept: 'application/json',
      'content-type': 'application/json' }, body: body && JSON.stringify({ data: body }) });
    const res = await r.json();
    if (!r.ok) throw new Error(`Duffel ${path}: ${res.errors?.[0]?.message ?? r.status}`);
    return res.data;
  };
  const describe = (o) => ({
    title: `${o.owner.name} · ${o.slices.map((s) => `${s.origin.iata_code}→${s.destination.iata_code}`).join(' / ')}`,
    details: o.slices.map((s) => `${s.segments[0].departing_at.slice(0, 16).replace('T', ' ')} · ${s.segments.length - 1 ? `${s.segments.length - 1} עצירות` : 'ישירה'}`).join(' | '),
    netPrice: Number(o.total_amount), currency: o.total_currency,
  });

  return {
    id: 'duffel', kind: 'flight',
    // query: { origin: 'TLV', destination: 'ATH', departureDate, returnDate?, adults = 1, cabinClass }
    async search({ origin, destination, departureDate, returnDate, adults = 1, cabinClass = 'economy', limit = 20 }) {
      const slices = [{ origin, destination, departure_date: departureDate }];
      if (returnDate) slices.push({ origin: destination, destination: origin, departure_date: returnDate });
      const data = await call('POST', '/air/offer_requests?return_offers=true', {
        slices, passengers: Array.from({ length: Number(adults) }, () => ({ type: 'adult' })), cabin_class: cabinClass });
      return data.offers.sort((a, b) => a.total_amount - b.total_amount).slice(0, limit)
        .map((o) => ({ ref: o.id, ...describe(o) }));
    },
    async quote(ref) { return describe(await call('GET', `/air/offers/${ref}`)); },
    // MVP books a single adult traveler.
    async book(ref, { traveler }) {
      const offer = await call('GET', `/air/offers/${ref}`);
      const order = await call('POST', '/air/orders', {
        type: 'instant',
        selected_offers: [ref],
        passengers: [{ id: offer.passengers[0].id, given_name: traveler.firstName, family_name: traveler.lastName,
          born_on: traveler.bornOn, gender: traveler.gender, title: traveler.gender === 'f' ? 'ms' : 'mr',
          email: traveler.email, phone_number: traveler.phone }],
        payments: [{ type: 'balance', amount: offer.total_amount, currency: offer.total_currency }],
      });
      return { supplierRef: order.booking_reference, status: 'confirmed', orderId: order.id };
    },
  };
}
