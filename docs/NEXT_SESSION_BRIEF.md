# Kesor Bank — next session brief

## Merchant M8 source complete — 4 November 2026

M8a (live payment feed, in-app banner, Sound/Vibration settings) and M8b (owner transfers: a
shop's business wallet to the same owner's own wallet, approved with a fresh PIN in the Customer
App) are implemented, plus G1 (riel sign) and the G2/G4 notes. Read `MERCHANT_M8_TRANSFERS.md`.
Backend **234/234** (220 + 14), Merchant **106/106** (73 + 33), Customer **273/273** (251 + 22),
both analyses clean, Merchant fixture **232** renders and Customer transfer fixture **24** renders
without overflow. Migration **V21** (`merchant_owner_transfers`); `FinancialPostingService.
postOwnerTransfer` is the only business-wallet debit path. **Not done / not verified:** nothing is
committed (work is uncommitted on `docs-built-with`; M7 was merged by PR #1), Android native code
(`MerchantLinkBridge.kt`, debug manifests) was not compiled, no APK, no dev backend restart or
migration (V19–V21 are unapplied to development), no device approval. M9 still needs your explicit
go-ahead. Usage at the end of the run: 69% five-hour and 46% weekly remaining; threshold not hit.

## Merchant M7 commit checkpoint — 3 November 2026

The user authorized committing M7 and adding Codex as a contributor. This commit
includes the full M7 implementation, F1–F6 fixes, verification/handoffs,
plus a Codex co-author trailer (AI credit now lives in the README "Built with"
section; `CONTRIBUTORS.md` was removed). Branch:
`merchant-m4-shop-registration`; use `git log -1` for the commit ID. No push or
merge; `.claude/` is excluded and preserved. Latest checks remain backend 220,
Merchant 73, clean Merchant analysis and 220 no-overflow renders. No source
changed after those checks; only contributor/checkpoint documentation changed.
Native/device limits and M8/M9 scope remain unchanged. The uncommitted statements
below are historical verification checkpoints superseded by this commit note.

## Merchant M7 F1–F6 follow-up complete — 3 November 2026

Receipt times are covered by the exact Phnom Penh midnight regression; receipt
cards/shared text show exact human-form rates; all payment counts use one EN/KM
helper. Request-history expiry work is capped at 50 total rows per call with
effective expiry filters, page-first budgeting and ascending payment locks.
Concurrent-update notices refresh Sales/Reports; isolation is unchanged. Sales
title and controller OpenAPI/response types are aligned with conventions.

Final backend **220/220**, Merchant **73/73**, Merchant analysis clean; visual
fixture **220 renders** without overflow, all five requested updated renders
inspected. See `MERCHANT_M7_SALES.md` for follow-up logs and known limits.
Customer diff is empty; prior Customer 251/251 was not rerun for this follow-up.
No APK, dev backend/database action, migration, credential entry or commit.
M7 remains uncommitted on `merchant-m4-shop-registration` / `669154d`; initial
M7 work and `.claude/` are preserved. M8/M9 remain untouched. Usage: 36% five-hour
and 90% weekly remaining, above the reporting threshold. The original checkpoint
below remains historical evidence of the first M7 implementation.

## Merchant M7 source complete — 3 November 2026

M7 sales history, snapshot receipts, collection reports, request history and
QR/receipt save/share are implemented. Read `MERCHANT_M7_SALES.md` for files,
routes, decisions, verification and limits. Final backend **219/219** (211 + 8),
Merchant **66/66** (53 + 13), Customer **251/251**, both analyses clean; Merchant
visual fixture **220 renders**, no overflow. Seven renders were inspected,
including Khmer at 2x text and dark mode. Logs are listed in the M7 report.

Only `merchant_collections` counts as a sale; totals remain separate by receiving
currency and use Asia/Phnom_Penh boundaries. List/report reads share a database
snapshot; history uses validated keyset cursors. Receipts preserve payment-time
identity and share only safe card/text fields. Request lists settle expiry and
never expose QR strings. No migration was added; V21 remains free for M8.

Branch `merchant-m4-shop-registration`, HEAD `669154d` (plan commit after M5/M6).
M7 is **uncommitted**; no commit/push/merge. Starting tree had only `.claude/`
untracked, which is preserved. Customer source and existing migrations are
unchanged. No APK, backend restart, development DB access or private credential
entry occurred. Native Android compilation/gallery/share-sheet/device acceptance
remain unverified and belong to later acceptance. V19/V20 remain unapplied to
development by this task. M8/M9 were not started; do not continue them under the
M7-only assignment. A future assignment can follow the remaining-work plan.
Latest usage: 54% five-hour and 93% weekly remaining; threshold not triggered.

## Next work: follow MERCHANT_REMAINING_WORK_PLAN.md

M7 is complete in source/automated verification. The implementation plan for the
remaining M8 alerts/owner transfers, small gaps and M9 pilot APKs
is `MERCHANT_REMAINING_WORK_PLAN.md`. Implementing agents start there. APKs are
built only in M9 and only after the user approves.

## Merchant M5 + M6 source complete - 3 November 2026

Dashboard, wallet details and QR collection (fixed-amount requests and the
reusable shop QR) are implemented with migration V20, plus the Customer scan/pay
side (verified shop name/logo, expiry/cancel/inactive checks, shop name on
receipts). Read `MERCHANT_M5_M6_COLLECTION.md`. Full backend **211/211**;
Merchant Flutter 53; Customer Flutter 251; 146 Merchant renders. **Pending:** V19+V20 not applied
to development, no APKs built/installed, no device payment. Business-wallet
debits are blocked until M8 owner transfers. Work is on branch
`merchant-m4-shop-registration` (M4 committed as `7b711d5`; M5/M6 uncommitted).

## Merchant M4 source complete - 3 November 2026

Shop registration, shop profile/logo and the two business wallets are implemented
(source + automated verification). Read `MERCHANT_M4_SHOP.md` for routes, V19,
app behaviour and evidence. Full backend **203/203**, Merchant Flutter **42/42**,
**106** Merchant renders, analysis clean. Customer App source is unchanged.
**Pending:** V19 is not applied to the development database (backend was stopped),
no APK was built/installed (no device connected) and no device acceptance exists.
Next: restart the backend (applies V19), build/install the Merchant APK, let the
user register a shop privately, then M5 dashboard. Work is uncommitted on `main`
(`a88b061`); earlier statements about `kesor-phase4-fixes`/`e1a9da2` are stale.
Usage tool unavailable in this session; unavailable is not zero.

## Merchant M3 complete - 31 October 2026

M3 development sign-in is complete. Both final APKs are installed on Samsung
`R9TXB0G1VKT`. The user privately approved Customer sign-in and confirmed:
**"Register Shop or my existing shop opens, including after reopening."**
This verifies the native approval/return path, expected routing and session
restore with the tablet's existing Don't keep activities setting.

Read `MERCHANT_M3_HANDOFF.md` for exact protocol/native behavior, artifacts,
hashes and acceptance limits. M0-M3 are complete for the adopted development
scope; M4-M9 are not started and M10-M13 remain deferred. M4 registration is next.

Customer full regression: **247 passed**; focused + visual: **14 passed**;
final visual fixture: **24** combinations and reachable lower controls.
Merchant final full run: **28 passed**, including **90** visual combinations,
failed-storage revocation and cancellation/logout versus new-sign-in overlap.
Analysis is clean in both apps. Prior M2 backend **191/191** log was confirmed;
M3 made no backend Java/migration source changes and claims no new full rerun.

Backend: **8080 / Java 2036**, launcher 10272. Controlled restart applied **V18
over V17** at 11:30 local; private environment preserved. Live OpenAPI has all 12
Merchant paths. Samsung reached the session endpoint over Wi-Fi (401/no-store).
Both APKs use `http://172.16.128.192:8080/api/v1`; installed hashes match
verified outputs. No private environment files are packaged.

New source: shared `frontend/packages/kesor_auth_handoff`, Merchant API gateway/
secure journal and retained Android engine; separate Customer approval bridge,
fresh-PIN page and Settings > Merchant sessions. Exact callback/state and peer
package/signer checks; explicit same-body 60-second exchange recovery; durable
cancellation, Merchant rotation/logout and owner revocation. Customer PINs/tokens
never cross the Merchant link. Registration/financial capabilities remain M4+.

Device Don't keep activities=1 and text scale=1.3 were preserved. The agent
entered no personal PIN/OTP. The user performed personal approval privately.
Source remains uncommitted on `kesor-phase4-fixes` / `e1a9da2`; prior Customer
work is preserved. Release HTTPS links still require a supplied domain/release
certificate. Other native edge cases have automated coverage; do not claim every
physical scenario was personally tested from this successful round trip.
Usage/quota tool unavailable in this session; unavailable is not zero.

Outputs: `C:\Users\User\Documents\Codex\2026-10-31\kesor-bank-is-a-digital-banking\outputs`.
Merchant: `KesorMerchant-M3-SignIn.apk` (SHA-256
`128df250e8b82c42429f34254cb9c3ad55265aed4323c60df3d4b533d617c8c8`).
Customer: `KesorBank-M3-Approval.apk` (SHA-256
`a3e2d16993680337f829944c4f8eccf8712555c152cfe58b87c1f780f8937c74`).

## Home Favorite Recipients — 31 October 2026

The Home section is now titled "Favorite Recipients" (អ្នកទទួលពេញចិត្ត). It no
longer lists counterparties from transfer history; it shows only favorites the
customer added manually through its form (`FavoriteRecipient.manual`, stored in
the device-local, per-user `RecipientFavoritesStore`), one per account number.
Transfer-screen "Save to Favorites" bookmarks do not appear on Home.
Empty state: "Add people you transfer to often."
The Add button opens an "Add to favorites" form: Account/Wallet number required
(10-20 digits), Name optional and customizable (max 40; empty uses the
server account name). The shell verifies the number with `RecipientDirectory`
(must be another active Kesor account; own accounts refused) and stores its
currency. `FavoriteRecipient` gained an optional `name` (JSON stays version 1,
old entries load unchanged); a transfer's "Save to Favorites" keeps an existing
custom name, and the Transfer saved-recipients sheet shows it. "All" lists
favorites with remove. Locked Home's Add asks to unlock. Tests: 234 passing
(new `test/home_recipients_test.dart`), analysis clean, Home visual QA passing.
No backend/database changes.

## Merchant M2 — backend security implementation, 31 October 2026

M2 approval/session code is complete: full backend regression passes **191 tests,
0 failures/errors/skips**, finished 10:42 Asia/Phnom_Penh on 31 October 2026.
Read `MERCHANT_M2_SECURITY.md` for the exact twelve API routes and M3 integration
contract, and `MERCHANT_APP_PROGRESS.md` for current evidence. V18 adds Customer
session backfill/purpose-scoped uniqueness, durable approval attempts and budgets.
Fresh Customer PIN approval shares the existing persistent attempt limit; codes
are S256/state/secret/client/callback-bound. Merchant sessions have a distinct
audience/purpose, rotating refresh credentials, owner revocation, race-safe
cancellation and 60-second encrypted response-loss recovery. Existing Customer
sessions retain their behavior; PIN security changes also cancel unexchanged codes.

The suite includes 30 new M2 checks plus all 161 existing backend tests. Actual
restart recovery, V17 Customer-session upgrade, purpose/audience isolation,
concurrent approval/exchange/cancellation/revocation, PIN budget, refresh reuse,
shop scope/status, audit secrecy, budgets, cleanup and API contracts pass. Older
fixture session cleanup now removes approval dependents first; assertions and
database foreign-key guards are preserved. `git diff --check` passes.
All migration tests use isolated PostgreSQL. The active Wi-Fi backend (observed
PID 16248 / 8080) is left unchanged; V18 has not been applied to development by
this task. No `.env`, Flutter source, APK, live customer data or financial rows
were changed. M3 app approval/native handoff is next after M2; the installed M1
Merchant gateway still intentionally reports unavailable. M0-M2 are complete;
M3-M9 are not started and M10-M13 remain deferred. Latest usage check: 78%
five-hour, 29% weekly remaining; neither crossed the 10% reporting threshold.
Detailed continuation steps and exact log/file boundaries are saved in the
progress report and copied to this chat's outputs. No commit/push/merge was made.

## Customer Home + Wallet & Accounts UI — 31 October 2026

Home balance card now has exactly three equal-width actions (Transfer, Scan QR,
My QR; tooltips `Transfer`, `Scan QR`, `Receive`) instead of a six-item
horizontal scroller. Balance and transaction amounts stay on one line and scale
down instead of wrapping. The `accounts` page (opened from the balance card) is
now `WalletAccountsScreen` (`lib/features/accounts/presentation/wallet_accounts_screen.dart`):
navy total-balance card with KHR/USD totals and hide toggle, three actions
(Transfer, My QR, Open accounts), wallet tiles with status chips, and a selected
wallet card (copyable number, details, activity). Activity now opens History.
Tests: 230 passing, analysis clean. Render QA: `flutter test tool/home_wallet_visual_qa.dart`
(output `.local/qa/home-wallet`) — 48 Home and 16 Wallet variants, no overflow.
Welcome/login: artwork now draws under a transparent status bar (bottom inset
kept) and the hero crops its lower edge on short screens so the footer fits
without scrolling; the 440x956 reference geometry is unchanged. Wi-Fi API/dev
debug APK (`http://172.16.128.192:8080/api/v1`) installed with `adb install -r`
on TECNO LJ6 `1429155557104952`; backend started on 8080 via `mvnw spring-boot:run`.
My QR: the receiving wallet is a drop-down (`qr-wallet-select`, items keep
`qr-wallet-<number>` keys) above the QR card instead of a list of rows; QR max
size 250 -> 200 with tighter card padding so it fits the TECNO viewport without
scrolling. `tool/qr_visual_qa.dart` gained a `tecno` variant and its fixed-amount
step now uses the Enter amount dialog.
No backend/database changes were made.

## Customer Wi-Fi APK — 31 October 2026

User requested firewall setup and a Customer APK for same-network access without
USB debugging. `KesorBank-WiFi-Test.apk` is built for
`http://172.16.128.192:8080/api/v1`. Five configuration tests passed; APK build,
embedded URL, signing certificate and absence of `.env` files were verified.
The connected TECNO phone (`172.16.128.213`) reached the backend through wlan0 and
received the expected unauthenticated 401. Existing enabled Public Java firewall
rules already allow this connection, so no firewall/profile changes or elevation
were necessary. No APK installation or customer authentication was performed in
this task. Backend PID 18612/port 8080 and database were left unchanged.

See `frontend/customer_app/docs/WIFI_DEVELOPMENT.md` for installation, hash,
firewall scope and network evidence. The APK/setup notes are in this chat's outputs.
An API-origin change may require a new sign-in because secure storage is scoped
by API URL. Use existing account identity; server-side accounts/data are unchanged.
Merchant milestones remain M0/M1 complete, M2 next.

## Merchant implementation checkpoint — 31 October 2026

Implementation is authorized from M0. Read `MERCHANT_APP_PROGRESS.md` for the
current checkpoint and usage-reporting rule, and `MERCHANT_M0_CONTRACTS.md` for
audited decisions/API/session/data contracts. M0 is complete: 161 backend tests,
230 Customer Flutter tests and clean analysis; read-only live schema V17, zero
shops/merchant accounts, three unchanged legacy personal-wallet duplicate groups.
M1 app/shared-theme foundation is complete. Post-extraction Customer regression
also passed 230 tests; Merchant passed 11 foundation checks plus the 78-render
visual fixture, with clean analysis in both apps. Both normal API/dev Android APKs
built successfully. `KesorMerchant-M1-Foundation.apk` is installed alongside the
unchanged Customer Scanner APK, and its native welcome screen was visually
verified. APK/hash/output locations and exact M2 continuation steps are in the
progress report. Gradle daemon stopped; backend/USB forwarding left available.

M2/M3 sign-in approval and backend integration are not implemented. The normal
Merchant entrypoint fails closed with service unavailable; shop/financial screens
are test fixtures only. There is no local/demo login, payment or new live migration.
Existing scanner changes remain preserved on `kesor-phase4-fixes` at `e1a9da2`.

## Merchant App planning — 31 October 2026

The user requested an implementation plan for a separate Android-first Merchant
App. Its only sign-in is approval in Customer App via deep link, followed by shop
registration and exactly two business wallets (KHR/USD). Shop name/logo are its
profile. See [MERCHANT_APP_IMPLEMENTATION_PLAN.md](MERCHANT_APP_IMPLEMENTATION_PLAN.md)
for agreed requirements, proposed defaults, M0-M9 first-release milestones and
M10-M13 deferred work. At that planning checkpoint no implementation had started;
the implementation checkpoint above supersedes that status. Preserve scanner work.

## Latest UI update — scanner, 31 October 2026

The scanner now follows the user's image layout with a full camera area, gold
rounded viewfinder, Kesor Scan title/close, Flash and Upload QR pills, and a Kesor
brand footer. It retains verified QR-to-Transfer handoff and local image decoding.
See `frontend/customer_app/docs/SCANNER_SCREEN.md`. Full Flutter suite: 230 passing;
analysis clean; 12 scanner visual variants passed. Changes are on
`kesor-phase4-fixes`, based on `e1a9da2`, and remain uncommitted/unpushed.
No backend or database changes were made for this scanner UI update.

The normal API/dev Android debug build succeeded and `KesorBank-Scanner-Test.apk`
was installed on Samsung `R9TXB0G1VKT` with `adb install -r`, preserving app data.
APK and sample renders are in
`C:\Users\User\Documents\Codex\2026-10-31\kesor-bank-is-a-digital-banking\outputs`.
APK SHA-256: `134d3334707d52ae1f8755ba2da3cf9eea3f441fd7c6d1b78416aa800a85cca4`.
Gradle daemon stopped after packaging. Backend 8080 and USB forwarding were left
available. Hardware camera/gallery acceptance of the new UI remains pending.

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
