// Deterministic supplier for development and tests. Same interface as real adapters:
//   search(query) -> [{ ref, title, details, netPrice, currency }]
//   quote(ref)    -> { netPrice, currency, title, details }   (re-validate before selling)
//   book(ref, { traveler, partnerOrderId }) -> { supplierRef, status }
export function mockProvider({ id = 'mock', kind = 'hotel' } = {}) {
  const prices = new Map();
  const catalog = kind === 'hotel'
    ? [['hotel-a', 'מלון חוף הים ★★★★', 120], ['hotel-b', 'מלון בוטיק במרכז העיר ★★★', 95], ['hotel-c', 'ריזורט הכל כלול ★★★★★', 260]]
    : [['flight-a', 'טיסה ישירה – חברה א׳', 310], ['flight-b', 'טיסה עם עצירה – חברה ב׳', 220]];
  for (const [ref, , price] of catalog) prices.set(ref, price);
  const item = (ref) => {
    const row = catalog.find((c) => c[0] === ref);
    if (!row) throw new Error(`Unknown ${id} ref ${ref}`);
    return { ref, title: row[1], details: kind === 'hotel' ? 'לילה, ארוחת בוקר' : 'מחלקת תיירים, כולל מזוודה', netPrice: prices.get(ref), currency: 'USD' };
  };
  return {
    id, kind,
    async search() { return catalog.map(([ref]) => item(ref)); },
    async quote(ref) { return item(ref); },
    async book(ref, { partnerOrderId }) { item(ref); return { supplierRef: `MOCK-${partnerOrderId}`, status: 'confirmed' }; },
    setPrice(ref, price) { prices.set(ref, price); }, // test helper: simulate supplier price change
  };
}
