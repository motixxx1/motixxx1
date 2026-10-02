import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Marketplace, MAX_OFFERS } from '../src/marketplace.js';

const TLV = { lat: 32.0853, lng: 34.7818 };
const EILAT = { lat: 29.5577, lng: 34.9519 };

function setup() {
  const pushes = [];
  const m = new Marketplace({ notify: (id, msg) => pushes.push({ id, msg }), welcomeCredit: 0 });
  const client = m.registerClient({ phone: '050', name: 'דנה' });
  const mkPro = (cats, { loc = TLV, credit = 100, modes } = {}) => {
    const p = m.registerPro({ phone: '052', name: 'pro', categories: cats, location: loc, radiusKm: 20, serviceModes: modes });
    m.setAvailability(p.id, true);
    if (credit) m.topUp(p.id, credit);
    return p;
  };
  const job = (opts = {}) => m.createJob({ clientId: client.id, categoryId: 'plumbing.unclog',
    description: 'סתימה', location: TLV, address: 'הרצל 1', ...opts });
  return { m, client, mkPro, job, pushes };
}

test('onsite dispatch targets only available, matching, nearby, funded pros', () => {
  const { m, mkPro, job, pushes } = setup();
  const good = mkPro(['plumbing']);
  mkPro(['plumbing'], { loc: EILAT });     // too far
  mkPro(['locksmith']);                    // wrong category
  mkPro(['plumbing'], { credit: 0 });      // no credit
  const off = mkPro(['plumbing']); m.setAvailability(off.id, false);
  const j = job();
  assert.deepEqual(j.dispatchedTo, [good.id]);
  assert.equal(pushes.length, 1);
});

test('remote job reaches remote-capable pros anywhere in the country', () => {
  const { m, mkPro, job } = setup();
  const remoteTech = mkPro(['computers'], { loc: EILAT });
  mkPro(['computers'], { modes: ['onsite'] }); // only does house calls
  const j = job({ categoryId: 'computers.software', mode: 'remote', location: undefined });
  assert.deepEqual(j.dispatchedTo, [remoteTech.id]);
  assert.equal(m.feed(remoteTech.id).length, 1);
});

test('mode must be allowed by the category', () => {
  const { job } = setup();
  assert.throws(() => job({ mode: 'remote' }), /not available/);
});

test('licensed category blocked until admin approves document', () => {
  const { m, mkPro, job } = setup();
  const pro = mkPro(['electric']);
  assert.equal(job({ categoryId: 'electric.short' }).dispatchedTo.length, 0);
  const doc = m.uploadDocument(pro.id, { type: 'license', url: 's3://x' });
  m.approveDocument(pro.id, doc.id);
  assert.deepEqual(job({ categoryId: 'electric.short' }).dispatchedTo, [pro.id]);
});

test('phone stays hidden unless client allowed calls', () => {
  const { m, mkPro, job } = setup();
  const a = mkPro(['plumbing']);
  const private_ = m.sendOffer(job().id, a.id, { price: 300 });
  assert.equal(private_.phone, undefined);
  const callable = m.sendOffer(job({ allowCalls: true }).id, a.id, { price: 300 });
  assert.equal(callable.phone, '050');
});

test('offer charges lead price; duplicates, low credit and full jobs are rejected', () => {
  const { m, mkPro, job } = setup();
  const j = job();
  const pros = Array.from({ length: MAX_OFFERS + 1 }, () => mkPro(['plumbing']));
  m.sendOffer(j.id, pros[0].id, { price: 200 });
  assert.equal(m.pros.get(pros[0].id).balance, 100 - j.leadPrice);
  assert.throws(() => m.sendOffer(j.id, pros[0].id, {}), /already/);
  pros.slice(1, MAX_OFFERS).forEach((p) => m.sendOffer(j.id, p.id, { price: 250 }));
  assert.equal(m.feed(pros.at(-1).id).length, 0);
  assert.throws(() => m.sendOffer(j.id, pros.at(-1).id, {}), /maximum/);
  const poor = mkPro(['plumbing'], { credit: 10 });
  assert.throws(() => m.sendOffer(job().id, poor.id, {}), /credit/i);
});

test('client sees offers with pro details and accepts one', () => {
  const { m, client, mkPro, job } = setup();
  const [a, b] = [mkPro(['plumbing']), mkPro(['plumbing'])];
  const j = job();
  m.sendOffer(j.id, a.id, { price: 300, message: 'מגיע תוך שעה' });
  m.sendOffer(j.id, b.id, { price: 250 });
  assert.throws(() => m.clientJobs(client.id, 'someone-else'), /Not your/);
  const [mine] = m.clientJobs(client.id, client.id);
  assert.equal(mine.offers.length, 2);
  assert.equal(mine.offers[0].pro.phone, '052');
  m.acceptOffer(j.id, client.id, mine.offers[1].id);
  assert.equal(m.jobs.get(j.id).assignedProId, b.id);
  assert.equal(m.jobs.get(j.id).offers[0].status, 'rejected');
  assert.equal(m.teaser(m.jobs.get(j.id), m.pros.get(b.id)).phone, '050');
  assert.equal(m.teaser(m.jobs.get(j.id), m.pros.get(a.id)).phone, undefined);
});

test('onsite + in-app payment: escrow, signature, commission, ratings', () => {
  const { m, client, mkPro, job } = setup();
  const pro = mkPro(['plumbing']);
  const j = job({ paymentMode: 'in_app' });
  const { myOffer } = m.sendOffer(j.id, pro.id, { price: 1000 });
  m.acceptOffer(j.id, client.id, myOffer.id);
  assert.deepEqual(m.jobs.get(j.id).escrow, { amount: 1000, status: 'held' });
  m.advance(j.id, pro.id, 'en_route');
  m.advance(j.id, pro.id, 'in_progress', { photos: ['before.jpg'] });
  assert.throws(() => m.advance(j.id, pro.id, 'completed'), /signature/);
  m.advance(j.id, pro.id, 'completed', { photos: ['after.jpg'], signature: 'sig.png' });
  const done = m.confirmCompletion(j.id, client.id);
  assert.equal(done.escrow.fee, 120);
  assert.equal(done.escrow.payout, 880);
  m.rate(j.id, client.id, 5, 'מעולה');
  m.rate(j.id, pro.id, 4);
  assert.deepEqual(m.rating(m.pros.get(pro.id)), { ratingAvg: 5, ratingCount: 1 });
});

test('in-app payment needs a priced offer', () => {
  const { m, client, mkPro, job } = setup();
  const pro = mkPro(['plumbing']);
  const j = job({ paymentMode: 'in_app' });
  const { myOffer } = m.sendOffer(j.id, pro.id, { message: 'אתן מחיר אחרי בדיקה' });
  assert.throws(() => m.acceptOffer(j.id, client.id, myOffer.id), /priced/);
});

test('remote + direct payment: no en-route step, work log, no escrow', () => {
  const { m, client, mkPro, job } = setup();
  const pro = mkPro(['computers']);
  const j = job({ categoryId: 'computers.software', mode: 'remote', location: undefined });
  const { myOffer } = m.sendOffer(j.id, pro.id, { price: 150 });
  m.acceptOffer(j.id, client.id, myOffer.id);
  assert.throws(() => m.advance(j.id, pro.id, 'en_route'), /not allowed/);
  m.advance(j.id, pro.id, 'in_progress', { note: 'התחברתי ב-AnyDesk' });
  m.addLog(j.id, pro.id, { text: 'הוסרו 3 וירוסים', photos: ['scan.png'] });
  m.advance(j.id, pro.id, 'completed');
  const done = m.confirmCompletion(j.id, client.id);
  assert.equal(done.escrow, null);
  assert.equal(done.workLog.length, 2);
  assert.ok(!m.history(pro.id).some((e) => e.type === 'payout'));
});

test('quick start: welcome credit, and referral bonus only after first completed job', () => {
  const m = new Marketplace({ welcomeCredit: 30, referralBonus: 25 });
  const client = m.registerClient({ phone: '050', name: 'C' });
  const veteran = m.registerPro({ phone: '1', name: 'ותיק' });
  const rookie = m.registerPro({ phone: '2', name: 'מתחיל', referralCode: veteran.refCode });
  assert.equal(rookie.balance, 30);
  assert.equal(rookie.referredBy, veteran.id);
  // signs up with no categories, fills them in later, and can offer right away with the free credit
  m.updateProfile(rookie.id, { categories: ['help'], location: TLV });
  m.setAvailability(rookie.id, true);
  const j = m.createJob({ clientId: client.id, categoryId: 'help.furniture', description: 'ארון איקאה', location: TLV, address: 'x' });
  assert.deepEqual(j.dispatchedTo, [rookie.id]);
  const { myOffer } = m.sendOffer(j.id, rookie.id, { price: 200 });
  assert.equal(veteran.balance, 30);
  m.acceptOffer(j.id, client.id, myOffer.id);
  m.advance(j.id, rookie.id, 'en_route');
  m.advance(j.id, rookie.id, 'in_progress');
  m.advance(j.id, rookie.id, 'completed', { signature: 's' });
  m.confirmCompletion(j.id, client.id);
  assert.equal(veteran.balance, 55);
  assert.equal(rookie.completedJobs, 1);
});
