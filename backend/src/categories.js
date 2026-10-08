// Hierarchical category tree (parent -> sub-categories). Anything a person can do for
// another person belongs here; "other" catches the rest. Subs inherit parent settings
// and may override them.
// requirement: null | 'license' | 'insurance' | 'criminal_record' | 'minors_clearance' | 'vehicle'
// modes: where the work happens — 'onsite' (at the client), 'remote', 'phone',
//        'delivery' (pick something up at A, bring it to B)
// starter: no license/tools needed — anyone can sign up and take these jobs today
// payment: 'in_app' forces platform payment (e.g. travel, where we pay the supplier)
const ALL = ['onsite', 'remote', 'phone'];
const ONSITE = ['onsite'];
const DIGITAL = ['remote', 'phone'];
const DELIVERY = ['delivery'];

export const CATEGORIES = [
  // ---- Delivery & errands
  { id: 'delivery', name: 'שליחויות ומשלוחים', requirement: null, leadPrice: 3, modes: DELIVERY, starter: true, subs: [
    { id: 'delivery.food', name: 'משלוח אוכל ממסעדה' },
    { id: 'delivery.groceries', name: 'קניות מהסופר / מהמכולת' },
    { id: 'delivery.pharmacy', name: 'איסוף מבית מרקחת' },
    { id: 'delivery.package', name: 'משלוח חבילה / מסמכים בעיר' },
    { id: 'delivery.intercity', name: 'משלוח בין-עירוני' },
    { id: 'delivery.large', name: 'משלוח פריט גדול (רכב מסחרי)', requirement: 'vehicle', leadPrice: 8 },
    { id: 'delivery.flowers', name: 'זרים ומתנות' },
  ] },
  { id: 'errands', name: 'סידורים ועזרה אישית', requirement: null, leadPrice: 5, modes: ['onsite', 'delivery'], starter: true, subs: [
    { id: 'errands.queue', name: 'עמידה בתור במקומך' },
    { id: 'errands.post', name: 'איסוף/שליחת דואר ודואר רשום' },
    { id: 'errands.office', name: 'סידורים במשרדי ממשלה / בנק' },
    { id: 'errands.home_wait', name: 'המתנה בבית לטכנאי או למשלוח (מעל גיל 18)' },
    { id: 'errands.personal_shopper', name: 'קניות אישיות' },
    { id: 'errands.elderly_companion', name: 'ליווי מבוגרים לבדיקות ולסידורים' },
  ] },

  // ---- Home services
  { id: 'plumbing', name: 'אינסטלציה', requirement: null, leadPrice: 25, modes: ONSITE, subs: [
    { id: 'plumbing.unclog', name: 'פתיחת סתימות' },
    { id: 'plumbing.leak_camera', name: 'איתור נזילות במצלמה' },
    { id: 'plumbing.pipes', name: 'החלפת צנרת' },
    { id: 'plumbing.boiler', name: 'דוד שמש / דוד חשמל' },
    { id: 'plumbing.fixtures', name: 'התקנת ברזים וכלים סניטריים' },
  ] },
  { id: 'electric', name: 'חשמל', requirement: 'license', leadPrice: 30, modes: ONSITE, subs: [
    { id: 'electric.panel', name: 'לוחות חשמל' },
    { id: 'electric.short', name: 'קצר' },
    { id: 'electric.ev_charger', name: 'התקנת עמדות טעינה לרכב' },
    { id: 'electric.lighting', name: 'תאורה וגופי תאורה' },
    { id: 'electric.solar', name: 'מערכות סולאריות' },
  ] },
  { id: 'renovation', name: 'בינוי ושיפוצים', requirement: 'insurance', leadPrice: 35, modes: ONSITE, subs: [
    { id: 'renovation.tiling', name: 'ריצוף' },
    { id: 'renovation.drywall', name: 'עבודות גבס' },
    { id: 'renovation.demolition', name: 'שבירת קירות' },
    { id: 'renovation.paint', name: 'טיח וצבע' },
    { id: 'renovation.waterproofing', name: 'איטום' },
    { id: 'renovation.kitchen', name: 'שיפוץ מטבח' },
    { id: 'renovation.bathroom', name: 'שיפוץ חדר רחצה' },
  ] },
  { id: 'carpentry', name: 'נגרות, אלומיניום וזכוכית', requirement: null, leadPrice: 25, modes: ONSITE, subs: [
    { id: 'carpentry.furniture', name: 'נגרות ורהיטים בהזמנה' },
    { id: 'carpentry.aluminum', name: 'אלומיניום, חלונות ותריסים' },
    { id: 'carpentry.glass', name: 'זגגות ומקלחונים' },
    { id: 'carpentry.blinds', name: 'וילונות ותריסים' },
    { id: 'carpentry.upholstery', name: 'ריפוד' },
  ] },
  { id: 'locksmith', name: 'מנעולנות', requirement: 'criminal_record', leadPrice: 15, modes: ONSITE, subs: [
    { id: 'locksmith.door', name: 'פריצת דלתות' },
    { id: 'locksmith.car_keys', name: 'שכפול מפתחות רכב' },
    { id: 'locksmith.safe', name: 'התקנת כספות' },
  ] },
  { id: 'hvac', name: 'מיזוג אוויר', requirement: null, leadPrice: 20, modes: ONSITE, subs: [
    { id: 'hvac.install', name: 'התקנת מזגן' },
    { id: 'hvac.repair', name: 'תיקון ומילוי גז' },
    { id: 'hvac.cleaning', name: 'ניקוי מזגנים' },
  ] },
  { id: 'appliances', name: 'תיקון מכשירי חשמל', requirement: null, leadPrice: 15, modes: ONSITE, subs: [
    { id: 'appliances.washer', name: 'מכונת כביסה ומייבש' },
    { id: 'appliances.fridge', name: 'מקרר ומקפיא' },
    { id: 'appliances.oven', name: 'תנור, כיריים ומדיח' },
    { id: 'appliances.small', name: 'מכשירים קטנים' },
  ] },
  { id: 'help', name: 'עזרה ועבודות כלליות', requirement: null, leadPrice: 8, modes: ONSITE, starter: true, subs: [
    { id: 'help.furniture', name: 'הרכבת רהיטים' },
    { id: 'help.handyman', name: 'תיקונים קטנים בבית (הנדימן)' },
    { id: 'help.carrying', name: 'סבלות ועזרה בהעברת דירה' },
    { id: 'help.garden', name: 'גינון' },
    { id: 'help.errands', name: 'סידורים ושליחויות' },
    { id: 'help.tv_mount', name: 'תליית טלוויזיה, מדפים ותמונות' },
  ] },
  { id: 'cleaning', name: 'ניקיון', requirement: null, leadPrice: 10, modes: ONSITE, starter: true, subs: [
    { id: 'cleaning.home', name: 'ניקיון בית' },
    { id: 'cleaning.post_renovation', name: 'ניקיון אחרי שיפוץ' },
    { id: 'cleaning.office', name: 'ניקיון משרדים' },
    { id: 'cleaning.upholstery', name: 'ניקוי ספות ושטיחים' },
    { id: 'cleaning.windows', name: 'ניקוי חלונות' },
    { id: 'cleaning.ironing', name: 'כביסה וגיהוץ' },
  ] },
  { id: 'garden', name: 'גינה, בריכה וחוץ', requirement: null, leadPrice: 12, modes: ONSITE, subs: [
    { id: 'garden.landscaping', name: 'גינון ועיצוב גינות' },
    { id: 'garden.irrigation', name: 'מערכות השקיה' },
    { id: 'garden.pool', name: 'תחזוקת בריכות' },
    { id: 'garden.trees', name: 'גיזום עצים' },
  ] },
  { id: 'pest', name: 'הדברה', requirement: 'license', leadPrice: 15, modes: ONSITE, subs: [
    { id: 'pest.general', name: 'הדברת מזיקים' },
    { id: 'pest.termites', name: 'טרמיטים' },
    { id: 'pest.rodents', name: 'מכרסמים' },
  ] },
  { id: 'moving', name: 'הובלות', requirement: null, leadPrice: 20, modes: ONSITE, subs: [
    { id: 'moving.apartment', name: 'הובלת דירה' },
    { id: 'moving.small', name: 'הובלה קטנה' },
    { id: 'moving.storage', name: 'אחסון' },
    { id: 'moving.crane', name: 'מנוף', requirement: 'license' },
  ] },

  // ---- Vehicles
  { id: 'auto', name: 'רכב', requirement: null, leadPrice: 15, modes: ONSITE, subs: [
    { id: 'auto.mechanic', name: 'מכונאי עד הבית', requirement: 'license' },
    { id: 'auto.battery', name: 'התנעה והחלפת מצבר' },
    { id: 'auto.tire', name: 'פנצ׳ר והחלפת צמיג' },
    { id: 'auto.towing', name: 'גרירה', requirement: 'license', leadPrice: 20 },
    { id: 'auto.wash', name: 'שטיפת רכב עד הבית' },
    { id: 'auto.inspection', name: 'ליווי לטסט / בדיקה לפני קנייה' },
  ] },

  // ---- Technology & digital
  { id: 'computers', name: 'מחשבים וטכנולוגיה', requirement: null, leadPrice: 12, modes: ALL, subs: [
    { id: 'computers.repair', name: 'תיקון מחשבים ולפטופים' },
    { id: 'computers.software', name: 'התקנת תוכנה והסרת וירוסים' },
    { id: 'computers.network', name: 'רשתות ו-WiFi' },
    { id: 'computers.data_recovery', name: 'שחזור מידע' },
    { id: 'computers.phone_repair', name: 'תיקון סמארטפונים', modes: ONSITE },
    { id: 'computers.smart_home', name: 'בית חכם ומצלמות אבטחה', modes: ONSITE },
  ] },
  { id: 'digital', name: 'שירותים דיגיטליים', requirement: null, leadPrice: 10, modes: DIGITAL, subs: [
    { id: 'digital.website', name: 'בניית אתרים וחנויות' },
    { id: 'digital.apps', name: 'פיתוח אפליקציות' },
    { id: 'digital.marketing', name: 'שיווק דיגיטלי ורשתות חברתיות' },
    { id: 'digital.design', name: 'עיצוב גרפי ולוגו' },
    { id: 'digital.video', name: 'עריכת וידאו' },
    { id: 'digital.writing', name: 'כתיבת תוכן' },
    { id: 'digital.translation', name: 'תרגום' },
    { id: 'digital.typing', name: 'הקלדה ותמלול' },
  ] },

  // ---- Professional & legal
  { id: 'legal', name: 'משפטי', requirement: null, leadPrice: 15, modes: DIGITAL, subs: [
    { id: 'legal.consult', name: 'ייעוץ עורך דין', requirement: 'license', modes: ALL },
    { id: 'legal.process_serving', name: 'מסירה משפטית של כתבי בי-דין', modes: DELIVERY, leadPrice: 10 },
    { id: 'legal.notary', name: 'נוטריון', requirement: 'license', modes: ONSITE },
    { id: 'legal.documents', name: 'הכנת מסמכים ומילוי טפסים' },
    { id: 'legal.mediation', name: 'גישור' },
  ] },
  { id: 'professional', name: 'ייעוץ ושירותים מקצועיים', requirement: null, leadPrice: 15, modes: DIGITAL, subs: [
    { id: 'professional.bookkeeping', name: 'הנהלת חשבונות' },
    { id: 'professional.tax', name: 'החזרי מס ודוחות', requirement: 'license' },
    { id: 'professional.insurance', name: 'סוכן ביטוח', requirement: 'license' },
    { id: 'professional.mortgage', name: 'ייעוץ משכנתאות' },
    { id: 'professional.real_estate', name: 'תיווך נדל"ן', requirement: 'license', modes: ALL },
    { id: 'professional.business', name: 'ייעוץ עסקי' },
  ] },

  // ---- People: education, care, health, beauty
  { id: 'tutoring', name: 'שיעורים והדרכה', requirement: null, leadPrice: 8, modes: ['onsite', 'remote'], starter: true, subs: [
    { id: 'tutoring.private', name: 'שיעורים פרטיים לתלמידים', requirement: 'minors_clearance' }, // police clearance for work with minors
    { id: 'tutoring.adults', name: 'שיעורים למבוגרים וסטודנטים' },
    { id: 'tutoring.languages', name: 'שפות' },
    { id: 'tutoring.music', name: 'שיעורי נגינה' },
    { id: 'tutoring.tech_seniors', name: 'הדרכת מחשב וסמארטפון' },
    { id: 'tutoring.driving', name: 'שיעורי נהיגה', requirement: 'license', modes: ONSITE },
  ] },
  { id: 'care', name: 'ילדים, מבוגרים וחיות', requirement: null, leadPrice: 8, modes: ONSITE, subs: [
    { id: 'care.babysitting', name: 'בייביסיטר', requirement: 'minors_clearance' },
    { id: 'care.elderly', name: 'מטפל/ת למבוגרים' },
    { id: 'care.dog_walking', name: 'הוצאת כלבים' },
    { id: 'care.pet_sitting', name: 'שמירה על חיות מחמד' },
    { id: 'care.pet_grooming', name: 'טיפוח כלבים' },
  ] },
  { id: 'wellness', name: 'בריאות וכושר', requirement: null, leadPrice: 10, modes: ['onsite', 'remote'], subs: [
    { id: 'wellness.trainer', name: 'מאמן כושר אישי' },
    { id: 'wellness.massage', name: 'עיסוי עד הבית' },
    { id: 'wellness.nutrition', name: 'תזונאי/ת', requirement: 'license' },
    { id: 'wellness.yoga', name: 'יוגה ופילאטיס' },
  ] },
  { id: 'beauty', name: 'יופי וטיפוח', requirement: null, leadPrice: 8, modes: ONSITE, subs: [
    { id: 'beauty.hair', name: 'תספורת ועיצוב שיער עד הבית' },
    { id: 'beauty.makeup', name: 'איפור' },
    { id: 'beauty.nails', name: 'מניקור ופדיקור' },
    { id: 'beauty.bridal', name: 'כלה וערב' },
  ] },

  // ---- Events
  { id: 'events', name: 'אירועים', requirement: null, leadPrice: 15, modes: ONSITE, subs: [
    { id: 'events.photography', name: 'צילום סטילס ווידאו' },
    { id: 'events.dj', name: 'DJ ומוזיקה' },
    { id: 'events.catering', name: 'קייטרינג ושף פרטי' },
    { id: 'events.staff', name: 'מלצרים וצוות אירוע', starter: true, leadPrice: 5 },
    { id: 'events.design', name: 'עיצוב ובלונים' },
    { id: 'events.kids', name: 'הפעלות לילדים', requirement: 'minors_clearance' },
  ] },

  // ---- Travel & supplier inventory
  { id: 'travel', name: 'נסיעות ותיירות', requirement: null, leadPrice: 10, modes: DIGITAL, payment: 'in_app', subs: [
    { id: 'travel.hotel', name: 'מלונות' },
    { id: 'travel.flight', name: 'טיסות' },
    { id: 'travel.package', name: 'חבילת נופש (טיסה + מלון)' },
    { id: 'travel.local', name: 'צימרים ונופש בארץ' },
    { id: 'travel.activities', name: 'אטרקציות וסיורים' },
  ] },

  { id: 'other', name: 'אחר – כל מומחיות', requirement: null, leadPrice: 10, modes: [...ALL, 'delivery'], starter: true, subs: [
    { id: 'other.general', name: 'משהו אחר' },
  ] },
];

// A license is per profession: an electrician's license does not unlock pest control.
// 'license' becomes 'license:<category>' (the field, or the specialty when only it is licensed);
// the other requirements (insurance, police certificates, vehicle) belong to the person.
const REQ_NAMES = { insurance: 'ביטוח צד ג׳', criminal_record: 'אישור היעדר רישום פלילי',
  minors_clearance: 'אישור משטרה לעבודה עם קטינים', vehicle: 'רישיון רכב ונהיגה' };
export const requirementNames = {};
for (const p of CATEGORIES) {
  if (p.requirement === 'license') p.requirement = `license:${p.id}`;
  for (const s of p.subs) if (s.requirement === 'license') s.requirement = `license:${s.id}`;
  for (const c of [p, ...p.subs]) {
    const r = c.requirement;
    if (!r) continue;
    c.requirementName = r.startsWith('license:') ? `רישיון ${c.name}` : REQ_NAMES[r] ?? r;
    requirementNames[r] = c.requirementName;
  }
}
export const isRequirement = (r) => !!requirementNames[r];

const index = new Map();
for (const p of CATEGORIES) {
  index.set(p.id, { ...p, parent: null });
  for (const s of p.subs) {
    index.set(s.id, { leadPrice: p.leadPrice, modes: p.modes, requirement: p.requirement, requirementName: p.requirementName,
      starter: !!p.starter, payment: p.payment ?? null, ...s, parent: p.id });
  }
}

export const getCategory = (id) => index.get(id);
export const searchCategories = (q = '') =>
  [...index.values()].filter((c) => c.name.includes(q) || c.id.includes(q)).map(({ subs, ...c }) => c);
