# ProMarket – הכל מהכל, קריאה אחת

**במקום לחפש בגוגל – פותחים קריאה ומקבלים הצעות.** שליח שיביא אוכל, מסירה משפטית, אינסטלטור, טכנאי מחשבים,
בייביסיטר, חופשה ביוון – כל מי שיש לו מומחיות (או רגליים ואופנוע) נרשם בדקה ומרוויח.

📄 **האפיון המלא: [`docs/PRD.md`](docs/PRD.md)**

## ⬇️ הורדה: https://github.com/motixxx1/motixxx1/releases/tag/promarket-latest
כל שינוי בקוד בונה מחדש את כל הקבצים אוטומטית (GitHub Actions).

| קובץ | מה זה |
|---|---|
| `ProMarket-client.apk` | אפליקציה ללקוחות |
| `ProMarket-pro.apk` | אפליקציה למקצוענים, שליחים וסוכנים |
| `promarket-server-linux-x64.tar.gz` | שרת למחשב/שרת לינוקס – **Node.js כלול** |
| `promarket-server-linux-arm64.tar.gz` / `-linux-armv7l` | שרת ל-Raspberry Pi – Node.js כלול |
| `promarket-server-windows-x64.zip` | שרת לווינדוס – Node.js כלול |
| `promarket-server.zip` | שרת בלי Node (ל-Docker או למי שיש Node 22) |

### הפעלת השרת על 192.168.1.244
```bash
tar -xzf promarket-server-linux-x64.tar.gz
cd promarket-server
./start.sh            # ווינדוס: להקליק פעמיים על start.bat
```
- לקוחות: `http://192.168.1.244:3000` · מקצוענים: `http://192.168.1.244:3000/pro`
- ה-APK כבר מוגדר לכתובת `http://192.168.1.244:3000` (משנים ע"י משתנה `SERVER_URL` ב-GitHub → Settings → Variables, או בתוך האפליקציה כשהיא לא מצליחה להתחבר).
- הגדרות (טלפון אדמין, SMS, ספקים): `config.env` בתיקיית השרת. הפעלה אוטומטית: `promarket.service`. פרטים: `README-SERVER.txt`.
- **192.168.x.x היא כתובת ברשת הביתית** – הטלפונים צריכים להיות על אותו Wi-Fi. לגישה מכל מקום: הפניית פורט + דומיין + HTTPS, או שרת בענן (למטה).
- פורט 3000 צריך להיות פתוח בחומת האש (`sudo ufw allow 3000`).

## 🌐 אפשרות: שרת בענן (Render)
[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/motixxx1/motixxx1)
לוחצים, נכנסים עם GitHub, ממלאים `ADMIN_PHONES`, ומקבלים כתובת `https://...onrender.com` (תוכנית Starter ~7$ לחודש כולל דיסק).

### ⚠️ מצב הדגמה
כל עוד לא מחוברים SMS אמיתי וסליקה, השרת רץ ב-`DEMO_MODE`: קוד הכניסה מוצג על המסך וטעינת קרדיט היא בלי תשלום.
**כלומר כל אחד יכול להיכנס בשם כל מספר טלפון – לנתוני הדגמה בלבד.** לפני משתמשים אמיתיים:
מגדירים `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM` (קוד הכניסה יישלח ב-SMS ולא יוצג), מחברים סליקה, ומסירים `DEMO_MODE`.

## מה עובד
- **הכל מהכל**: 26 תחומי-על ו-129 תתי-תחומים, חיפוש וקיצורי דרך. משלוחים, סידורים, מסירה משפטית, רכב, יופי, חיות, אירועים, דיגיטל, נסיעות, ועוד.
- **4 סוגי ביצוע**: אצל הלקוח · מרחוק · בטלפון · **איסוף ומשלוח** (נקודת איסוף + יעד, "השליח קונה עבורך" עם החזר מלא).
- **כניסה ב-SMS**, הרשמה בצעד אחד, 30 ₪ מתנה, חבר מביא חבר.
- **תמונות וסרטון בקריאה**: עד 8 תמונות וסרטון אחד (עד 100MB), מהגלריה או מצילום. תמונות מוקטנות לפני העלאה. רק מקצוענים מחוברים רואים אותם, לא הלוח הציבורי.
- **הצעות**: הטלפון של הלקוח מוסתר עד אישור; עד 5 הצעות לקריאה; דירוג הדדי.
- **תשלום** ישירות או באפליקציה (מוחזק עד אישור, 12% עמלה).
- **מלאי ספקים**: RateHawk (מלונות), Duffel (טיסות), ו**API לספקים שלך** (צימרים, אטרקציות, מוצרים) – סוכנים מוכרים עם רווח משלהם.
- **שמירת נתונים** לקובץ, איתור כתובות (OpenStreetMap), ניווט Waze, אישורי מסמכים ע"י אדמין.

## מבנה
| נתיב | מה יש |
|---|---|
| `backend/src/` | השרת: `marketplace.js` (קריאות, הצעות, תשלום), `categories.js`, `auth.js`, `catalog.js`, `partners.js`, `providers/`, `store.js`, `geocode.js`, `sms.js` |
| `backend/public/` | `index.html` – אתר/אפליקציית לקוח · `pro.html` – אתר/אפליקציית מקצוען |
| `android/` | שתי אפליקציות אנדרואיד (client / pro) מאותו קוד |
| `.github/workflows/` | בניית APK, חבילת השרת וקבצי Google Play |
| `render.yaml`, `backend/Dockerfile` | העלאה לאוויר |

## פיתוח מקומי
```bash
cd backend
npm start       # http://localhost:3000 (לקוח) · /pro (מקצוען)
```

| משתנה | למה |
|---|---|
| `AUTH_SECRET` | חובה בפרודקשן – חתימת טוקנים |
| `DEMO_MODE=1` | מצב הדגמה (ראו למעלה) |
| `ADMIN_PHONES` | טלפונים של אדמינים, מופרדים בפסיק |
| `DATA_FILE` | איפה לשמור את הנתונים (ברירת מחדל `./data/state.json`) |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM` | SMS אמיתי |
| `RATEHAWK_KEY_ID`, `RATEHAWK_API_KEY`, `DUFFEL_TOKEN` | ספקי נסיעות (לבדוק קודם ב-sandbox) |
