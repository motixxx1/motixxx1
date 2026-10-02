// Hierarchical category tree (parent -> sub-categories). Seed of the open-ended tree:
// any expertise can be added as a parent or sub. Subs inherit parent settings.
// requirement: null | 'license' | 'insurance' | 'criminal_record' | 'minors_clearance'
// modes: where the work can happen — 'onsite' (at the client), 'remote', 'phone'
// starter: no license/tools needed — anyone can sign up and take these jobs today
// payment: 'in_app' forces platform payment (e.g. travel, where we pay the supplier)
const ALL = ['onsite', 'remote', 'phone'];

export const CATEGORIES = [
  { id: 'computers', name: 'מחשבים וטכנולוגיה', requirement: null, leadPrice: 12, modes: ALL, subs: [
    { id: 'computers.repair', name: 'תיקון מחשבים ולפטופים' },
    { id: 'computers.software', name: 'התקנת תוכנה והסרת וירוסים' },
    { id: 'computers.network', name: 'רשתות ו-WiFi' },
    { id: 'computers.data_recovery', name: 'שחזור מידע' },
    { id: 'computers.phone_repair', name: 'תיקון סמארטפונים', modes: ['onsite'] },
  ] },
  { id: 'plumbing', name: 'אינסטלציה', requirement: null, leadPrice: 25, modes: ['onsite'], subs: [
    { id: 'plumbing.unclog', name: 'פתיחת סתימות' },
    { id: 'plumbing.leak_camera', name: 'איתור נזילות במצלמה' },
    { id: 'plumbing.pipes', name: 'החלפת צנרת' },
  ] },
  { id: 'electric', name: 'חשמל', requirement: 'license', leadPrice: 30, modes: ['onsite'], subs: [
    { id: 'electric.panel', name: 'לוחות חשמל' },
    { id: 'electric.short', name: 'קצר' },
    { id: 'electric.ev_charger', name: 'התקנת עמדות טעינה לרכב' },
  ] },
  { id: 'renovation', name: 'בינוי ושיפוצים', requirement: 'insurance', leadPrice: 35, modes: ['onsite'], subs: [
    { id: 'renovation.tiling', name: 'ריצוף' },
    { id: 'renovation.drywall', name: 'עבודות גבס' },
    { id: 'renovation.demolition', name: 'שבירת קירות' },
    { id: 'renovation.paint', name: 'טיח וצבע' },
  ] },
  { id: 'locksmith', name: 'מנעולנות', requirement: 'criminal_record', leadPrice: 15, modes: ['onsite'], subs: [
    { id: 'locksmith.door', name: 'פריצת דלתות' },
    { id: 'locksmith.car_keys', name: 'שכפול מפתחות רכב' },
    { id: 'locksmith.safe', name: 'התקנת כספות' },
  ] },
  { id: 'hvac', name: 'מיזוג אוויר', requirement: null, leadPrice: 20, modes: ['onsite'], subs: [
    { id: 'hvac.install', name: 'התקנת מזגן' },
    { id: 'hvac.repair', name: 'תיקון ומילוי גז' },
    { id: 'hvac.cleaning', name: 'ניקוי מזגנים' },
  ] },
  { id: 'help', name: 'עזרה ועבודות כלליות', requirement: null, leadPrice: 8, modes: ['onsite'], starter: true, subs: [
    { id: 'help.furniture', name: 'הרכבת רהיטים' },
    { id: 'help.handyman', name: 'תיקונים קטנים בבית (הנדימן)' },
    { id: 'help.carrying', name: 'סבלות ועזרה בהעברת דירה' },
    { id: 'help.garden', name: 'גינון' },
    { id: 'help.errands', name: 'סידורים ושליחויות' },
  ] },
  { id: 'travel', name: 'נסיעות ותיירות', requirement: null, leadPrice: 10, modes: ['remote', 'phone'], payment: 'in_app', subs: [
    { id: 'travel.hotel', name: 'מלונות' },
    { id: 'travel.flight', name: 'טיסות' },
    { id: 'travel.package', name: 'חבילת נופש (טיסה + מלון)' },
  ] },
  { id: 'moving', name: 'הובלות', requirement: null, leadPrice: 20, modes: ['onsite'], subs: [
    { id: 'moving.apartment', name: 'הובלת דירה' },
    { id: 'moving.small', name: 'הובלה קטנה' },
  ] },
  { id: 'cleaning', name: 'ניקיון', requirement: null, leadPrice: 10, modes: ['onsite'], starter: true, subs: [
    { id: 'cleaning.home', name: 'ניקיון בית' },
    { id: 'cleaning.post_renovation', name: 'ניקיון אחרי שיפוץ' },
  ] },
  { id: 'tutoring', name: 'שיעורים והדרכה', requirement: null, leadPrice: 8, modes: ['onsite', 'remote'], starter: true, subs: [
    { id: 'tutoring.private', name: 'שיעורים פרטיים', requirement: 'minors_clearance' }, // police clearance for work with minors
    { id: 'tutoring.tech_seniors', name: 'הדרכת מחשב וסמארטפון' },
  ] },
  { id: 'professional', name: 'ייעוץ ושירותים מקצועיים', requirement: null, leadPrice: 15, modes: ['remote', 'phone'], subs: [
    { id: 'professional.bookkeeping', name: 'הנהלת חשבונות' },
    { id: 'professional.legal', name: 'ייעוץ משפטי', requirement: 'license' },
    { id: 'professional.design', name: 'עיצוב גרפי ובניית אתרים' },
  ] },
  { id: 'other', name: 'אחר – כל מומחיות', requirement: null, leadPrice: 10, modes: ALL, starter: true, subs: [
    { id: 'other.general', name: 'משהו אחר' },
  ] },
];

const index = new Map();
for (const p of CATEGORIES) {
  index.set(p.id, { ...p, parent: null });
  for (const s of p.subs) {
    index.set(s.id, { leadPrice: p.leadPrice, modes: p.modes, requirement: p.requirement,
      starter: !!p.starter, payment: p.payment ?? null, ...s, parent: p.id });
  }
}

export const getCategory = (id) => index.get(id);
export const searchCategories = (q = '') =>
  [...index.values()].filter((c) => c.name.includes(q) || c.id.includes(q)).map(({ subs, ...c }) => c);
