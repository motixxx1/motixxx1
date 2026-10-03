// Generates one illustration per top-level category into public/img/cat/<id>.svg.
// Run: node tools/gen-category-images.mjs   (re-run after adding a category)
import { writeFileSync, mkdirSync } from 'node:fs';
import { CATEGORIES } from '../src/categories.js';

// id: [emoji, colorA, colorB, pattern]
const LOOK = {
  delivery: ['🛵', '#ff6a00', '#ffb347', 'lines'], errands: ['🛍️', '#f43f5e', '#fb923c', 'dots'],
  plumbing: ['🔧', '#2563eb', '#38bdf8', 'waves'], electric: ['💡', '#f59e0b', '#fde047', 'rays'],
  renovation: ['🏗️', '#b45309', '#f59e0b', 'bricks'], carpentry: ['🪚', '#78350f', '#d97706', 'lines'],
  locksmith: ['🔑', '#334155', '#64748b', 'dots'], hvac: ['❄️', '#0891b2', '#67e8f9', 'rays'],
  appliances: ['🧺', '#6366f1', '#a5b4fc', 'dots'], help: ['🛠️', '#be185d', '#f472b6', 'bricks'],
  cleaning: ['🧹', '#0d9488', '#5eead4', 'bubbles'], garden: ['🌳', '#15803d', '#86efac', 'leaves'],
  pest: ['🐜', '#65a30d', '#bef264', 'dots'], moving: ['🚚', '#16a34a', '#4ade80', 'lines'],
  auto: ['🚗', '#475569', '#94a3b8', 'lines'], computers: ['💻', '#7c3aed', '#c4b5fd', 'grid'],
  digital: ['🎨', '#c026d3', '#f0abfc', 'grid'], legal: ['⚖️', '#1e3a8a', '#60a5fa', 'bricks'],
  professional: ['📊', '#0f766e', '#2dd4bf', 'grid'], tutoring: ['🎓', '#4f46e5', '#818cf8', 'grid'],
  care: ['🐕', '#a16207', '#fcd34d', 'paws'], wellness: ['🧘', '#059669', '#6ee7b7', 'waves'],
  beauty: ['💅', '#db2777', '#f9a8d4', 'bubbles'], events: ['🎉', '#9333ea', '#f472b6', 'confetti'],
  travel: ['✈️', '#0ea5e9', '#7dd3fc', 'clouds'], other: ['✨', '#64748b', '#cbd5e1', 'bubbles'],
};
const rnd = (seed) => () => (seed = (seed * 16807) % 2147483647) / 2147483647;

function pattern(kind, r) {
  const out = [];
  const N = (n, f) => { for (let i = 0; i < n; i++) out.push(f(i)); };
  const W = 400, H = 240;
  if (kind === 'dots') N(28, () => `<circle cx="${r() * W | 0}" cy="${r() * H | 0}" r="${3 + r() * 7 | 0}" fill="#fff" opacity=".18"/>`);
  if (kind === 'bubbles') N(14, () => `<circle cx="${r() * W | 0}" cy="${r() * H | 0}" r="${10 + r() * 28 | 0}" fill="none" stroke="#fff" stroke-width="3" opacity=".3"/>`);
  if (kind === 'lines') N(10, (i) => `<rect x="${-40 + i * 50}" y="-20" width="14" height="320" fill="#fff" opacity=".1" transform="rotate(20 200 120)"/>`);
  if (kind === 'rays') N(14, (i) => `<path d="M200 120 L${200 + 420 * Math.cos(i * 0.449)} ${120 + 420 * Math.sin(i * 0.449)} L${200 + 420 * Math.cos(i * 0.449 + 0.16)} ${120 + 420 * Math.sin(i * 0.449 + 0.16)}Z" fill="#fff" opacity=".13"/>`);
  if (kind === 'waves') N(5, (i) => `<path d="M0 ${150 + i * 22} Q100 ${120 + i * 22} 200 ${150 + i * 22} T400 ${150 + i * 22} V240 H0Z" fill="#fff" opacity=".1"/>`);
  if (kind === 'bricks') N(24, (i) => `<rect x="${(i % 6) * 70 - (i / 6 | 0) % 2 * 35}" y="${(i / 6 | 0) * 60}" width="64" height="26" rx="4" fill="#fff" opacity=".12"/>`);
  if (kind === 'grid') N(11, (i) => `<path d="M${i * 40} 0V240M0 ${i * 24}H400" stroke="#fff" stroke-width="1.5" opacity=".2"/>`);
  if (kind === 'leaves') N(16, () => `<ellipse cx="${r() * W | 0}" cy="${r() * H | 0}" rx="8" ry="18" fill="#fff" opacity=".2" transform="rotate(${r() * 180 | 0} 200 120)"/>`);
  if (kind === 'paws') N(8, () => { const x = r() * W | 0, y = r() * H | 0; return `<g fill="#fff" opacity=".22"><ellipse cx="${x}" cy="${y}" rx="12" ry="10"/><circle cx="${x - 14}" cy="${y - 14}" r="5"/><circle cx="${x}" cy="${y - 19}" r="5"/><circle cx="${x + 14}" cy="${y - 14}" r="5"/></g>`; });
  if (kind === 'confetti') N(34, (i) => `<rect x="${r() * W | 0}" y="${r() * H | 0}" width="8" height="14" rx="2" fill="${['#fff', '#fde047', '#67e8f9', '#fb7185'][i % 4]}" opacity=".6" transform="rotate(${r() * 180 | 0} 200 120)"/>`);
  if (kind === 'clouds') N(5, () => { const x = r() * W | 0, y = r() * 200 | 0; return `<g fill="#fff" opacity=".35"><ellipse cx="${x}" cy="${y}" rx="40" ry="14"/><ellipse cx="${x + 22}" cy="${y - 10}" rx="24" ry="14"/></g>`; });
  return out.join('');
}

mkdirSync(new URL('../public/img/cat/', import.meta.url), { recursive: true });
let n = 0;
for (const c of CATEGORIES) {
  const [emoji, a, b, pat] = LOOK[c.id] ?? LOOK.other;
  const r = rnd(c.id.split('').reduce((s, ch) => s * 31 + ch.charCodeAt(0), 7) % 2147483646 + 1);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 240" role="img" aria-label="${c.name}">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient>
<radialGradient id="s" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#fff" stop-opacity=".55"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient></defs>
<rect width="400" height="240" fill="url(#g)"/>${pattern(pat, r)}
<circle cx="200" cy="120" r="105" fill="url(#s)"/>
<circle cx="200" cy="120" r="74" fill="#fff" opacity=".92"/>
<circle cx="200" cy="120" r="74" fill="none" stroke="${a}" stroke-width="4" opacity=".35"/>
<text x="200" y="146" font-size="82" text-anchor="middle" font-family="'Apple Color Emoji','Segoe UI Emoji','Noto Color Emoji',sans-serif">${emoji}</text>
</svg>\n`;
  writeFileSync(new URL(`../public/img/cat/${c.id}.svg`, import.meta.url), svg);
  n++;
}
console.log(`${n} images`);
