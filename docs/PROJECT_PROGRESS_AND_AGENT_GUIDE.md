# Kesor Bank — progress and agent guide

Updated 4 November 2026, Asia/Phnom_Penh. This is the single place for **current status,
rules, setup, commands and open work**. Product detail lives in two sibling documents:

| Document | Covers |
| --- | --- |
| [CUSTOMER_APP.md](CUSTOMER_APP.md) | Customer App and the shared banking backend: auth, PIN, accounts, transfers, QR, analytics, AI assistant, Settings, Android notes |
| [MERCHANT_APP.md](MERCHANT_APP.md) | Merchant App: decisions, contracts, M0–M8 as built, M9 plan, deferred M10–M13 |
| This file | Progress, agent rules, environment, commands, conventions, backlog |

Other docs that stay next to the code: `AGENTS.md` (short pointer file for agents),
`README.md`, the module READMEs, and `frontend/customer_app/docs/*` (screen-level
design notes and `WIFI_DEVELOPMENT.md`). More documents (for example a plan file) can be
added later; list them in the table above.

The earlier ~40 chronological reports, phase plans and handoffs were consolidated into
these three files. Nothing was lost: the last commit that still contains them is
`ccc10bd`. Read any old file with `git show ccc10bd:docs/<NAME>.md`.

---

## 1. Project snapshot

- Repository: `C:\Users\User\Documents\GitHub\AiDigitalBankingApp` (GitHub `Chips-beans/AiDigitalBankingApp`), branch `main`.
- `backend/digital-banking` — Spring Boot 4.1, Spring Security, JPA, Flyway, PostgreSQL. Java 21 target (workstation JDK 24).
- `frontend/customer_app` — Flutter Customer App (`com.bank.customer_app`).
- `frontend/merchant_app` — Flutter Merchant App (`com.bank.merchant_app`), Android-first.
- `frontend/packages/kesor_design_system` (shared theme/tokens), `frontend/packages/kesor_auth_handoff` (app-to-app approval transport).
- Both apps share one backend and database. The Merchant App never has its own login: it signs in through approval in the Customer App.
- Latest schema: **V21** in source. The development database is behind (see §6).

## 2. Progress

### Customer App and backend

| Area | State |
| --- | --- |
| Email OTP + Telegram (browser and native Android) sign-in, onboarding, profile photos | Built. User personally verified native Telegram login and Create Profile → PIN → Home on the Samsung tablet. |
| Server-enforced 4-digit PIN (V13), masked Home until first tap, 3-minute idle lock | Built, automated checks pass. Device acceptance of the later PIN rework not recorded. |
| USD/KHR wallets (automatic at signup, V16), manual transfers with fixed 1 USD = 4,000 KHR, recipient lookup, transfer PIN proof | Built; full backend suite green. |
| QR receive/scan/pay (internal Kesor QR only), Save/Share QR card | Built. Camera/gallery acceptance on device pending. |
| Monthly Analytics | Built; user accepted the screen's appearance. |
| Read-only AI assistant (Gemini) | Built. Live success proven only with `gemini-3.5-flash-lite` (Khmer intent turns); Gemini prose (`explanationStatus=AI`), English locale, monthly summary and payment-refusal turns are unverified. |
| Settings (profile edit, PIN change, alerts, language/theme, FAQ) | Built; user confirmed "Settings looks correct and pages open". PIN change, notification delivery not personally tested. |
| Home (3 actions, Favorite Recipients), Wallet & Accounts screen, scanner UI, Receive QR redesign | Built; device acceptance pending. |

### Merchant App

| Milestone | State |
| --- | --- |
| M0 audit/contracts, M1 shell, M2 backend approval/sessions, M3 app-to-app sign-in | Complete. User confirmed on device: "Register Shop or my existing shop opens, including after reopening." |
| M4 shop registration + two wallets (V19), M5 dashboard/wallets, M6 QR collection (V20) | Source + automated checks complete, merged. **Not applied to the dev DB, no device acceptance.** |
| M7 sales, receipts, reports, sharing | Source + automated complete, merged (PR #1). Native sharing not device-verified. |
| M8 payment alerts + owner transfers (V21), G1 riel sign, G2/G4 notes | Source + automated complete, committed `dc1e4ef`, merged by PR #3. **Android Kotlin not compiled, V19–V21 not applied to dev, no device approval.** |
| **M9 integrated acceptance + pilot APKs** | **Not started — needs the user's explicit "yes"** (backend restart, APK builds, install). |
| M10–M13 (push/voice, cashiers/refunds, branches/payment links/AI, KHQR/Bakong) | Deferred. |

### Test baselines to keep green (4 November 2026)

| Suite | Result |
| --- | --- |
| Backend `./mvnw.cmd -o test` | **234/234** |
| Merchant `flutter test test --concurrency=1` | **106/106**; visual fixture 232 renders, no overflow |
| Customer `flutter test --concurrency=1` | **273/273**; Merchant-transfer approval fixture 24 renders |
| `flutter analyze` both apps, `git diff --check` | Clean |

No suite has been rerun since the M8 commit; the numbers are the M8 evidence.

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
| `DEV_SEED_ENABLED`, `DEV_SEED_PASSWORD` | Opt-in demo fixtures (`alice.demo`, `bob.demo`, `empty.demo`, `employee.demo`), local profile only. |
| `TEST_OPENING_FUNDING_ENABLED` | Default false. When true (only `local/dev/test/staging`), a new USD wallet gets 200.00 and a new KHR wallet 100,000 as `TEST_OPENING_CREDIT`. Startup fails under `prod`. |
| `TRANSFER_PIN_REQUIRED` | Enforced in dev since Phase 4.2; do not turn off. |
| `TELEGRAM_CLIENT_ID/SECRET/REDIRECT_URI`, `TELEGRAM_NATIVE_REDIRECT_URI`, `TELEGRAM_FRONTEND_ORIGIN` | Blank disables Telegram; email still works. Native redirect is `https://app937652339-login.tg.dev/tglogin`. Keep BotFather at RS256. |
| `GEMINI_ENABLED`, `GEMINI_CUSTOMER_CONTEXT_ENABLED`, `GEMINI_API_KEY`, `GEMINI_MODEL` | Defaults off. Configured model is `gemini-3.5-flash-lite` (others stalled). |
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
- Gemini: key and both flags configured; model `gemini-3.5-flash-lite`.
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

### Next step
**M9 — integrated acceptance and pilot APKs.** Start by asking the user for permission to restart the dev backend (applies V19–V21) and build/install APKs. Then: full sequential automated run; inspect port 8080 owner; restart via the launcher; confirm Flyway applied V19–V21 and the new paths in OpenAPI; compile and build both APKs (`KesorMerchant-M9-Pilot.apk`, `KesorBank-M9-Pilot.apk`); verify (no `.env`, API origin, SHA-256); install with `adb install -r` only on the user's go-ahead; hand the user the acceptance script in [MERCHANT_APP.md](MERCHANT_APP.md) §9 and record answers verbatim; write the M9 result into §2 and the Merchant document (no separate report file). **First real-world risks:** the Kotlin in both `MerchantLinkBridge.kt` files and the new debug manifests has never been compiled.

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
- **4 Nov 2026** — M8 merged (PR #3). Docs consolidated into three files.
- **3 Nov 2026** — M7 (sales/receipts/reports/sharing) and F1–F6 follow-ups; M4–M7 merged (PR #1).
- **31 Oct 2026** — M0–M3 complete with user-confirmed device round trip; Customer Phase 4 (transfers with conversion, Home masked until PIN, Receive QR redesign, profile photo fix), Settings, scanner UI; full backend suite repaired after V16.
- **29–30 Oct 2026** — Unified auth, native Telegram, profile photos (V12), PIN (V13), paired accounts + internal QR (V14), Monthly Analytics, AI assistant (V15).
- **Oct 2026 (earlier)** — Foundation F1–F5 and Phase 0/1: OTP auth, sessions, accounts, internal transfers, history, financial integrity and audit (V2–V9).
