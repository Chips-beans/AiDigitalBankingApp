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
| Optional Analytics watercolor asset (4 Nov) | Generated transparent Khmer money-planning PNG at `frontend/customer_app/assets/analytics/khmer-money-planning.png`; delivered separately, not wired into the screen. Uncommitted. |
| Read-only AI assistant (OpenAI-compatible gateway; Gemini removed 5 Nov 2026) | Built; 5 Nov 2026 added general money guidance (education + budgeting tips, `GENERAL`/`MIXED` modes), `TOTALS`/`COMPARE` tools and number-checked free-form text — automated tests only, no live Gemini run of the new prompts (see CUSTOMER_APP.md §8). Live success proven only with `gemini-3.5-flash-lite` (Khmer intent turns); Gemini prose (`explanationStatus=AI`), English locale, monthly summary and payment-refusal turns are unverified. |
| Settings (profile edit, PIN change, alerts, language/theme, FAQ) | Built; user confirmed "Settings looks correct and pages open". PIN change, notification delivery not personally tested. |
| Home (3 actions, Favorite Recipients), Wallet & Accounts screen, scanner UI, Receive QR redesign | Built; device acceptance pending. |
| Customer Figma section redesign (4 Nov) | Implemented all five frames in section `387:6034`: Home, Wallet, Analytics, AI Assistant and blurred My QR overlay. Customer 273/273 tests, 300 responsive renders without layout exceptions, analysis clean. Uncommitted; no APK/device acceptance. See Customer document §14. |

### Merchant App

| Milestone | State |
| --- | --- |
| M0 audit/contracts, M1 shell, M2 backend approval/sessions, M3 app-to-app sign-in | Complete. User confirmed on device: "Register Shop or my existing shop opens, including after reopening." |
| M4 shop registration + two wallets (V19), M5 dashboard/wallets, M6 QR collection (V20) | Source + automated checks complete, merged. **Not applied to the dev DB, no device acceptance.** |
| M7 sales, receipts, reports, sharing | Source + automated complete, merged (PR #1). Native sharing not device-verified. |
| M8 payment alerts + owner transfers (V21), G1 riel sign, G2/G4 notes | Source + automated complete, committed `dc1e4ef`, merged by PR #3. **Android Kotlin not compiled, V19–V21 not applied to dev, no device approval.** |
| **M9 integrated acceptance + pilot APKs** | **Not started — needs the user's explicit "yes"** (backend restart, APK builds, install). |
| M10–M13 (push/voice, cashiers/refunds, branches/payment links/AI, KHQR/Bakong) | Deferred. |
| Merchant Figma Quiet v2 redesign (4 Nov) | Implemented the 28 reference frames in Figma section `370:4356`: three tabs, drawer navigation, flat screens, bundled SVGs and adaptive numeric entry. 112 Merchant tests pass; 294 responsive renders without overflow; analysis clean; 34-state screenshot catalog exported. Uncommitted; no APK/device acceptance. See Merchant document §13. |
| Earlier Merchant UI refinement (4 Nov) | Welcome, Home, Collect, Sales and Merchant shared presentation widgets refined against the existing Kesor design system. Initial pass: 109 tests, analysis clean, 232 before/after renders. Later user request restores the original Home shop card/action tiles; see Merchant document §12 for current evidence. Uncommitted; no native/device acceptance. |

### Test baselines to keep green (4 November 2026)

| Suite | Result |
| --- | --- |
| Backend `./mvnw.cmd -o test` | **250/250** (5 Nov 2026, after assistant review fixes; was 247) |
| Merchant `flutter test test --concurrency=1` | **112/112** after Figma Quiet v2; visual fixture 294 renders, no overflow |
| Customer `flutter test --concurrency=1` | **273/273**; Customer Figma fixture 300 renders without layout exceptions; Merchant-transfer approval fixture 24 renders |
| `flutter analyze` both apps, `git diff --check` | Clean |

Merchant and Customer checks were rerun for their 4 November Figma redesigns. Backend numbers
remain the M8 evidence; that suite was not rerun for these presentation changes.

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
- AI gateway: previously configured for Gemini; the `.env` needs the new `AI_*` keys (see §4) before the assistant is available again.
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
