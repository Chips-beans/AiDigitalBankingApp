# Kesor Bank — next session brief

Updated 31 October 2026, Asia/Phnom_Penh. This is the consolidated current state;
older entries in `CURRENT_PROJECT_HANDOFF.md` are chronological snapshots.

## Start and preserve

- Project: `C:\Users\User\Documents\GitHub\AiDigitalBankingApp`.
- Read `AGENTS.md`, this brief, `docs/CURRENT_PROJECT_HANDOFF.md`, then the relevant
  feature document listed below.
- HEAD at this handoff: `60f8137`. Many tracked edits and untracked source/assets
  remain uncommitted. Preserve all of them. Do not reset/clean, discard files,
  reset the database, rewrite applied migrations or clear device data for setup.
- Keep backend `.env` credentials private. Do not print them, put them in Flutter,
  copy them into summaries or change assignments without a task requiring it.
- Run heavy tests/builds **sequentially**; this PC has approximately 8 GB RAM.
- Cloudflare: use the cf CLI unless the project has a Wrangler configuration.

## Implemented

Stack: Flutter/Dart customer app; Spring Boot 4.1.1/Spring Security/JPA backend,
Flyway and PostgreSQL. Java targets 21 (this workstation used JDK 24.0.2).
Development PostgreSQL is normally `localhost:5432/digital_banking_db`; credentials
belong only in private configuration. Tests use a separate embedded database.

**Customer banking:** email OTP and Telegram authentication, onboarding, profile
photos, four-digit server-enforced PIN protection/recovery, USD/KHR accounts,
manual internal transfers, QR generation/scanning/transfers, transaction history,
receipts and Monthly Analytics. Financial operations retain ownership checks,
exact money calculations, idempotency and recovery of uncertain requests.

Paired test-account opening was designed to fund a newly created USD account with
USD 200 and a KHR account with KHR 100,000 only when server test funding is enabled.
Zero funding is the default without that flag. **The existing V16 automatic-wallet
work now has failing wallet/pair/QR tests; verify that interaction before claiming
the current full account-opening regression is sound.** Do not alter real balances
or weaken assertions to conceal those failures.

**AI Assistant:** authenticated, read-only balances, transaction search, receipt
explanations, monthly summaries, English/Khmer help, saved conversations and
idempotent request recovery. It cannot prepare or submit payments. Verified cards
come from backend records; optional Gemini interpretation/prose is validated and
has localized fallback behavior.

**Profile image correction:** Create Profile uses a live initial from the name
when no photo is selected. Selected photos preview immediately during authenticated
upload; failure/lock/sign-out safely clear or restore previews. Eight focused
photo widget checks were added. Personal physical-picker acceptance is not recorded.

**Telegram Android return:** personally verified by the user reaching Create
Profile/PIN/Home. The fix covers activity recreation, single-task return, retained
in-process Flutter engine and native callbacks without state only for an active
server-PKCE-bound attempt. Server nonce/signature/PKCE/one-use checks remain intact.
Do not revert these fixes while debugging other Android behavior.

**Transfer UI and bottom bar:** Figma entry/review/success, spacing/type/buttons,
original icon artwork, KHR Cambodia flag and borderless USD flag. Dark account/
receiver icons have no gold background, as the user requested. Shared floating
navigation uses the original chat icon. Receipt data comes from confirmed results.
Manual receiver names are unavailable from the API, so real account numbers fill
that position; do not invent recipient identities.

**Settings:** Figma `320:308`, dynamic name/photo/initial, profile name/photo/contact
editing, current-PIN-verified PIN changes, local Android alert preferences/settings/
test alerts, English/Khmer, System/Light/Dark, FAQ/AI help, support email, demo policy
readers and confirmed sign-out. User confirmed: **"Settings looks correct and pages
open"** on the installed device. This confirms appearance/navigation, not a personal
PIN change or notification delivery.

Settings APIs under `/api/v1`: `PUT /auth/profile/details` updates completed profiles
without repeating onboarding/opening wallets; `POST /auth/pin/change` verifies the
current PIN, uses the shared persistent five-attempt counter, changes the existing
peppered BCrypt hash and revokes other sessions. Fifth mismatch closes all customer
PIN locks. Mutations are never automatically replayed.

## Current runtime and device

Rechecked for this summary on 31 October:

| Item | Current / latest verified state |
|---|---|
| Backend | Running on 8080, Java PID 19572; launcher PID 33884 |
| Database | PostgreSQL service `postgresql-x64-18` running; latest verified schema V16 |
| Device | Samsung SM-X216B, serial `R9TXB0G1VKT`, authorized and connected |
| API forwarding | `adb reverse tcp:8080 tcp:8080` active |
| APK mode | API/dev, normal entrypoint, `http://127.0.0.1:8080/api/v1` |
| Latest installed APK | `KesorBank-Settings-Test.apk`, installed with `adb install -r` |
| Gradle | Build daemon stopped after packaging |
| Gemini | Key and both flags configured previously; live success still unverified |

Recheck processes/devices at the next session; PIDs and connections can change.
Keep backend/USB forwarding available for user testing unless asked to stop.
Do not start another server on the same port without checking its owner.

The device has **Don't keep activities enabled**, **130% text scale** and **300
font-weight adjustment**. These were respected, not changed. Never request or
enter the customer's PIN, Telegram codes or password; the customer approves
personal authentication and security changes privately.

Backend private runtime logs:
`backend/digital-banking/.local/settings-backend-20261031.log` and `.err.log`.
The ignored `.local/start-settings-backend.ps1` constrains backend memory. Settings
added no migration; V16 was already present when the latest backend restarted.

## Verification — distinguish current from historical

- **219 full Flutter tests passed** with concurrency 1.
- Flutter analysis: **no issues**.
- Web/Wasm debug build and normal Android debug build: **passed**.
- **27 focused backend tests passed:** 23 `ContinuationAuthTests` and four
  `FoundationReadinessTests`, including new profile/PIN security and API contracts.
- **44 Settings renders** passed layout checks; reference geometry was asserted
  and images inspected. Both languages/themes, all feature pages, small screens,
  2× text, landscape and tablet are covered.
- Transfer previously passed 213 full Flutter tests, then 14 focused checks and
  56 renders; the later 219-test suite includes the current transfer tests.
- Latest APK installed successfully without clearing app data; both Settings API
  routes were confirmed in live read-only OpenAPI. Settings device UI/navigation
  accepted. Telegram native personal return accepted.
- **Update 31 October (later):** the full backend suite now passes, 155/155, after
  the Priority 1 fix below. The paragraph that follows is historical.
- Historical: **Do not report the full backend suite as passing.** Historical 148-pass evidence
  predates the current V16 wallet work. The Settings full run had 154 tests with
  11 failures and one error; one failure was the old path-count assertion for the
  two new APIs. That assertion was corrected and the four contract tests passed.
  The other 11 cases reproduce on unchanged HEAD as listed next.

## Unfixed issues and pending checks

### Phase 4 (user bug list) — 4.1 and 4.2 done, 4.3–4.5 pending

**4.2 update (~03:08):** the Flutter transfer flow is done. The QR scan opens the normal
transfer screen, Home and saved recipients fill the number and show name and photo,
USD↔KHR conversion is previewed on review, and the PIN is asked at confirm and retry.
`KesorBank-Phase42-Test.apk` is installed (data kept). **The dev backend now enforces
transfer PIN proofs** (PID 18612, launcher 24540, log `.local/p42-backend-20261031.log`).
Device acceptance by the user is pending. Details are in `docs/IMPLEMENTATION_PLAN.md` 4.2.
Earlier 4.1 notes follow; the process-only `TRANSFER_PIN_REQUIRED=false` they mention
is no longer in effect.


Done 31 October ~02:50, full backend suite 161/161: recipient lookup by account number
(full name and photo), counterparty names in history ("Kesor Bank" for opening and
bank deposits), fixed-rate USD↔KHR transfers (4000, KHR→USD rounded down), the
transfer quote, and one-time transfer PIN proofs. Contracts are in
`docs/IMPLEMENTATION_PLAN.md` Phase 4.1. The dev backend was restarted on 4.1 at 02:52
(Java PID 35896, launcher 29008, log `.local/p41-backend-20261031.log`; dev DB migrated
to **V17**, which is additive). It was launched with process-only
`TRANSFER_PIN_REQUIRED=false` (`.env` is unchanged) so the installed APK can still
transfer. Restart without that variable once the 4.2 APK is installed. Diagnostic
logging for Telegram 503s was added to `TelegramOidcClient`; it's waiting on a
Telegram retry by the user.

### Priority 1: 11 reproducible backend baseline cases — RESOLVED 31 October 2026

The user chose **automatic wallets** (V16): one USD and one KHR wallet per customer
at signup/profile completion. `AccountPairService` now locks the customer, creates
and funds only a missing wallet, always returns the full USD-then-KHR pair and
reports `testFundingApplied` only when both returned wallets carry their opening
credit. Pair/QR tests use fresh wallet-less customers instead of mutating the shared
`alice.demo`/`bob.demo` fixtures (that sharing caused the 1250 → 1280 drift).
Expectations V16 legitimately changed were updated: signup returns two zero-balance
wallets, the `POST /accounts` audit uses a wallet-less customer and also asserts the
limit rejection, migration version 16. No expected balance was replaced by an
observed value. A new test covers signup funding once plus pair opening returning
the same wallets. **Full backend suite: 155 tests, 0 failures, 0 errors**
(`backend/digital-banking/.local/plan-phase1-full-backend.log`). Details:
`docs/IMPLEMENTATION_PLAN.md` Phase 1 and `docs/QR_CUSTOMER_FLOW.md`.

Restarted 31 October ~01:26 with this code: Java PID 26628, launcher PID 34888,
logs `.local/plan-backend-20261031.log`/`.err.log`; schema unchanged (V16, no
migration); `adb reverse tcp:8080` restored. Read-only development-DB check: no
account has two opening credits; legacy data still contains 10 customers with no
wallet, 8 with one, and 3 with duplicate same-currency wallets from pre-V16 pair
openings (pair opening returns the earliest wallet per currency; no data was
changed). A live new signup was **not** performed because it sends a real OTP
email; verify it on the device with a fresh email when convenient.

Original record, kept for history:

An isolated unchanged archive of HEAD `60f8137` ran **152 tests: 10 failures and
one error**. It reproduces these 11 cases without the Settings changes:

| Test class | Failing method(s) |
|---|---|
| `AccountPairQrTests` | `qrRejectsOwnershipPrecisionCurrencyAndUnregisteredPayloads` (null account lookup error) |
| `AccountPairQrTests` | `customerJourneyBothCurrenciesStaticReuseAndDynamicRetry` (currency mismatch) |
| `AccountPairQrTests` | `concurrentFixedPaymentPostsExactlyOnceAndStaticGenerationIsStable` |
| `AccountPairQrTests` | `concurrentSameKeyQrRequestsReturnOneReceiptAndManualKeysAreSeparate` |
| `AccountPairQrTests` | `secondAccountFailureRollsBackFirstAccountCreditAndRequest` |
| `AccountPairQrTests` | `fundedPairsReplayConflictAndPreserveExistingAccounts` |
| `FoundationHandoffTests` | `nativeMigrationPreservesExistingV10ProfilesAndBrowserFlows` (expects V15, gets V16) |
| `PhaseOneFinancialTests` | `realAuthenticationAccountAndAdministrativeActionsEmitAudits` |
| `PhaseZeroIntegrationTests` | `localFixturesAndOpenApiAreReadyForFlutter` |
| `PhaseZeroIntegrationTests` | `signupUsesRealSmtpAndReturnsServerIdentityWithEmptyAccounts` (expects zero, gets two accounts) |
| `QrPaymentIntegrationTests` | `pairedOpeningIsZeroFundedByDefault` |

Investigate V16 automatic wallet creation/account limits versus paired opening,
fixture selection, mutable shared seed balances, QR account/currency selection,
idempotent funding and rollback. These are investigation leads, not a proven common
root cause. Establish intended behavior before changing tests. Preserve V16 and
the user's data. Fix implementation defects and isolate test fixtures as needed;
do not simply replace expected balances/statuses with observed values.

Evidence:

- Current source test logs: `backend/digital-banking/.local/settings-full-backend-tests.log`
  and `settings-focused-backend-tests.log`; XML/text under `target/surefire-reports`.
  Later focused runs overwrite their own class reports, not the full-run log.
- Unchanged baseline and its `baseline-tests.log`/Surefire reports:
  `C:\Users\User\Documents\Codex\2026-10-30\kesor-bank-now-has-the-main\work\settings-backend-baseline\backend\digital-banking`.

### Other unfinished acceptance and intentional limits

1. **Live Gemini — update ~02:00: working with `gemini-3.5-flash-lite`** (new key,
   `.env` model switched at the user's request, backend PID 31644). Six live Khmer
   turns completed in ≤3.3 s with correct balance/help cards; the one explanation
   attempt fell back (`FALLBACK`), so Gemini prose, English locale, monthly summary
   and payment refusal remain unverified. Details in `docs/AI_ASSISTANT.md`.
   Earlier record — **checked 31 October, failing:** key accepted and model
   `gemini-3.8-flash` listed, but every `generateContent` request stalls with no
   response (20–60 s; also other flash models), and all real device turns ended
   `AI_TIMEOUT`. Provider/project-side; user must check the key's project
   (billing/quota/status) or issue a new key. Evidence: `docs/AI_ASSISTANT.md`.
   Original item: verify one successful English answer and one Khmer answer,
   actual provider/model availability and prose quality, plus safe fallback/recovery.
   Key/flag configuration alone and demo cards do not establish provider success.
   Do not expose the key or turn read-only AI into a payment executor.
2. **Physical device — 31 October 01:43 check:** prep verified (installed APK SHA-256
   matches `KesorBank-Settings-Test.apk`, built after the last Flutter edits; camera
   granted; `adb reverse` active). After the user reported the checklist done: the
   app was connected and reading data (live adb→8080 connection; Khmer Analytics
   screen showing USD income $200.00 at 01:44), but there were **no audit events, new
   or revoked sessions, or new accounts since the 01:26 restart** (reads are not
   audited), and `POST_NOTIFICATIONS` was still `granted=false`. So PIN change/recovery,
   signup and notification items have no server/OS evidence yet; photo/QR/visual items
   need the user's own report. The user then confirmed they **only did the visual
   checks**; PIN change/recovery, notifications, gallery photo, camera QR and fresh
   signup remain untested. **User accepted (31 October): "Yes, all correct"** for the
   corrected transfer icons/flags and the Analytics screen as shown, including the
   large faded lotus area at its top (intended, not a bug). Original item: privately test PIN change/recovery and notification permission/
   delivery, camera QR scanning and gallery photo selection. Android notification
   permission was off at the last read-only check. Transfer icon/flag corrections
   were installed, but final explicit device acceptance of that corrected flow is
   not recorded. Submit no real payment merely to verify UI.
3. **Biometrics:** intentionally disabled at the user's request. Keep disabled.
4. **Notifications:** local opt-in Android activity alerts only; background push
   delivery is not implemented. Alerts contain no account values.
5. **Support/legal:** `reachsteav2@gmail.com` is the user-provided support contact.
   Terms/Privacy are explicitly demo data by request. Real published policies and
   production agreements have not been provided; do not invent them.
6. **Platform/integration limits:** native iOS build/device acceptance remains
   unverified. QR tests are not Bakong/KHQR certification or proof of external
   settlement. Manual transfer recipient display names require an API capability
   if requested later.

Settings placeholders and the previously broken personal Telegram return are
**resolved**, not remaining tasks. Runtime, phone, schema and Gemini configuration
statements in older handoff snapshots must not override this brief.

## Feature documents and source pointers

- `docs/AI_ASSISTANT.md` — read-only boundaries, APIs, provider and recovery.
- `docs/NATIVE_TELEGRAM_SETUP.md` — retained engine, callback rules and native setup.
- `docs/QR_CUSTOMER_FLOW.md` — paired opening/QR contract; reconcile with V16 failures.
- `docs/APP_PIN.md` — existing PIN setup/unlock/recovery; Settings additions are
  in `frontend/customer_app/docs/SETTINGS_SCREEN.md`.
- `frontend/customer_app/docs/EMAIL_AUTH_SCREENS.md` — onboarding/photo screens.
- `frontend/customer_app/docs/TRANSFER_SCREEN.md` — complete transfer reference.
- `frontend/customer_app/docs/SETTINGS_SCREEN.md` — Settings, new APIs and local alerts.
- New Settings Dart UI/platform files: `frontend/customer_app/lib/features/settings/`.
- Session/profile/PIN wiring: `lib/features/auth/session_controller.dart`,
  `lib/features/auth/data/settings_gateway.dart`, `app_pin_gateway.dart` and
  `lib/features/accounts/presentation/accounts_shell.dart` under the Flutter app.
- Android bridges: `KesorApplication.kt`, `SettingsBridge.kt`, `MainActivity.kt`,
  `TelegramLoginBridge.kt` in `android/app/src/main/kotlin/com/bank/customer_app/`.

## Commands — run only the checks relevant to the next change

Backend commands, from `backend/digital-banking`:

```powershell
.\mvnw.cmd spring-boot:run
.\mvnw.cmd -q "-Dtest=ContinuationAuthTests,FoundationReadinessTests" test
.\mvnw.cmd test
```

Tests use isolated embedded PostgreSQL/local SMTP. Never point them at the live
development database. Inspect the existing listener before starting the backend.

Flutter commands, from `frontend/customer_app`, sequentially:

```powershell
flutter test --concurrency=1
flutter analyze
flutter test tool/settings_visual_qa.dart --concurrency=1
flutter build web --wasm --debug
flutter build apk --debug --dart-define=APP_ENV=dev --dart-define=APP_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
```

ADB is `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`:

```powershell
adb devices
adb -s R9TXB0G1VKT reverse tcp:8080 tcp:8080
adb -s R9TXB0G1VKT install -r <verified-new-apk>
```

Use a replacement install to preserve data. Stop Gradle daemons after packaging
when not needed. No production deployment, commit or merge was performed.

## Latest deliverables

Folder:
`C:\Users\User\Documents\Codex\2026-10-30\kesor-bank-now-has-the-main\outputs`.

- Latest APK: `KesorBank-Settings-Test.apk` — **245,222,373 bytes**.
- SHA-256: `9b24c6975e1589db8d70812682662a690aef81514988284a0e69b1ee23daf0c7`.
- `Settings-Implementation-Notes.md`, `Settings-Figma-Light.png`,
  `Settings-Figma-Dark.png`, Khmer and feature-page renders.
- Earlier transfer APK/renders and `Transfer-Flow-Notes.md` remain available, but
  the Settings APK includes the preserved photo/Telegram/transfer corrections.
