import { randomUUID } from 'node:crypto';
import { distanceKm } from './geo.js';
import { getCategory } from './categories.js';

export const MAX_OFFERS = 5;
export const COMMISSION_RATE = 0.12;
export const WELCOME_CREDIT = 30;   // free credit so anyone can send first offers without paying
export const REFERRAL_BONUS = 25;   // to the referrer when the referred pro completes a first job
export const MODES = ['onsite', 'remote', 'phone'];
export const PAYMENT_MODES = ['in_app', 'direct'];

// Job status flow per service mode (after the client accepts an offer).
const FLOW = {
  onsite: { assigned: 'en_route', en_route: 'in_progress', in_progress: 'completed' },
  remote: { assigned: 'in_progress', in_progress: 'completed' },
  phone: { assigned: 'in_progress', in_progress: 'completed' },
};

export class MarketplaceError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const fail = (code, msg) => { throw new MarketplaceError(code, msg); };
const round1 = (n) => Math.round(n * 10) / 10;

// In-memory store behind a small service API. Swap for Postgres/PostGIS repos.
export class Marketplace {
  constructor({ notify = () => {}, welcomeCredit = WELCOME_CREDIT, referralBonus = REFERRAL_BONUS } = {}) {
    this.welcomeCredit = welcomeCredit;
    this.referralBonus = referralBonus;
    this.pros = new Map();
    this.clients = new Map();
    this.jobs = new Map();
    this.ledger = [];
    this.notify = notify; // (userId, payload) => FCM high-priority push
  }

  // ---- Onboarding ----
  // Quick start: phone + name is enough. Categories/area can be filled in later;
  // the welcome credit lets a new pro send first offers before paying anything.
  registerPro({ phone, name, categories = [], location = null, radiusKm = 20, serviceModes = MODES, referralCode }) {
    if (!name) fail('bad_name', 'Name required');
    const referrer = referralCode ? [...this.pros.values()].find((p) => p.refCode === referralCode) : null;
    const pro = { id: randomUUID(), phone, name, categories: [], location: null, radiusKm, serviceModes: MODES,
      available: false, balance: 0, documents: [], approvedRequirements: [], ratings: [],
      refCode: randomUUID().slice(0, 6).toUpperCase(), referredBy: referrer?.id ?? null, referralPaid: false,
      completedJobs: 0, createdAt: Date.now() };
    this.updateProfile(pro, { categories, location, radiusKm, serviceModes });
    this.pros.set(pro.id, pro);
    if (this.welcomeCredit) {
      pro.balance += this.welcomeCredit;
      this.#record(pro.id, 'welcome_bonus', this.welcomeCredit, {});
    }
    return pro;
  }
  updateProfile(proOrId, { name, categories, location, radiusKm, serviceModes } = {}) {
    const pro = typeof proOrId === 'string' ? this.#pro(proOrId) : proOrId;
    for (const c of categories ?? []) if (!getCategory(c)) fail('bad_category', `Unknown category ${c}`);
    for (const m of serviceModes ?? []) if (!MODES.includes(m)) fail('bad_mode', `Unknown mode ${m}`);
    if (serviceModes && !serviceModes.length) fail('bad_mode', 'At least one service mode');
    if (radiusKm !== undefined && !(radiusKm > 0 && radiusKm <= 500)) fail('bad_radius', 'Radius 1-500 km');
    if (name) pro.name = name;
    if (categories) pro.categories = categories;
    if (location !== undefined) pro.location = location;
    if (radiusKm !== undefined) pro.radiusKm = radiusKm;
    if (serviceModes) pro.serviceModes = serviceModes;
    return pro;
  }
  proByPhone(phone) { return [...this.pros.values()].find((p) => p.phone === phone); }
  clientByPhone(phone) { return [...this.clients.values()].find((c) => c.phone === phone); }
  getPro(id) { return this.#pro(id); }
  publicPro(pro) {
    const { id, name, categories, serviceModes, available, balance, refCode, approvedRequirements, documents, radiusKm, location } = pro;
    return { id, name, categories, serviceModes, available, balance, refCode, approvedRequirements, radiusKm, location,
      documents: documents.map(({ id, type, status }) => ({ id, type, status })), ...this.rating(pro) };
  }
  registerClient({ phone, name }) {
    if (!name) fail('bad_name', 'Name required');
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

  canServe(pro, job) {
    const cat = getCategory(job.categoryId);
    if (!cat || !pro.serviceModes.includes(job.mode)) return false;
    const covers = pro.categories.some((c) => c === job.categoryId || c === cat.parent);
    return covers && (!cat.requirement || pro.approvedRequirements.includes(cat.requirement));
  }
  // Remote/phone work has no distance limit; onsite work must be within the pro's radius.
  inRange(pro, job, maxKm = pro.radiusKm) {
    if (job.mode !== 'onsite') return true;
    return !!pro.location && distanceKm(pro.location, job.location) <= maxKm;
  }

  // ---- Wallet ----
  topUp(proId, amount, method = 'card') {
    if (!(amount > 0)) fail('bad_amount', 'Amount must be positive');
    const pro = this.#pro(proId);
    pro.balance += amount;
    return this.#record(proId, 'topup', amount, { method });
  }
  history(proId) { return this.ledger.filter((e) => e.proId === proId); }

  // ---- Requests (client side) ----
  createJob({ clientId, categoryId, mode = 'onsite', description, location, address, phone, media = [],
    urgency = 'normal', budget = null, allowCalls = false, paymentMode = 'direct' }) {
    const client = this.#client(clientId);
    const cat = getCategory(categoryId) ?? fail('bad_category', 'Unknown category');
    if (!cat.modes.includes(mode)) fail('bad_mode', `${cat.name} is not available as ${mode}`);
    if (cat.payment === 'in_app') paymentMode = 'in_app'; // e.g. travel: we pay the supplier
    if (!PAYMENT_MODES.includes(paymentMode)) fail('bad_payment_mode', 'Unknown payment mode');
    if (!description) fail('bad_description', 'Description required');
    if (mode === 'onsite' && !location) fail('bad_location', 'Location required for onsite work');
    const job = { id: randomUUID(), clientId, categoryId, mode, description, location: location ?? null,
      address: address ?? null, phone: phone ?? client.phone, media, urgency, budget,
      allowCalls: !!allowCalls, paymentMode, leadPrice: cat.leadPrice, status: 'open',
      offers: [], assignedProId: null, escrow: null, workLog: [], signature: null, createdAt: Date.now() };
    this.jobs.set(job.id, job);
    job.dispatchedTo = this.dispatch(job);
    return job;
  }

  // Geo-push dispatcher: available, matching category + mode, in range, enough credit.
  dispatch(job) {
    const targets = [];
    for (const pro of this.pros.values()) {
      if (!pro.available || pro.balance < job.leadPrice) continue;
      if (!this.canServe(pro, job) || !this.inRange(pro, job)) continue;
      targets.push(pro.id);
      const d = job.mode === 'onsite' ? round1(distanceKm(pro.location, job.location)) : null;
      this.notify(pro.id, { type: 'new_job', jobId: job.id, mode: job.mode, distanceKm: d });
    }
    return targets;
  }

  // What a pro (or the public board) sees. Contact details only when the client
  // allowed calls and the pro sent an offer, or after the client accepted the pro.
  teaser(job, viewer) {
    const pub = { id: job.id, categoryId: job.categoryId, mode: job.mode, description: job.description,
      media: job.media, urgency: job.urgency, budget: job.budget, allowCalls: job.allowCalls,
      paymentMode: job.paymentMode, leadPrice: job.leadPrice, status: job.status, createdAt: job.createdAt,
      offersLeft: MAX_OFFERS - job.offers.length };
    if (job.location) pub.location = { lat: +job.location.lat.toFixed(2), lng: +job.location.lng.toFixed(2) };
    if (viewer?.location && job.location) pub.distanceKm = round1(distanceKm(viewer.location, job.location));
    if (!viewer) return pub;
    const offer = job.offers.find((o) => o.proId === viewer.id);
    const assigned = job.assignedProId === viewer.id;
    // Agents never see the supplier's net price or the platform's cut.
    if (offer) pub.myOffer = { ...offer, items: offer.items?.map(({ net, netILS, platformFee, ...i }) => i) ?? null };
    if (assigned || (offer && job.allowCalls)) {
      Object.assign(pub, { phone: job.phone, address: job.address, location: job.location });
    }
    if (assigned) {
      const e = job.escrow;
      Object.assign(pub, { workLog: job.workLog, booking: job.booking ?? null,
        escrow: e && { amount: e.amount, status: e.status, payout: e.payout } });
    }
    return pub;
  }

  // Full view for the job owner: offers include the pro's name, phone and rating,
  // so the client decides whether to call, chat or simply accept.
  clientJobs(clientId, requesterId) {
    if (clientId !== requesterId) fail('forbidden', 'Not your requests');
    this.#client(clientId);
    return [...this.jobs.values()].filter((j) => j.clientId === clientId)
      .sort((a, b) => b.createdAt - a.createdAt)
      .map(({ dispatchedTo, escrow, ...j }) => ({ ...j,
        escrow: escrow && { amount: escrow.amount, status: escrow.status },
        offers: j.offers.map((o) => {
          const pro = this.pros.get(o.proId);
          const items = o.items?.map(({ kind, title, details, price, freeCancellationBefore }) =>
            ({ kind, title, details, price, freeCancellationBefore }));
          return { ...o, items, pro: { name: pro.name, phone: pro.phone, ...this.rating(pro) } };
        }) }));
  }

  // ---- Pro side ----
  feed(proId, { maxKm, urgency, mode } = {}) {
    const pro = this.#pro(proId);
    return [...this.jobs.values()]
      .filter((j) => j.status === 'open' && j.offers.length < MAX_OFFERS
        && !j.offers.some((o) => o.proId === proId)
        && this.canServe(pro, j) && this.inRange(pro, j, maxKm ?? pro.radiusKm)
        && (!urgency || j.urgency === urgency) && (!mode || j.mode === mode))
      .map((j) => this.teaser(j, pro))
      .sort((a, b) => (b.urgency === 'urgent') - (a.urgency === 'urgent')
        || (a.distanceKm ?? 0) - (b.distanceKm ?? 0) || b.createdAt - a.createdAt);
  }
  proJobs(proId, requesterId) {
    if (proId !== requesterId) fail('forbidden', 'Not your jobs');
    const pro = this.#pro(proId);
    return [...this.jobs.values()]
      .filter((j) => j.assignedProId === proId || j.offers.some((o) => o.proId === proId))
      .map((j) => this.teaser(j, pro));
  }

  // Sending an offer costs the category's lead price (pay-per-lead).
  // Synchronous => atomic in single-threaded Node.
  // Production: SELECT ... FOR UPDATE / Redis Lua script on the offers counter.
  // `items` are supplier products already priced by the Travel service — never pass raw client input.
  sendOffer(jobId, proId, { price = null, eta = null, message = '', items = null } = {}) {
    const job = this.#job(jobId);
    const pro = this.#pro(proId);
    if (job.status !== 'open') fail('closed', 'Job is no longer open');
    if (job.offers.length >= MAX_OFFERS) fail('full', 'Job already has the maximum number of offers');
    if (job.offers.some((o) => o.proId === proId)) fail('already_offered', 'You already sent an offer');
    if (!this.canServe(pro, job) || !this.inRange(pro, job)) fail('not_eligible', 'Not eligible for this job');
    if (price !== null && !(price >= 0)) fail('bad_price', 'Invalid price');
    if (items && job.paymentMode !== 'in_app') fail('in_app_required', 'Catalog items can only be sold with in-app payment');
    if (pro.balance < job.leadPrice) fail('insufficient_credit', 'Insufficient credit');
    pro.balance -= job.leadPrice;
    this.#record(proId, 'offer_fee', -job.leadPrice, { jobId });
    if (items) price = Math.round(items.reduce((s, i) => s + i.price, 0) * 100) / 100;
    job.offers.push({ id: randomUUID(), proId, price, eta, message, items, status: 'pending', at: Date.now() });
    this.notify(job.clientId, { type: 'new_offer', jobId, offers: job.offers.length });
    return this.teaser(job, pro);
  }

  // Validation shared by acceptOffer and the async travel pre-checks.
  offerForAccept(jobId, clientId, offerId) {
    const job = this.#job(jobId);
    if (job.clientId !== clientId) fail('forbidden', 'Not your job');
    if (job.status !== 'open') fail('closed', 'Job is no longer open');
    const offer = job.offers.find((o) => o.id === offerId) ?? fail('not_found', 'Offer not found');
    if (job.paymentMode === 'in_app' && !(offer.price > 0)) fail('price_required', 'In-app payment needs a priced offer');
    return { job, offer };
  }

  acceptOffer(jobId, clientId, offerId, { traveler } = {}) {
    const { job, offer } = this.offerForAccept(jobId, clientId, offerId);
    if (offer.items && !(traveler?.firstName && traveler?.lastName && traveler?.email)) {
      fail('traveler_required', 'Traveler name and email required');
    }
    for (const o of job.offers) o.status = o === offer ? 'accepted' : 'rejected';
    job.assignedProId = offer.proId;
    job.status = 'assigned';
    // In-app: the client's card is charged now and the money is held until completion.
    if (job.paymentMode === 'in_app') job.escrow = { amount: offer.price, status: 'held' };
    if (offer.items) {
      const sum = (k) => Math.round(offer.items.reduce((s, i) => s + i[k], 0) * 100) / 100;
      job.escrow.breakdown = { supplier: sum('netILS'), platformFee: sum('platformFee'), agentFee: sum('agentFee') };
      job.traveler = traveler;
      job.booking = { status: 'pending' };
    }
    this.notify(offer.proId, { type: 'offer_accepted', jobId });
    return job;
  }

  // Supplier booking outcome (called by the API after Travel.book).
  bookingConfirmed(jobId, bookings) {
    const job = this.#job(jobId);
    job.booking = { status: 'confirmed', items: bookings };
    job.workLog.push({ at: Date.now(), stage: job.status, photos: [],
      text: `הזמנה אושרה אצל הספק: ${bookings.map((b) => `${b.title} (${b.supplierRef})`).join(', ')}` });
    this.notify(job.clientId, { type: 'booking_confirmed', jobId });
    return job;
  }
  bookingFailed(jobId, reason, partial = []) {
    const job = this.#job(jobId);
    job.booking = { status: partial.length ? 'needs_support' : 'failed', reason, items: partial };
    job.status = 'booking_failed';
    if (job.escrow) job.escrow.status = partial.length ? 'held_for_support' : 'refunded';
    this.notify(job.clientId, { type: 'booking_failed', jobId });
    return job;
  }

  // Documentation: notes and photos the assigned pro attaches while working.
  addLog(jobId, proId, { text = '', photos = [] }) {
    const job = this.#job(jobId);
    if (job.assignedProId !== proId) fail('forbidden', 'Not assigned to you');
    if (job.status === 'closed_done') fail('closed', 'Job is closed');
    if (!text && !photos.length) fail('empty_log', 'Text or photos required');
    const entry = { at: Date.now(), stage: job.status, text, photos };
    job.workLog.push(entry);
    return entry;
  }

  advance(jobId, proId, status, { photos = [], note = '', signature } = {}) {
    const job = this.#job(jobId);
    if (job.assignedProId !== proId) fail('forbidden', 'Not assigned to you');
    if (FLOW[job.mode][job.status] !== status) fail('bad_transition', `${job.status} -> ${status} not allowed`);
    if (job.booking && job.booking.status !== 'confirmed') fail('booking_pending', 'Supplier booking not confirmed');
    if (status === 'completed' && job.mode === 'onsite' && !signature) fail('signature_required', 'Client signature required');
    job.status = status;
    if (signature) job.signature = signature;
    if (note || photos.length) job.workLog.push({ at: Date.now(), stage: status, text: note, photos });
    this.notify(job.clientId, { type: 'job_status', jobId, status });
    return job;
  }

  // Client confirms completion -> in-app payments release escrow minus commission.
  confirmCompletion(jobId, clientId) {
    const job = this.#job(jobId);
    if (job.clientId !== clientId) fail('forbidden', 'Not your job');
    if (job.status !== 'completed') fail('bad_transition', 'Job not completed');
    if (job.escrow?.status === 'held') {
      const b = job.escrow.breakdown;
      // Services: commission on the whole price. Travel: supplier is paid its net,
      // the platform keeps its markup + commission on the agent's markup.
      const base = b ? b.agentFee : job.escrow.amount;
      const commission = Math.round(base * COMMISSION_RATE * 100) / 100;
      const fee = Math.round(((b?.platformFee ?? 0) + commission) * 100) / 100;
      const payout = Math.round((base - commission) * 100) / 100;
      Object.assign(job.escrow, { status: 'released', fee, payout });
      this.#record(job.assignedProId, 'payout', payout, { jobId, fee });
    }
    job.status = 'closed_done';
    this.#onProCompleted(this.#pro(job.assignedProId));
    return job;
  }

  // Referral bonus is paid only once the referred pro actually completes a job (anti-fraud).
  #onProCompleted(pro) {
    pro.completedJobs += 1;
    if (pro.referredBy && !pro.referralPaid && this.referralBonus) {
      const referrer = this.pros.get(pro.referredBy);
      if (referrer) {
        referrer.balance += this.referralBonus;
        this.#record(referrer.id, 'referral_bonus', this.referralBonus, { referredProId: pro.id });
      }
      pro.referralPaid = true;
    }
  }

  rate(jobId, fromId, score, text = '') {
    const job = this.#job(jobId);
    if (!['completed', 'closed_done'].includes(job.status)) fail('bad_transition', 'Job not finished');
    if (!(score >= 1 && score <= 5)) fail('bad_score', 'Score 1-5');
    const target = fromId === job.clientId ? this.#pro(job.assignedProId)
      : fromId === job.assignedProId ? this.#client(job.clientId) : fail('forbidden', 'Not a party');
    target.ratings.push({ jobId, score, text });
    return target.ratings;
  }
  rating(user) {
    const n = user.ratings.length;
    return { ratingAvg: n ? round1(user.ratings.reduce((s, r) => s + r.score, 0) / n) : null, ratingCount: n };
  }

  #record(proId, type, amount, meta) {
    const e = { id: randomUUID(), proId, type, amount, meta, at: Date.now() };
    this.ledger.push(e);
    return e;
  }
  #pro(id) { return this.pros.get(id) ?? fail('not_found', 'Pro not found'); }
  #client(id) { return this.clients.get(id) ?? fail('not_found', 'Client not found'); }
  #job(id) { return this.jobs.get(id) ?? fail('not_found', 'Job not found'); }
}
