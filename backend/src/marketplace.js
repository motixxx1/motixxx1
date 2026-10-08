import { randomUUID } from 'node:crypto';
import { distanceKm } from './geo.js';
import { getCategory, isRequirement, requirementNames } from './categories.js';

export const MAX_OFFERS = 5;
export const COMMISSION_RATE = 0.12;
export const WELCOME_CREDIT = 30;   // free credit so anyone can send first offers without paying
export const REFERRAL_BONUS = 25;   // to the referrer when the referred pro completes a first job
export const TOPUP_PACKAGES = [50, 100, 200, 500]; // credit packages a pro can buy (ILS)
export const MODES = ['onsite', 'remote', 'phone', 'delivery'];
const PHYSICAL = ['onsite', 'delivery']; // modes where distance matters
export const PAYMENT_MODES = ['in_app', 'direct'];
export const PAY_METHODS = ['cash', 'bit', 'transfer', 'card', 'other']; // how a direct payment reached the pro
// what a customer is told about: offers on a request, status changes, and (off by default) news
export const NOTIFY_DEFAULTS = { offers: true, status: true, promos: false };

// Job status flow per service mode (after the client accepts an offer).
const FLOW = {
  // arrived = "I'm here": the client sees it live, then work starts.
  onsite: { assigned: 'en_route', en_route: 'arrived', arrived: 'in_progress', in_progress: 'completed' },
  remote: { assigned: 'in_progress', in_progress: 'completed' },
  phone: { assigned: 'in_progress', in_progress: 'completed' },
  // Courier: on the way to pickup -> picked up -> delivered (photo as proof).
  delivery: { assigned: 'en_route', en_route: 'picked_up', picked_up: 'arrived', arrived: 'completed' },
};

export class MarketplaceError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const fail = (code, msg) => { throw new MarketplaceError(code, msg); };
const round1 = (n) => Math.round(n * 10) / 10;

// In-memory store behind a small service API. Swap for Postgres/PostGIS repos.
export class Marketplace {
  // leadFees: pay-per-lead on (each offer costs credit) or off (launch period: offers are free).
  // payments: in-app card payments available (needs a payment provider; off = direct payment only).
  constructor({ notify = () => {}, welcomeCredit = WELCOME_CREDIT, referralBonus = REFERRAL_BONUS,
    leadFees = true, payments = true } = {}) {
    this.leadFees = leadFees;
    this.payments = payments;
    this.welcomeCredit = leadFees ? welcomeCredit : 0;
    this.referralBonus = leadFees ? referralBonus : 0;
    this.pros = new Map();
    this.clients = new Map();
    this.jobs = new Map();
    this.ledger = [];
    this.topups = [];     // credit purchases: { id, proId, amount, status: 'pending' | 'paid', createdAt, paidAt }
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
  proByPhone(phone) { return [...this.pros.values()].find((p) => p.phone === phone && !p.deleted); }
  clientByPhone(phone) { return [...this.clients.values()].find((c) => c.phone === phone && !c.deleted); }
  isActive(role, id) { const u = (role === 'pro' ? this.pros : this.clients).get(id); return !!u && !u.deleted; }

  // Account deletion (required by app stores): personal details are erased, open requests
  // are cancelled, and the account can't be used any more. Blocked while a job is in progress.
  deleteAccount(role, id) {
    const active = ['assigned', 'en_route', 'picked_up', 'arrived', 'in_progress', 'completed'];
    const mine = [...this.jobs.values()].filter((j) => (role === 'pro' ? j.assignedProId : j.clientId) === id);
    if (mine.some((j) => active.includes(j.status))) fail('active_jobs', 'Finish or cancel the work in progress first');
    if (role === 'pro') {
      const pro = this.#pro(id);
      Object.assign(pro, { deleted: true, name: 'מקצוען שמחק את החשבון', phone: null, available: false, categories: [],
        location: null, documents: [], refCode: null });
      for (const j of this.jobs.values()) if (j.status === 'open') j.offers = j.offers.filter((o) => o.proId !== id);
    } else {
      const c = this.#client(id);
      Object.assign(c, { deleted: true, name: 'לקוח שמחק את החשבון', phone: null, addresses: [], payMethod: null });
      for (const j of mine) {
        if (j.status === 'open') j.status = 'cancelled';
        Object.assign(j, { phone: null, address: j.address && 'נמחק', description: 'נמחק לבקשת הלקוח', media: [] });
      }
    }
    return { deleted: true };
  }
  getPro(id) { return this.#pro(id); }
  // The name shown to the other side; customers and pros can change it.
  rename(role, id, name) {
    const n = String(name ?? '').trim().replace(/\s+/g, ' ');
    if (n.length < 2 || n.length > 40) fail('bad_name', 'Name must be 2-40 characters');
    const u = role === 'pro' ? this.#pro(id) : this.#client(id);
    u.name = n;
    return { name: n };
  }
  // ---- customer profile: saved addresses, preferred payment method, notifications
  clientProfile(id) {
    const c = this.#client(id);
    return { name: c.name, phone: c.phone, addresses: c.addresses ?? [], payMethod: c.payMethod ?? null,
      notify: { ...NOTIFY_DEFAULTS, ...(c.notify ?? {}) } };
  }
  addAddress(id, { label, address, location } = {}) {
    const c = this.#client(id);
    const a = String(address ?? '').trim().replace(/\s+/g, ' ');
    if (a.length < 3 || a.length > 160) fail('bad_address', 'Address must be 3-160 characters');
    const l = String(label ?? '').trim().replace(/\s+/g, ' ').slice(0, 30) || 'כתובת';
    const loc = location && Number.isFinite(+location.lat) && Number.isFinite(+location.lng) ? { lat: +location.lat, lng: +location.lng } : null;
    c.addresses = c.addresses ?? [];
    if (c.addresses.length >= 10) fail('too_many_addresses', 'Up to 10 saved addresses');
    c.addresses.push({ id: randomUUID(), label: l, address: a, location: loc });
    return this.clientProfile(id);
  }
  removeAddress(id, addrId) {
    const c = this.#client(id);
    c.addresses = (c.addresses ?? []).filter((x) => x.id !== addrId);
    return this.clientProfile(id);
  }
  clientSettings(id, { payMethod, notify } = {}) {
    const c = this.#client(id);
    if (payMethod !== undefined) {
      if (payMethod !== null && !PAY_METHODS.includes(payMethod)) fail('bad_pay_method', 'Unknown payment method');
      c.payMethod = payMethod;
    }
    if (notify && typeof notify === 'object') {
      const n = { ...NOTIFY_DEFAULTS, ...(c.notify ?? {}) };
      for (const k of Object.keys(NOTIFY_DEFAULTS)) if (typeof notify[k] === 'boolean') n[k] = notify[k];
      c.notify = n;
    }
    return this.clientProfile(id);
  }
  // A customer's own label for a request ("the AC in the living room"); empty = back to the category name.
  renameJob(clientId, jobId, title) {
    const job = this.#job(jobId);
    if (job.clientId !== clientId) fail('forbidden', 'Not your request');
    const t = String(title ?? '').trim().replace(/\s+/g, ' ').slice(0, 60);
    if (t) job.title = t; else delete job.title;
    return { title: job.title ?? null };
  }
  publicPro(pro) {
    const { id, name, categories, serviceModes, available, balance, refCode, approvedRequirements, documents, radiusKm, location } = pro;
    return { id, name, categories, serviceModes, available, balance, refCode, approvedRequirements, radiusKm, location,
      documents: documents.map(({ id, type, status, reason }) => ({ id, type, status, reason: reason ?? null })), ...this.rating(pro) };
  }
  registerClient({ phone, name }) {
    if (!name) fail('bad_name', 'Name required');
    const c = { id: randomUUID(), phone, name, ratings: [] };
    this.clients.set(c.id, c);
    return c;
  }
  uploadDocument(proId, { type, url }) {
    const pro = this.#pro(proId);
    if (!isRequirement(type)) fail('bad_document_type', 'Unknown document type');
    if (!/^\/media\/[0-9a-f-]{36}$/.test(String(url ?? ''))) fail('bad_document', 'Attach a photo of the document');
    const doc = { id: randomUUID(), type, url, status: 'pending', uploadedAt: Date.now() };
    pro.documents.push(doc);
    return doc;
  }
  // Admin: manual approval unlocks that profession (or requirement) only.
  approveDocument(proId, docId) {
    const pro = this.#pro(proId);
    const doc = pro.documents.find((d) => d.id === docId) ?? fail('not_found', 'Document not found');
    doc.status = 'approved'; doc.reviewedAt = Date.now(); delete doc.reason;
    if (!pro.approvedRequirements.includes(doc.type)) pro.approvedRequirements.push(doc.type);
    return doc;
  }
  // Admin: a document that isn't valid (unreadable, expired, someone else's). The pro sees the reason.
  rejectDocument(proId, docId, reason = '') {
    const pro = this.#pro(proId);
    const doc = pro.documents.find((d) => d.id === docId) ?? fail('not_found', 'Document not found');
    doc.status = 'rejected'; doc.reviewedAt = Date.now();
    doc.reason = String(reason ?? '').trim().slice(0, 200) || null;
    // a rejected document never keeps a profession unlocked unless another approved one covers it
    if (!pro.documents.some((d) => d.type === doc.type && d.status === 'approved')) {
      pro.approvedRequirements = pro.approvedRequirements.filter((r) => r !== doc.type);
    }
    return doc;
  }
  // Admin: everything waiting for review, oldest first.
  pendingDocuments() {
    return [...this.pros.values()].filter((p) => !p.deleted).flatMap((pro) => pro.documents.filter((d) => d.status === 'pending')
      .map((d) => ({ ...d, proId: pro.id, proName: pro.name, proPhone: pro.phone, typeName: requirementNames[d.type] ?? d.type,
        categories: pro.categories.filter((c) => getCategory(c)?.requirement === d.type).map((c) => getCategory(c).name) })))
      .sort((a, b) => (a.uploadedAt ?? 0) - (b.uploadedAt ?? 0));
  }
  setAvailability(proId, available) { this.#pro(proId).available = !!available; }
  updateLocation(proId, location) { const p = this.#pro(proId); p.location = location; p.locationAt = Date.now(); }

  canServe(pro, job) {
    const cat = getCategory(job.categoryId);
    if (!cat || !pro.serviceModes.includes(job.mode)) return false;
    const covers = pro.categories.some((c) => c === job.categoryId || c === cat.parent);
    return covers && (!cat.requirement || pro.approvedRequirements.includes(cat.requirement));
  }
  // Remote/phone work has no distance limit; onsite/delivery must be within the pro's
  // radius (for delivery: measured to the pickup point).
  inRange(pro, job, maxKm = pro.radiusKm) {
    if (!PHYSICAL.includes(job.mode)) return true;
    return !!pro.location && distanceKm(pro.location, job.location) <= maxKm;
  }

  // ---- Wallet ----
  topUp(proId, amount, method = 'card') {
    if (!(amount > 0) && !(amount < 0 && String(method).startsWith('admin:'))) fail('bad_amount', 'Amount must be positive');
    const pro = this.#pro(proId);
    pro.balance += amount;
    return this.#record(proId, 'topup', amount, { method });
  }
  // Self-service credit purchase. The pro starts one (pending); credit is added only when the
  // payment provider confirms it (confirmTopup), exactly once.
  startTopup(proId, amount) {
    if (!TOPUP_PACKAGES.includes(amount)) fail('bad_amount', 'Choose one of the credit packages');
    this.#pro(proId);
    const t = { id: randomUUID(), proId, amount, status: 'pending', createdAt: Date.now(), paidAt: null };
    this.topups.push(t);
    return t;
  }
  confirmTopup(id) {
    const t = this.topups.find((x) => x.id === id) ?? fail('not_found', 'Unknown payment');
    if (t.status === 'paid') return t; // providers retry webhooks
    t.status = 'paid'; t.paidAt = Date.now();
    this.#pro(t.proId).balance += t.amount;
    this.#record(t.proId, 'topup', t.amount, { method: 'card', ref: t.id });
    return t;
  }
  history(proId) { return this.ledger.filter((e) => e.proId === proId); }

  // ---- Requests (client side) ----
  // For delivery: location/address = pickup point, dropoff = { address, location }.
  // itemsCost: money the pro lays out for the client (e.g. buying the food) and gets back in full.
  createJob({ clientId, categoryId, mode = 'onsite', description, location, address, phone, media = [],
    urgency = 'normal', budget = null, allowCalls = false, paymentMode = 'direct', dropoff = null, itemsCost = null,
    clientPrice = null }) {
    const client = this.#client(clientId);
    const cat = getCategory(categoryId) ?? fail('bad_category', 'Unknown category');
    if (!cat.modes.includes(mode)) fail('bad_mode', `${cat.name} is not available as ${mode}`);
    if (cat.payment === 'in_app') paymentMode = 'in_app'; // e.g. travel: we pay the supplier
    if (paymentMode === 'in_app' && !this.payments) fail('payments_disabled', 'In-app payment is not available yet');
    if (!PAYMENT_MODES.includes(paymentMode)) fail('bad_payment_mode', 'Unknown payment mode');
    if (!description) fail('bad_description', 'Description required');
    if (PHYSICAL.includes(mode) && !location) fail('bad_location', 'Location required');
    if (mode === 'delivery' && !(address && dropoff?.address && dropoff?.location)) {
      fail('bad_dropoff', 'Delivery needs pickup and drop-off addresses');
    }
    if (itemsCost != null && !(itemsCost >= 0)) fail('bad_items_cost', 'Invalid items cost');
    // A fixed price lets the first matching pro who accepts it take the job (no offers round).
    // Not for travel: those prices come from supplier inventory.
    if (clientPrice != null && !(Number(clientPrice) > 0)) fail('bad_price', 'Invalid price');
    if (clientPrice != null && cat.parent === 'travel') fail('bad_price', 'Travel is priced by suppliers');
    const job = { id: randomUUID(), clientId, categoryId, mode, description, location: location ?? null,
      address: address ?? null, phone: phone ?? client.phone, media, urgency, budget,
      allowCalls: !!allowCalls, paymentMode, leadPrice: this.leadFees ? cat.leadPrice : 0, status: 'open',
      dropoff: mode === 'delivery' ? { address: dropoff.address, location: dropoff.location } : null,
      itemsCost: itemsCost == null ? null : Number(itemsCost),
      clientPrice: clientPrice == null ? null : Number(clientPrice),
      payMethod: client.payMethod ?? null,
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
      const d = PHYSICAL.includes(job.mode) ? round1(distanceKm(pro.location, job.location)) : null;
      this.notify(pro.id, { type: 'new_job', jobId: job.id, mode: job.mode, distanceKm: d });
    }
    return targets;
  }

  // What a pro (or the public board) sees. Contact details only when the client
  // allowed calls and the pro sent an offer, or after the client accepted the pro.
  teaser(job, viewer) {
    const pub = { id: job.id, categoryId: job.categoryId, mode: job.mode, description: job.description,
      urgency: job.urgency, budget: job.budget, allowCalls: job.allowCalls,
      paymentMode: job.paymentMode, leadPrice: job.leadPrice, status: job.status, createdAt: job.createdAt,
      itemsCost: job.itemsCost, clientPrice: job.clientPrice ?? null, payMethod: job.payMethod ?? null, offersLeft: Math.max(0, MAX_OFFERS - job.offers.length) };
    const approx = (l) => ({ lat: +l.lat.toFixed(2), lng: +l.lng.toFixed(2) });
    if (job.location) pub.location = approx(job.location);
    if (job.dropoff) {
      pub.dropoff = { location: approx(job.dropoff.location) };
      pub.tripKm = round1(distanceKm(job.location, job.dropoff.location));
    }
    if (viewer?.location && job.location) pub.distanceKm = round1(distanceKm(viewer.location, job.location));
    if (!viewer) return pub;
    pub.media = job.media; // photos/videos are shown to signed-in pros only, not on the public board
    const offer = job.offers.find((o) => o.proId === viewer.id);
    const assigned = job.assignedProId === viewer.id;
    // Agents never see the supplier's net price or the platform's cut.
    if (offer) pub.myOffer = { ...offer, items: offer.items?.map(({ net, netILS, platformFee, ...i }) => i) ?? null };
    if (assigned || (offer && job.allowCalls)) {
      Object.assign(pub, { phone: job.phone, address: job.address, location: job.location, dropoff: job.dropoff ?? undefined });
    }
    if (assigned) {
      const e = job.escrow;
      Object.assign(pub, { workLog: job.workLog, booking: job.booking ?? null,
        escrow: e && { amount: e.amount, status: e.status, payout: e.payout, fee: e.fee },
        takenAt: job.takenAt ?? null, completedAt: job.completedAt ?? null, closedAt: job.closedAt ?? null,
        proPayment: job.proPayment ?? null });
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
      .map(({ dispatchedTo, escrow, ...j }) => ({ ...j, tracking: this.#tracking(j),
        escrow: escrow && { amount: escrow.amount, status: escrow.status },
        rated: !!j.assignedProId && this.pros.get(j.assignedProId).ratings.some((r) => r.jobId === j.id),
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
    this.#charge(pro, job);
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
    this.#assign(job, offer);
    if (offer.items) {
      const sum = (k) => Math.round(offer.items.reduce((s, i) => s + i[k], 0) * 100) / 100;
      job.escrow.breakdown = { supplier: sum('netILS'), platformFee: sum('platformFee'), agentFee: sum('agentFee') };
      job.traveler = traveler;
      job.booking = { status: 'pending' };
    }
    this.notify(offer.proId, { type: 'offer_accepted', jobId });
    return job;
  }

  #charge(pro, job) {
    if (!(job.leadPrice > 0)) return; // free while lead fees are off
    if (pro.balance < job.leadPrice) fail('insufficient_credit', 'Insufficient credit');
    pro.balance -= job.leadPrice;
    this.#record(pro.id, 'offer_fee', -job.leadPrice, { jobId: job.id });
  }

  #assign(job, offer) {
    for (const o of job.offers) o.status = o === offer ? 'accepted' : 'rejected';
    job.assignedProId = offer.proId;
    job.status = 'assigned';
    job.takenAt = Date.now();
    // In-app: the client's card is charged now and the money is held until completion.
    if (job.paymentMode === 'in_app') {
      const reimburse = job.itemsCost ?? 0; // paid back to the pro in full, no commission
      job.escrow = { amount: offer.price + reimburse, reimburse, status: 'held' };
    }
  }

  // The client set a fixed price: the first matching pro who accepts it gets the job
  // right away; everyone it was offered to after that has missed it.
  // Synchronous => atomic in single-threaded Node (production: a conditional UPDATE).
  takeJob(jobId, proId) {
    const job = this.#job(jobId);
    const pro = this.#pro(proId);
    if (job.clientPrice == null) fail('no_price', 'This request has no fixed price - send an offer');
    if (job.status !== 'open') fail('taken', 'Another pro accepted first');
    if (!this.canServe(pro, job) || !this.inRange(pro, job)) fail('not_eligible', 'Not eligible for this job');
    let offer = job.offers.find((o) => o.proId === proId);
    if (!offer) {
      this.#charge(pro, job);
      offer = { id: randomUUID(), proId, eta: null, message: '', items: null, at: Date.now() };
      job.offers.push(offer);
    }
    Object.assign(offer, { price: job.clientPrice, instant: true });
    this.#assign(job, offer);
    this.notify(job.clientId, { type: 'job_taken', jobId, proId });
    for (const id of job.dispatchedTo ?? []) if (id !== proId) this.notify(id, { type: 'job_missed', jobId });
    return this.teaser(job, pro);
  }

  // Direct payments happen outside the app: the pro notes how and how much he was paid,
  // so his earnings history is complete.
  recordPayment(jobId, proId, { method, amount }) {
    const job = this.#job(jobId);
    if (job.assignedProId !== proId) fail('forbidden', 'Not assigned to you');
    if (!['completed', 'closed_done'].includes(job.status)) fail('bad_transition', 'Job not finished');
    if (job.paymentMode !== 'direct') fail('in_app_paid', 'Paid through the app');
    if (!PAY_METHODS.includes(method)) fail('bad_method', 'Unknown payment method');
    if (!(Number(amount) >= 0)) fail('bad_amount', 'Invalid amount');
    job.proPayment = { method, amount: Number(amount), at: Date.now() };
    return this.teaser(job, this.#pro(proId));
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
    (job.stamps ??= {})[status] = Date.now();
    if (status === 'completed') job.completedAt = Date.now();
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
      const reimburse = job.escrow.reimburse ?? 0;
      const base = b ? b.agentFee : job.escrow.amount - reimburse;
      const commission = Math.round(base * COMMISSION_RATE * 100) / 100;
      const fee = Math.round(((b?.platformFee ?? 0) + commission) * 100) / 100;
      const payout = Math.round((base - commission + reimburse) * 100) / 100;
      Object.assign(job.escrow, { status: 'released', fee, payout });
      this.#record(job.assignedProId, 'payout', payout, { jobId, fee });
    }
    job.status = 'closed_done';
    job.closedAt = Date.now();
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
    if (target.ratings.some((r) => r.jobId === jobId)) fail('already_rated', 'Already rated');
    target.ratings.push({ jobId, score, text });
    return target.ratings;
  }
  rating(user) {
    const n = user.ratings.length;
    return { ratingAvg: n ? round1(user.ratings.reduce((s, r) => s + r.score, 0) / n) : null, ratingCount: n };
  }

  // ---- Persistence (JSON snapshot; production: Postgres)
  snapshot() {
    return { pros: [...this.pros.values()], clients: [...this.clients.values()], jobs: [...this.jobs.values()], ledger: this.ledger, topups: this.topups };
  }
  restore({ pros = [], clients = [], jobs = [], ledger = [], topups = [] } = {}) {
    this.topups = topups;
    this.pros = new Map(pros.map((x) => [x.id, x]));
    // Licenses used to be one shared 'license' type; now each profession has its own.
    // Carry old approvals and documents over to the licensed professions the pro chose.
    for (const pro of this.pros.values()) {
      const keys = [...new Set((pro.categories ?? []).map((c) => getCategory(c)?.requirement).filter((r) => r?.startsWith('license:')))];
      if ((pro.approvedRequirements ?? []).includes('license')) {
        pro.approvedRequirements = [...new Set([...pro.approvedRequirements.filter((r) => r !== 'license'), ...keys])];
      }
      for (const d of pro.documents ?? []) if (d.type === 'license' && keys.length) d.type = keys[0];
    }
    this.clients = new Map(clients.map((x) => [x.id, x]));
    this.jobs = new Map(jobs.map((x) => [x.id, x]));
    this.ledger = ledger;
  }

  // Where the assigned pro is while he is on the way or on site, and a rough arrival time.
  // Only the client who owns the job gets this, and only while it is happening.
  #tracking(job) {
    if (!['en_route', 'picked_up', 'arrived'].includes(job.status) || !job.assignedProId) return null;
    const pro = this.pros.get(job.assignedProId);
    if (!pro?.location) return null;
    const target = job.status === 'picked_up' && job.dropoff?.location ? job.dropoff.location : job.location;
    const km = target ? distanceKm(pro.location, target) : null;
    // City driving ~25 km/h plus a minute of slack; "arrived" has no ETA.
    const etaMin = job.status === 'arrived' || km == null ? null : Math.max(1, Math.round(km / 25 * 60 + 1));
    return { lat: pro.location.lat, lng: pro.location.lng, at: pro.locationAt ?? null, km: km == null ? null : round1(km), etaMin,
      toward: target ? { lat: target.lat, lng: target.lng } : null };
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
