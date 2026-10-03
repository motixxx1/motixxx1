# Publishing to Google Play

What the code already does: release builds with R8, signed Android App Bundles, target SDK 36, edge-to-edge handling,
in-app and web **account deletion** (`/delete-account`), **privacy policy** (`/privacy`), **terms** (`/terms`),
no address box in the store build, plain http blocked when the server is https, production server refuses to start
without SMS. Listing text and graphics are in `store/`.

What only you can do:

## 1. Domain and HTTPS (required in practice)
The public address `http://87.68.15.249:3000` is a home IP over plain http. For Play use a domain with a certificate:
1. Buy a domain; point an A record at the server (or deploy to Render with the button in the README, which gives HTTPS for free).
2. On your own server put Caddy or nginx in front of port 3000 for the certificate.
3. GitHub → Settings → Variables → set `STORE_SERVER_URL` = `https://your-domain`.

## 2. Real SMS and payments
- `config.env`: remove `DEMO_MODE=1`, set `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM`. Without them a non-demo server won't start.
- Pros can't top up credit without a payment provider (the endpoint returns "payments disabled" outside demo mode). Connect a
  provider (e.g. Tranzila, Cardcom, Stripe) and credit the wallet from its webhook before launch, or Play reviewers and users
  will see a non-working flow.
- Set `ADMIN_PHONES` so you can approve documents.

## 3. Upload key (once)
```bash
keytool -genkeypair -v -keystore upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 upload.jks     # macOS: base64 -i upload.jks
```
Keep `upload.jks` and its passwords safe and backed up. Add repository secrets (Settings → Secrets and variables → Actions):
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`upload`), `ANDROID_KEY_PASSWORD`.
The next release then contains `ProMarket-client-play.aab` and `ProMarket-pro-play.aab`.
Never commit the keystore. Enroll in Play App Signing when asked.

## 4. Play Console
1. Create a developer account (one-time fee, identity verification; personal accounts must run a closed test with 12+ testers for 14 days before production).
2. Create two apps: `com.promarket.client` and `com.promarket.pro`; upload the matching `.aab` to a closed/internal test first.
3. Fill the listing from `store/listing.md`, upload icons, feature graphics and screenshots.
4. App content: privacy policy URL, **account deletion URL**, Data safety (table in `store/listing.md`), content rating, target audience 18+, ads: none.
5. Location permission: declare it is used in the foreground to match nearby requests (no background location).

## 5. Legal check
`/privacy` and `/terms` are drafts written from how the app works. Have a lawyer review them (Israeli privacy law, consumer
law, payments and marketplace liability, tax reporting for pros) and add your business name and address before launch.

## Risks to know
- Google's "minimum functionality" policy can reject apps that are only a website in a WebView. This app adds location,
  camera/gallery, dialer and navigation, but a native-feeling UI (see the React prototype port) lowers that risk.
- Installing the debug-signed APKs from the GitHub release over a Play version (or the other way around) needs an uninstall first, because the signing keys differ.
