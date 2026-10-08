// Install the web app on the phone's home screen.
// Android / desktop Chrome and Edge: a real one-tap install (the browser's own install prompt).
// iPhone / iPad: Apple lets no website add itself, so the button opens a short visual guide
// with an arrow pointing at the exact button to press in the browser in use.
(() => {
  const me = document.currentScript;
  const app = me?.dataset.app || 'client';
  const name = app === 'pro' ? 'זריז מקצוענים' : 'זריז';
  const icon = `/icons/${app}-180.png`;
  const ua = navigator.userAgent;
  const ios = /iphone|ipad|ipod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const ipad = /ipad/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const chromeIOS = /CriOS|EdgiOS|FxiOS/i.test(ua);
  const safariVer = +(ua.match(/Version\/(\d+)/)?.[1] || 0);
  const standalone = () => navigator.standalone || matchMedia('(display-mode: standalone)').matches;
  const ls = { get: (k) => { try { return localStorage.getItem(k); } catch { return null; } }, set: (k, v) => { try { localStorage.setItem(k, v); } catch {} } };
  let deferred = null;

  if ('serviceWorker' in navigator) addEventListener('load', () => navigator.serviceWorker.register('/sw.js').catch(() => {}));
  addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); deferred = e; changed(); maybeBanner(); });
  addEventListener('appinstalled', () => { deferred = null; document.getElementById('zinst')?.remove(); changed(); });
  const changed = () => dispatchEvent(new Event('zariz-install'));

  const canInstall = () => !standalone() && (!!deferred || ios);
  const css = (el, s) => { el.style.cssText = s; return el; };
  const SHARE = '<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12M8 7l4-4 4 4"/><path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/></svg>';
  const DOTS = '<svg width="26" height="26" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>';
  const ADD = '<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="3" width="18" height="18" rx="4"/><path d="M12 8v8M8 12h8"/></svg>';
  const CHECK = '<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';

  function guide() {
    // where the first button is, per browser
    const newSafari = !chromeIOS && !ipad && safariVer >= 26; // iOS 26: share sits in the ⋯ menu at the bottom
    const top = ipad || chromeIOS;
    const steps = newSafari
      ? [[DOTS, 'לוחצים על <b>⋯</b> בפינה הימנית למטה'], [SHARE, 'בוחרים <b>שיתוף</b>'], [ADD, 'גוללים ובוחרים <b>הוספה למסך הבית</b>'], [CHECK, 'לוחצים <b>הוספה</b>. זהו!']]
      : [[SHARE, top ? 'לוחצים על <b>שיתוף</b> למעלה' : 'לוחצים על <b>שיתוף</b> בסרגל למטה'], [ADD, 'גוללים ובוחרים <b>הוספה למסך הבית</b>'], [CHECK, 'לוחצים <b>הוספה</b>. זהו!']];
    const wrap = css(document.createElement('div'), 'position:fixed;inset:0;z-index:2147483000;background:rgba(10,12,20,.78);direction:rtl;font:500 18px/1.4 Rubik,system-ui,sans-serif;color:#14161f;display:flex;align-items:center;justify-content:center;padding:20px');
    wrap.setAttribute('role', 'dialog'); wrap.setAttribute('aria-label', 'התקנה במסך הבית');
    wrap.innerHTML = `<style>@keyframes zbob{0%,100%{transform:translateY(0)}50%{transform:translateY(14px)}}@keyframes zbobu{0%,100%{transform:translateY(0) rotate(180deg)}50%{transform:translateY(-14px) rotate(180deg)}}</style>
      <div style="width:100%;max-width:400px;background:#fff;border-radius:28px;padding:22px 20px 18px;box-shadow:0 30px 70px rgba(0,0,0,.45)">
        <div style="display:flex;align-items:center;gap:12px;margin-bottom:14px"><img src="${icon}" alt="" width="56" height="56" style="border-radius:14px">
          <div><b style="display:block;font-size:21px">מוסיפים את ${name} למסך הבית</b><span style="font-size:15px;color:#5c5966">פעם אחת, ואז נפתח בלחיצה כמו אפליקציה</span></div></div>
        ${steps.map(([i, t], n) => `<div style="display:flex;align-items:center;gap:14px;padding:10px 0;border-top:1px solid #f0ece4">
          <span style="width:30px;height:30px;border-radius:15px;background:#ff6a00;color:#fff;font-weight:800;font-size:16px;display:flex;align-items:center;justify-content:center;flex:none">${n + 1}</span>
          <span style="flex:1">${t}</span><span style="width:48px;height:48px;border-radius:14px;background:#f2f4f8;color:#0a84ff;display:flex;align-items:center;justify-content:center;flex:none">${i}</span></div>`).join('')}
        <button type="button" style="margin-top:10px;width:100%;min-height:54px;border:0;border-radius:27px;background:#1b1a20;color:#fff;font:inherit;font-weight:800;cursor:pointer">הבנתי</button>
      </div>`;
    // the arrow toward the browser's button
    const arrow = css(document.createElement('div'), `position:fixed;z-index:2147483001;width:64px;height:64px;pointer-events:none;${top
      ? `top:calc(6px + env(safe-area-inset-top));${ipad ? 'right:110px' : 'right:14px'};animation:zbobu 1s ease-in-out infinite`
      : `bottom:calc(10px + env(safe-area-inset-bottom));${newSafari ? 'right:14px' : 'left:calc(50% - 32px)'};animation:zbob 1s ease-in-out infinite`}`);
    arrow.innerHTML = '<svg viewBox="0 0 64 64" width="64" height="64"><circle cx="32" cy="32" r="30" fill="#ff6a00"/><path d="M32 14v30M20 34l12 12 12-12" stroke="#fff" stroke-width="6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    const close = () => { wrap.remove(); arrow.remove(); };
    wrap.querySelector('button').onclick = close;
    wrap.onclick = (e) => { if (e.target === wrap) close(); };
    document.body.append(wrap, arrow);
  }

  async function install() {
    document.getElementById('zinst')?.remove();
    if (deferred) {
      const d = deferred; deferred = null;
      d.prompt();
      try { await d.userChoice; } catch {}
      changed();
      return;
    }
    if (ios) return guide();
    alert('בתפריט הדפדפן בוחרים "התקנת האפליקציה" או "הוספה למסך הבית".');
  }

  function maybeBanner() {
    if (!canInstall() || document.getElementById('zinst')) return;
    const until = +(ls.get('installHintUntil') || 0);
    if (Date.now() < until) return;
    const b = css(document.createElement('div'), 'position:fixed;inset-inline:12px;bottom:calc(96px + env(safe-area-inset-bottom));z-index:95;max-width:520px;margin:0 auto;display:flex;gap:12px;align-items:center;background:#1b1a20;color:#fff;border-radius:22px;padding:12px 12px 12px 14px;box-shadow:0 18px 40px rgba(0,0,0,.35);font:500 15px/1.35 Rubik,system-ui,sans-serif;direction:rtl');
    b.id = 'zinst'; b.setAttribute('role', 'region'); b.setAttribute('aria-label', 'התקנת האפליקציה');
    b.innerHTML = `<img src="${icon}" alt="" width="46" height="46" style="border-radius:12px;flex:none"><span style="flex:1"><b style="display:block;font-size:16px">התקינו את ${name} בטלפון</b>נפתח בלחיצה מהמסך הראשי</span>
      <button type="button" data-go style="min-height:44px;padding:0 18px;border-radius:22px;border:0;background:#ff6a00;color:#fff;font:inherit;font-weight:800;cursor:pointer;flex:none">להתקנה</button>
      <button type="button" data-x aria-label="סגירה" style="width:40px;height:40px;border-radius:20px;border:0;background:#ffffff22;color:#fff;font-size:22px;cursor:pointer;flex:none">×</button>`;
    b.querySelector('[data-go]').onclick = () => { b.remove(); install(); };
    b.querySelector('[data-x]').onclick = () => { b.remove(); ls.set('installHintUntil', String(Date.now() + 7 * 864e5)); };
    document.body.appendChild(b);
  }
  if (ios) addEventListener('load', () => setTimeout(maybeBanner, 2500));

  window.zariz = Object.assign(window.zariz || {}, { install, canInstall });
  // Any element with data-install is the page's own install button: shown only when it can work.
  const sync = () => document.querySelectorAll('[data-install]').forEach((el) => { el.hidden = !canInstall(); });
  addEventListener('zariz-install', sync);
  addEventListener('DOMContentLoaded', sync);
  addEventListener('load', sync);
  document.addEventListener('click', (e) => { if (e.target.closest('[data-install]')) { e.preventDefault(); install(); } });
  window.zariz.sync = sync;
})();
