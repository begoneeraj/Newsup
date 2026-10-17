# TruthLens India — submission status

This is a release candidate, not a published or approved Google Play app.
Publisher: Pushpraj singh prashant. Public email: begoneraj@gmail.com.
Package: `com.begoneeraj.newsup`. Current source version: `2.1.4` / code `11`.

## October 17 update

- Built `TruthLensIndia-2.1.4-candidate.aab` (65,385,412 bytes), SHA-256 `fbbde8a5a4c05720252fb259419b7cd1434343df955444e2c29b576e13a6a90b`. ZIP integrity and all 12 native libraries' 16 KB load alignment pass. Literal-value scan found none of seven configured server credentials and no packaged `.env` file. This limited scan is not a complete security audit.
- Installed/opened updated debug preview on Pixel emulator `emulator-5554`; Android reports version 2.1.4/code 11/target API 36. Guided-tour render using mock news data: `build/app-tour-preview.png`; device screen: `build/truthlens-v214-preview.png`. The tour render is not a production-data/store screenshot.
- Device screenshot confirms the real tour is visible over the live feed with the first 100 fact checks loaded. Debug APK also passes the same literal server-credential scan. Live sign-in, push delivery and actual account deletion remain unverified.
- Added an 11-step guided tour over actual controls, Skip/Back/Next/Done, persisted completion, and replay from the account menu.
- All 13 Flutter tests pass, including all five home tabs, tour replay and completion, small-screen large-text tour, search/detail navigation, pagination beyond 1,000, retry and refresh races. Fixed detail statistics overflow and ExpansionTile ink layering discovered by the smoke test.
- Final Flutter analyzer passes. Seven focused Python source-policy/quota/HTTPS/credential-redaction tests pass. Existing Cloud Functions checks: 19 tests and TypeScript type checking passed. The complete Python AI pipeline suite was not run; its heavyweight model dependencies are not installed locally.
- Read-only backend audit found 9,794 fact checks, 10,438 public events, 115 science reports, 559 promises, but only two data stories, five slow crises and six underreported topics at audit time. News jobs were succeeding. Added feed pagination and independent saved-item loading; search explicitly searches loaded items.
- Live Sources now links to original articles, credits GDELT when used, and shows a friendly unavailable state. Real Firestore access still needs device verification.
- Mediastack now uses HTTPS and a conservative 100/month free-plan quota slice. Guardian requests are spaced for its developer limit. Logs omit credential-bearing error details. No private configuration files are tracked by Git.
- Source allowlist enforcement is available when NEWS_DEPLOYMENT_MODE=production. It has NOT been activated on deployed jobs and does not retroactively license or remove existing material. No external backend changes were deployed.
- Free/developer plans confirmed by owner. Mediastack free and Guardian developer access are non-commercial. NewsData access does not supply publisher republication rights. Reddit reuse and the unofficial YouTube transcript scraper need rights/policy review. Do not treat a paid API key or AI rewriting as blanket copyright clearance.
- The Live Sources UI retains a legacy NewsAPI filter, but current local Functions only export GDELT ingestion/classification; no active NewsAPI fetcher/key was found in inspected source/configuration. If an external legacy job still uses NewsAPI, its developer plan is development-only, excluding staging/production: https://newsapi.org/pricing . Cloud secret values and externally deployed job configurations were not audited.
- For more content, prioritize attributed PIB first-party releases (excluding third-party material), datasets covered by GODL with required attribution, NASA/USGS first-party science material subject to their exceptions, GDELT discovery with link-out, and publisher feeds with explicit redistribution/AI-processing permission. These are researched options, not newly deployed integrations.
- Official references: https://mediastack.com/pricing ; https://open-platform.theguardian.com/access/ ; https://newsdata.io/terms ; https://redditinc.com/policies/data-api-terms ; https://developers.google.com/youtube/terms/developer-policies ; https://www.gdeltproject.org/about.html ; https://www.pib.gov.in/content/132_2_Copyright-Policy.aspx?lang=1&reg=1 ; https://data.gov.in/Godl ; https://www.nasa.gov/nasa-brand-center/images-and-media/ .

The verification below records the previous 2.1.3 candidate; it does not certify the new build until the new artifact checks are recorded.

## Verified locally

- Six Flutter tests passed: adult/policy gating, pre-consent policy access, small-screen text scaling, and deletion ordering/failure handling.
- Final `flutter analyze --no-pub`: no issues found.
- Signed release candidate AAB built successfully; SHA-256 `4c1bc4274477dc980ab0136a555c168f55159fce448fd5bd49ad0909c0d088d9`.
- JAR signature verifier reports `jar verified`; the certificate is self-signed, as is usual for Android upload keys. This is not Play approval.
- ZIP integrity and all 12 bundled native ELF libraries checked; load segments are aligned to at least 16 KB. Generated APK alignment and Play/device compatibility remain separate checks.
- Updated debug preview installed on Pixel 9: version 2.1.3/code 10, target API 36. It launches to the adult/privacy acknowledgement screen. Screenshot: `build/truthlens-v213-preview.png`.
- Policy HTML pages served and inspected locally. They have not been publicly deployed.

## Launch blockers

1. Create and verify a Google Play Console developer account. Complete identity, contact, payment and real-device verification as requested by Google. Do not register a fictitious company.
2. Policy website is LOCAL ONLY at the owner's request. Publish `sites/truthlens-policies/dist` on a public HTTPS host. Set `POLICY_BASE_URL` and rebuild. Use `privacy.html` for the privacy URL, `delete-account.html` for deletion, and `contact.html` for news publisher contact. URLs must work without login.
3. Apply `supabase/migrations/0025_unregister_device_token.sql` to the actual backend. Verify with a disposable notification token that it removes only the specified token, never grants SELECT access and is idempotent. This migration has not been deployed by this task. Notification disable/account deletion fail closed if it is absent.
4. Test actual sign-in and deletion using a disposable account on the signed build. Do not delete the owner's account for testing. Verify the Firebase user is gone, the device token is removed, local data is cleared, reauthentication cancellation does not delete data, and offline failures allow retry. Unit tests are not a live backend deletion test.
5. Set up Play App Signing. Add the **Play app-signing certificate** SHA-1/SHA-256 to Firebase/OAuth, not just the local upload certificate. Download updated `google-services.json` if needed and retest Google sign-in through a Play testing track.
6. Audit the live content corpus: original publisher/author and source links on every news item; valid attribution on aggregated/AI content; permissions/licences for any full text or media. Fix existing “Unnamed news outlet” and missing-source content in the ingestion pipeline. Do not claim all articles were manually verified. The automated feed needs an ongoing corrections/moderation process.
7. Resolve the existing Firestore API/configuration issue observed in the emulator's earlier logs and verify the Crisis Tracker Live Sources section, all tabs and filters against production. Confirm rules/indexes and operational backend jobs.
8. Add at least two fresh phone screenshots of the final signed app. Launcher icon and 1024×500 feature graphic are supplied. Screenshots must show real current UI; do not use old screenshots that overstate verification.
9. Complete News & Magazines, Data Safety, app access, ads, target audience, content rating and any applicable government-information declarations accurately. Target audience 18+ does not determine the IARC rating; answer the questionnaire based on actual violence, suicide and other sensitive news content.
10. New personal developer accounts normally require at least 12 opted-in testers continuously for 14 days before applying for production access. Recruit real testers, act on feedback and keep evidence of testing. Google decides production access and review approval.

## Data Safety working inventory — verify before submission

| Data | Behaviour | Purpose |
| --- | --- | --- |
| Name, email, user ID and profile picture | Google/Firebase account data; sign-in required | Account management and app functionality |
| Device/installation identifiers and FCM registration token | Optional push, Firebase and Supabase | Notifications/app functionality |
| IP address and technical service-request data | Backend, font/image and hosting providers | Delivery/security; assess SDK disclosures and ephemeral processing |
| Bookmarks, reading progress, preferences, age/policy acknowledgement | On-device; not uploaded by these features | Local functionality |
| Support messages | Voluntarily emailed | Support, correction and rights requests |

No ads/analytics SDK was found in the app dependency inventory. Do not declare “no data collected”: authentication and notification SDKs process data. Review Google's definitions of collection, sharing, service-provider exceptions and ephemeral processing, plus Firebase/Google Sign-In/Supabase disclosures. No precise location, contacts, camera or microphone permission is requested. Internet traffic uses HTTPS. Confirm any changes to SDKs before every release.

## Publisher operating responsibilities

Monitor the support mailbox. The prepared policy states a target acknowledgement within 24 hours and resolution within 15 days, subject to applicable law and explained delays. Maintain a private request log; verify account ownership without asking for passwords/OTPs. Fulfil manual deletion requests via Firebase Admin and scoped Supabase cleanup. Confirm and document actual provider log/backup retention, cross-border processing arrangements, applicable Indian news-publisher obligations and copyright licences before launch. Do not assume all intermediary/news-publisher rules apply identically to an aggregator. MeitY's DPDP implementation is phased; verify the provisions effective at launch.

## Build

`powershell -File scripts/build_play_bundle.ps1 -Candidate` produces a signed local candidate with no public policy URL. **Do not submit that candidate.**

After resolving blockers: `powershell -File scripts/build_play_bundle.ps1 -PolicyBaseUrl https://YOUR-PUBLISHED-POLICY-SITE/`

Keep the existing keystore and passwords private and backed up. Never commit `.env`, `android/key.properties` or the keystore. Version codes must increase for each Play upload. No Play Console upload, production release, account creation or policy-site publication has been performed.

## Official references checked 17 October 2026

- https://support.google.com/googleplay/android-developer/answer/13327111 — account deletion in-app and via a web resource.
- https://support.google.com/googleplay/android-developer/answer/9935326 — news sources and contact transparency.
- https://support.google.com/googleplay/android-developer/answer/16189314 — news declaration, including AI aggregators.
- https://support.google.com/googleplay/android-developer/answer/14151465 — new personal account testing requirements.
- https://developer.android.com/google/play/requirements/target-sdk — current target API requirements.
- https://developer.android.com/guide/practices/page-sizes — native 16 KB page-size support.
- https://www.meity.gov.in/documents/act-and-policies/digital-personal-data-protection-rules-2025-gDOxUjMtQWa — final DPDP rules and enforcement timeline.
