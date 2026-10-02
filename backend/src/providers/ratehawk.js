// RateHawk / Emerging Travel Group partner API v3 (hotels, net B2B rates).
// Flow: search (SERP by region) -> prebook (locks rate, returns book_hash)
//       -> booking form -> booking finish -> poll finish status.
// Auth: HTTP Basic with KEY_ID:API_KEY from the RateHawk partner account.
// NOTE: field names follow the v3 docs (docs.emergingtravel.com); verify every call
// against the sandbox keys before going live — the docs could not be fetched while
// writing this adapter.
export function rateHawkProvider({ keyId, apiKey, baseUrl = 'https://api.worldota.net/api/b2b/v3',
  currency = 'USD', residency = 'il', language = 'en', fetchImpl = fetch, pollMs = 2000, maxPolls = 30 }) {
  const auth = 'Basic ' + Buffer.from(`${keyId}:${apiKey}`).toString('base64');
  const raw = async (path, body) => {
    const r = await fetchImpl(baseUrl + path, { method: 'POST',
      headers: { authorization: auth, 'content-type': 'application/json' }, body: JSON.stringify(body) });
    return r.json();
  };
  const call = async (path, body) => {
    const res = await raw(path, body);
    if (res.status !== 'ok') throw new Error(`RateHawk ${path}: ${res.error ?? res.status}`);
    return res.data;
  };
  const price = (rate) => {
    const pt = rate.payment_options.payment_types[0];
    return { netPrice: Number(pt.amount), currency: pt.currency_code,
      freeCancellationBefore: pt.cancellation_penalties?.free_cancellation_before ?? null };
  };
  const describe = (hotelId, rate, q) => ({
    title: hotelId.replace(/_/g, ' '), // TODO: real names/photos from the hotel static content dump
    details: [rate.room_name, rate.meal, `${q.checkin} → ${q.checkout}`].filter(Boolean).join(' · '),
  });

  return {
    id: 'ratehawk', kind: 'hotel',
    // query: { regionId, checkin: 'YYYY-MM-DD', checkout, adults = 2, children = [] }
    async search({ regionId, checkin, checkout, adults = 2, children = [], limit = 20 }) {
      const q = { checkin, checkout, adults, children };
      const data = await call('/search/serp/region/', { checkin, checkout, residency, language, currency,
        region_id: Number(regionId), guests: [{ adults: Number(adults), children }] });
      return (data.hotels ?? []).slice(0, limit).map((h) => {
        const rate = h.rates[0];
        const hash = rate.book_hash ?? rate.match_hash;
        return { ref: JSON.stringify({ hotelId: h.id, hash, ...q }), ...describe(h.id, rate, q), ...price(rate) };
      });
    },
    async quote(ref) {
      const r = JSON.parse(ref);
      const data = await call('/hotel/prebook', { hash: r.hash, price_increase_percent: 0 });
      const rate = data.hotels[0].rates[0];
      return { ...describe(r.hotelId, rate, r), ...price(rate), bookHash: rate.book_hash };
    },
    async book(ref, { traveler, partnerOrderId, userIp = '127.0.0.1' }) {
      const r = JSON.parse(ref);
      const { bookHash } = await this.quote(ref);
      const form = await call('/hotel/order/booking/form/', { partner_order_id: partnerOrderId,
        book_hash: bookHash, language, user_ip: userIp });
      const pay = form.payment_types.find((p) => p.type === 'deposit') ?? form.payment_types[0];
      await call('/hotel/order/booking/finish/', {
        user: { email: traveler.email, phone: traveler.phone },
        partner: { partner_order_id: partnerOrderId },
        language,
        rooms: [{ guests: [{ first_name: traveler.firstName, last_name: traveler.lastName }] }],
        payment_type: { type: pay.type, amount: pay.amount, currency_code: pay.currency_code },
      });
      for (let i = 0; i < maxPolls; i++) {
        const st = await raw('/hotel/order/booking/finish/status/', { partner_order_id: partnerOrderId });
        if (st.status === 'ok') return { supplierRef: String(form.order_id ?? partnerOrderId), status: 'confirmed', hotelId: r.hotelId };
        if (st.status !== 'processing') throw new Error(`RateHawk booking failed: ${st.error ?? st.status}`);
        await new Promise((res) => setTimeout(res, pollMs));
      }
      throw new Error('RateHawk booking still processing — check order status manually');
    },
  };
}
