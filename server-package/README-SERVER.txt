ProMarket – הפעלת השרת
=======================

1) מחלצים את הקובץ ונכנסים לתיקייה promarket-server

   לינוקס / Raspberry Pi:
       tar -xzf promarket-server-linux-x64.tar.gz      (או linux-arm64 / linux-armv7l)
       cd promarket-server
       ./start.sh

   ווינדוס:
       לחלץ את promarket-server-windows-x64.zip, להיכנס לתיקייה ולהקליק פעמיים על start.bat
       בחלון "חומת האש של Windows" – לאשר גישה (רשתות פרטיות).

   Docker (כל מערכת):
       לחלץ את promarket-server.zip, להיכנס לתיקייה, ולהריץ:  docker compose up -d

   בגרסאות linux / windows, Node.js כבר בפנים – לא צריך להתקין כלום.
   בקובץ promarket-server.zip (בלי Node) צריך Node.js 22 מותקן.

2) פותחים בדפדפן:
       http://192.168.1.244:3000        – לקוחות
       http://192.168.1.244:3000/pro    – מקצוענים / שליחים / סוכנים

3) מתקינים בטלפון את ה-APK (ProMarket-client.apk / ProMarket-pro.apk) פעם אחת.
   הם מוגדרים לכתובת החיצונית http://87.68.15.249:3000, ובבית עוברים לבד לכתובת הביתית אם הראשונה לא נגישה.
   מכאן העדכונים מגיעים דרך השרת.

חשוב לדעת
---------
* כדי שהאפליקציה תעבוד מכל מקום: בראוטר מפנים פורט 3000 (TCP) אל 192.168.1.244, ופותחים אותו בחומת האש.
  הכתובת החיצונית 87.68.15.249 חייבת להישאר קבועה. אם היא משתנה, האפליקציה תפסיק להתחבר עד שיעודכן SERVER_URL.
  בחנות האפליקציות נדרש דומיין עם HTTPS.
* פורט 3000 צריך להיות פתוח בחומת האש. בלינוקס עם ufw:  sudo ufw allow 3000
* כדאי שהשרת יקבל תמיד את אותה כתובת: להגדיר בראוטר "DHCP reservation" ל-192.168.1.244.
* הגדרות (טלפון אדמין, SMS אמיתי, ספקי נסיעות): עורכים את config.env ומפעילים מחדש.
* כניסה למשתמשים דורשת ספק SMS (ראו למטה). בלי ספק אי אפשר להיכנס.
  לניסיון בבית בלבד אפשר להוסיף DEMO_MODE=1 ב-config.env: הקוד מוצג על המסך. לא להשאיר בשרת ציבורי.
* הנתונים נשמרים במסד נתונים SQLite: data/zariz.db (נתונים ישנים מ-state.json מועברים אליו לבד).
  גיבוי יומי אוטומטי ב-data/backups (7 הימים האחרונים). אפשר לפתוח את הקובץ עם DB Browser for SQLite.
* הפעלה אוטומטית עם הדלקת המחשב (לינוקס): ראו promarket.service.

עדכונים אוטומטיים
------------------
* השרת בודק ב-GitHub כל חצי שעה אם יש גרסה חדשה ומתעדכן לבד. מסכים חדשים מגיעים
  לטלפונים מיד, בלי להתקין APK מחדש. לכבות: AUTO_UPDATE=0 ב-config.env.
* צריך להפעיל עם start.sh / start.bat (או promarket.service) כדי שהשרת יעלה מחדש אחרי עדכון.
* APK חדש צריך רק כשהאפליקציה עצמה משתנה. במקרה כזה האפליקציה תציע להוריד אותו.

SMS (חובה כדי שמשתמשים יוכלו להיכנס)
--------------------------------
* פותחים חשבון אצל ספק SMS ישראלי (או Twilio) וממלאים SMS_HTTP_URL או TWILIO_* ב-config.env.
* מפעילים מחדש את השרת.

כתובת HTTPS קבועה (חינם)
------------------------
1) נכנסים ל-duckdns.org (כניסה עם גוגל), יוצרים שם (למשל zariz-app) ומעתיקים את ה-token.
2) ב-config.env ממלאים:  DUCKDNS_DOMAIN=zariz-app   ו-   DUCKDNS_TOKEN=...
3) בראוטר מפנים את פורטים 80 ו-443 (TCP) למחשב הזה.
4) בתיקיית השרת:  sudo ./https-setup.sh
   (שרת שהותקן לפני שהקובץ קיים: מורידים אותו מ-
    https://github.com/motixxx1/motixxx1/releases/download/promarket-latest/https-setup.sh )
אחרי זה הכתובת https://zariz-app.duckdns.org עובדת, התעודה מתחדשת לבד, והשרת מעדכן את
DuckDNS כשכתובת ה-IP של הבית משתנה.

לפני חנות האפליקציות
--------------------
* השרת צריך כתובת ציבורית עם HTTPS (למשל Render, ראו render.yaml בפרויקט).
* ממלאים BUSINESS_NAME ו-SUPPORT_EMAIL: הם מופיעים במדיניות הפרטיות (/privacy),
  בתנאי השימוש (/terms) ובעמוד מחיקת החשבון (/delete-account).

מאגר פרטי ב-GitHub
* כשהמאגר פרטי, השרת צריך הרשאת קריאה כדי לקבל עדכונים ולהגיש את קובצי ה-APK לטלפונים.
* GitHub > Settings > Developer settings > Fine-grained tokens > Generate new token:
  Repository access: רק motixxx1, Permissions > Contents: Read-only.
* מוסיפים ל-config.env את השורה GITHUB_TOKEN=... ומפעילים מחדש.
* קישורי ההורדה לאפליקציות: https://zarizapp.duckdns.org/download/ProMarket-client.apk
  ו-https://zarizapp.duckdns.org/download/ProMarket-pro.apk

קרדיט למקצוענים
* מקצוען לא יכול להטעין לעצמו קרדיט בחינם. קרדיט נכנס רק בשתי דרכים:
  תשלום דרך ספק סליקה (TOPUP_URL), או מנהל שמוסיף אותו ידנית.
* דף ניהול: https://zarizapp.duckdns.org/admin – נכנסים עם טלפון שמופיע ב-ADMIN_PHONES וקוד ב-SMS,
  מחפשים את המקצוען ומוסיפים או מורידים קרדיט. כל פעולה נרשמת בהיסטוריה שלו.
* מצב דמו (DEMO_MODE=1) נכבה אוטומטית כשמוגדר ספק SMS.

SMS דרך SMSAPI (smsapi.com)
* בפאנל של SMSAPI: API Tokens > יוצרים טוקן עם הרשאת SMS. Sender names > מוסיפים שם שולח (למשל Zariz) ומחכים לאישור.
* ב-config.env:
    SMSAPI_TOKEN=הטוקן
    SMSAPI_FROM=Zariz
  ומפעילים מחדש. SMSAPI קודם ל-Twilio אם שניהם מוגדרים.
* בדיקה בלי לשלוח ובלי לשלם: SMSAPI_TEST=1 (להסיר אחרי הבדיקה).
