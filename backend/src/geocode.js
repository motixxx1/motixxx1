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

// Coordinates -> street address (for "use my location"), via Nominatim.
export function nominatimReverse({ fetchImpl = fetch, userAgent = 'Zariz/1.0' } = {}) {
  return async ({ lat, lng }) => {
    const url = `https://nominatim.openstreetmap.org/reverse?format=json&zoom=18&accept-language=he&lat=${lat}&lon=${lng}`;
    const r = await fetchImpl(url, { headers: { 'user-agent': userAgent }, signal: AbortSignal.timeout(5000) });
    if (!r.ok) return null;
    const a = (await r.json()).address ?? {};
    const street = [a.road, a.house_number].filter(Boolean).join(' ');
    const city = a.city ?? a.town ?? a.village ?? a.suburb ?? '';
    return [street, city].filter(Boolean).join(', ') || null;
  };
}

// MapTiler (with MAPTILER_KEY): better Hebrew addresses, same interface as above.
export function maptilerGeocoder({ key, fetchImpl = fetch } = {}) {
  const cache = new Map();
  return async (address) => {
    const q = String(address ?? '').trim();
    if (!q) return null;
    if (cache.has(q)) return cache.get(q);
    const r = await fetchImpl(`https://api.maptiler.com/geocoding/${encodeURIComponent(q)}.json?key=${key}&country=il&language=he&limit=1`,
      { signal: AbortSignal.timeout(5000) });
    const f = r.ok ? (await r.json()).features?.[0] : null;
    const loc = f?.center ? { lat: f.center[1], lng: f.center[0] } : null;
    cache.set(q, loc);
    return loc;
  };
}
export function maptilerReverse({ key, fetchImpl = fetch } = {}) {
  return async ({ lat, lng }) => {
    const r = await fetchImpl(`https://api.maptiler.com/geocoding/${lng},${lat}.json?key=${key}&language=he&limit=1`,
      { signal: AbortSignal.timeout(5000) });
    const f = r.ok ? (await r.json()).features?.[0] : null;
    return f?.place_name?.replace(/, ישראל$/, '') ?? null;
  };
}

// Address suggestions while typing (public address data): [{ label, lat, lng }].
const short = new Map();
function cached(key, ms, fn) {
  const hit = short.get(key);
  if (hit && Date.now() - hit.at < ms) return hit.v;
  const v = fn().catch(() => []);
  short.set(key, { at: Date.now(), v });
  if (short.size > 2000) short.delete(short.keys().next().value);
  return v;
}
export function maptilerSuggest({ key, fetchImpl = fetch } = {}) {
  return (q) => cached('m:' + q, 3600_000, async () => {
    const r = await fetchImpl(`https://api.maptiler.com/geocoding/${encodeURIComponent(q)}.json?key=${key}&country=il&language=he&limit=6&autocomplete=true`,
      { signal: AbortSignal.timeout(4000) });
    if (!r.ok) return [];
    return ((await r.json()).features ?? []).filter((f) => f.center).map((f) => ({
      label: String(f.place_name ?? f.text ?? '').replace(/, ישראל$/, ''), lat: f.center[1], lng: f.center[0] }));
  });
}
export function nominatimSuggest({ fetchImpl = fetch, userAgent = 'Zariz/1.0' } = {}) {
  return (q) => cached('n:' + q, 3600_000, async () => {
    const r = await fetchImpl(`https://nominatim.openstreetmap.org/search?format=json&limit=6&countrycodes=il&accept-language=he&addressdetails=1&q=${encodeURIComponent(q)}`,
      { headers: { 'user-agent': userAgent }, signal: AbortSignal.timeout(4000) });
    if (!r.ok) return [];
    return (await r.json()).map((h) => {
      const a = h.address ?? {};
      const street = [a.road ?? a.pedestrian ?? a.amenity ?? h.name, a.house_number].filter(Boolean).join(' ');
      const city = a.city ?? a.town ?? a.village ?? a.suburb ?? '';
      return { label: [street, city].filter(Boolean).join(', ') || h.display_name, lat: Number(h.lat), lng: Number(h.lon) };
    }).filter((x, i, all) => all.findIndex((y) => y.label === x.label) === i);
  });
}

// Map tiles for the apps. With a MapTiler key: MapTiler streets (light) / dark.
// Without: OpenStreetMap (fine for testing; heavy use needs a tile provider).
export function mapTiles(key) {
  return key
    ? { light: `https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=${key}`,
        dark: `https://api.maptiler.com/maps/streets-v2-dark/256/{z}/{x}/{y}.png?key=${key}`,
        attribution: '© MapTiler © OpenStreetMap' }
    : null;
}
