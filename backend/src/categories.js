// Hierarchical category tree (parent -> sub-categories). Seed of the 200+ tree.
// requirement: null | 'license' | 'insurance' | 'criminal_record'
export const CATEGORIES = [
  { id: 'plumbing', name: 'אינסטלציה', requirement: null, leadPrice: 25, subs: [
    { id: 'plumbing.unclog', name: 'פתיחת סתימות' },
    { id: 'plumbing.leak_camera', name: 'איתור נזילות במצלמה' },
    { id: 'plumbing.pipes', name: 'החלפת צנרת' },
  ] },
  { id: 'electric', name: 'חשמל', requirement: 'license', leadPrice: 30, subs: [
    { id: 'electric.panel', name: 'לוחות חשמל' },
    { id: 'electric.short', name: 'קצר' },
    { id: 'electric.ev_charger', name: 'התקנת עמדות טעינה לרכב' },
  ] },
  { id: 'renovation', name: 'בינוי ושיפוצים', requirement: 'insurance', leadPrice: 35, subs: [
    { id: 'renovation.tiling', name: 'ריצוף' },
    { id: 'renovation.drywall', name: 'עבודות גבס' },
    { id: 'renovation.demolition', name: 'שבירת קירות' },
    { id: 'renovation.paint', name: 'טיח וצבע' },
  ] },
  { id: 'locksmith', name: 'מנעולנות', requirement: 'criminal_record', leadPrice: 15, subs: [
    { id: 'locksmith.door', name: 'פריצת דלתות' },
    { id: 'locksmith.car_keys', name: 'שכפול מפתחות רכב' },
    { id: 'locksmith.safe', name: 'התקנת כספות' },
  ] },
];

const index = new Map();
for (const p of CATEGORIES) {
  index.set(p.id, { ...p, parent: null });
  for (const s of p.subs) index.set(s.id, { ...s, parent: p.id, requirement: p.requirement, leadPrice: p.leadPrice });
}

export const getCategory = (id) => index.get(id);
export const searchCategories = (q = '') =>
  [...index.values()].filter((c) => c.name.includes(q) || c.id.includes(q)).map(({ subs, ...c }) => c);
