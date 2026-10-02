import { randomUUID } from 'node:crypto';
import { distanceKm } from './geo.js';
import { getCategory } from './categories.js';

export const MAX_CLAIMS = 3;
export const COMMISSION_RATE = 0.12;

export class MarketplaceError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const fail = (code, msg) => { throw new MarketplaceError(code, msg); };

// In-memory store behind a small service API. Swap for Postgres/PostGIS repos.
export class Marketplace {
  constructor({ notify = () => {} } = {}) {
    this.pros = new Map();
    this.clients = new Map();
    this.jobs = new Map();
    this.ledger = [];
    this.notify = notify; // (proId, payload) => FCM high-priority push
  }

  // ---- Onboarding ----
  registerPro({ phone, name, categories = [], location, radiusKm = 20 }) {
    for (const c of categories) if (!getCategory(c)) fail('bad_category', `Unknown category ${c}`);
    const pro = { id: randomUUID(), phone, name, categories, location, radiusKm,
      available: false, balance: 0, documents: [], approvedRequirements: [], ratings: [] };
    this.pros.set(pro.id, pro);
    return pro;
  }
  registerClient({ phone, name }) {
    const c = { id: randomUUID(), phone, name, ratings: [] };
    this.clients.set(c.id, c);
    return c;
  }
  uploadDocument(proId, { type, url }) {
    const pro = this.#pro(proId);
    const doc = { id: randomUUID(), type, url, status: 'pending' };
    pro.documents.push(doc);
    return doc;
  }
  // Admin: manual approval unlocks licensed categories.
  approveDocument(proId, docId) {
    const pro = this.#pro(proId);
    const doc = pro.documents.find((d) => d.id === docId) ?? fail('not_found', 'Document not found');
    doc.status = 'approved';
    if (!pro.approvedRequirements.includes(doc.type)) pro.approvedRequirements.push(doc.type);
    return doc;
  }
  setAvailability(proId, available) { this.#pro(proId).available = !!available; }
  updateLocation(proId, location) { this.#pro(proId).location = location; }

  canServe(pro, categoryId) {
    const cat = getCategory(categoryId);
    if (!cat) return false;
    const covers = pro.categories.some((c) => c === categoryId || c === cat.parent || categoryId.startsWith(c + '.'));
    return covers && (!cat.requirement || pro.approvedRequirements.includes(cat.requirement));
  }

  // ---- Wallet ----
  topUp(proId, amount, method = 'card') {
    if (!(amount > 0)) fail('bad_amount', 'Amount must be positive');
    const pro = this.#pro(proId);
    pro.balance += amount;
    return this.#record(proId, 'topup', amount, { method });
  }
  history(proId) { return this.ledger.filter((e) => e.proId === proId); }

  // ---- Jobs ----
  createJob({ clientId, categoryId, description, location, address, phone, media = [], urgency = 'normal', budget = null }) {
    const cat = getCategory(categoryId) ?? fail('bad_category', 'Unknown category');
    if (!location) fail('bad_location', 'Location required');
    const job = { id: randomUUID(), clientId, categoryId, description, location, address, phone, media,
      urgency, budget, leadPrice: cat.leadPrice, status: 'open', claims: [], assignedProId: null,
      escrow: null, createdAt: Date.now() };
    this.jobs.set(job.id, job);
    job.dispatchedTo = this.dispatch(job);
    return job;
  }

  // Geo-push dispatcher: available, matching category, within pro radius, positive credit.
  dispatch(job) {
    const targets = [];
    for (const pro of this.pros.values()) {
      if (!pro.available || !pro.location || pro.balance < job.leadPrice) continue;
      if (!this.canServe(pro, job.categoryId)) continue;
      const d = distanceKm(pro.location, job.location);
      if (d > pro.radiusKm) continue;
      targets.push(pro.id);
      this.notify(pro.id, { type: 'new_job', jobId: job.id, distanceKm: Math.round(d * 10) / 10 });
    }
    return targets;
  }

  // Public teaser: no phone / exact address until claimed.
  teaser(job, viewer) {
    const { phone, address, clientId, claims, escrow, dispatchedTo, ...pub } = job;
    const out = { ...pub, claimsLeft: MAX_CLAIMS - claims.length,
      location: { lat: +job.location.lat.toFixed(2), lng: +job.location.lng.toFixed(2) } };
    if (viewer?.location) out.distanceKm = Math.round(distanceKm(viewer.location, job.location) * 10) / 10;
    if (viewer && claims.includes(viewer.id)) Object.assign(out, { phone, address, location: job.location, claimed: true });
    return out;
  }

  feed(proId, { maxKm, urgency } = {}) {
    const pro = this.#pro(proId);
    return [...this.jobs.values()]
      .filter((j) => j.status === 'open' && this.canServe(pro, j.categoryId))
      .map((j) => this.teaser(j, pro))
      .filter((j) => j.distanceKm <= (maxKm ?? pro.radiusKm) && (!urgency || j.urgency === urgency))
      .sort((a, b) => a.distanceKm - b.distanceKm);
  }

  // Pay-per-lead claim. Synchronous => atomic in single-threaded Node.
  // Production: SELECT ... FOR UPDATE / Redis Lua script on claims counter.
  claim(jobId, proId) {
    const job = this.#job(jobId);
    const pro = this.#pro(proId);
    if (job.status !== 'open') fail('closed', 'Job is closed');
    if (job.claims.includes(proId)) fail('already_claimed', 'Already claimed');
    if (!this.canServe(pro, job.categoryId)) fail('not_eligible', 'Not eligible for this category');
    if (pro.balance < job.leadPrice) fail('insufficient_credit', 'Insufficient credit');
    pro.balance -= job.leadPrice;
    job.claims.push(proId);
    this.#record(proId, 'lead_purchase', -job.leadPrice, { jobId });
    if (job.claims.length >= MAX_CLAIMS) job.status = 'closed';
    return this.teaser(job, pro);
  }

  // ---- Lifecycle / commission (escrow) ----
  assign(jobId, clientId, proId, price) {
    const job = this.#job(jobId);
    if (job.clientId !== clientId) fail('forbidden', 'Not your job');
    if (!job.claims.includes(proId)) fail('not_claimed', 'Pro has not claimed this job');
    job.assignedProId = proId;
    job.status = 'assigned';
    if (price) job.escrow = { amount: price, status: 'held' }; // payment captured via PSP
    return job;
  }
  advance(jobId, proId, status, { photos = [], signature } = {}) {
    const flow = { assigned: 'en_route', en_route: 'in_progress', in_progress: 'completed' };
    const job = this.#job(jobId);
    if (job.assignedProId !== proId) fail('forbidden', 'Not assigned to you');
    if (flow[job.status] !== status) fail('bad_transition', `${job.status} -> ${status} not allowed`);
    if (status === 'in_progress') job.beforePhotos = photos;
    if (status === 'completed') {
      if (!signature) fail('signature_required', 'Client signature required');
      Object.assign(job, { afterPhotos: photos, signature });
    }
    job.status = status;
    return job;
  }
  // Client confirms completion -> release escrow minus commission.
  confirmCompletion(jobId, clientId) {
    const job = this.#job(jobId);
    if (job.clientId !== clientId) fail('forbidden', 'Not your job');
    if (job.status !== 'completed') fail('bad_transition', 'Job not completed');
    if (job.escrow?.status === 'held') {
      const fee = Math.round(job.escrow.amount * COMMISSION_RATE * 100) / 100;
      const payout = job.escrow.amount - fee;
      Object.assign(job.escrow, { status: 'released', fee, payout });
      this.#record(job.assignedProId, 'payout', payout, { jobId, fee });
    }
    job.status = 'closed_done';
    return job;
  }
  rate(jobId, fromId, score, text = '') {
    const job = this.#job(jobId);
    if (!['completed', 'closed_done'].includes(job.status)) fail('bad_transition', 'Job not finished');
    if (!(score >= 1 && score <= 5)) fail('bad_score', 'Score 1-5');
    const target = fromId === job.clientId ? this.#pro(job.assignedProId)
      : fromId === job.assignedProId ? this.clients.get(job.clientId) : fail('forbidden', 'Not a party');
    target.ratings.push({ jobId, score, text });
    return target.ratings;
  }

  #record(proId, type, amount, meta) {
    const e = { id: randomUUID(), proId, type, amount, meta, at: Date.now() };
    this.ledger.push(e);
    return e;
  }
  #pro(id) { return this.pros.get(id) ?? fail('not_found', 'Pro not found'); }
  #job(id) { return this.jobs.get(id) ?? fail('not_found', 'Job not found'); }
}
