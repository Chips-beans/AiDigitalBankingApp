# Kesor Bank — progress and agent guide

Updated 7 November 2026, Asia/Phnom_Penh. This is the single place for **current status,
rules, setup, commands and open work**. Product detail lives in two sibling documents:

| Document | Covers |
| --- | --- |
| [CUSTOMER_APP.md](CUSTOMER_APP.md) | Customer App and the shared banking backend: auth, PIN, accounts, transfers, QR, analytics, AI assistant, Settings, Android notes |
| [MERCHANT_APP.md](MERCHANT_APP.md) | Merchant App: decisions, contracts, M0–M8 as built, M9 plan, deferred M10–M13 |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Hosting (Railway): what is live, Railway variables, runbooks for deploying changes, migrations, variables, Gmail token renewal, APK rebuilds, rollback, tear-down |
| This file | Progress, agent rules, environment, commands, conventions, backlog |

Other docs that stay next to the code: `AGENTS.md` (short pointer file for agents),
`README.md`, [CONTRIBUTING.md](../CONTRIBUTING.md), GitHub issue/PR templates, the module READMEs,
`showcase/README.md`, and `frontend/customer_app/docs/*` (screen-level
design notes and `WIFI_DEVELOPMENT.md`). More documents (for example a plan file) can be
added later; list them in the table above.

The earlier ~40 chronological reports, phase plans and handoffs were consolidated into
these three files. Nothing was lost: the last commit that still contains them is
`ccc10bd`. Read any old file with `git show ccc10bd:docs/<NAME>.md`.

---

## 1. Project snapshot

- Repository: `C:\Users\User\Documents\GitHub\AiDigitalBankingApp` (GitHub `Chips-beans/AiDigitalBankingApp`), current/default publication branch **`main`**; `railway-gmail-otp` merged on 7 November 2026.
- `backend/digital-banking` — Spring Boot 4.1, Spring Security, JPA, Flyway, PostgreSQL. Java 21 target (workstation JDK 24).
- `frontend/customer_app` — Flutter Customer App (`com.bank.customer_app`).
- `frontend/merchant_app` — Flutter Merchant App (`com.bank.merchant_app`), Android-first.
- `frontend/packages/kesor_design_system` (shared theme/tokens), `frontend/packages/kesor_auth_handoff` (app-to-app approval transport).
- Both apps share one backend and database. The Merchant App never has its own login: it signs in through approval in the Customer App.
- Latest schema: **V21** in source. The development database is behind (see §6).
- **Hosted:** backend live on Railway at `https://backend-production-18646.up.railway.app` (schema V21, Gmail API OTP, native Telegram) for a short live run, deployed from `main` commit `c3957fc` on 7 November; pilot APKs point at it. See [DEPLOYMENT.md](DEPLOYMENT.md).
- **Showcase live:** `https://showcase-website-production.up.railway.app`, isolated Railway `Showcase Website` service. Both APK download buttons work since 7 Nov (arm64-only debug APKs baked into the image, deployment `203ffb07`). Banking backend/database unchanged.

## 2. Progress

### Codex contributor attribution — 7 November 2026

At the user's request, a documentation contribution authored as **Codex
<noreply@openai.com>** records Codex's implementation and verification work in
`CONTRIBUTING.md`. GitHub's API confirms that this email links to the `codex`
account. Existing application edits are excluded from this attribution change;
no application build, test run or deployment is part of it. Details are in §8.

### Railway backend matches main — 7 November 2026

User-authorized backend-only deployment **`f97bf1e0-6079-4c16-9bd8-6bd14328a80b` SUCCESS**,
from `main` **`c3957fc`**, including the review fixes. Exact configuration fingerprints, variables,
domain, Postgres deployment/instance/volume and showcase service match the before-state.
Flyway validated all **20** migrations: schema **V21**, up to date, no migration necessary.
Application started with Gmail API active; public/protected route checks pass. Backend **275/275**
tested-source evidence retained. No APK/device work; M9 acceptance remains open. Deployment
records committed to `main`. Details and evidence are in §8 and DEPLOYMENT.md.

### Default-branch handoff — 7 November 2026

The user authorized merging and pushing `railway-gmail-otp` into the default branch.
`main` fast-forwarded from `c82a029` to `e4e13b9`, bringing in all five published commits,
including backend fixes `9217244`, repository organization and the complete showcase.
This companion documentation commit records `main` as the handoff entry point.
Application code is identical to the tested source branch; backend **275/275** and the
passing website-only build evidence remain applicable. Backend deployment subsequently completed
as recorded above; M9 acceptance remains open.

### Backend review fixes — 7 November 2026

All three repository review findings are fixed in backend commit `9217244`: test SMTP selection is pinned,
legacy merchant-pair creation/replay verifies ownership, and pair-opening fingerprints
cover type/category/merchant with safe promotion of verified legacy responses. No migration.
Baseline regressions reproduced **12 failures in 23 checks**; focused fixes **23/23** pass.
Final backend suite **275/275** passes with Gmail selected globally, zero failures/errors/skips;
both test harnesses override it to local SMTP. Evidence is recorded in §8 below. Backend source is
committed and deployed from `main` as recorded above; device/M9 acceptance remains open.
Customer §27 has the contract and §28 has deployment evidence.

### Repository organization — 7 November 2026

Root/module navigation, contribution instructions and GitHub issue/PR templates refreshed.
Browser-review output is ignored without deletion. Showcase has explicit website-only
dev/build/preview commands; its separate build output excludes local APK downloads.
Existing documents/source/assets preserved; organization and complete showcase source/assets
are included in the companion 7 November handoff commit. Source review
identified three backend follow-ups, recorded under §8 and Customer §26; the subsequent
fixes are summarized above and in Customer §27. No banking source changes or banking-suite
reruns were part of the earlier organization-only pass.

**Current publication/package summary:** default branch **`main`** contains backend fixes
`9217244` and organization/showcase handoff `e4e13b9`, merged from `railway-gmail-otp` on 7 November.
The user explicitly authorized publishing the full showcase and merging the handoff into `main`.
Latest recorded APK pair is `20261106-161530`, including wallet/auth fixes, still awaiting
device acceptance (Customer §25, Merchant §20). Showcase source, required assets and current
documentation are included in the handoff; its latest recorded live website deployment is the 6 Nov website-only
release. Implementation rows below also retain dated historical verification details;
publication/APK/deployment-pending wording in older rows is superseded by this summary.

### Customer App and backend

| Area | State |
| --- | --- |
| Banking updates published (6 Nov) | Customer/Merchant source, required assets, shared packages, backend PIN preview, tests and docs committed/pushed as `33595d6` on `railway-gmail-otp`. Earlier banking "uncommitted" notes below are historical. Live Railway backend already matches all 277 deployment inputs; healthy probes, no redeploy needed. APKs unchanged; showcase/local artifacts excluded. See §8 publication record. |
| Linked merchant wallets in Customer (6 Nov) | Empty placeholder removed. Actual merchant KHR/USD cards, balances, copy, read-only details/activity/receipts; no cards without business wallets. Isolated personal money flows, entry/pull refresh, stale/retry and session guards. Customer **307/307**, analysis clean, **96 responsive renders** without layout exceptions. Uncommitted; current APKs unchanged, device/live acceptance pending. Customer §22; Merchant §17. |
| Updated Customer Railway APK (6 Nov) | Built from current source with all latest designs and PIN Home preview. Debug/dev/API, unchanged Railway URL, verified package/signature/assets/CRC/checksum, previous APK archived. Not installed; device acceptance pending. Customer document §21; packaging evidence in §8 below. |
| AI Assistant Figma redesign (6 Nov) | Current `385:2708` implemented with exact three auto-send prompts and matching reference anchors. Customer **298/298**, analysis clean, **72 responsive renders**, no overflow. Uncommitted; packaged 6 Nov, no device/live-provider acceptance. Customer document §20–21. |
| Customer Figma Section 3 implementation (6 Nov) | Wallets, Wallet Detail, Transaction Detail and Customer splash implemented from `431:2446`. Customer **294/294**, analysis clean, **288 responsive renders**, no layout exceptions. Receipt PNG export and matching-wallet PIN continuation covered. Uncommitted; packaged 6 Nov, device acceptance pending. Customer document §19, §21. |
| Transaction & Wallet Detail Figma designs (6 Nov) | Initially created in section `422:2062`; Transaction Detail `426:993`, Wallet Detail `426:877`. User subsequently moved/edited them in section `431:2446`; Flutter implementation now recorded in Customer document §19. Original design record: §18. |
| Email OTP + Telegram (browser and native Android) sign-in, onboarding, profile photos | Built. User personally verified native Telegram login and Create Profile → PIN → Home on the Samsung tablet. |
| Server-enforced 4-digit PIN (V13), Home preview and protected-feature continuation | 6 Nov source implementation: recent transactions and manual favorites visible before PIN; all money masked; PIN continues selected feature. Every normal background visit locks; 3-minute foreground idle limit retained. Backend deployed to Railway 6 Nov (SUCCESS, 261/261 backend tests); included in the updated 6 Nov Customer APK. Device acceptance pending. |
| USD/KHR wallets (automatic at signup, V16), manual transfers with fixed 1 USD = 4,000 KHR, recipient lookup, transfer PIN proof | Built; full backend suite green. |
| QR receive/scan/pay (internal Kesor QR only), Save/Share QR card | Built. Camera/gallery acceptance on device pending. |
| Monthly Analytics | Built; user accepted the screen's appearance. |
| Optional Analytics watercolor asset (4 Nov) | Generated transparent Khmer money-planning PNG at `frontend/customer_app/assets/analytics/khmer-money-planning.png`; delivered separately, not wired into the screen. Uncommitted. |
| Optional Analytics header asset (5 Nov) | Generated transparent navy/gold wallet, coins and chart PNG at `frontend/customer_app/assets/analytics/monthly-money-overview.png` for above the month selector. Delivered separately; not wired into the screen. Uncommitted. |
| Read-only AI assistant (OpenAI-compatible gateway; Gemini removed 5 Nov 2026) | Built: `GENERAL`/`MIXED`, `TOTALS`/`COMPARE`, number-checked prose. Recorded 5 Nov Groq smoke: **16/16** EN/KM answers with `explanationStatus=AI`, 0.5–2.4 s, three format retries recovered. Railway flags enabled 6 Nov; hosted-device/provider acceptance remains pending. Customer §8; historical provider records in §8 below. |
| Settings (profile edit, PIN change, alerts, language/theme, FAQ) | Built; user confirmed "Settings looks correct and pages open". PIN change, notification delivery not personally tested. |
| Home (3 actions, Favorite Recipients), Wallet & Accounts screen, scanner UI, Receive QR redesign | Built; device acceptance pending. |
| Customer Figma section redesign (4 Nov) | Implemented all five frames in section `387:6034`: Home, Wallet, Analytics, AI Assistant and blurred My QR overlay. Customer 273/273 tests, 300 responsive renders without layout exceptions, analysis clean. Uncommitted; no APK/device acceptance. See Customer document §14. |
| Customer QR entry + Analytics Figma redesign (5 Nov) | Separate QR entry `404:901` and Analytics `413:5956` implemented from section `413:6086`; 284 Customer tests, 144 responsive renders plus 16 Analytics PNGs; no page scroll. User-approved smaller QR keypad targets in short landscape. Uncommitted; no APK/device/live work. Customer document §16. |
| Transfer success overflow fix (5 Nov) | Current Figma `308:740` proportions restored; confirmation/receipt fit one screen, no page scroll, both actions remain visible at full tap size. Native safe areas, compact portrait and landscape supported. Uncommitted; automated evidence below; no APK/device acceptance. See Customer document §15. |

### Showcase website

| Area | State |
| --- | --- |
| Railway website deployment (6 Nov) | **LIVE** at `https://showcase-website-production.up.railway.app`; final website-only deployment `b64073e6-b37a-448f-8425-388ebc0c1d48` SUCCESS. Includes all subsequent UI/credit/footer updates below. Public HTTP 200 and 1440/390/320 EN/KM checks pass. Backend/Postgres configurations, deployments, instances and database volume unchanged. APK hosting explicitly deferred; local APK download checks below do not apply to hosted routes. Source/docs remain uncommitted. |
| Say Kokann QA credit (6 Nov) | Role now `Back-end Developer · QA Tester`, with Khmer translation; description/layout retained. Production build and 320px EN/KM wrapping checks pass. Uncommitted, not deployed. |
| Footer cleanup and Figma action (6 Nov) | Removed student/location/year and course/academic-year blocks. Added a localized gold Figma button directly under GitHub using the supplied shared URL; Back to top retained. Production build and eight EN/KM footer checks at 1440/768/390/320 pass with matching button style, >=48px targets and no overflow. Uncommitted, not deployed; §8 evidence below. |
| Real links, APK downloads and team credits (6 Nov) | Buttons serve verified `20261106-161530` Railway APKs with download filenames; predev/prebuild sync checks latest size/hash/verification and packages ignored downloads. GitHub/Figma URLs set exactly as supplied. Seng: Back-end/Flutter/UX/UI + existing description and DevOps/hosting/deployment; Say: Back-end + backend/app testing; third profile unchanged. Both actual browser downloads match source hashes; 16 EN/KM × theme × width team checks pass. Uncommitted, not deployed; §8 below. |
| Theme and Khmer switches (6 Nov) | Added reference-style circular sun/moon control and EN/ខ្មែរ capsule beside GitHub/Figma, with saved preferences and system-theme default. Whole-page copy/captions/accessible labels translated; local licensed Google Sans for Khmer, Poppins retained for English. Khmer canvas shaping preserved. Production build and 16 theme/language/viewport cases pass at 1440/768/390/320, no overflow/broken images/runtime errors. Merchant mobile clipping fixed; header controls sit above the lanyard. Uncommitted, not deployed; §8 evidence below. |
| Section backgrounds and footer (6 Nov) | Current four-section page refined with approved porcelain/white/cool-gray/slate-navy/deep-navy fields and compact three-column footer, stacked on phones. All footer content/links retained. Hero/shared CSS prefix and 30 protected source files unchanged; all 21 measured section/hero geometry groups match at 1440/768/390/320. Production build and targeted contrast/keyboard/anchors/reduced-motion checks pass. Existing mobile Merchant clipping/320px overflow and seven baseline inspector finding categories retained. Uncommitted, not deployed; §8 evidence below. |
| Hero left-side spacing (6 Nov) | User subsequently authorized hero spacing edits. `showcase/src/hero.css` now groups headline/description/actions with content-driven text height, 32px desktop gaps and 16px button separation; phone gaps 24/28/12px. Type, colors, copy, hero JSX, splash, grid and lanyard unchanged. Production build passes; 1440/768/390/320 captures have no horizontal overflow and keep button sizes. Uncommitted; evidence in §8. |
| Below-hero showcase redesign (6 Nov) | Rebuilt `showcase/src/App.jsx` and below-hero `styles.css` using UI/UX Pro Max + design-taste-frontend: product introduction/navigation, Customer screen index, Merchant screen run, five-stage payment walkthrough, open technology rows, sample team roster and compact wordmark footer. Hero/splash/component sources and shared CSS prefix verified unchanged. Production build passes; inspector 1440/768/390 **0 FAIL, 3 WARN** with only protected splash timing/coverage allowances. Browser: all 12 selectors, five stages, keyboard/range, anchors and reduced motion pass; 1440/768/390/320 have no horizontal overflow/broken images. No deployment or commit. Evidence: §8 below. |
| Project showcase site (6 Nov) | Layout pass built in `showcase/` (Vite + React, brand navy/gold, Poppins): hero, Customer App, Merchant App, How it works (payment slider), Tech stack, Team, Footer. Screenshots are WebP copies of `Flutter Screen/` captures. **All content is placeholder** (APK/Figma links `#`, team, university/course, illustrative API log lines) in `showcase/src/data.js`. Hero rebuilt from Figma `437:2492`; its ID badge is React Bits Lanyard (`src/components/Lanyard.jsx`, three.js, lazy-loaded) with Kesor card/strap art in `public/lanyard/`. Hero background is React Bits CursorGrid aligned to the copy block; a StrokeText "KESOR Bank" splash (`src/Splash.jsx`) plays on every load, then the hero entrance runs. React Bits sources in `src/components/` carry small local edits (Lanyard window events/numeric anchor, CursorGrid origin, StrokeText width-only resize). Run `npm --prefix showcase run dev`. Not deployed; uncommitted. |

### Merchant App

| Milestone | State |
| --- | --- |
| Merchant sign-in diagnostics/recovery (6 Nov) | Specific EN/KM error messages and safe Copy details; distinct Android verification/opening failures, preserved HTTP status, failed-start and malformed-exchange recovery fixes. Full Merchant **144/144**, Customer handoff **38/38**, **192 responsive renders**, both Kotlin compile checks pass. Uncommitted; APKs unchanged, friend's exact cause/device acceptance pending. Merchant §18; Customer §23. |
| Updated Merchant Railway APK (6 Nov) | Built from current source with the full Figma Change list redesign and new splash. Debug/dev, unchanged Railway URL, verified package/signature/assets/CRC/checksum, previous APK archived. Not installed; device acceptance pending. Merchant document §16. |
| Merchant Figma splash (6 Nov) | White splash, original vector logo layers and shared Figma motion implemented from `418:6159`. Merchant **119/119**, analysis clean, **30 splash renders**, no layout exceptions. Uncommitted; packaged 6 Nov, device acceptance pending. Merchant document §15–16. |
| Merchant Figma Change list redesign (5 Nov) | Source implemented against all 28 frames in section `363:3084`; 118/118 Merchant tests, analysis clean, 294 responsive renders without layout exceptions. Uncommitted; packaged 6 Nov. Comparison/golden and device visual acceptance still open. Merchant document §14, §16. |
| M0 audit/contracts, M1 shell, M2 backend approval/sessions, M3 app-to-app sign-in | Complete. User confirmed on device: "Register Shop or my existing shop opens, including after reopening." |
| M4 shop registration + two wallets (V19), M5 dashboard/wallets, M6 QR collection (V20) | Source + automated checks complete, merged. **Not applied to the dev DB, no device acceptance.** |
| M7 sales, receipts, reports, sharing | Source + automated complete, merged (PR #1). Native sharing not device-verified. |
| M8 payment alerts + owner transfers (V21), G1 riel sign, G2/G4 notes | Source + automated complete, committed `dc1e4ef`, merged by PR #3. Android Kotlin compiled in Railway APKs; Railway at V21. V19–V21 not applied to local dev; no device approval. |
| **M9 integrated acceptance + pilot APKs** | **Packaging complete 6 Nov with explicit authorization.** Latest Railway APKs built and verified; installation and user acceptance pending, no backend restart performed. M9 is not complete. |
| M10–M13 (push/voice, cashiers/refunds, branches/payment links/AI, KHQR/Bakong) | Deferred. |
| Merchant Figma Quiet v2 redesign (4 Nov) | Implemented the 28 reference frames in Figma section `370:4356`: three tabs, drawer navigation, flat screens, bundled SVGs and adaptive numeric entry. 112 Merchant tests pass; 294 responsive renders without overflow; analysis clean; 34-state screenshot catalog exported. Uncommitted; no APK/device acceptance. See Merchant document §13. |
| Earlier Merchant UI refinement (4 Nov) | Welcome, Home, Collect, Sales and Merchant shared presentation widgets refined against the existing Kesor design system. Initial pass: 109 tests, analysis clean, 232 before/after renders. Later user request restores the original Home shop card/action tiles; see Merchant document §12 for current evidence. Uncommitted; no native/device acceptance. |

### Test baselines to keep green (backend 7 November; apps 6 November 2026)

| Suite | Result |
| --- | --- |
| Backend `./mvnw.cmd -o "-Dapp.mail.provider=gmail-api" test` | **275/275**, zero failures/errors/skips (7 Nov, all three review fixes; inherited Gmail overridden by both SMTP fixtures) |
| Merchant `flutter test test --concurrency=1` | **144/144** (6 Nov, sign-in diagnostics/recovery); 192 auth-error renders without layout exceptions, analyzer clean. Splash fixture 30 and earlier Change list fixture 294 renders remain historical evidence. |
| Customer `flutter test --concurrency=1` | **307/307** (6 Nov, linked merchant wallets); Merchant-wallet fixture 96 renders, analysis clean. Assistant fixture 72 renders and Section 3 fixture 288 renders remain earlier evidence, as do Customer Figma 300 and Merchant-transfer approval 24 renders. |
| `flutter analyze` both apps, `git diff --check` | Clean |

Customer and Merchant full suites and analysis were rerun for Section 3 on 6 November.
Latest Merchant sign-in evidence supersedes that Merchant baseline: 144/144, both analyzers
clean, Customer handoff/payment subset 38/38; the Customer full 307/307 run is the preceding
linked-wallet change. Both app Kotlin compile checks pass without APK assembly.
The backend baseline is the 7 November repository-review fix run, superseding the 6 November
261-test PIN deployment evidence. Flutter was unchanged and its suites were not repeated for
these backend fixes. The hosted backend now runs `main` commit `c3957fc`; deployment evidence is below.

## 3. Rules for every agent session

1. Read this file, then the product document for the area you touch. Read `AGENTS.md` for project rules.
2. **Preserve work.** Never reset, clean, stash-drop, force-push or delete someone's files. `.claude/` is untracked on purpose.
3. **Secrets.** Backend credentials live only in the ignored `backend/digital-banking/.env`. Never print, commit, document, log or package them (no `.env` in any APK). Never put keys in Flutter.
4. **Never request, enter or log a PIN, OTP, password or Telegram code.** The user does personal approval privately on the device.
5. **No APK build, dev-backend restart or dev-DB migration** without the user's explicit approval. Tests use embedded PostgreSQL and a local SMTP fixture (`PostgresIntegrationTest`), never the live database.
6. **Commit/push/merge only when asked.** Report "uncommitted" at checkpoints.
7. **Heavy jobs one at a time.** The PC has ~8 GB RAM: one Maven or Flutter run/build at once; stop Gradle daemons afterwards.
8. **Never weaken tests** to make them pass. Do not change expected balances to observed values; fix the cause.
9. **Format only the files you touched** (`dart format <files>`), then check `git diff --stat`.
10. **Money:** exact decimal strings (USD scale 2, KHR scale 0); never `double`; never add USD and KHR together. Business day = Asia/Phnom_Penh.
11. Applied Flyway migrations are immutable. Add the next version; when you do, bump `FoundationHandoffTests` (`getVersion()` and the applied-count assertion).
12. Do not touch the tablet's accessibility/developer settings (Don't keep activities = on, font scale 1.3). Install APKs with `adb install -r` (keeps data).
13. Cloudflare work: use the `cf` CLI unless the project has a Wrangler config.
14. **Usage reporting:** check available usage before each milestone and during long tasks. If a window has under 10% left, save a detailed checkpoint in this file, tell the user, and continue authorized work. Unavailable usage is not zero.
15. **Docs:** at each milestone update §2 of this file and the matching section of the product document. Do not add new per-milestone report files; add a short dated entry to §8 instead.
16. Report outcomes faithfully: separate automated evidence from device/personal acceptance and say what was *not* verified.

Checkpoint report template:

```
Milestone / step:
Built:
Tests: backend X/X, Customer Y, Merchant Z, fixture N renders, analysis clean?
Not done / not verified:
Decisions I made (with reason):
Committed?
Next step:
```

## 4. Environment and setup

### Prerequisites
Java 21+ with the Maven wrapper, PostgreSQL (workstation: PostgreSQL 18, DB `digital_banking_db` on `localhost:5432`), Flutter 3.47.x / Dart 3.13.x, Android SDK. A Gmail sender with an app password and controlled recipient inboxes are needed for live OTP. Docker, banking credentials and an AI key are not required for the base app.

### Backend configuration (`backend/digital-banking/.env`, ignored)
Copy `.env.example` if missing; edit existing keys, never duplicate a key.

| Setting | Notes |
| --- | --- |
| `DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD` | `localhost` / `5432` / `digital_banking_db` / your role. Do not recreate an existing DB. |
| `JWT_SECRET` | Base64 of ≥32 random bytes. `JWT_EXPIRATION_MS` 900000, `JWT_REFRESH_EXPIRATION_MS` 604800000. |
| `SPRING_PROFILES_ACTIVE` / `SERVER_PORT` | `local` / `8080` |
| `MAIL_HOST/PORT/USERNAME/PASSWORD/SMTP_AUTH/STARTTLS` | `smtp.gmail.com`, `587`, sender address, Google app password (needs 2-Step Verification), `true`, `true`. The `local` profile inherits Gmail defaults. |
| `MAIL_PROVIDER`, `GMAIL_CLIENT_ID/SECRET/REFRESH_TOKEN`, `GMAIL_SENDER` | `smtp` (default, uses `MAIL_*`) or `gmail-api` (HTTPS port 443, for hosts that block SMTP such as Railway Trial or Render free). Gmail API needs a Google Cloud OAuth client (Web application) and a refresh token for the sending account with scope `gmail.send`, obtained via OAuth Playground. Consent screen stays in **Testing**: the refresh token expires after ~7 days — create it just before going live and replace it when OTP mail fails with `invalid_grant` in the logs. Unknown provider value stops startup; blank Gmail settings only log a warning (names only). Sending account currently the user's own Gmail. |
| `DEV_SEED_ENABLED`, `DEV_SEED_PASSWORD` | Opt-in demo fixtures (`alice.demo`, `bob.demo`, `empty.demo`, `employee.demo`), local profile only. |
| `TEST_OPENING_FUNDING_ENABLED` | Default false. When true (only `local/dev/test/staging`), a new USD wallet gets 200.00 and a new KHR wallet 100,000 as `TEST_OPENING_CREDIT`. Startup fails under `prod`. |
| `TRANSFER_PIN_REQUIRED` | Enforced in dev since Phase 4.2; do not turn off. |
| `TELEGRAM_CLIENT_ID/SECRET/REDIRECT_URI`, `TELEGRAM_NATIVE_REDIRECT_URI`, `TELEGRAM_FRONTEND_ORIGIN` | Blank disables Telegram; email still works. Native redirect is `https://app937652339-login.tg.dev/tglogin`. Keep BotFather at RS256. |
| `AI_ENABLED`, `AI_CUSTOMER_CONTEXT_ENABLED`, `AI_API_URL`, `AI_API_KEY`, `AI_MODEL`, `AI_JSON_MODE`, `AI_REASONING_EFFORT` | Defaults off. Groq: URL `https://api.groq.com/openai/v1`, model `qwen/qwen3.8-27b` (must match an id from `GET /v1/models`), JSON mode `schema`, reasoning `none`. Free key from console.groq.com; free-tier limits are low (check the console limits page). Old `GEMINI_*` keys in your `.env` are now ignored; add the `AI_*` keys. |
| `MERCHANT_*` links, `app.merchant.*` | See [MERCHANT_APP.md](MERCHANT_APP.md) §3. Development defaults are the debug custom schemes. |
| `app.pin.pepper` | Defaults to the JWT secret; keep stable and backed up. Rotating it invalidates PIN hashes. |

### Start the backend
Check what owns port 8080 first; reuse a healthy instance, stop only that specific process to restart.

```powershell
Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue | Select LocalAddress,LocalPort,OwningProcess
# from backend/digital-banking, when the port is free:
.\mvnw.cmd spring-boot:run
```

A memory-capped launcher exists at `backend/digital-banking/.local/` (ignored). Swagger UI: `http://localhost:8080/swagger-ui/index.html` (select a group such as `foundation` or `merchant-auth`). API prefix `/api/v1`. Verify migrations with `SELECT version, success FROM flyway_schema_history ORDER BY installed_rank;` — never run Flyway clean.

### Live email check
Request a code with `POST /api/v1/auth/request-otp` (SIGNUP for a new address, LOGIN for an existing customer). HTTP 200 is intentionally generic and does not prove delivery: confirm in the real Inbox/Spam. Codes last 5 minutes; respect Retry-After. Automated tests never send real mail.

### Run / build the apps
```powershell
# Customer or Merchant app directory
flutter pub get
flutter run -d <device-id>       # emulator debug builds use http://10.0.2.2:8080/api/v1
flutter build apk --debug --dart-define=APP_ENV=dev --dart-define=APP_MODE=api --dart-define=API_BASE_URL=http://<PC-IP>:8080/api/v1
```

- USB device: `adb reverse tcp:8080 tcp:8080` (repeat after reconnect) and use `http://127.0.0.1:8080/api/v1`.
- Same Wi-Fi: use the PC's current IP (last used `172.16.128.192`); see `frontend/customer_app/docs/WIFI_DEVELOPMENT.md`. A changed API origin may need a new sign-in because secure storage is scoped by API URL.
- Use `GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1` for APK builds. Verify the compiled API origin, record SHA-256, confirm no `.env` inside the APK.
- Release App Links need a user-controlled domain and release certificate; none exists. Telegram's `tg.dev` domain must not be reused.

### Hosted deployment (Railway)
The backend runs on Railway for a short live run; both pilot APKs point at it. **Everything about
hosting — what is live, every Railway variable, and runbooks for deploying a change, adding a
migration, changing a variable, renewing the Gmail token, rebuilding APKs, rollback and tear-down —
is in [DEPLOYMENT.md](DEPLOYMENT.md).** Read it before touching the live system; changes to it need
the user's approval.

## 5. Commands

```bash
# backend/digital-banking  (log long runs to .local/<name>.log; full suite ~5 min)
./mvnw.cmd -o "-Dtest=MerchantSalesTests" test
./mvnw.cmd -o test
# On Windows stop any server running from target/*.jar before `clean verify`.

# frontend/customer_app and frontend/merchant_app
flutter analyze
flutter test test --concurrency=1
flutter test tool/merchant_visual_qa.dart --concurrency=1     # merchant visual fixture -> .local/qa/<milestone>/
```

## 6. Runtime and device (last known — recheck before relying)

- Development backend, PostgreSQL service `postgresql-x64-18`, USB forwarding and installed APKs were last observed on 31 October–3 November. The dev backend was then at **V18**; **V19–V21 are not applied**. Do not assume anything is running now.
- Devices: Samsung SM-X216B tablet `R9TXB0G1VKT` (Don't keep activities on, text scale 1.3, font weight +300) and a TECNO phone `1429155557104952`. Last installed Merchant APK was the M3 sign-in build; last Customer APK predates Merchant M4+.
- AI gateway: the recorded 5 Nov Groq live smoke passed; Railway AI flags were enabled 6 Nov.
  Local `.env` and current provider health were not inspected in the 7 Nov repository review.
- Local ignored evidence: `backend/digital-banking/.local/`, `frontend/*/.local/` (test logs, QA renders). APK outputs went to `C:\Users\User\Documents\Codex\2026-10-31\kesor-bank-is-a-digital-banking\outputs`.

## 7. Conventions

### Backend
- Every Merchant API starts with `sessions.merchant(user, sid)` then `MerchantShopService.requireShop(owner)`; owner/shop/wallet are **never** taken from the request.
- Register every new Merchant path in `SessionPurposePolicy.SHOP_ROUTES`; otherwise Merchant sessions get `CUSTOMER_SESSION_REQUIRED`.
- Errors: `ApiException(HttpStatus, "UPPER_SNAKE", "message")`; foreign/missing resources are a plain 404. Responses: `ResponseEntity` + `CacheControl.noStore()` + `ApiResponse.success(...)`.
- Request DTOs that create data reject unknown fields (`@JsonAnySetter` throws).
- Writes that move money or create records take `Idempotency-Key` (`[A-Za-z0-9_-]{16,128}`); store `sha256(key)` and `sha256(canonical body)`; same key+body replays, same key+other body is `409 IDEMPOTENCY_CONFLICT`.
- Rate limits: `MerchantAuthRateLimiter.check(lane, ownerId, perMinute)`; **lane names ≤ 15 characters**.
- Lock order: registered `payments` row → request/intent rows → accounts (accounts in id order).
- Merchant services use `JdbcTemplate` text blocks; JPA only where the module already does.
- Tests share one Spring context: `@SpringBootTest(classes = DigitalBankingApplication.class, webEnvironment = RANDOM_PORT, properties = "app.dev.opening-funding.enabled=true")`; reuse fixtures in `MerchantCollectionTests` (`shop()`, `payer()`, `pay()`, `race()`).

### Flutter
- Strings via `t(context, en, km)` and `mText(...)` (`lib/core/merchant_strings.dart`); every user-facing string has English and Khmer.
- Reuse the shared widgets (`SurfaceCard`, `NavyCard`, `ActionTile`, `StatusChip`, `NoticeBanner`, `KesorQrCard`, `ReceiptLines`…). The Merchant UI must keep matching the Customer App.
- Parse defensively (unknown values → `INVALID_RESPONSE`). An *uncertain* outcome (offline, timeout, 5xx, unparseable) means the server may have acted: never auto-resend a money operation; retry only with the original key.
- Controllers are per-owner `ChangeNotifier`s disposed on sign-out/owner change; ignore late responses (generation counters).
- Widget tests: set a tall viewport (`devicePixelRatio=1`, 480×2600); `pump` after `ensureVisible`; screens with timers use `pump(Duration)` not `pumpAndSettle`; scroll to top in fixtures with `ScrollableState.position.jumpTo(0)`.
- Add every new screen to the visual fixture and inspect representative renders (EN/KM, light/dark, 2× text, tablet).

## 8. Open work and backlog

### 7 November 2026 — Codex added through linked commit authorship

- The user requested Codex in the GitHub repository's Contributors list. Read-only
  GitHub API checks confirmed existing contributors `re4chh`, `Chips-beans` and
  `claude`, and that `noreply@openai.com` maps to the `codex` account. Earlier
  Codex assistance was credited through commit-message co-author trailers.
- Added a contribution acknowledgment and attribution guidance to `CONTRIBUTING.md`.
  This focused documentation contribution uses Codex as its Git author, retaining
  the configured human committer without changing repository/global Git identity.
  GitHub calculates the Contributors list from default-branch history and may
  refresh it asynchronously. The previously removed README section stays removed.
- Validation: documentation links and staged whitespace checked. Only these two
  documentation files are included; existing application edits and local artifacts
  are excluded. No application tests, APK build/install, deployment or DB change.

### 7 November 2026 — Handoff cleanup: contributors, license, redundant briefs

- README "Built with" section removed and a License section added. Added MIT `LICENSE` (copyright
  "Kesor Bank project team"; bundled fonts keep their OFL terms) — the user may change the
  license/holder. GitHub's Contributors sidebar is computed from commit authors, so AI assistants
  appear there only for commits they authored (follow-up commit authored as Claude); `Co-authored-by`
  lines do not add them.
- Removed `docs/MERCHANT_FEATURE_LIST.md` and `docs/MERCHANT_DESIGN_CHANGE_LIST.md` (obsolete redesign
  briefs that referenced the ignored local `Flutter Screen/` folder); recoverable from git history.
- Review found no tracked secrets. Possibly unreferenced images in both apps' `assets/` were
  reported but not removed (needs a build check). Committed and pushed to `main` at user request.

### 7 November 2026 — Backend fixes deployed from main; database/configuration preserved

- User explicitly requested deployment while preserving database and configuration. Uploaded only
  an audited committed backend snapshot from **`c3957fc7785dedd2ba6e77d4a0f5bd66a03611af`**,
  `main`: **278 files / 1,203,956 bytes**, snapshot SHA-256
  `cbb66365562007cfc18cb41c36b219797ed8c2a585dac0151912de52e217490b`.
  Inputs are Dockerfile, .dockerignore, pom.xml and src only; no credentials, frontend or outputs.
  All **276** tested source/pom inputs match after Git newline normalization (227 exact, 49 LF/CRLF);
  all **20** migrations exactly match the previous deployed snapshot. Backend **275/275** reused.
- Explicit project `c4ac8b7a-7a1a-4f08-9060-d0b444f05eda`, production environment
  `a7d550e4-e298-45d2-9c87-5bc778731653`, backend service
  `61f5742d-bc85-4d96-b802-0fe9915ae402`; `railway up` isolated payload with `--path-as-root`,
  `--no-gitignore`, `--detach`, `--json` and explicit selectors. Deployment
  **`f97bf1e0-6079-4c16-9bd8-6bd14328a80b` SUCCESS**; predecessor
  `8fc7d198-bdc9-4a93-bd16-793b8c6b9668` is the rollback reference.
- Full environment/service configuration fingerprints match exactly; all 25 configured backend
  variables/references, JWT/PIN secret, domain, scaling and build/deploy settings preserved.
  No variable values were printed or saved. Postgres deployment
  `0695dccd-17dd-4db5-ba42-8712d5fd9590` and running instance unchanged; database volume
  `0e36244d-ce49-453e-94e5-049a137505b7` (`postgres-volume-Dubs`), attachment and mount unchanged.
  Showcase deployment `b64073e6-b37a-448f-8425-388ebc0c1d48` and its volume/instance unchanged.
- Startup: 20 migrations validated, current V21, up to date, no migration necessary;
  `Started DigitalBankingApplication`, Gmail API provider active. HTTPS Swagger/foundation
  OpenAPI **200**, accounts/Merchant/pair-opening without auth **401**, foundation **44 paths**
  with pair-opening and PIN-preview contracts present. No authenticated money operation attempted.
- Evidence: `.local/railway-backend-main-20261107/` contains sanitized before/after snapshots,
  payload manifest, deployment identity, build events, startup verification, HTTP and route probes.
  No local .env read; credentials were not printed or saved in this evidence.
- No database recreation, new migration, configuration change, dev-backend restart, APK build/install,
  actual sign-in/payment or device acceptance. M9/hosted APK delivery remain open. These deployment
  records were committed to `main` on 7 November with the handoff cleanup below.
  Earlier undeployed-backend notes below describe prior steps and are superseded by this record.

### 7 November 2026 — Handoff merged into the default branch

- User explicitly requested merge/push to `main`. Fetched both branches and confirmed GitHub's
  default HEAD is `main`: old head `c82a029e4d1f833c1e96fb4694c9214ec500b93f`, source head
  `e4e13b9e465e8e4bf8575a07a6018eddab43e08e`. Main had no independent commits; the fast-forward
  brought over all five source-branch commits without conflict or application-source changes.
- Preserved the existing checkout, ignored local artifacts and the independent saved-recipients
  worktree. `railway-gmail-otp` remains available at its published head. Updated README/current
  progress, Customer handoff and deployment notes to identify `main` as the current entry point.
- Retained exact-source verification: backend **275/275**, zero failures/errors/skips under
  inherited Gmail override, and passing website build. Backend's 276 source/manifest inputs match
  the tested files after Git newline normalization (272 byte-identical, four CRLF/LF-only).
  Documentation links, diff checks and branch ancestry are checked before push;
  no repeated heavy suites for this code-identical merge.
- Push/ref confirmation and scope evidence: `.local/main-handoff-merge-20261107/`. Publication
  targets `origin/main` without force or history rewrite. No deployment, configuration/database
  changes, APK build/install or device acceptance; backend fixes remain undeployed and M9 is open.
  Earlier branch-pending notes below are historical and superseded by this default-branch record.

### 7 November 2026 — GitHub handoff publication

- User requested commit/push of the repository organization and backend fixes, then explicitly
  selected inclusion of the complete showcase source and assets so a fresh checkout is usable.
- Backend fix commit **`92172444e8c0ab647ac3b5b64637f1764d44ef39`** contains the five Java
  implementation/regression files. The companion **Organize repository and publish showcase
  source for handoff** commit includes navigation, contributor commands, issue/PR templates,
  refreshed product/deployment/progress docs, and complete showcase source/assets/lockfile.
- Exact-source test evidence retained: backend **275/275**, zero failures/errors/skips with
  inherited Gmail selected; website-only build/static preview/asset checks pass. All 276 backend
  source/manifest inputs still match the final test run. No repeated heavy suites for publication.
- Publication uses `origin/railway-gmail-otp`; `main` is unchanged. Audit and remote-ref
  confirmation are recorded in `.local/repository-publication-20261107/`. Credentials, local
  evidence, browser captures, exported screenshot collections, APKs, generated downloads,
  dependencies and build outputs are excluded. Showcase's required source WebP assets are included.
- No Railway deployment/configuration, dev-backend restart, database migration, APK build/install
  or device acceptance. Backend fixes remain undeployed; M9 and hosted APK delivery remain open.
  Earlier uncommitted/publication-pending entries below describe the state at those earlier steps
  and are superseded by this handoff record.

### 7 November 2026 — Three backend findings fixed (uncommitted)

- User requested fixes and regression tests for the three repository review findings.
  Parent implemented in the existing checkout; all prior organization/showcase/docs work preserved.
- Pinned the integration fixture's mail provider; added an explicit Gmail-selection override test
  that asserts SMTP before attempting delivery and confirms the local capture server receives it.
  The separate Foundation restart-test launcher now pins and asserts SMTP as well.
- Account-pair merchant requests now resolve/lock/check the actual owner's shop before creation
  or replay. Explicit foreign/missing shops return 404; unauthorized attempts create no accounts,
  postings or request row. Existing implicit owner requests continue to work.
- Fingerprints now include account type, normalized category and merchant ID. Stored type-only
  fingerprints can be upgraded from matching non-empty saved responses, without recreating or
  funding accounts. Pending/null/empty or mismatched legacy responses fail closed with 409;
  previously stored responses are never accepted for another category/shop. No Flyway changes.
- Regression-first evidence: isolated `git archive c6a9f8b` backend snapshot (no `.env`) with new
  tests, **23 total / 12 expected failures / 0 errors**, including foreign empty/partial shops,
  changed category/merchant, ambiguous legacy records and mail-provider selection. Fixed focused
  run **23/23**, then added null-JSON legacy coverage and fixture ownership cleanup before the
  final full run. First full run **275/275**; final rerun after restart-fixture hardening with
  `./mvnw.cmd -o "-Dapp.mail.provider=gmail-api" test` also **275/275**, **30 executed suites**,
  zero failures/errors/skips. Both harness XML reports confirm the inherited Gmail setting;
  SMTP assertions/local delivery still pass. All 12 baseline failures now pass. All **276**
  source/manifest inputs remain unchanged through the final run; no migration edits.
- Evidence in `.local/backend-findings-20261107/`: `verification.json`, `baseline-results.json`,
  `focused-results.json`, `initial-full-results.json`, source manifests, baseline/focused/full logs
  and `final-full-reports/`. Report totals count only executed suites, excluding stale older XML.
  The isolated baseline snapshot is retained as reproduction evidence. Local links and final
  diff checks pass; all **1,184** original files remain and the Git index is unchanged.
- Updated contributor/test instructions, Customer §26–27 and the deployment source-divergence note.
  All three findings resolved; ready for developer handoff. All changes uncommitted.
  No live deployment/configuration, backend restart, dev-DB migration, APK build/install,
  credentials read, real email/payment or device acceptance. Current hosted code remains the
  prior published version; these fixes need a separately requested deployment.

### 7 November 2026 — Repository review and organization (uncommitted)

- Used two read-only workers for structure/docs and banking-source review; parent integrated
  changes in the existing checkout. Baseline `c6a9f8b`, branch `railway-gmail-otp`; four existing
  modified documents and untracked showcase/output were preserved. Baseline hashes/diff:
  `.local/repository-review-20261107/`. No files moved or deleted, staged, committed or pushed.
- Added repository map and contributor commands, issue/PR templates, showcase onboarding and
  explicit website-only commands. Updated Merchant M1-era README, Customer wallet onboarding,
  AI contract/live-evidence summaries and Merchant evidence baseline. Browser captures under
  `/output/playwright/` are now ignored; original files retained.
- `build:website` uses a separate `dist-website/`, filtering local downloads; existing guarded
  APK commands and verification script remain intact. Deployment docs describe both paths.
- Verification: `npm --prefix showcase run build:website` passed (75 modules; existing lazy
  Lanyard >500 kB warning). Output **76 files / 9,167,997 bytes**, no downloads/APKs/`.env`;
  all **71** public assets byte-identical to source despite APKs present in `public/downloads/`.
  Default/website/preview config assertions pass; local preview serves HTML, JS, CSS, Khmer font,
  screenshot and logo with HTTP 200 (**6** probes). Independent source/diff review found no
  material issues. No browser visual acceptance claimed for these tooling-only changes.
- All **1,184** original source/document/output files remain; only the 12 intended existing
  files changed relative to the captured baseline. **55** relative links across **29** Markdown
  files resolve; **8** ignore/exception checks and npm lockfile metadata match pass.
  `git diff --check` clean. Evidence: `.local/repository-review-20261107/verification.json`
  and `preview-smoke.json`; baseline hashes and original docs diff kept alongside them.
- **Historical review follow-ups (resolved in the subsequent fixes above / Customer §27):**
  1. **P1 — Test mail-provider isolation:** `PostgresIntegrationTest` overrides SMTP connection
     settings but not `app.mail.provider`. Ambient `MAIL_PROVIDER=gmail-api` can select the Gmail
     API instead of local SMTP. Pin the fixture to SMTP and add a controlled override assertion.
     Contributor commands currently pass `-Dapp.mail.provider=smtp` as a temporary guard.
  2. **P2 — Legacy account-pair merchant ownership:** `AccountPairService.open` accepts supplied
     `merchantId` without resolving its owner. A foreign legacy/sparse shop missing a wallet can
     receive a newly created account assigned to the caller. Normal registration creates both
     wallets, limiting this condition. Authorize before creation; cover foreign/missing-wallet cases.
  3. **P2 — Account-pair idempotency:** the request fingerprint hashes `accountType` only; changing
     `accountCategory` or `merchantId` with the same key can replay an unrelated success. Canonicalize
     all operation-defining fields, plan compatibility for stored records and add regressions.
- No banking runtime changes, heavy banking suites, credentials read, APK work, device operations,
  backend restart, migration, live service change or external publication. This is a bounded review,
  not a comprehensive security audit. Next: resolve the backend follow-ups with isolated regressions;
  separately requested source publication and M9 acceptance remain open.

### 7 November 2026 — Showcase APK downloads fixed

- Cause: Trial limits (500 MB volume, ~216 MB upload cap) could not carry the all-ABI 245/231 MB debug APKs.
  User chose to rebuild arm64-only and bake the files into the image. `--target-platform android-arm64`
  alone still left plugin x86/ARMv7 libraries (179/165 MB); `--split-per-abi` gave **128,659,813**
  (Customer) and **95,949,078** (Merchant) bytes, versionCode 2001, same signing certificate as the
  previous APKs, SHA-256 `070840d5…2b0ac` / `7a81bc88…09bb`. Verified with `.local/verify_apk_refresh.py`
  (now honours `APK_SOURCE_NAME`) and promoted; previous all-ABI APKs archived. Evidence:
  `.local/apk-refresh-20261107-073812/` (two discarded attempts in subfolders).
- `showcase/hosting/nginx.conf` now serves `/downloads/*.apk` from the image (volume and gzip tricks removed).
  Package `.local/showcase-deploy-20261107/pkg` (153 MB compressed) deployed to the Showcase Website service
  only: `203ffb07-fa39-46dc-8f49-499fa7086146` SUCCESS. Public download hashes match; backend/Postgres
  deployments unchanged, Swagger 200. Dropped support: 32-bit ARM and x86 devices.
- Follow-up (user asked): stale showcase volume `32d81461…` deleted; automatic Showcase redeploy `8c5c8eb4…` online, both APK hashes re-verified; `postgres-volume-Dubs` and backend/Postgres deployments untouched.
- Not done: device install/acceptance.
- Usage checked: 37% (5-hour) and 91% (weekly) remaining.

### 6 November 2026 — Showcase website deployed; APK hosting deferred (superseded by 7 Nov above)

- User steering: "Deploy the Website First No need to care about apk now." Stopped task-specific
  APK transfer/batch processes and deployed the small website-only package. Deployment
  `b64073e6-b37a-448f-8425-388ebc0c1d48` **SUCCESS**, public URL
  `https://showcase-website-production.up.railway.app`, Nginx port 80. Includes all approved
  backgrounds, footer, theme/Khmer switches, links and QA Tester credit. No APKs in this package.
- Public HTTP 200; browser verification at 1440/en, 390/km and 320/en confirms exact viewport
  widths, updated role translations, footer Figma URL, removed metadata, no broken loaded images
  and no runtime errors. Reviewed desktop/mobile screenshots. Evidence:
  `.local/showcase-deploy-20261106/public-ui-verification.json`, `live-*.jpg`,
  `website-only-final-manifest.json`, `website-only-final-upload.log`.
- Protected banking comparison `banking-after.json`: no configuration changes; backend remains
  deployment `8fc7d198-bdc9-4a93-bd16-793b8c6b9668`, Postgres remains
  `0695dccd-17dd-4db5-ba42-8712d5fd9590`, database volume unchanged; Swagger HTTP 200.
- APK hosting remains deferred, not verified. Showcase-only volume retained with incomplete
  staging files; do not resume transfers without a new user request. Temporary registered SSH
  key revoked; fingerprint-guarded removal of generated private/public files confirmed.
  No banking mutation, APK rebuild/install, commit or push. This completion record supersedes
  the historical checkpoint below. Deployment runbook updated.

### 6 November 2026 — Historical Showcase deployment checkpoint (superseded above)

- User explicitly authorized deployment to the empty website service, preserving backend/database.
  Project `c4ac8b7a-7a1a-4f08-9060-d0b444f05eda`, production `a7d550e4-e298-45d2-9c87-5bc778731653`.
  Website service **Showcase Website** `57761625-19f6-4f2f-ba34-193668277189`; backend remains
  `61f5742d-bc85-4d96-b802-0fe9915ae402`; Postgres `326bd50b-2a12-40ea-9d40-173f781c06c0`.
- Website deployment `db6c2aa5-050a-4ce0-aee0-8f182183c144` SUCCESS; public domain provisioned:
  `https://showcase-website-production.up.railway.app`, target port 80. **APK delivery NOT complete.**
  Source build/current UI includes all approved edits and QA Tester credit. Initial 485MB payload
  upload failed 413 (216MB compressed); smaller public-only 9MB payload succeeded.
- Website-only volume `32d81461-0013-47f1-a309-020c0519c763` mounted `/apk-downloads`. Trial's
  default volume cannot hold both raw APKs; no subscription upgrade or banking changes performed.
  Final plan: store transparent gzip APKs (~208MB total); Nginx `gzip_static always; gunzip on`
  preserves original download filenames and bytes. Both modules verified present. Source configs
  are in `showcase/hosting/`; gzip-aware audited payload is `.local/showcase-deploy-20261106/web-payload-gzip`.
- Compressed APK records: `.local/showcase-deploy-20261106/compressed-apks.json`; canonical original
  hashes unchanged from 161530 release. Local gzip round-trip hashes verified. SSH/SFTP uploads
  have been slow/reset and currently left incomplete files; **do not claim downloads work yet**.
  A temporary personal SSH key `codex-showcase-20261106-temporary` was registered (fingerprint
  `SHA256:YvCMpGv5TLHcJv8ZIbOTE4JI/zl23MOvxA4UiUcn+cc`); private key is only in user `.ssh`.
  **Revoke this registered key after completion.** Native SSH configuration is the ignored
  `.local/showcase-deploy-20261106/ssh-config`, alias `kesor-showcase-upload`, pointing at current
  website instance `a20ea070-6fbc-493b-aed1-f903c2bf660a`. Regenerate if redeployment changes instance.
- Next: stop only task-specific transfer processes; deploy APK gzip pieces via source archives
  individually below the upload limit, with an entrypoint copying/assembling verified pieces into
  `/apk-downloads`. There are two ~60MB bank pieces and one ~87MB merchant gzip; three small
  deployments to **website ID only** avoid SSH transfer bottlenecks. Then run public verification.
- Evidence/baseline in `.local/showcase-deploy-20261106/`: `before.json` (protected bank configs,
  instances/deployments/volumes), audited manifests, logs, compression records, and pending
  `verify-live.mjs` which tests public UI and actual APK download SHA-256. Before backend probe
  through native Windows TLS: Swagger 200; Python's TLS store had an expired-root error, so use
  curl.exe/browser for public HTTPS verification. No banking mutation issued. Backend baseline
  deployment `8fc7d198-bdc9-4a93-bd16-793b8c6b9668`, Postgres `0695dccd-17dd-4db5-ba42-8712d5fd9590`.
- Usage checked: 9% primary / 86% secondary remaining; user notified. Continue authorized work.
  Preserve all work; no commits/pushes requested. Final docs/after-state verification still pending.

### 6 November 2026 — Say Kokann QA Tester credit (uncommitted)

- Added QA Tester beside Say's Back-end Developer role in EN/KM; kept his description and all
  other profiles/layout unchanged. Production build passes (existing lazy Lanyard size warning),
  diff check clean; both labels fit/wrap at 320px with no runtime errors. Captures/checks:
  `.local/showcase-say-qa/`. Usage checked: 36% primary / 90% secondary remaining. Not deployed.

### 6 November 2026 — Footer cleanup and Figma button (uncommitted)

- Removed both requested footer metadata blocks in all languages and their unused footer layout
  styles/import. Added `View on Figma` directly below GitHub, using the same gold button class and
  the existing shared Figma destination. Added Khmer label; kept Back to top and other content.
- Production build passes, including existing APK integrity preparation; only the existing lazy
  Lanyard size warning remains. Eight EN/KM × 1440/768/390/320 browser checks pass: metadata absent,
  correct destinations, Figma beneath GitHub, matching button fills, >=48px targets, no horizontal
  overflow/runtime errors. All eight screenshots reviewed. `git diff --check` clean.
- Evidence: `.local/showcase-footer-links/checks.json` and eight viewport captures. Usage checked:
  41% primary / 91% secondary remaining. Uncommitted; no deployment or APK/backend changes.

### 6 November 2026 — Showcase real links, Railway APK downloads and team credits (uncommitted)

- User supplied GitHub `.git` and Figma URLs; applied them to the shared link data (both GitHub
  links and the Figma button). APK links now use same-origin `/downloads/kesor-bank.apk` and
  `/downloads/kesor-merchant.apk`, with native download filenames `Kesor Bank.apk` / `KesorMerchant.apk`.
- Used latest verified active release **20261106-161530**, not the earlier 055520 pair. Customer:
  **245,526,174 bytes**, SHA-256 `03bbfe42c152ea830e358cc3995c2a4937c00fad7f6b438673ed7308aed20ec7`.
  Merchant: **231,059,332 bytes**, SHA-256 `ee2a462b55135fd41e7ec2146e0d550670cc51082c4f8d92f0709f8f42a18a3e`.
  Rechecked both canonical hashes against the active verification record; ZIP/kernel inspection
  confirms embedded Railway `/api/v1` URL and zero `.env` entries. No APK rebuilt or modified.
- Added `showcase/scripts/sync-apks.mjs` with `sync:apks`, predev and prebuild hooks. Checks both
  canonical files against the latest active release/size/hash/signature/Railway verification before
  packaging; copies verified files through a checked temporary file and emits an integrity manifest.
  Generated `public/downloads/` and production output are ignored. Missing/stale/unverified inputs
  fail preparation instead of shipping placeholder links. Deployment document records the workflow
  and corrects older prose that still described the preceding APK pair.
- Updated Seng's role to **Back-end Developer · Flutter Developer · UX/UI Designer**; kept his
  original description and appended DevOps, hosting and deployment credit. Say is **Back-end Developer**
  with backend development/app testing duties. Som's complete profile remains identical. Khmer
  translations updated for the changed roles/descriptions. No CSS/layout or component changes.
- Validation: production build passes (existing lazy Lanyard size warning), diff check clean.
  Clicked both actual APK buttons in Chromium, waited for completed downloads, and independently
  verified downloaded sizes/hashes against canonical release and `dist/` files. Exact GitHub/Figma
  destinations and download attributes verified. **16/16** EN/KM × light/dark × 1440/768/390/320 team
  checks pass with no text/horizontal overflow or runtime errors; all screenshot sheets reviewed.
  Third-profile identity/role/description/photo equality asserted. APK/generated paths verified ignored.
- Evidence: `.local/showcase-info/verification.json`, `apk-inspection.json`, actual browser downloads,
  16 Team screenshots and four sheets; generated `showcase/public/downloads/manifest.json`.
  Usage checked: 43% primary / 91% secondary remaining. No commit, push, public hosting/deployment,
  APK build/install, backend restart, migration or authenticated device/live-provider acceptance.

### 6 November 2026 — Showcase light/dark theme and Khmer language switches (uncommitted)

- User requested dark/light mode, Khmer with Google Sans, and reference-style controls aligned
  with GitHub/Figma at the top right. Implemented with design-taste-frontend and UI/UX Pro Max.
  Existing page/component structure, light palette, screenshot art and identity assets retained.
  Narrow headers retain the accessible brand name while visually showing the logo and icon links;
  new switches and links stay on one aligned row with >=44px targets down to 320px.
- `Preferences.jsx` supplies React context, native toggle/language buttons, translated accessible
  names/pressed states, safe storage and before-paint theme/lang updates. `i18n.js` contains Khmer
  page copy, headings, navigation, descriptions, captions, team roles/duties and image labels.
  Product/technology/person names and embedded screenshots remain original. `index.html` restores
  valid `kesor-theme` / `kesor-language` before first paint; first visit uses system theme + English.
  User choice persists across reload. Blocked localStorage falls back safely without disabling controls.
- `preferences.css` adds the reference's circle/capsule styling, navy dark palette, Khmer leading
  and responsive typography. Google Sans Regular/Medium/Bold and OFL license copied from existing
  Customer assets to `showcase/public/fonts/`; all 63 Khmer code points used are present in every
  weight. Browser platform-font inspection confirms custom **Google Sans Medium** draws the heading.
  English remains Poppins. No new dependency or remote font request.
- Hero canvas colors/grid/orbit path follow theme; Khmer hero words use Google Sans and whole-run
  shaping in TechText so dependent vowels/subscripts stay connected. CircularCarousel has optional
  accessible-label format props and updates translated metadata without reloading images/restarting
  the ring; its live announcement is localized. Header stacking and opaque theme-button background
  prevent the draggable badge/strap from covering controls. A `minmax(0,1fr)` mobile Merchant track
  fixes the previously recorded clipped copy and 15px overflow at 320px.
- Validation: production build passes (existing lazy Lanyard >500kB warning), `git diff --check`
  clean. **16/16** combinations of EN/KM × light/dark × 1440/768/390/320 pass: exact locale/theme
  state, fonts, translated captions, pressed state, >=44px targets, same-row header placement,
  unobstructed hit tests, no horizontal/text overflow, broken images or runtime exceptions.
  Reload persistence at all four widths, system-dark initialization and unavailable storage pass.
  Real Tab traversal/focus, Space theme activation and Enter language activation pass. New control
  text contrast >=12.92:1 (selected language 16.65:1), focus tokens >=12.79:1, dark prose >=11.51:1.
- Evidence: `.local/showcase-preferences/report.json`, `keyboard.json`, 56 settled captures and
  four contact sheets (all reviewed), `header-dark.jpg`, and `inspect-final/report.json`/sheets.
  Unmodified style conventions and splash timing remain inspector exceptions: final production
  scan reports five existing FAIL categories and six WARNs (including the new 14px control type
  size and a phone headline heuristic after hiding the brand wordmark). No zero-FAIL claim.
  The prior Merchant edge-text finding no longer occurs. No new images or proof/content invented.
- No commit, push, deployment, backend/database/APK work. Existing unrelated tree changes retained.
  Usage checked: 52% primary / 93% secondary remaining. Next: user visual/Khmer wording acceptance.

### 6 November 2026 — Showcase section backgrounds and footer (uncommitted)

- Implemented the user's approved plan using design-taste-frontend and UI/UX Pro Max. Current
  rendered sections are Customer, Merchant, Built together and Team; older showcase composition
  records below remain historical. Backgrounds are `#F4F7FA`, `#FFFFFF`, `#E9EFF5`, `#102A43`,
  then footer `#081626`. Tokens are scoped below the hero. Merchant shading and Team dome
  backgrounds/overlays inherit their section color; existing fades/masks/component behavior retained.
- Changed only `showcase/src/App.jsx` (two color props and Footer markup) and below-hero
  `showcase/src/styles.css`. Footer keeps all five links, wordmark, copy and project metadata;
  desktop/tablet uses three main columns and two metadata columns, <=760px stacks them. All links
  have >=44px targets and the gold action has a contrasting white keyboard focus ring.
- Production build passes (existing lazy Lanyard >500kB warning). Before/after browser capture at
  1440/768/390/320: all 21 measured hero/section geometry groups match at every width; all 30 other
  source files and the shared CSS prefix match. No new runtime errors, broken images or overflow.
  Footer target bounds/heights, all four anchor destinations including Back to top, five-link Tab
  traversal and visible focus pass. Reduced-motion footer content/zero transitions pass at all widths.
  Checked prose, stack labels, Team and footer text contrast is >=5.40:1; white footer focus against
  deep navy also exceeds 3:1. Desktop footer height reduces from 648.6px to 340.8px.
- Baseline limits preserved: Merchant mobile paragraph clips, and 320px document width is 335px both
  before and after. Full-page inspector retains the same seven FAIL categories (protected Hero
  star/splash timing/coverage/reduced-motion timing, existing component gradient/shadow, Merchant
  edge text), with four WARNs on production versus five on the prior dev baseline. These are not
  claimed fixed; no redesign of protected sections/components undertaken. Source lint likewise
  flags existing protected component effects and typography conventions.
- Evidence: `.local/showcase-backgrounds/` contains before/after source and geometry snapshots,
  captures, `comparison.json` (zero changes outside footer geometry), `checks.json`, local review
  notes, and `inspect-after/report.json` plus screenshot sheets. All final captures inspected.
  Usage checked: 69% primary / 95% secondary remaining. No commit, push, deployment, APK,
  backend/database change or content/placeholder replacement. Next: user visual acceptance.

### 6 November 2026 - Updated Railway APKs completed and verified

Both user-authorized debug/dev builds completed from `c6a9f8b`, unchanged Railway API, Customer API mode. Customer Gradle retry 360.8 s; Merchant 249.2 s. First Customer attempt was stopped for low-memory recovery; final builds used 1 GiB Gradle heap and in-process Kotlin, with Gradle stopped afterwards.

- customer_app: **245,526,174 bytes**, SHA-256 `03bbfe42c152ea830e358cc3995c2a4937c00fad7f6b438673ed7308aed20ec7`. Canonical filename unchanged; versioned copies `.local/apk/20261106-161530/`. Old APKs archived/checksummed before replacement.
- merchant_app: **231,059,332 bytes**, SHA-256 `ee2a462b55135fd41e7ec2146e0d550670cc51082c4f8d92f0709f8f42a18a3e`. Canonical filename unchanged; versioned copies `.local/apk/20261106-161530/`. Old APKs archived/checksummed before replacement.

Verified package IDs, matching pinned signatures, Railway URL, latest wallet/auth and native markers, required assets, CRC and no .env. All 550 source inputs unchanged; manifest `222b5c557d7ad94fb0b45183fefcb1872f4afd8d07e1250053e5bb2829ed7e85`. Evidence `.local/apk-refresh-20261106-161530/verification.json` and adjacent logs. Low-memory checkpoint superseded; interrupted-attempt evidence retained in the local build record.

Existing tests Customer 307/handoff 38, Merchant 144 and clean analyzers retained; no source change or repeated suites. Backend/Postgres SUCCESS, Swagger 200; no deploy/configuration/migration. No install, actual sign-in/payment or device acceptance; M9 remains open. Customer §25, Merchant §20 and deployment records updated. Documentation uncommitted; no commit/push.



### 6 November 2026 — Banking changes published; live backend confirmed current

- User explicitly requested commit/push and an up-to-date deployed backend, then selected banking
  updates together, excluding showcase. Commit **`33595d69ab1e0ca6f9763e8005d01919c095a2da`**
  (`Update banking apps, linked merchant wallets and sign-in recovery`) pushed successfully to
  `origin/railway-gmail-otp`; remote SHA verified. No merge into `main` requested or performed.
- Published **233 files**: Customer/Merchant UI/splashes and supporting assets, linked merchant
  wallet views, PIN Home preview/continuation, Merchant sign-in diagnostics/recovery, shared
  packages, tests/fixtures and project/deployment docs. Root `.gitignore` protects credentials,
  local agent/worktree/evidence files, exported screenshots and APKs. Staged audit found no
  credential/artifact inclusions. Unrelated `showcase/` preserved locally and uncommitted.
- Backend deployment **`8fc7d198-bdc9-4a93-bd16-793b8c6b9668`**, SUCCESS, already contains the latest
  backend source. All **277** recorded deployment inputs (including 31 test files and 20 schema
  migrations) match the working source byte-for-byte and the committed source after Git newline
  normalization. No new build inputs. Existing snapshot SHA-256:
  `98bfa5ada6963a9662c1206db68a8469403ab328e90d49f43f36a79b0f43e849`.
  **No redeploy needed or performed**; no Railway variables, secrets or database service changed.
- Live verified with normal Windows HTTPS clients: Swagger **200**, foundation OpenAPI **200**
  with **44** paths and PIN Home preview present; unauthenticated personal accounts and Merchant
  session both **401**. Schema remains V21. Postgres deployment remains
  `0695dccd-17dd-4db5-ba42-8712d5fd9590`, SUCCESS. Source comparison/probes/audit evidence:
  repository `.local/github-banking-publication/`.
- Existing exact-source automated evidence retained: backend **261/261**, Customer full **307/307**
  (wallet baseline) plus current handoff **38/38**, Merchant full **144/144**, both analyzers and
  Kotlin compile checks clean. No source changes or repeated suites needed for publication.
- Existing APK hashes unchanged; they do not contain the latest wallet/auth source fixes.
  No APK packaging/install, actual user sign-in/payment or device acceptance. Friend's failure
  remains unconfirmed until reproduction with updated diagnostics; M9 stays open. Customer §24,
  Merchant §19 and deployment source mapping updated. Historical "uncommitted" banking entries
  above/below are superseded by this publication; showcase remains outside it.

### 6 November 2026 — Merchant sign-in diagnostics and recovery (uncommitted)

- User approved the source plan for a friend's generic Khmer sign-in failure. Exact device cause
  remains unconfirmed: both apps installed, failure timing unknown, no attached device, available
  server logs inconclusive. Read-only checks: expected Railway backend SUCCESS/dev, Swagger 200,
  unauthenticated Merchant session 401. No live changes or authentication attempt.
- Implemented failure stage/code/status propagation with a safe allowlisted copy report; native
  missing/mismatched/unsupported/unopenable app distinctions; EN/KM explanations and actions.
  Existing pinning, explicit components, debug restrictions and exact links remain unchanged.
  Shared transport retains status for invalid JSON/envelopes. No credentials, callbacks, request
  bodies or account data are copied or logged.
- Explicit retry clears incomplete failed-start drafts but resumes known attempts. Malformed token
  results immediately require identical-body exchange recovery within 60 seconds; saved-token
  identity retries do not mint another session. Cancellation, uncertain refresh and late-result
  safeguards retained; storage errors typed, corrupt stored auth preserved. Late reopen failures
  cannot resurrect errors after cancellation.
- Merchant full **144/144**, Customer handoff/payment **38/38**. **192** error-screen renders
  (eight states, phone/tablet widths, EN/KM, both themes, 1×/2× text): no layout exceptions;
  Retry/Recover, Copy and Back reachable, targets ≥48dp. Eight sheets/full-size examples reviewed.
  Both Android Kotlin compile checks pass (no Flutter compilation or APK assembly); Gradle stopped.
  Both app analyzers and the final diff check are clean.
- Evidence: Merchant `.local/merchant-auth-{all-tests,analyze,visual,kotlin}.log`,
  `.local/qa/merchant-auth/`; Customer `.local/merchant-auth-{customer-handoff,analyze,kotlin}.log`.
  Regression tests `test/merchant_auth_diagnostics_test.dart`; fixture
  `tool/merchant_auth_visual_qa.dart`. Merchant §18 and Customer §23 updated.
- Existing uncommitted work/APKs preserved; no backend/configuration change, restart, migration,
  deployment, APK packaging/install, actual sign-in/payment, commit or push. APK checksums still
  match the 6 Nov packaging record. Usage checked: 41% primary / 21% secondary remaining.
  Next: separately authorized updated APKs and friend's approval → return → shop acceptance;
  collect safe error details if it recurs. M9 remains open.

### 6 November 2026 — Linked merchant wallets in Customer (uncommitted)

- Implemented the approved plan: real merchant KHR/USD cards below personal wallets with exact
  balances, status, copy, actual counts and details/activity/receipts. Empty merchant results hide
  the cards; approved sign-in without shop registration remains empty. Merchant sign-out preserves
  ownership. Existing Customer `accounts/me?category=MERCHANT` is sufficient; no backend changes.
- Merchant-only read adapter, separate account/history controllers and routes preserve personal
  transfer/QR selection. My QR is hidden on merchant details. Entry/pull refresh, loading, separate
  retry, explicit stale notice, full empty-list removal and session/generation guards included.
- Customer full **307/307**, new focused **9/9**, analyzer/diff checks clean. Visual fixture **96**
  renders across four states, three phone/tablet sizes, EN/KM, light/dark and 1×/2× text, without
  layout exceptions. Four contact sheets and representative full-size PNGs inspected. Logs in
  Customer `.local/merchant-wallets-{focused,all-tests,analyze,visual}.log`; images in
  `.local/qa/merchant-wallets/`; fixture `tool/merchant_wallets_visual_qa.dart`.
- Customer §22 and Merchant §17 updated. Existing uncommitted work and APKs preserved. No backend/
  Merchant source or tests changed/run, no build/install, restart, migration, deployment, real
  payment, commit or push. Automated fixtures are not authenticated live/device acceptance.
  Usage checked: 72% primary / 25% secondary remaining. Next: separately authorized Customer APK
  packaging and device comparison to the same owner's Merchant KHR/USD accounts. M9 still open.

### 6 November 2026 — Hero left-side spacing follow-up (uncommitted)

- User explicitly requested a cleaner left-side hero, superseding the earlier exact-hero restriction
  only for its spacing. Updated `showcase/src/hero.css`: unitless headline leading, auto-height
  supporting copy, 32px desktop content gaps, 16px separation between APK buttons; phone copy/action
  gaps 24/28px and button gap 12px. Kept original text, typography sizes, colors, button dimensions,
  copy origin, hero JSX/entrance timings, CursorGrid, Lanyard, splash and all below-hero source.
- Production Vite build passes (existing lazy three.js chunk warning). Before/after browser captures
  at 1440/768/390/320: no horizontal overflow; desktop buttons remain 256×64, phone 288×48.
  Desktop action row moved from y554 to y483, phone (390px) from y648 to y618; lanyard/hero frame
  sizes unchanged. Final production inspector 1440/768/390: **0 FAIL, 3 existing WARN**, with
  existing protected splash/coverage allowances; all final screenshot sheets viewed. Evidence:
  `.local/hero-spacing/` before/after CSS, PNGs, geometry logs and critique;
  `.taste-skill/hero-spacing/` final report and sheets.
- No deployment, backend/Flutter/device work, commit or push. Existing APK/Figma placeholders remain.

### 6 November 2026 — Showcase below-hero redesign (uncommitted)

- User requested removal of generic design while preserving the hero and splash exactly.
  Changed only `showcase/src/App.jsx` and the below-hero portion of `showcase/src/styles.css`;
  existing unrelated tree work preserved. Removed the generic marquee from the page without deleting
  its source. Retained navy/gold/Poppins, all actual product screenshots, both app feature browsers
  and payment slider. Replaced repeated split chapters/initials tiles/raw URL footer with distinct
  product compositions, open technology rows, a text roster and a compact Kesor wordmark close.
- Hero, splash, their Lanyard/CursorGrid/StrokeText sources/styles and `data.js` match before hashes;
  original font declarations, tokens and shared CSS prefix match exactly. Assets, entrance timing,
  3D badge interactions and hero placeholder destinations were untouched. Roster/course remain sample
  content, explicitly labelled; illustrative payment screenshots are not live transaction evidence.
- `npm --prefix showcase run build` passes (existing lazy three.js >500 kB warning remains).
  Changed-source taste lint **0 FAIL** (Poppins brand notices only). Final production inspection at
  1440/768/390: **0 FAIL, 3 WARN**, with `--allow late-title,covered-text` exclusively for the
  user-protected splash covering the existing hero during load. No new content excluded. Remaining
  warnings: type-size count includes protected hero; product interface imagery rather than photography;
  no supplied honest process video. All ten final inspector screenshots and settled hero/customer
  screenshots visually reviewed. Final self-critique **7.46/10**, limited by sample team/course and
  placeholder APK/Figma links; not external design acceptance.
- Browser exercise: all **12** app selectors and **5** payment stages update their intended screens;
  keyboard Enter and range Home/ArrowRight work; five section links resolve; reduced-motion content
  visible; no page exceptions. At 1440/768/390/320, no horizontal overflow, broken images or new
  button targets under 44px. Baseline blank-gap warning removed. No backend/Flutter/device suites
  needed or run for this website-only change.
- Evidence: `.taste-skill/showcase-before/`, `showcase-after/`, `showcase-final/` (production reports
  and screenshot sheets), `.taste-skill/showcase-redesign/notes.md` (inventory, copy, dealt direction,
  adaptations and critiques; seed 973830440), `.local/showcase-redesign/` (source snapshots, protected
  hash verification, browser-check JSON/log and settled PNGs). No third-party imagery added.
- Usage checked: 91% primary / 28% secondary remaining. Uncommitted; no push or live deployment.
  Next: user visual review, then replace sample project/team/download data before any authorized launch.

### 6 November 2026 — Updated Railway APKs built and verified

- User explicitly requested updated APKs for both apps using Railway. Built sequentially from the
  current uncommitted tree, base `e6c58b677b5688c23b4e5ef06b8293aea5121903`, preserving all existing
  work. Both `flutter build apk --debug` succeeded (Gradle Customer 193.1 s, Merchant 160.1 s).
  Defines: both `APP_ENV=dev`, `API_BASE_URL=https://backend-production-18646.up.railway.app/api/v1`;
  Customer also `APP_MODE=api`. Gradle daemons disabled and stopped after each build.
- Customer `frontend/customer_app/.local/apk/Kesor Bank.apk`: **245,521,948 bytes** (234.15 MiB),
  SHA-256 `6F74DCEED6FCB7CA10030E9B2B784D469BBEF1B26DE10ED3C867A803D433A214`.
  Includes latest Assistant with all three exact auto-send questions, Wallets/Wallet Detail/Transaction
  Detail, navy splash, QR/Analytics, transfer-success and PIN Home preview work.
- Merchant `frontend/merchant_app/.local/apk/KesorMerchant.apk`: **205,414,739 bytes** (195.90 MiB),
  SHA-256 `EB495F273A84059DC4B568FFB123873CF1B125BE2B633646F3FF67EE394B6C01`.
  Includes latest Figma Change list designs, white Merchant splash and M4–M8 functionality.
- Versioned copies: each app's `.local/apk/20261106-055520/`. Previous canonical APKs copied into
  each app's `.local/apk/archive/20261106-055520-previous-<old-hash-prefix>/` and verified before
  replacement; no old APK deleted. New canonical/versioned checksums match.
- Verified expected package IDs (`com.bank.customer_app`, `com.bank.merchant_app`), valid v2
  signatures matching previous APKs, Railway URL in both kernels, old Wi-Fi address absent,
  zero `.env` entries, latest design markers/original assets and ZIP CRC checks. All **550** recorded
  app/shared build inputs stayed unchanged. Source manifest SHA-256:
  `c3f6e6ec4eca56be1d5af0643b472c8c9cc80460fcec0bc5e801564ce81c2a60`.
- Evidence: repository `.local/apk-refresh-20261106-055520/` contains source manifests,
  `{customer,merchant}-build.log`, Gradle-stop, signature and package logs plus `verification.json`.
  Existing baselines retained: Customer **298/298**, Merchant **119/119**, both analyzers clean;
  no source change or suite rerun needed for packaging. Read-only live probes: Swagger **200**,
  unauthenticated accounts **401**. Usage checked: primary 85%, secondary 30% remaining.
- No installation, authenticated device/live-provider acceptance, backend/configuration change,
  restart, migration, payment, commit or push. M9 installation/user acceptance remains open.
  Customer §21, Merchant §16 and deployment current-APK record updated. Next: install on the user's
  requested device when authorized, then follow Merchant §9 acceptance without changing device settings.

### 6 November 2026 — AI Assistant Figma redesign completed (uncommitted)

- Implemented current `385:2708`: welcome spacing/type/emblem, original updated SVG, faint gold glows, exact three horizontal questions above the inset composer. At 440×999 the emblem, questions and composer start at y154/y821/y887. Back circle is 44px with a 48px target; title aligns at x72. Device system chrome remains native.
- Exact prompts auto-send via the existing controller: `How much did I spend this week?`, `How does the 50/30/20 rule work?`, `Show my biggest payment this month`. Khmer equivalents provided. Double taps send once; unavailable/pending/privacy gates, history, recovery, keyboard and PIN behavior retained. Full privacy disclosure remains in history.
- Customer full **298/298**, analysis clean; focused assistant **16/16**. Visual fixture **72 renders**, six sizes × two themes × EN/KM × three text scales: no overflow, every suggestion reachable. Reference anchors asserted and PNGs inspected. Logs: Customer `.local/assistant-redesign-all-tests.log`, `assistant-redesign-analyze.log`, `assistant-redesign-focused.log`, `assistant-redesign-visual.log`, final repeat `assistant-redesign-final-check.log`. PNGs and exact asset audit: `.local/qa/assistant-redesign/`.
- Existing work preserved. Customer document §20 updated. No APK/device acceptance, live AI-provider check, backend change, restart, deployment or commit. Usage checkpoint was saved and user notified below 10%; authorized work continued. Figma context: repository `.local/figma-detail-design/assistant-385-2708.txt`, session `fdae9366-897f-4f06-8e89-c06faea9d37f`.


### 6 November 2026 — Figma Section 3 implemented in Flutter (uncommitted)

- Customer Wallets, Wallet Detail, receipt overlay and navy splash, plus white Merchant splash implemented from section `431:2446`. Current edits (no detail-header logos, no Wallet Detail Sort button) followed; existing source work preserved.
- Existing controllers retain authorization, pagination, errors and money precision. Receipt metadata, expansion, PNG Share/Download, copy/account options and back navigation work. Approval code is labelled unavailable because the API provides none. PIN continuation waits for loaded accounts and resolves the receipt's wallet/currency.
- Automated: Customer **294/294**, Merchant **119/119**, both analyzers clean; **288 Customer + 30 Merchant splash renders**, no layout exceptions. Android receipt export tested with a mocked channel; splash timing/reduced motion tested; splash XML parses; diff check clean.
- Evidence: Customer `.local/section3-all-tests-verified.log`, `section3-analyze-final.log`, `section3-visual-verified.log`; Merchant `.local/section3-all-tests.log`, `section3-analyze-final.log`, `section3-visual.log`; both apps' `.local/qa/section3/` PNGs. Asset/context ledger: repository `.local/figma-detail-design/`.
- Not done: APK build/install, actual Android launch/export acceptance, backend restart, migration, real payment, deployment or commit. Usage checked: 20% primary and 36% secondary remaining. Next: user visual review, then separately authorized packaging/device acceptance.

### 6 November 2026 — Transaction and Wallet Detail designs in Figma

- Created two editable screens in the user's working section of `Mkhqgqnt1SQoq4pn9INLY5`, following the attached receipt-sheet and wallet-history references. Board `426:868`; original reference images preserved.
- Reused Kesor's vector logo, existing text styles/color variables, icons, buttons and transaction-row components. Added one reusable receipt metadata row (`426:1120`) beside the design board.
- Verified editable layer structure (no complete-screen image fills), Poppins/Google Sans fonts and final composition. Local visual evidence: `.local/figma-detail-design/final.png`; node/session ledger: `.local/figma-detail-design/state.json`.
- Figma design only; no application/backend changes, tests, builds, deployment or device acceptance. Documentation remains uncommitted. Usage checked: primary 59%, secondary 42% remaining. Next: user design review; implementation is separate work.

### 6 November 2026 — Railway PIN Home preview deployment

- User explicitly authorized backend deployment. Full backend **261/261**, log
  `backend/digital-banking/.local/railway-pin-preview-full-tests.log`.
- Deployed isolated, verified 277-file backend build snapshot (no credentials/frontend/local outputs)
  with explicit project/environment/service selection. Base `e6c58b6`, uncommitted PIN changes;
  snapshot SHA-256 `98bfa5ada6963a9662c1206db68a8469403ab328e90d49f43f36a79b0f43e849`.
  Complete file hashes in backend `.local/railway-pin-preview-payload.json`. No commit/push.
- Deployment `8fc7d198-bdc9-4a93-bd16-793b8c6b9668` **SUCCESS**. Existing Railway URL retained;
  schema V21 up to date, no migrations; Gmail API configured. No variable or Postgres service changes.
- Verified live: Swagger 200; preview endpoint and six-field schema in foundation OpenAPI; protected
  accounts 401 without authentication; invalid dummy ticket returns 401 `PIN_TICKET_INVALID` with
  `no-store`. Postgres deployment still `0695dccd-17dd-4db5-ba42-8712d5fd9590`, SUCCESS.
- Build/startup logs and final service-status JSON in backend `.local/railway-pin-preview-*`.
  Previous backend deployment `1d35a295-87fb-4287-94b0-6a6798490069` is the rollback reference.
- Not verified: authenticated customer preview/device acceptance. No APK build/install or real money
  action. The Customer APK must still be rebuilt/installed for the frontend behavior. Source/docs remain
  uncommitted. Usage checked: primary 67%, secondary 43% remaining. Deployment document §1/§9 updated.


### 6 November 2026 — Home preview before PIN (uncommitted)

- **Built:** ticket-authenticated `POST /auth/pin/home-preview`, latest five distinct personal-wallet postings,
  no amounts/balances/account numbers/remarks. Ticket validation reuses customer/session/device/expiry checks;
  configured, non-recovery PIN required; `no-store`; grants no banking tokens and changes no attempt budget.
  No migration. API security and foundation contract updated.
- **Customer:** existing Home layout shows masked money, preview activity and per-owner manual favorites.
  Saved labels/initials, masked suffix fallback; live recipient lookups wait for unlock. Typed destination
  handoff continues Wallet, tabs, transfer/favorite, QR, history/details, Inbox and favorite add/manage after
  correct PIN. Cancel/back/background/sign-out clear the destination; protected data revalidated after unlock.
  Every normal background locks; 3-minute foreground idle and trusted image-selection lease retained.
  Privacy cover now also covers preview; late PIN results are invalidated, foreground rechecks ticket status.
- **Automated:** Customer full **286/286**; final PIN/preview **11/11**, including 12 EN/KM light/dark phone,
  landscape and tablet renders with no layout exceptions. Initial backend full run **259/261**: failures were
  the new preview fixture lacking postings and the foundation route-count assertion. Added seven explicit
  postings, exact response-field assertions and API contract coverage; corrected affected backend suites
  **28/28**. Full backend suite was not repeated after those corrections. Final `flutter analyze --no-pub` and
  `git diff --check` are clean. Font-complete preview matrix rerun **2/2**; representative EN light phone
  and KM dark tablet renders inspected. Usage checked: 79% primary / 45% secondary remaining.
- **Evidence:** backend `.local/pin-preview-tests.log` (initial full), `.local/pin-preview-focused.log` (green);
  Customer `.local/pin-preview-flutter-final.log`, `.local/pin-preview-final-focused.log`,
  `.local/pin-preview-analyze.log`, `.local/qa/pin-preview/` (fixture values, not live data).
- **Not verified:** APK/native device appearance, hardware image handoffs or live API acceptance. No backend
  restart, deployment, live database change, APK build/install, commit/push or payment. Existing unrelated
  Customer/Merchant/docs/artwork edits preserved. Next: user device acceptance after separately authorized
  packaging/deployment. Customer document §3 and §17 describe the contract and behavior.


### 5 November 2026 — final QR/Analytics checkpoint (usage threshold)

- **Milestone:** Customer Figma section `413:6086`, QR `404:901` and Analytics `413:5956`, source implementation complete, uncommitted.
- **Built:** dedicated QR entry inside the existing transfer host; exact amount/keypad/currency/wallet/remark layout, verified payee, fixed-payment conversion checks. Existing normal transfer, review/PIN, receipt and unresolved journal recovery preserved. Analytics exact artwork, pale header, rounded panel, paired totals and live chart; single shell navigation with 400px cap. QR tablet max 440×957; Analytics tablet chart retains reference height.
- **Decisions authorized:** no page scroll or row stacking; locally fitted text/decoration; user explicitly chose smaller keypad targets in short landscape over scrolling. Tested landscape keys ~18–21px, portrait main targets ≥48px. Existing theme/localization retained; new labels translated.
- **Tests:** full Customer **284/284**. After final layout refinements, affected tests **25/25** and both visual fixtures passed: **144** matrix renders plus **16** Analytics PNGs. Keypad → review → edit works in size/theme variants; main actions hit-test, no page scroll/layout exceptions/chart-navigation overlap. Analyzer and final diff check clean. Backend/Merchant suites not rerun for this Customer-only presentation work.
- **Evidence:** `frontend/customer_app/.local/section2-all-tests.log`, `section2-final-focused.log`, `section2-final-visual.log`, `section2-analyze.log`, `section2-diff-check.log`; `.local/qa/customer-section-2/` contains Figma reference exports, final 144 PNGs, comparison/contact sheets and asset audit (16 assets, 11 exact SVG comparisons). Customer document §16 records the implementation. Fixture amounts are not live data.
- **Preserved:** prior uncommitted Merchant/docs/artwork work and transfer-success fixes. No credentials read, changed or packaged; no backend/database/live service changes, APK build/install, commit/push or real payment.
- **Not verified:** device appearance, hardware camera/gallery round trip, real payment. No pixel-perfect or personal acceptance claimed. Next: user visual review of `comparison.png`; packaging/device acceptance only after separate authorization.
- **Usage:** primary 8% remaining, secondary 48% remaining. Threshold reported; final handoff continues normally.


5 November 2026 checkpoint: generated the optional `monthly-money-overview.png` Analytics
header with the built-in image tool; inspected the result and verified PNG dimensions and alpha.
No app code changed, no runtime tests needed, no device acceptance or screen integration.
Usage windows remain above the reporting threshold. Asset and documentation uncommitted.

5 November follow-up: delivered `frontend/customer_app/assets/analytics/monthly-money-overview-watercolor.png`
to match the user's painted reference. Built-in image edit; original preserved. Inspected
output and verified 1536×1024 RGBA with transparent pixels. No app integration; uncommitted.

5 November color follow-up: delivered `monthly-money-overview-watercolor-gold.png` in the same
Analytics asset folder, with a light gold background wash requested by the user. Built-in image
edit; visually inspected and PNG alpha verified. Earlier variants preserved; no code changes,
runtime tests or app integration; uncommitted.

### Next step
**M9 — device installation and integrated acceptance.** Latest Railway APKs are built and verified
(6 Nov entry above); Railway already has V21, and both native link bridges/debug manifests compiled.
Install with `adb install -r` on the user's requested device only when authorized, preserve its settings,
then use [MERCHANT_APP.md](MERCHANT_APP.md) §9 and record answers verbatim. Native Telegram,
app-to-app approval, save/share, sound/vibration, process restoration and current visual acceptance
remain device checks. A local-backend restart/migration is a separate authorized workflow if requested;
it is not needed to install these Railway builds. Record M9's remaining gates in §2 and the Merchant
document without creating a separate report file.

### Customer device acceptance still owed
Notification permission/alerts, PIN change and recovery, gallery photo, camera QR scan, fresh signup showing USD+KHR wallets, post-rework masked Home/idle lock, Favorite Recipients, new Home/Wallet UI. Submit no real payment merely to verify UI.

### Known issues and intentional limits
- Merchant feed: one duplicate banner is possible if a feed poll lands before the Collect screen's 2-second status poll.
- Merchant owner transfer: if the app dies during an *uncertain create*, a retry is refused (`OWNER_TRANSFER_IN_PROGRESS`) until the first intent expires (≤5 min). No money moves without PIN approval.
- Customer App draws ៛ small in English text (fixed only in Merchant, G1).
- Legacy `GET /merchants/me/accounts` remains a Customer-session route (removal is the user's decision, G2). EMV tag 59 truncates long/Khmer shop names to 25 bytes (G4, accepted).
- Concurrent owner updates in sales/reports can return `409 CONCURRENT_UPDATE`; the app offers Try again.
- 3 legacy customers have duplicate same-currency personal wallets from pre-V16 pair openings; untouched (no personal `(user_id,currency)` uniqueness constraint exists).
- Biometrics are intentionally disabled. Alerts are local, opt-in Android notifications; background push is not implemented.
- Support contact `reachsteav2@gmail.com`; Terms/Privacy are demo text by request. Do not invent real policies.
- QR is internal Kesor QR only: no Bakong/KHQR certification or external settlement is claimed. iOS native build/device acceptance is unverified. Release signing is still the debug key.

### Backlog (not scheduled)
1. Background push (FCM) and optional voice alerts (Merchant M10).
2. Cashiers, shift closing/export, controlled refunds (M11); branches, payment links/invoices, read-only sales assistant (M12); KHQR/Bakong integration and reconciliation (M13, needs provider access).
3. Native iOS build and acceptance (needs a Mac).
4. Release HTTPS App Links (needs a domain and release certificate), release signing, real policies.
5. Older backend ambitions never built: fraud detection and employee review, password recovery/device admin, disputes and monitoring, payment-provider settlement, categorization/budgets. Full text: `git show ccc10bd:docs/BACKEND_ADVANCED_ROADMAP.md`.

### Dated log
- **5 Nov 2026 — Customer QR entry + Analytics, Figma section 413:6086 (uncommitted).** Built dedicated post-scan `QrTransferScreen` inside the shared payment host, exact QR assets and Analytics illustration, rounded lower Analytics panel, paired totals/chart and centered tablet composition/navigation. Normal entry, review/PIN/receipt and original-key unresolved recovery retained. No page scrolling or row reflow; user explicitly approved sub-48px QR keypad targets in short landscape (about 18–21px in fixtures); portrait main targets remain ≥48px. Customer **284/284**, final focused **25/25**, new visual **144 renders** plus existing Analytics **16 PNGs**, analyzer/diff checks clean; asset audit covers 16 assets and 11 exact SVG comparisons. Final screenshots, contact sheets, comparison and asset audit in Customer `.local/qa/customer-section-2/`; logs `.local/section2-*.log`; Customer document §16. Screenshot data is offline fixture data. Preserved prior uncommitted work, transfer-success fixes, optional artwork and Merchant changes. No APK/build/install/backend/DB/live payment/commit or device acceptance. Next: visual review and separately authorized packaging/device acceptance. Final usage check: primary 92% used (8% remaining), secondary 52% used (48% remaining). Detailed final checkpoint saved below under §8; implementation and checks complete.
- **5 Nov 2026 — Customer transfer success overflow (uncommitted).** Updated current Figma `308:740` proportions (148 × 126 seal slot, 64px amount, 440 × 956 reference); compact spacing on short screens, side-by-side landscape, complete receipt/messages fitted above unscaled actions and native safe areas. Success page scrolling removed; existing entry/review behavior and transfer safety unchanged. Customer suite **276/276**; final visual fixture **60 renders**, including **20 success variants** with no page scroll, all main sections on screen, no receipt/action overlap, ≥48px action targets and both callbacks tappable. EN/KM, both themes, USD/KHR, native insets, 1×/1.3×/2× text, long details, phones/landscape/tablet covered. Representative final images inspected. Analysis/diff checks clean. Evidence: Customer `.local/transfer-success-tests.log`, `.local/transfer-success-visual.log`, `.local/transfer-success-analyze.log` and `.local/qa/transfer-flow/`. Existing transparent artwork/flags reused; extreme height/text combinations shrink receipt text to meet the one-screen requirement. No APK/build/install, device acceptance, backend or database action. Next: user visual review; native packaging remains subject to §3 approval.
- **5 Nov 2026 — Merchant Figma Change list source redesign (uncommitted).** All 28 frames from section `363:3084` mapped to current flows, exact Figma artwork/assets bundled, Merchant-only navy/gold card treatment, full-screen Collect, functional Home shortcuts, drawer/profile/settings and responsive layout updates. Merchant **118/118**, analysis clean, **294 responsive renders** without layout exceptions; financial/controller checks retained. Local references, asset audit, overlays/diffs and logs: `frontend/merchant_app/.local/figma-change/`; render matrix: `.local/qa/figma-change/`. Comparison metrics are diagnostic, not pixel-perfect acceptance; approved goldens/device review remain pending. No device attached, no APK build/install/backend restart/live payment. Backend/Customer/shared packages unchanged. Usage checked, both windows above reporting threshold. Next: visual acceptance and separately approved APK/device verification; Merchant document §14.
- **5 Nov 2026 — Native Telegram login enabled on Railway.** Copied `TELEGRAM_CLIENT_ID`, `TELEGRAM_CLIENT_SECRET` and `TELEGRAM_NATIVE_REDIRECT_URI` from the local `.env` via CLI (values never printed; verified equal by comparison). Not copied: `TELEGRAM_REDIRECT_URI` / `TELEGRAM_FRONTEND_ORIGIN` (browser/web flow, point at local setup). The native flow returns through Telegram's `app937652339-login.tg.dev` App Link, so no BotFather change or APK rebuild. Redeploy `44bd9373` SUCCESS; live `POST /auth/telegram/native/start` → 200 with an `oauth.telegram.org/auth` URL and the registered redirect (one unused 5-minute flow left by the check). **Not verified:** the device round trip (Telegram approval → App Link → `/native/exchange`) with the Railway APKs; App Link opening depends on the APK's debug signing key matching the one used in the earlier tablet test (same PC, expected to match).
- **5 Nov 2026 — Railway APKs built (not installed).** User confirmed the live OTP email reached the Gmail **Inbox**. Built debug APKs (one at a time, Gradle daemon off) from branch `railway-gmail-otp` (frontend identical to `main`) with `APP_ENV=dev`, `API_BASE_URL=https://backend-production-18646.up.railway.app/api/v1` (Customer also `APP_MODE=api`). **First successful compile of the Merchant Kotlin (`MerchantLinkBridge.kt`) and debug manifests.** `frontend/customer_app/.local/apk/KesorBank-Railway.apk` (later renamed by the user to `Kesor Bank.apk`) 234.1 MB SHA-256 `D57D261EBEE8AB1467F5B78AFDDFC1ADD44937858FCBAF71B5635D5B517F05F4`; `frontend/merchant_app/.local/apk/KesorMerchant-Railway.apk` (later renamed to `KesorMerchant.apk`) 195.9 MB SHA-256 `B3BD7EB04769B2DACC8D02613E4AD1539FFA76FB025B04F9A8842AEDD8382E55`. Both: Railway URL present in `kernel_blob.bin`, no `.env` entry, old Wi-Fi IP absent. Build logs `frontend/*/.local/railway-apk-build.log`. **Not done:** install (`adb install -r`, needs approval; secure storage is scoped by API URL, so expect a new sign-in), device acceptance against Railway.
- **5 Nov 2026 — Backend live on Railway (docs uncommitted).** Project `superb-respect`, environment `production`, region US East: services `Postgres` (template `postgres-ssl:18`, volume `postgres-volume-Dubs`) and `backend` (deployed with `railway up --service backend` from branch `railway-gmail-otp` @ `e6c58b6`; the org repo `Chips-beans/AiDigitalBankingApp` is not connected to Railway). URL **`https://backend-production-18646.up.railway.app`** (API base `…/api/v1`). Incident: the first `railway up` ran while the CLI was linked to the Postgres service and replaced its container; the empty database service was deleted and recreated, nothing lost; always pass `--service backend`. Variables set via CLI from the local `.env` without printing values (DB references, pool 5/1, `dev` profile, new 32-byte `JWT_SECRET` that differs from local, Gmail API, test opening funding on; no AI or Telegram settings). Evidence: Flyway empty schema → **V21** (20 migrations), started in 7.2 s, log `OTP email is delivered through the Gmail API`; HTTPS `swagger-ui` 200, `v3/api-docs/foundation` 200, `/api/v1/accounts` 401 unauthenticated. Live OTP: `POST /api/v1/auth/email/request` for the user's own address returned 200 in 1.9 s (the CONTINUE flow always delivers and a Gmail failure would be 503, so 200 means Gmail accepted the message); no Gmail warnings in the logs. **Not verified:** inbox placement of that code (user to confirm), either app against the live URL (APKs not built), memory headroom under use. Leftover detached empty volume `postgres-volume` to delete in the dashboard.
- **5 Nov 2026 — Railway deployment prepared (uncommitted, not deployed).** User confirmed both `LIVE-TEST` emails reached the Gmail **Inbox**. Added `backend/digital-banking/Dockerfile` (Maven build image instead of `mvnw` so the build does not need curl/wget; JRE 21, non-root, Railway `PORT`) and `.dockerignore`; checklist now in `DEPLOYMENT.md`. Findings: profile must be `dev` (MerchantAuthConfig accepts custom-scheme links and MerchantOnboardingPolicy activates shops only under local/dev/test; `local` would add seed users); photos/logos are BYTEA, so no volume needed; per-IP rate limits use `getRemoteAddr()`, which behind Railway's proxy may be the proxy address. Checked: `mvnw -o -DskipTests package` produces the single `digital-banking-0.0.1-SNAPSHOT.jar` (62.6 MB) the Dockerfile copies. **Not verified:** Docker image build (Docker is not installed on this PC), container start on Railway, memory headroom on the Trial instance, APKs against the Railway URL.
- **5 Nov 2026 — OTP email over the Gmail API for Railway hosting (uncommitted).** Decision (user): host the backend on Railway (Trial, $5 / 30 days) for a ~5-day live run and keep real email OTP. Railway Trial/Hobby and Render free block outbound SMTP 25/465/587, so `smtp.gmail.com:587` would time out. Built: `MailProviderConfig` picks the `EmailService` from `MAIL_PROVIDER` (`smtp` default → existing `EmailServiceImpl`; `gmail-api` → new `GmailApiEmailService`). The Gmail sender refreshes an OAuth access token (cached until 60 s before expiry), posts the same message text (shared `OtpEmailText`) as base64url MIME to `gmail/v1/users/me/messages/send`, retries once after a 401, 5 s timeouts, credentials only to HTTPS/loopback. Every failure is still `503 OTP_DELIVERY_UNAVAILABLE`; logs carry only HTTP status and the OAuth error code (e.g. `invalid_grant` = expired token), never OTP, recipient, tokens or bodies. OTP generation, hashing, rate limits, Flutter apps and schema unchanged (no migration). Tests: `GmailApiEmailServiceTests` 9/9 against a loopback fake of Google's endpoints; full backend **260/260** (existing SMTP path unchanged). User created the Google Cloud OAuth client and refresh token (own Gmail account, Testing mode) and added `GMAIL_*` to the ignored `.env`. **Live check** (temporary test reading `.env`, no backend restart, dev DB untouched; test deleted afterwards): first attempt failed `unauthorized_client` (refresh token issued for the Playground's default client; fixed by regenerating with "Use your own OAuth credentials"); then a real send succeeded but took 10.3 s. Cause: Jakarta Mail's Message-ID generation did a local hostname lookup (≈5 s on this PC). Fix: the Gmail sender's mail Session sets `mail.host`/`mail.from` (same idea as `MAIL_CLIENT_HOSTNAME` for SMTP); MIME build 5,106 ms → 82 ms; confirming real send **1.7 s** cold (token refresh ≈0.5 s cold / 0.1 s warm). Two `LIVE-TEST` emails were sent to the user's own address; inbox/spam placement awaits the user's check. Gmail unit tests rerun 9/9 after the fix (full suite not rerun; SMTP path untouched). **Not done:** Railway deployment (Dockerfile, env variables, Postgres), APK builds against the Railway URL, delivery to a non-Gmail inbox.
- **5 Nov 2026 — First live Groq run + currency-word fix (uncommitted).** Ran 10 EN/KM questions against the real Groq key on a throwaway embedded database (dev DB untouched, V19–V21 still pending); evidence in `backend/digital-banking/.local/live-assistant-smoke.md`. Intent was correct for all 10, replies took 0.5–2.6 s, figures matched. Run 1: every English data answer was `FALLBACK` because the model writes "your USD balance" and the validator banned USD/KHR words. Fix: currency names are allowed in fact prose (digits stay banned); a code written right next to a placeholder ("USD {{v}}") is rejected; the composer prompt says so. Run 2: English Q1–Q4 all `explanationStatus=AI` (Q4 `MIXED` with tips). **Open:** in run 2 two Khmer questions got HTTP 400 from Groq (shown as 503 `AI_UNAVAILABLE`); run 1 answered them. Follow-up: `GatewayAdapter` now reads only `error.code` from a provider error body (never the message or `failed_generation`), logs it, retries once on `json_validate_failed`, and a second refusal becomes `AI_INVALID_RESPONSE` (data answers then fall back to verified cards). Run 3 confirmed the cause is `json_validate_failed`. Run 3: 8/10 OK; KM "balances" was refused twice in a row (HTTP 502, three runs: OK / 400 / 400+retry 400), and EN "emergency fund" hit the 10 s per-call read timeout once (1–2 s in the other runs). Cause (captured via a loopback relay in a temporary test, evidence `.local/groq-khmer-rejections.md`): Groq checks strict output only after generation, and the strict-mode intent prompt never named the keys, so the model wrote `{"}}` or invented keys. Fix: the intent prompt always carries a compact example object (`GatewayAdapter.INTENT_EXAMPLE`). Re-run: 0/6 format refusals. Then: (1) Groq free tier refused whole requests with 429 "Request too large … OTPM Limit 1000" because `max_tokens` was 2048 → now 300 (intent) / 700 (answer) / 800 (insights) via `GatewayAdapter.maxTokens`. (2) In Khmer the model sometimes copied verified figures literally ("USD 187.50") → `AssistantEngine.restoreFacts` turns an exact, whole copy of a supplied value (≥4 chars, containing a digit) back into its placeholder; any other number is still rejected. Final live run: **16/16 answers `explanationStatus=AI`** (10 EN/KM questions + Khmer balances ×6), 0.5–2.4 s. Remaining risk: the Khmer intent step still degenerates in about 3 of 16 calls (`json_validate_failed`, runaway invented key); the one retry recovered all 3, but two refusals in a row would show `AI_INVALID_RESPONSE`. The temporary live test was deleted (it would call Groq during `mvnw test`); evidence stays in `backend/digital-banking/.local/`. Backend **251/251**.
- **5 Nov 2026 — AI assistant review fixes (uncommitted).** `TOTALS`: half-open ranges close at today (from only) or the first day of the end's month (to only); the daily average divides only by elapsed days. `AssistantEngine.render`: money directives are blocked only toward a third party ("pay yourself first", "transfer to savings" pass); credential clauses are rejected when they hand a PIN/OTP over without an earlier prohibition in the same clause, or state a 3+ digit number; accented Latin no longer counts as a foreign script. `GatewayAdapter` waits up to 1.5 s for a provider permit and logs non-2xx status plus model/jsonMode/reasoning flag (never the body). New `AIConfigCheck` warns at startup when `GEMINI_*` names remain (names only). Backend **250/250**. Not changed: TOTALS still sums monthly overviews (up to ~13 per currency) to keep one income/outgoing definition. Not verified: any live Groq call.
- **5 Nov 2026 — AI provider: Groq (uncommitted).** Rayu Code dropped (API key needs a paid plan). Defaults now Groq + `qwen/qwen3.8-27b`; strict `json_schema` response format (`AI_JSON_MODE`), `reasoning_effort` (`AI_REASONING_EFFORT`, default `none`), inline `<think>` stripping, and a server-side language/script check for Khmer and English answers. Tests: backend **247/247** (AssistantTests 20, AssistantProviderTests 8); Customer app unchanged this step (last run 276/276). **Not verified:** any live Groq call (latency, Khmer quality, free-tier 429 frequency, whether strict schema is accepted for the intent schema). User adds `AI_API_KEY` and flags to `.env`, then approves a restart.
- **5 Nov 2026 — AI assistant provider: Gemini removed, OpenAI-compatible gateway (Rayu Code) added (uncommitted).** User decision after Gemini proved slow/unreliable. `GeminiAdapter` → `GatewayAdapter` (`POST {AI_API_URL}/chat/completions`, `Authorization: Bearer`, prompt-requested JSON with strict downstream validation, key only over HTTPS/loopback); properties prefix `app.ai.gateway`, env `AI_API_URL|AI_API_KEY|AI_MODEL|AI_ENABLED|AI_CUSTOMER_CONTEXT_ENABLED`; `.env.example`, tests, Flutter privacy caption and docs updated; no `gemini` string remains in code. Tests: backend **244/244**, Customer **276/276**, analysis clean. **Not verified:** any live gateway call (latency, JSON compliance, Khmer quality, model availability on the user's plan — Rayu docs list API access on Pro/Plus/Max). User must add `AI_*` keys to the ignored `.env` and approve a backend restart; old `GEMINI_*` lines can be deleted (and the Google key revoked). Next: one live smoke pass, then consider skipping the classify call for common questions.
- **5 Nov 2026 — AI assistant: general money guidance (uncommitted).** Decisions (user): free-form answers use number-checked tool results only; scope is education + budgeting tips, no product/investment recommendations. Built: intent `TOTALS`/`COMPARE`/`GENERAL` + `general` flag; `Provider.compose` replaces `explain`; `AssistantEngine.render` validator (no digits/%/currency words/magnitude words in fact-based prose, ordinary numbers only in general-only prose, credential/directive/link checks); server-added disclaimer; `Answer.mode` (null for old data); sanitized question only goes to Gemini; Flutter shows mode label, hides "Data as of" for general answers, new suggestions + privacy caption (EN/KM). Tests: backend **242/242** (AssistantTests 18, AssistantProviderTests 5), Customer **276/276**, `flutter analyze` clean. Not verified: any live Gemini call with the new classifier/composer prompts (flags/key unchanged; needs a real-model pass for Khmer GENERAL answers and false-rejection rate), device UI, and visual QA of the Figma-redesigned assistant screen with the added caption and 4th suggestion. No schema change (no migration), no backend restart, no commit. Next: live prompt pass, counterparty names, largest-transaction/count tool, contextual "explain this" entry points.
- **4 Nov 2026 — Customer Figma section 387:6034 (uncommitted).** All five requested frames implemented with existing live controllers and locally bundled exports. Home actions are Wallet / Scan QR / Transfer; Wallet uses per-currency cards and number copy; Analytics is flat with segmented currency control; Assistant is standalone with Back and a composer above native bottom insets; My QR overlays a blurred real Home with gold/navy card and both wallet rows. Full Customer suite 273/273, focused post-spacing tests green, 300 offline renders (EN/KM, light/dark, 1×/1.3×/2×, 320/375/440 px phones, landscape and tablet) without layout exceptions; analysis clean. Assets and logs: Customer document §14. No backend/native build/install or real payment. Analytics uses verified income/expense rows because the API has no payment-method category breakdown. Native appearance/personal acceptance pending. Next: user review of local renders; APK/device work still requires explicit approval under §3.
- **4 Nov 2026 — Analytics illustration asset (uncommitted).** Generated a transparent Khmer money-planning watercolor PNG matching the existing Cambodian artwork, saved at `frontend/customer_app/assets/analytics/khmer-money-planning.png`. Inspected the artwork and checked PNG dimensions/alpha; no app integration, builds or runtime changes. Usage windows above the reporting threshold.
- **4 Nov 2026 — Merchant Figma Quiet v2 redesign (uncommitted).** Replaced the earlier UI presentation with the user’s explicit Figma reference, section `370:4356`; all existing work/files preserved. New Merchant-only theme, three tabs plus side menu, flat Home/wallet/sales/report/request rows, amount keypad, white QR, receipts, forms, approval/result states, settings pages and sign-out sheet. Registration now reviews the draft before creating it; same-key uncertain recovery remains unchanged. Approval expiry is exposed read-only from the existing auth journal. **112/112 Merchant tests pass** (including filter contrast, exact USD keypad submission and small-window/2× Khmer keyboard checks); **294 responsive renders without overflow**, all inspected in contact sheets and representative full-size images; analyzer and diff checks clean. Final Welcome spacing (12 variants) and approval asset capture (2 variants) rechecked. Export: `Flutter Screen/Merchant App Figma Quiet/`, **34 states, 36 PNGs**, preview, overview and index. Usage checked, both windows above the reporting threshold. Backend, Customer and shared design package unchanged; M9 remains unstarted.
- **4 Nov 2026 — Home card restored to user's reference (uncommitted).** Original navy gradient, faded Kesor mark, shop identity/ID/status layout and three Collect/Sales/Edit shop tiles restored. Home opts into `NavyCard.branded`; other navy surfaces and earlier screen refinements retained. Targeted shop/accessibility tests **18/18**, visual fixture **232 renders/no overflow**, analysis and diff checks clean. Representative phone/dark/320 px/2× Khmer/tablet renders inspected; current preview `frontend/merchant_app/.local/qa/card-restore-preview.png`. No device/APK/backend work. Merchant App v2 screenshot folder remains the earlier exported snapshot.
- **4 Nov 2026 — Merchant v2 screenshot export (uncommitted).** Exported all 28 catalog screens/states as 38 PNGs (including 10 scrolled views) to `Flutter Screen/Merchant App v2`, with overview and index. English/light, 393×852 logical phone viewport, 1179×2556 PNGs. Catalog fixture passed; every PNG decoded and dimensions/coverage checked. Existing screenshot folders preserved; controlled Flutter fixture renders, not device/live payment evidence.
- **4 Nov 2026 — Merchant UI refinement (uncommitted).** Built: existing gold/navy and bilingual type roles retained; one generated welcome illustration; collections-first Home with grouped wallets and wider tablet layout; compact Sales filters; simpler Collect fields with a wrapping, semantically labelled order note; accessible wallet keyboard/copy feedback, contrast and currency alignment improvements. Tests: Merchant **109/109**, analysis clean, visual fixture **232/232 renders** in six viewports/light-dark/EN-KM/up to 2× text; all final renders inspected through 28 contact sheets and representative full-size images. Before/after evidence: `frontend/merchant_app/.local/qa/ui-before`, `ui-after`, `ui-review`; critique `.local/ui-critique.md` in that app. Not verified: no Android device attached, TalkBack/VoiceOver/native integration/APK not exercised; web build unavailable because Merchant has no web target. Backend, Customer App, shared package, data/state/controllers/routes/dependencies unchanged. Usage checked, both windows comfortably above the reporting threshold. Next: review the local comparison images; M9 remains separately unstarted and subject to its existing approval rules.
- **4 Nov 2026** — M8 merged (PR #3). Docs consolidated into three files.
- **3 Nov 2026** — M7 (sales/receipts/reports/sharing) and F1–F6 follow-ups; M4–M7 merged (PR #1).
- **31 Oct 2026** — M0–M3 complete with user-confirmed device round trip; Customer Phase 4 (transfers with conversion, Home masked until PIN, Receive QR redesign, profile photo fix), Settings, scanner UI; full backend suite repaired after V16.
- **29–30 Oct 2026** — Unified auth, native Telegram, profile photos (V12), PIN (V13), paired accounts + internal QR (V14), Monthly Analytics, AI assistant (V15).
- **Oct 2026 (earlier)** — Foundation F1–F5 and Phase 0/1: OTP auth, sessions, accounts, internal transfers, history, financial integrity and audit (V2–V9).
