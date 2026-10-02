// Twilio SMS (works for Israeli numbers). Any provider with the same signature can replace it:
//   sendSms(phoneE164Digits, text) => Promise
export function twilioSms({ accountSid, authToken, from, fetchImpl = fetch }) {
  const auth = 'Basic ' + Buffer.from(`${accountSid}:${authToken}`).toString('base64');
  return async (phone, text) => {
    const r = await fetchImpl(`https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`, {
      method: 'POST',
      headers: { authorization: auth, 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ To: `+${phone}`, From: from, Body: text }),
    });
    if (!r.ok) throw new Error(`SMS failed: ${r.status} ${await r.text()}`);
  };
}
