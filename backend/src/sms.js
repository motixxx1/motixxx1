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

// SMSAPI (smsapi.com): OAuth token from the SMSAPI panel. `from` must be a sender name verified
// there; without it the account's default sender is used. test=true checks requests without sending.
export function smsapiSms({ token, from = '', test = false, fetchImpl = fetch }) {
  return async (phone, text) => {
    const params = new URLSearchParams({ to: phone, message: text, format: 'json', encoding: 'utf-8' });
    if (from) params.set('from', from);
    if (test) params.set('test', '1');
    let last;
    for (const host of ['https://api.smsapi.com', 'https://api2.smsapi.com']) {
      try {
        const r = await fetchImpl(`${host}/sms.do`, { method: 'POST',
          headers: { authorization: `Bearer ${token}`, 'content-type': 'application/x-www-form-urlencoded' }, body: params });
        const body = await r.text();
        let data = null; try { data = JSON.parse(body); } catch {}
        if (!r.ok || data?.error) throw Object.assign(new Error(`SMS failed: ${data?.error ?? r.status} ${data?.message ?? body}`), { final: r.status < 500 });
        return;
      } catch (e) { last = e; if (e.final) break; }
    }
    throw last;
  };
}

// SMS4Free (sms4free.co.il): API key from the account, the account's mobile number (user) and
// password (pass), and the sender (a name or number approved in the account). The reply is a
// number: the count of messages sent, or a negative error code.
export function sms4freeSms({ key, user, pass, sender, url = 'https://api.sms4free.co.il/ApiSMS/v2/SendSMS', fetchImpl = fetch }) {
  const local = (p) => (String(p).startsWith('972') ? '0' + String(p).slice(3) : String(p));
  return async (phone, text) => {
    const body = JSON.stringify({ key, user: local(user.replace(/\D/g, '')), pass, sender, recipient: local(phone), msg: text });
    let r = await fetchImpl(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body });
    if (r.status === 404 && url.includes('/v2/')) r = await fetchImpl(url.replace('/v2/', '/'), { method: 'POST', headers: { 'content-type': 'application/json' }, body });
    const raw = await r.text();
    let data = raw; try { data = JSON.parse(raw); } catch {}
    const code = typeof data === 'number' ? data : Number(data?.status ?? data?.d ?? data);
    if (!r.ok || !(code > 0)) {
      const why = { '-1': 'key, user or pass is wrong', '-2': 'sender not approved', '-3': 'recipient invalid', '-4': 'no SMS left in the package', '-5': 'message invalid' }[String(code)] ?? '';
      throw new Error(`SMS failed: ${r.status} ${raw.slice(0, 200)} ${why}`);
    }
  };
}

// Any SMS gateway with an HTTP API (most Israeli providers: 019, InforU, Cellact, Micropay...).
// The URL / body are templates: {phone} = 972501234567, {phone0} = 0501234567, {text} = the message.
//   SMS_HTTP_URL=https://gateway.example/send?user=X&pass=Y&to={phone0}&msg={text}   (GET)
//   SMS_HTTP_METHOD=POST  SMS_HTTP_BODY={"to":"{phone}","message":"{text}"}  SMS_HTTP_HEADERS={"Authorization":"Basic ..."}
export function httpSms({ url, method = 'GET', body = '', headers = {}, fetchImpl = fetch }) {
  const fill = (tpl, phone, text, enc) => tpl
    .replaceAll('{phone0}', enc(phone.startsWith('972') ? '0' + phone.slice(3) : phone))
    .replaceAll('{phone}', enc(phone)).replaceAll('{text}', enc(text));
  const jsonEsc = (s) => JSON.stringify(s).slice(1, -1);
  return async (phone, text) => {
    const r = await fetchImpl(fill(url, phone, text, encodeURIComponent), {
      method, headers: { ...(method === 'POST' && { 'content-type': body.trim().startsWith('{') ? 'application/json' : 'application/x-www-form-urlencoded' }), ...headers },
      body: method === 'POST' ? fill(body, phone, text, body.trim().startsWith('{') ? jsonEsc : encodeURIComponent) : undefined,
    });
    if (!r.ok) throw new Error(`SMS failed: ${r.status} ${await r.text()}`);
  };
}
