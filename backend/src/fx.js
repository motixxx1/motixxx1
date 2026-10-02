// Currency conversion to ILS. Static table for development; production should load
// daily rates (e.g. Bank of Israel representative rates) and add a buffer for FX risk.
const DEFAULT_RATES = { ILS: 1, USD: 3.7, EUR: 4.0, GBP: 4.7 };

export function makeFx(rates = DEFAULT_RATES, buffer = 0.02) {
  return (amount, currency) => {
    const rate = rates[currency];
    if (!rate) throw new Error(`No FX rate for ${currency}`);
    return Math.round(amount * rate * (currency === 'ILS' ? 1 : 1 + buffer) * 100) / 100;
  };
}
