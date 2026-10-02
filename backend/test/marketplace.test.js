import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Marketplace, MAX_CLAIMS } from '../src/marketplace.js';

const TLV = { lat: 32.0853, lng: 34.7818 };
const BEERSHEBA = { lat: 31.2518, lng: 34.7913 };

function setup() {
  const pushes = [];
  const m = new Marketplace({ notify: (id, msg) => pushes.push({ id, msg }) });
  const client = m.registerClient({ phone: '050', name: 'דנה' });
  const mkPro = (cats, loc = TLV, credit = 100) => {
    const p = m.registerPro({ phone: '052', name: 'pro', categories: cats, location: loc, radiusKm: 20 });
    m.setAvailability(p.id, true);
    if (credit) m.topUp(p.id, credit);
    return p;
  };
  const job = (cat = 'plumbing.unclog', loc = TLV) => m.createJob({ clientId: client.id, categoryId: cat,
    description: 'סתימה', location: loc, address: 'הרצל 1', phone: '050' });
  return { m, client, mkPro, job, pushes };
}

test('dispatch targets only available, matching, nearby, funded pros', () => {
  const { m, mkPro, job, pushes } = setup();
  const good = mkPro(['plumbing']);
  mkPro(['plumbing'], BEERSHEBA);         // too far
  mkPro(['locksmith']);                   // wrong category
  mkPro(['plumbing'], TLV, 0);            // no credit
  const off = mkPro(['plumbing']); m.setAvailability(off.id, false);
  const j = job();
  assert.deepEqual(j.dispatchedTo, [good.id]);
  assert.equal(pushes.length, 1);
});

test('licensed category blocked until admin approves document', () => {
  const { m, mkPro, job } = setup();
  const pro = mkPro(['electric']);
  assert.equal(job('electric.short').dispatchedTo.length, 0);
  const doc = m.uploadDocument(pro.id, { type: 'license', url: 's3://x' });
  m.approveDocument(pro.id, doc.id);
  assert.deepEqual(job('electric.short').dispatchedTo, [pro.id]);
});

test('teaser hides contact until claim; claim charges credit', () => {
  const { m, mkPro, job } = setup();
  const pro = mkPro(['plumbing']);
  const j = job();
  assert.equal(m.feed(pro.id)[0].phone, undefined);
  const claimed = m.claim(j.id, pro.id);
  assert.equal(claimed.phone, '050');
  assert.equal(m.pros.get(pro.id).balance, 100 - j.leadPrice);
  assert.throws(() => m.claim(j.id, pro.id), /Already/);
});

test('job closes after MAX_CLAIMS and disappears from feed', () => {
  const { m, mkPro, job } = setup();
  const pros = Array.from({ length: MAX_CLAIMS + 1 }, () => mkPro(['plumbing']));
  const j = job();
  pros.slice(0, MAX_CLAIMS).forEach((p) => m.claim(j.id, p.id));
  assert.equal(m.jobs.get(j.id).status, 'closed');
  assert.equal(m.feed(pros.at(-1).id).length, 0);
  assert.throws(() => m.claim(j.id, pros.at(-1).id), /closed/);
});

test('insufficient credit rejects claim', () => {
  const { m, mkPro, job } = setup();
  const pro = mkPro(['plumbing'], TLV, 10);
  const j = job();
  assert.throws(() => m.claim(j.id, pro.id), /credit/i);
});

test('full lifecycle with escrow commission and ratings', () => {
  const { m, client, mkPro, job } = setup();
  const pro = mkPro(['plumbing']);
  const j = job();
  m.claim(j.id, pro.id);
  m.assign(j.id, client.id, pro.id, 1000);
  m.advance(j.id, pro.id, 'en_route');
  m.advance(j.id, pro.id, 'in_progress', { photos: ['before.jpg'] });
  assert.throws(() => m.advance(j.id, pro.id, 'completed', { photos: ['a.jpg'] }), /signature/);
  m.advance(j.id, pro.id, 'completed', { photos: ['after.jpg'], signature: 'sig.png' });
  const done = m.confirmCompletion(j.id, client.id);
  assert.equal(done.escrow.fee, 120);
  assert.equal(done.escrow.payout, 880);
  m.rate(j.id, client.id, 5, 'מעולה');
  m.rate(j.id, pro.id, 4);
  assert.equal(m.pros.get(pro.id).ratings[0].score, 5);
});
