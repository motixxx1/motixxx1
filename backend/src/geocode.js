// Address -> { lat, lng } using OpenStreetMap Nominatim (free; max ~1 request/second,
// must send a real User-Agent). Swap for Google Geocoding when volume grows.
export function nominatimGeocoder({ fetchImpl = fetch, userAgent = 'ProMarket/0.1', country = 'il' } = {}) {
  const cache = new Map();
  return async (address) => {
    const key = String(address ?? '').trim();
    if (!key) return null;
    if (cache.has(key)) return cache.get(key);
    const url = `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=${country}` +
      `&accept-language=he&q=${encodeURIComponent(key)}`;
    const r = await fetchImpl(url, { headers: { 'user-agent': userAgent }, signal: AbortSignal.timeout(5000) });
    const [hit] = r.ok ? await r.json() : [];
    const loc = hit ? { lat: Number(hit.lat), lng: Number(hit.lon) } : null;
    cache.set(key, loc);
    return loc;
  };
}
