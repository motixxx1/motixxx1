import { mockProvider } from './mock.js';
import { rateHawkProvider } from './ratehawk.js';
import { duffelProvider } from './duffel.js';

// Builds the supplier registry from environment variables. Mock suppliers are
// available only in development so agents can try the flow without real contracts.
export function providersFromEnv(env = process.env, { dev = false } = {}) {
  const list = [];
  if (env.RATEHAWK_KEY_ID && env.RATEHAWK_API_KEY) {
    list.push(rateHawkProvider({ keyId: env.RATEHAWK_KEY_ID, apiKey: env.RATEHAWK_API_KEY,
      baseUrl: env.RATEHAWK_BASE_URL || undefined }));
  }
  if (env.DUFFEL_TOKEN) list.push(duffelProvider({ token: env.DUFFEL_TOKEN }));
  if (dev) list.push(mockProvider({ id: 'mock-hotels', kind: 'hotel' }), mockProvider({ id: 'mock-flights', kind: 'flight' }));
  return list;
}
