# Kesor Merchant — remaining work plan (M7, M8, M9 and gaps)

**Owner:** project manager. **Audience:** the implementing agent.
**Written:** 3 November 2026, Asia/Phnom_Penh. **Status at writing:** M0–M6 source
complete and committed on branch `merchant-m4-shop-registration`
(`7b711d5` M4, `373f03a` M5/M6). M7–M9 are not started.

This document tells you **what to build, in what order, where, how to verify it,
and what you must not do.** When this plan and older documents disagree, this plan
wins for M7–M9; for anything already built, the code and the M4/M5–M6 docs win.

**M7 checkpoint, 3 November 2026:** source/automated complete, included in the
user-authorized M7/F1–F6 commit with Codex credit (see `git log -1`); no push/merge;
latest F1–F6 follow-up backend 220, Merchant 73, Merchant analysis clean, 220
no-overflow renders (five requested follow-up renders inspected); Customer
unchanged (prior 251). See `MERCHANT_M7_SALES.md`. No migration, dev runtime,
APK or device acceptance; M8/M9 were not started in the M7-only run. The status
at writing and baseline instructions below remain historical start conditions.

---

## 0. Before you write any code

### 0.1 Read, in this order

1. `AGENTS.md` (project rules — mandatory).
2. `docs/NEXT_SESSION_BRIEF.md` (top sections only: M5/M6, M4, M3).
3. `docs/MERCHANT_M0_CONTRACTS.md` sections 2, 4, 6, 7 (decisions, access matrix,
   contracts, report definition).
4. `docs/MERCHANT_M4_SHOP.md` and `docs/MERCHANT_M5_M6_COLLECTION.md`
   (what exists and the conventions it uses).
5. `docs/MERCHANT_M3_HANDOFF.md` (app-to-app approval transport; needed for M8).
6. This file, completely.

### 0.2 Confirm the starting state

```bash
git status --short
git log --oneline -3
```

Expected: branch `merchant-m4-shop-registration`, HEAD `373f03a`, only `.claude/`
untracked. If the tree is dirty with work you did not make, **stop and report**;
never reset, clean, stash-drop or overwrite it.

### 0.3 Hard rules (from the user and the project)

| Rule | Detail |
| --- | --- |
| No APK builds until M9, and only with explicit user approval | The user said "don't build APK yet". M9 starts with a question to the user. |
| No commits/pushes/merges unless the user asks | Report "uncommitted" at each checkpoint. |
| Never touch the live development database for tests | Tests use embedded PostgreSQL (`PostgresIntegrationTest`). Do not restart or migrate the dev backend before M9. |
| Never request, enter or log a PIN, OTP or password | Personal approval is always done privately by the user on the device. |
| Keep secrets out of code, logs, docs and APKs | Backend `.env` stays private and unread. |
| Run heavy jobs sequentially | The PC has ~8 GB RAM: one Maven/Flutter test run or build at a time. |
| Preserve existing behavior | Do not weaken assertions, delete tests or change expected balances to make tests pass. Fix the cause. |
| Format only files you touched | `dart format lib` reformats unrelated Customer files. Use `dart format <your files>` and check `git diff --stat` before finishing. |

### 0.4 Usage reporting (from AGENTS.md)

Check the available usage tool before each milestone. If a window is below 10%,
write a detailed checkpoint into `docs/MERCHANT_APP_PROGRESS.md` and
`docs/NEXT_SESSION_BRIEF.md` and tell the user. Unavailable data is **not** zero —
say "unavailable".

---

## 1. Conventions you must follow (learned while building M4–M6)

Follow the code around you. These are the patterns that already exist and the
mistakes that already cost time.

### 1.1 Backend (Spring Boot 4, Java 21, `backend/digital-banking`)

- **Every Merchant API** starts with `sessions.merchant(user, sid)`
  (`MerchantAuthService.merchant`). It locks the owner row and checks the Merchant
  session. Then derive the shop with `MerchantShopService.requireShop(owner)`.
  **Never** accept owner ID, shop ID, merchant code or wallet ownership from the request.
- **Route registration:** add every new Merchant path pattern to
  `SessionPurposePolicy.SHOP_ROUTES` (it feeds both the purpose filter and
  `SecurityConfig`). A path missing there returns `CUSTOMER_SESSION_REQUIRED` for
  Merchant sessions. Do not change the legacy `GET /merchants/me/accounts`.
- **Errors:** `ApiException(HttpStatus, "UPPER_SNAKE_CODE", "Human message")`.
  Foreign or missing resources are `ResourceNotFoundException` (404) with no detail.
- **Responses:** `ResponseEntity` with `CacheControl.noStore()` and
  `ApiResponse.success(value, message)` (see `MerchantCollectionController.body`).
- **Money** leaves the server as exact decimal text:
  `MerchantShopService.money(BigDecimal, currency)` (KHR scale 0, USD scale 2).
  Never `double`. Never add USD and KHR together.
- **Business day** is `MerchantCollectionService.BUSINESS_ZONE` (Asia/Phnom_Penh).
- **Request DTOs that create or change data** reject unknown fields with a
  `@JsonAnySetter` that throws (see `MerchantShopDtos.Strict`,
  `MerchantCollectionDtos.NewPaymentRequest`).
- **Idempotency:** writes that create money movements or records take an
  `Idempotency-Key` header (`[A-Za-z0-9_-]{16,128}`), store `sha256(key)` and
  `sha256(canonical body)`; same key + same body replays (200), same key + other
  body is `409 IDEMPOTENCY_CONFLICT`.
- **Rate limits:** `MerchantAuthRateLimiter.check(lane, ownerId, perMinute)`.
  **Lane names must be ≤ 15 characters** — the stored key is `lane:sha256` in an
  80-character column; a longer lane caused a 409 `RESOURCE_CONFLICT` in M6.
- **Locks:** financial state changes lock the registered `payments` row first,
  then request/intent rows, then accounts. Keep that order in any new code.
- **Data access style:** `JdbcTemplate` with SQL text blocks in Merchant services;
  JPA only where the module already uses it (accounts, payments, transactions).
- **Migrations:** next free version is **V21**. Additive only; never edit V1–V20.
  When you add one, bump `FoundationHandoffTests` (`getVersion()` and
  `applied().hasSize(n)` — currently `"20"` and `19`).
- **Tests:** HTTP integration tests extend `PostgresIntegrationTest`. Merchant tests
  share one Spring context by using exactly:
  `@SpringBootTest(classes = DigitalBankingApplication.class, webEnvironment = RANDOM_PORT, properties = "app.dev.opening-funding.enabled=true")`.
  Reuse the fixtures in `MerchantCollectionTests` (`shop()`, `payer()`, `pay()`,
  `race()`); payers need the PIN prepare/setup step to get an unlocked token.

### 1.2 Merchant Flutter app (`frontend/merchant_app`)

- Text/strings: `t(context, en, km)` and `mText(context, size, lineHeight, …)` from
  `lib/core/merchant_strings.dart`. Every user-facing string has English **and**
  Khmer.
- Visual building blocks are in `lib/features/shop/shop_widgets.dart`
  (`SurfaceCard`, `NavyCard`, `SectionTitle`, `ActionTile`, `CircleAction`,
  `StatusChip`, `CurrencyBadge`, `NoticeBanner`, `shopAmount`) and
  `lib/features/collect/` (`KesorQrCard`, `ReceiptLines`, `ActivityRow`,
  `ReceiptRow`). Reuse them; the UI must keep matching the Customer App.
- All Merchant APIs live behind `MerchantShopGateway` (implemented by
  `MerchantShopApi`). Add new methods to the right interface
  (`MerchantCollectGateway` for sales/reports/transfers) and to the test fake
  `FakeShopGateway` in `test/merchant_shop_test.dart`.
- Parse defensively: unknown enum values or missing fields → `ShopFailure('INVALID_RESPONSE')`.
  `ShopFailure.uncertain` (offline/timeout/5xx/unparseable) means "the server may
  have done it" — never resend a money operation automatically.
- Controllers are `ChangeNotifier`s created per owner in `_MerchantAppState._syncShop`
  and disposed on sign-out, so private data never survives owner change.
- Pushed pages are popped on any session phase change (already handled by
  `navigator.popUntil` in `_syncShop`); just push with `Navigator.of(context)`.

### 1.3 Flutter tests

- Unit/widget tests in `test/`; visual fixture in `tool/merchant_visual_qa.dart`
  (writes PNGs to `.local/qa/<milestone>/`). Add every new screen to the fixture.
- Widget tests: set a tall viewport (`devicePixelRatio = 1`, `physicalSize = 480×2600`)
  so lazy lists build everything.
- After `tester.ensureVisible(...)` always `pump`/`pumpAndSettle` before tapping.
- Screens with periodic timers (countdowns, polling) never settle: use
  `pump(Duration)` there, not `pumpAndSettle`.
- To scroll to the top in the fixture use `ScrollableState.position.jumpTo(0)`; a
  drag down triggers pull-to-refresh and pollutes the screenshot.

### 1.4 Commands (run from each module directory, one at a time)

```bash
# backend/digital-banking
./mvnw.cmd -o "-Dtest=MerchantSalesTests" test
./mvnw.cmd -o test          # full suite, ~5 min; log to .local/<name>.log

# frontend/merchant_app and frontend/customer_app
flutter analyze
flutter test test --concurrency=1
flutter test tool/merchant_visual_qa.dart --concurrency=1   # merchant only
```

Current baselines you must keep green: **backend 211**, **Customer 251**,
**Merchant 53**, Merchant fixture **146 renders**, analysis clean in both apps.

---

## 2. Work order and checkpoints

| Step | Milestone | Depends on | Size | Checkpoint report |
| --- | --- | --- | --- | --- |
| 1 | **M7** Sales history, receipts, reports, QR/receipt sharing | M6 | Medium | Source/F1–F6 automated complete: backend 220, Merchant 73, 220 renders; Customer unchanged (prior 251); included in user-authorized commit; native/device acceptance pending ([report](MERCHANT_M7_SALES.md)) |
| 2 | **M8a** Live payment feed + in-app alerts + settings | M7 | Small | After app tests |
| 3 | **M8b** Owner transfers (Merchant → own personal wallet) | M7 | Large, security-critical | After backend, after both apps |
| 4 | **G** Small gaps (riel glyph, docs) | any | Small | With M8 |
| 5 | **M9** Integrated acceptance and pilot APKs | all, **user approval** | Medium | Before building, after install, after user test |

Do the milestones in this order. Do not start M8b before M7 is green: its wallet
activity and "not a sale" rules depend on M7's definitions.

At each checkpoint, report to the user in plain language: what was built, the test
counts, what is not done or not verified, and that nothing is committed.

---

## 3. M7 — Sales history, receipts and reports

### 3.1 Goal

A shop owner can find any confirmed payment, open its receipt, share it, see
daily/monthly collection totals, and save/share the shop QR.

### 3.2 Definitions (do not change)

- A **sale/collection** is one row of `merchant_collections` (a confirmed QR credit
  to this shop's business wallet). Nothing else counts: not deposits, not manual
  transfers into the wallet, not owner transfers, not waiting/expired/cancelled
  requests.
- Amount/currency = what the **shop received** (`amount`, `currency`). The payer's
  side (`paid_amount`, `paid_currency`, `exchange_rate`) is informational.
- Day and month boundaries are Asia/Phnom_Penh. USD and KHR are always separate.
- Receipts show the snapshot (`store_name`, payer first name, masked account) — never
  the current shop profile and never more payer data.

### 3.3 Backend

No migration is expected: `merchant_collections` already has
`(merchant_id, created_at DESC, transaction_id DESC)`. If profiling shows a need,
add indexes in **V21** only.

New routes (all Merchant-session; add patterns to `SHOP_ROUTES`):

| Route | Contract |
| --- | --- |
| `GET /api/v1/merchants/me/sales` | Query: `from`, `to` (ISO dates, inclusive, business zone; default today; max span 366 days), `currency` (`KHR`/`USD`/absent = both), `q` (optional, 1–50 chars: matches transaction reference suffix, request reference, or order note, case-insensitive), `cursor` (opaque), `size` (default 20, max 50). Returns `{items: Receipt[], nextCursor, totals: [{currency,count,gross}]}` where totals cover the **whole filter**, not the page. |
| `GET /api/v1/merchants/me/sales/{reference}` | One receipt by transaction reference; 404 if not this shop's. Adds `walletAccountNumber`, `exchangeRate`, `requestReference`, `orderReference`, `paidAt`. |
| `GET /api/v1/merchants/me/reports/collections` | Query: `period` = `DAY` or `MONTH`, `from`, `to` (DAY: max 92 days; MONTH: max 24 months). Returns buckets `[{bucket:"2026-11-03", currency, count, gross}]` for **every** bucket in range (zero-filled) and both currencies, plus grand totals per currency. |
| `GET /api/v1/merchants/me/payment-requests` | Request history (separate from sales): `status` filter (`WAITING`/`PAID`/`EXPIRED`/`CANCELLED`), `cursor`, `size`. Settle lazily-expired rows exactly like `MerchantCollectionService.settle` before returning. No QR string in list items. |

Implementation notes:

- Put this in a new `MerchantSalesService` (+ `MerchantSalesController` or extend
  `MerchantCollectionController`), reusing `COLLECTION_SQL`/`collection()` from
  `MerchantCollectionService` (make them package-visible rather than copying).
- **Keyset pagination**, not OFFSET: order by `created_at DESC, transaction_id DESC`;
  cursor = base64url of `"<epochMicros>:<transactionId>"`; validate and reject
  malformed cursors with 400. This is what guarantees no duplicates/omissions when
  new payments arrive while paging.
- Date filters: convert `from` 00:00 and `to+1` 00:00 in the business zone to
  `OffsetDateTime` and use `created_at >= ? AND created_at < ?`.
- Reports: generate the bucket series in SQL
  (`generate_series` at the business zone) or in Java, then left-join the grouped
  sums. Group with `date_trunc('day'|'month', created_at AT TIME ZONE 'Asia/Phnom_Penh')`.
- Read-only queries: still call `sessions.merchant(...)` first (it validates the session).
- Rate limit lanes (≤ 15 chars): `sales-list` 120/min, `sales-report` 60/min.

Backend tests — new `MerchantSalesTests` (shared Merchant context). Must cover:

1. Pagination over > 2 pages returns every payment exactly once; a payment arriving
   between page requests does not create a duplicate or gap on later pages.
2. Filters: currency, date range, `q` by order note and by request reference.
3. Totals in the list equal the sum of all filtered items (not just the page).
4. Business-day boundary: payments at 23:59 and 00:01 Phnom Penh land in different
   days (set `created_at` directly with SQL to control time).
5. Report DAY/MONTH zero-fills empty buckets, keeps KHR and USD separate, and
   reconciles to the sales list totals for the same range.
6. Exclusions: a deposit and a manual transfer into the business wallet, and an
   expired/cancelled request, never appear in sales or reports.
7. Cross-shop: another shop's reference returns 404; a Customer session gets
   `MERCHANT_SESSION_REQUIRED`; malformed cursor/dates/oversized ranges return 400.
8. Snapshot: editing the shop name after a payment does not change the receipt.

### 3.4 Merchant app

Files: new `lib/features/sales/` (`sales_controller.dart`, `sales_view.dart`,
`receipt_page.dart`, `reports_page.dart`) and models/gateway methods in
`features/collect/merchant_collect.dart`.

**Sales tab** (replaces the current "latest 10" view in `_ShopShell`):

- Top: period chips — *Today*, *Yesterday*, *7 days*, *This month*, *Custom*
  (date-range picker). Currency segmented control — *All / KHR / USD*. Search field
  (reference or order note, debounced 400 ms).
- Summary card (reuse `TodayCard` style): totals for the active filter per currency.
- List grouped by business day with a small day header showing that day's count and
  totals; rows reuse `ReceiptRow`. Infinite scroll with a "Load more" fallback and
  pull-to-refresh. Empty, loading, error and offline states use `NoticeBanner`.
- Header action: *Reports* → `ReportsPage`; secondary action: *Requests* → request
  history (status chips; tap a WAITING request opens it in the Collect tab).

**Receipt page** (open from any receipt row, including Home and wallet activity
QR rows): navy header card with amount and "Payment received", then `ReceiptLines`
(payer, converted amount, order note, full transaction reference with copy button,
time, wallet). Actions: *Share receipt* (text and PNG — see 3.5) and *Copy reference*.

**Reports page:** *Daily / Monthly* toggle, currency toggle (never combined),
range picker (default last 7 days / last 6 months), a simple bar chart (follow the
style of the Customer App `features/analytics/presentation/daily_chart.dart`; no new
chart package), and a table of buckets with count and gross. Label clearly:
"Collections are payments received, not profit."

**Controller rules:** a filter change cancels in-flight results (generation counter,
like `MerchantSession._generation`); never mix pages from different filters.

### 3.5 Save/share shop QR and receipts (closes the M6 gap)

Port the Customer App's native share bridge rather than adding a plugin:

- Copy `customer_app/android/.../ShareBridge.kt` into `merchant_app` (package
  `com.bank.merchant_app`), register it in the Merchant `KesorApplication`/`MainActivity`
  the same way the Customer app does, and add the matching `FileProvider` entry and
  `res/xml` paths (mirror `customer_app/android/app/src/main/AndroidManifest.xml`
  lines ~39–47). Change the gallery folder to `Pictures/Kesor Merchant`.
- Dart side: copy `customer_app/lib/core/platform/image_share.dart` to
  `merchant_app/lib/core/platform/image_share.dart` (same channel name pattern but
  a Merchant-specific channel, e.g. `kesor/merchant_share`).
- Render PNGs with a `RepaintBoundary` around `KesorQrCard` (shop QR) and around a
  receipt card. Buttons: *Save to gallery*, *Share*. Never put tokens, full payer
  account numbers or internal IDs in shared text.
- Handle `APP_UNAVAILABLE` / Android < 10 save errors with a clear message.

### 3.6 Merchant tests and fixture

- `test/merchant_sales_test.dart`: controller paging (no duplicates when a new page
  overlaps), filter-change race (late page from old filter ignored), receipt
  parsing, report zero-fill rendering, share failure message.
- Extend `FakeShopGateway` with sales/report/history methods.
- Fixture: add `sales` (populated), `sales-empty`, `receipt`, `reports-day`,
  `reports-month`, `requests` screens; output to `.local/qa/m7/`.

### 3.7 M7 exit gate

Backend full suite green (211 + new), Merchant tests green, Customer suite
unchanged and green, fixture renders without overflow, analysis clean,
`docs/MERCHANT_M7_SALES.md` written (same structure as the M5/M6 doc), progress and
brief updated.

---

## 4. M8a — Live payment feed, in-app alerts and settings

### 4.1 Goal

Payments made to the **reusable shop QR** (which has no request to watch) appear
immediately while the app is open, with an optional sound/vibration. No background
push yet (that is M10) — the UI must say so honestly.

### 4.2 Build

- `PaymentFeedController` (per owner, created/disposed in `_syncShop`): while the
  app is resumed **and** a shop is READY, poll `GET /merchants/me/dashboard` every
  10 s (back off to 30 s after 3 failures; stop when paused/covered/signed out).
  Keep the set of seen transaction references (seeded from the first load, so old
  payments never alert). New references → refresh `ShopController`, show an in-app
  banner ("+25,000 ៛ from Sophea"), and if enabled play a short system sound
  (`SystemSound.play(SystemSoundType.alert)`) and `HapticFeedback.mediumImpact()`.
- Deduplicate by reference across the request flow too: a payment already shown by
  `CollectController` as PAID must not alert twice.
- **More → Payment alerts** settings row: toggles *Sound* and *Vibration* (stored in
  `MerchantPreferences`, device-local), plus the honest note: "Alerts work while
  Kesor Merchant is open. Background notifications are coming later."
- Do not add a backend route; the dashboard already returns `recent`.

### 4.3 Tests

Feed starts/stops with lifecycle; first load does not alert; a new reference alerts
once; collect-flow payment does not double alert; sign-out clears seen references;
failures back off. Fixture: the in-app banner state.

---

## 5. M8b — Owner transfers (business wallet → owner's personal wallet)

This moves real money. Read the whole section before starting.

### 5.1 Scope (v1, do not widen)

- Source: one of **this shop's** business wallets.
- Destination: **the same owner's personal WALLET in the same currency** — chosen by
  the server, never typed by the user. No other destinations, no conversion.
- Amount: positive, currency precision, ≤ source balance at commit time.
- Approval: fresh PIN approval **in the Customer App**, bound to the exact intent
  (source, destination, currency, amount, intent ID). The Merchant app never sees
  the PIN or a Customer token.

If the owner has no personal wallet in that currency, return
`409 OWNER_WALLET_REQUIRED` with a message telling them to open it in Kesor Bank.

### 5.2 Flow

```
Merchant app                   Backend                         Customer app
------------                   -------                         ------------
POST owner-transfers  ───────► create intent (PENDING, 5 min)
  (Idempotency-Key)            returns intentId, approvalUri
open approvalUri  ───────────────────────────────────────────► kesorbank://merchant/transfer?intentId&handoffToken
                                                               GET intent details (customer session + handoff)
                                                               owner confirms exact amount, enters PIN
                               ◄── POST .../approve (PIN) ──── 
                               lock intent → verify PIN →
                               post transfer atomically →
                               intent COMPLETED, receipt
                               returns callbackUri ──────────► opens kesormerchant://transfer/callback?intentId&state
Merchant polls status ◄──────  COMPLETED + receipt
```

Approval **executes** the transfer in the same database transaction (no separate
"submit" step). This removes a whole class of approved-but-not-submitted races.
Denial or expiry moves no money.

### 5.3 Backend

Migration **V21** — `merchant_owner_transfers`:

- `id UUID PK`, `merchant_id`, `owner_user_id`, `source_account_number`,
  `destination_account_number`, `currency`, `amount NUMERIC(15,2) > 0`,
  `status` (`PENDING`,`COMPLETED`,`DENIED`,`CANCELLED`,`EXPIRED`,`FAILED`),
  `failure_code`, `key_hash`, `request_hash`, `intent_hash` (sha256 of the canonical
  source|destination|currency|amount|id), `handoff_hash`, `state` (callback state),
  `created_at`, `expires_at` (created + 5 min), `completed_at`,
  `transaction_id UNIQUE` (set only when COMPLETED),
  `UNIQUE(owner_user_id, key_hash)`, checks tying COMPLETED ↔ transaction_id.

Routes:

| Route | Session | Contract |
| --- | --- | --- |
| `POST /api/v1/merchants/me/owner-transfers` | Merchant | `Idempotency-Key`; body `{sourceAccountNumber, amount}`. Server resolves destination, checks shop ACTIVE, source owned, balance (advisory), creates PENDING intent. Returns `{intentId, sourceAccountNumber, destinationAccountNumber(masked), currency, amount, expiresAt, approvalUri, status}`. |
| `GET /api/v1/merchants/me/owner-transfers/{id}` | Merchant | Status + receipt when COMPLETED; settles expiry lazily. |
| `POST /api/v1/merchants/me/owner-transfers/{id}/cancel` | Merchant | PENDING → CANCELLED; COMPLETED stays COMPLETED (returned as such). |
| `GET /api/v1/merchant-transfers/{id}` | Customer | Header `X-Merchant-Handoff`; owner-only; shows shop name, source wallet (masked), destination wallet (masked), currency, exact amount, expiry. |
| `POST /api/v1/merchant-transfers/{id}/approve` | Customer | Body `{handoffToken, pin}`. See 5.4. Returns `{callbackUri}`. |
| `POST /api/v1/merchant-transfers/{id}/deny` | Customer | Body `{handoffToken}` → DENIED; returns callback with `error=access_denied`. |

Register the Customer routes in `SecurityConfig` as Customer-only and make sure
`SessionPurposePolicy` keeps Merchant sessions out of them (and Customer sessions out
of the `/merchants/me/owner-transfers*` routes).

### 5.4 Approve transaction (the critical part)

In one `@Transactional` method, in this order:

1. `locks.apply()`; lock the owner user row; lock the intent row `FOR UPDATE`.
2. Verify handoff token (constant-time hash compare), status `PENDING`, not expired,
   approving customer session belongs to the owner and is a valid, unlocked
   Customer session (reuse `MerchantAuthService.customer(...)` logic — expose it).
3. Verify the PIN with the shared persistent attempt budget. Add
   `AppPinService.verifyForOwnerTransfer(user, sid, pin)` mirroring
   `verifyForMerchantApproval` (same counter, same lockout). Use
   `@Transactional(noRollbackFor = AppPinService.PinRejected.class)` so failed
   attempts persist, exactly like `MerchantAuthService.approve`.
4. Recompute `intent_hash` from the row and compare (detects tampering).
5. Recheck: shop ACTIVE, source still this shop's ACTIVE business wallet, destination
   still the owner's ACTIVE personal wallet, same currency.
6. Post with a **new, explicit posting entry point**, e.g.
   `FinancialPostingService.postOwnerTransfer(owner, source, destination, amount, currency)`:
   - It is the **only** path allowed to debit a MERCHANT account; keep the existing
     `MERCHANT_WALLET_RESTRICTED` guard for every other path.
   - It locks both accounts (same id-ordered locking as `post`), checks balance
     (`InsufficientBalanceException` → intent `FAILED`, `failure_code=INSUFFICIENT_FUNDS`,
     committed, no money moved), refuses different currencies, writes a
     `TRANSFER` transaction with `operation='OWNER_TRANSFER'` and remark
     "Transfer to owner wallet".
   - Idempotency record: reuse `idempotency_records` with namespace `OWNER_TRANSFER`
     and the intent ID as key, so a replayed approve can never post twice.
7. Set intent `COMPLETED`, `transaction_id`, `completed_at`; audit
   `OWNER_TRANSFER_COMPLETED` (no PIN, no tokens in audit text).
8. Return the callback `kesormerchant://transfer/callback?intentId=…&state=…`.

Replays: approving a COMPLETED intent returns the same callback (no second posting);
DENIED/CANCELLED/EXPIRED return `409` with a named code.

Make sure owner transfers **do not** appear in sales/reports (they are not in
`merchant_collections`) and **do** appear in wallet activity as `TRANSFER_OUT`
(source) and in the owner's personal history as an incoming transfer named after
the shop (the `Account.merchantStoreName` formula already does this).

Backend tests — new `MerchantOwnerTransferTests`:

1. Happy path USD and KHR: balances move exactly; one transaction; status COMPLETED.
2. Destination cannot be chosen by the client (extra body fields → 400).
3. No personal wallet in that currency → `OWNER_WALLET_REQUIRED`.
4. Wrong PIN increments the shared counter; 5th locks Customer PIN gates; no money.
5. Wrong/missing handoff token, other customer, Merchant session on Customer route,
   Customer session on Merchant route → rejected, no money.
6. Expired, cancelled and denied intents never post; cancel vs approve race (use
   `race()`) has exactly one outcome.
7. Double approve (concurrent and sequential) posts once.
8. Insufficient funds at approval → FAILED, no money, intent cannot be retried.
9. Suspended shop at approval → rejected.
10. Owner transfer excluded from sales/reports; appears in wallet activity; the
    general `MERCHANT_WALLET_RESTRICTED` guard still blocks all other debits.
11. Audit text contains no PIN, handoff token or full account numbers.

### 5.5 Native transport (both apps)

Extend the M3 transport — do not invent a new one:

- Customer `android/app/src/debug/AndroidManifest.xml`: add an exact
  `kesorbank://merchant/transfer` filter next to `/approve`.
  `MerchantLinkBridge.kt` (Customer) must accept exactly that path with exactly
  `intentId` + `handoffToken`, same certificate/peer checks as approval.
- Merchant: add exact `kesormerchant://transfer/callback` handling in its
  `MerchantLinkBridge.kt` with `intentId` + `state` (or `error=access_denied`).
- Dart: extend `kesor_auth_handoff` with link constants and reuse `exactLink`,
  `secureEquals`. Keep the sign-in flow untouched; add regression tests proving the
  sign-in link and transfer link cannot be confused.
- Custom schemes stay debug-only, like M3. Release App Links remain a user
  dependency (domain + release certificate) — do not claim them.

### 5.6 Customer app

- Route `merchant/transfer` links through the existing approval coordinator in
  `features/merchant/merchant_approval.dart` (through sign-in, onboarding and PIN
  unlock gates, surviving process recreation, never overwriting an active request).
- New screen `merchant_transfer_approval_screen.dart`, built like
  `merchant_approval_screen.dart`: shop name, "From business wallet •••• 1234",
  "To your wallet •••• 5678", **large exact amount**, expiry countdown, *Approve with
  PIN* and *Decline*. PIN input clears on privacy/lifecycle change and never persists.
- On approval-response loss: reload status; never re-approve automatically.

### 5.7 Merchant app

- Wallet detail page: *Transfer to my wallet* button (disabled for non-ACTIVE shops
  or zero balance).
- `OwnerTransferPage`: amount entry (same validation as Collect), shows the server's
  destination (masked) after create; *Continue in Kesor Bank* opens the approval link;
  waiting state with countdown and *Cancel*; result states COMPLETED (receipt),
  DENIED, CANCELLED, EXPIRED, FAILED (insufficient funds).
- `OwnerTransferController`: saves the active intent ID per owner (like
  `CollectController`), resumes after restart, polls status every 2 s while waiting,
  reuses the same idempotency key after an uncertain create, and refreshes
  `ShopController` on completion.

### 5.8 Tests and fixture

Merchant: controller (resume, uncertain create, cancel-vs-complete shows
COMPLETED), link parsing negatives, page states. Customer: link routing through
gates, approval screen rendering EN/KM, PIN cleared on lifecycle, deny path,
response-loss reload. Fixtures: Merchant `owner-transfer-*` screens to
`.local/qa/m8/`; Customer approval screen added to its visual QA.

### 5.9 M8 exit gate

All suites green with new tests; both apps' analysis clean; no change to existing
sign-in protocol tests; `docs/MERCHANT_M8_TRANSFERS.md` written; M0 contract and
progress docs updated.

---

## 6. G — Small gaps

| ID | Gap | Instruction |
| --- | --- | --- |
| G1 | Riel sign ៛ renders tiny in English text | In `shopAmount` consumers, render amounts with a helper widget/`TextSpan` that draws "៛" with `fontFamily: 'Noto Sans Khmer'` (see `CurrencyBadge`). Merchant only; note the Customer App has the same issue and leave it unless the user asks. Check renders. |
| G2 | Legacy `GET /merchants/me/accounts` | **Do not change.** Record in docs that it is Customer-session legacy. Removing it needs a user decision. |
| G3 | QR save/share | Done in M7 (3.5). |
| G4 | EMV tag 59 truncates long/Khmer shop names to 25 bytes | Acceptable (the scan shows the verified name). Document only. |
| G5 | Docs drift | Every milestone updates `MERCHANT_APP_PROGRESS.md`, `NEXT_SESSION_BRIEF.md` (new top section), `CURRENT_PROJECT_HANDOFF.md` (top note) and the plan's milestone table. |

---

## 7. M9 — Integrated acceptance and pilot APKs

**Start by asking the user for permission** to restart the development backend and
build/install APKs. Do nothing in this section without a clear "yes".

### 7.1 Automated

1. Full backend suite, Customer full suite, Merchant full suite, both visual
   fixtures, `flutter analyze` both apps, `git diff --check`. Sequentially.

### 7.2 Runtime (after approval)

1. Inspect what owns port 8080 before stopping anything. Use the existing ignored
   launcher under `backend/digital-banking/.local/` (memory-capped). Restart; confirm
   Flyway applied V19–V21 in the log and that OpenAPI lists the new Merchant paths.
   Never print `.env` values.
2. Confirm the PC's current Wi-Fi IP (the last builds used `172.16.128.192`).

### 7.3 Build (after approval)

```bash
# each app directory, one at a time
flutter build apk --debug --dart-define=APP_ENV=dev --dart-define=APP_MODE=api --dart-define=API_BASE_URL=http://<PC-IP>:8080/api/v1
```

Use `GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1` (worked in
M3). Verify each APK: no `.env` inside, the API origin compiled in, SHA-256
recorded. Copy to the outputs folder used in earlier milestones with names
`KesorMerchant-M9-Pilot.apk` and `KesorBank-M9-Pilot.apk`. Install with
`adb install -r` (keeps data) only on the user's go-ahead. Do not change device
settings (Don't keep activities = on, font scale 1.3).

### 7.4 User acceptance script (the user performs it privately)

Give the user this checklist and record their answers verbatim:

1. Merchant → *Continue with Kesor Bank* → approve in Customer → returns.
2. Register shop (with logo) → Home shows two zero wallets.
3. Collect 1,000 ៛ → pay from Customer USD wallet → Merchant shows *Payment received*.
4. Shop QR → pay $1.00 from Customer → alert appears on Merchant (M8a).
5. Sales shows both; open a receipt; share it; Reports shows today.
6. Transfer to my wallet → approve in Customer with PIN → balances updated.
7. Cancel a waiting QR; let one expire; confirm the Customer cannot pay them.
8. Close and reopen both apps mid-request; the state is recovered.

### 7.5 M9 exit gate

All automated checks green; both APKs installed; user confirms the script; a
`docs/MERCHANT_M9_PILOT.md` report separates automated evidence from personal
device acceptance and lists remaining production dependencies (release domain and
certificate, M10–M13).

---

## 8. Out of scope (do not start)

M10 push/voice, M11 cashiers/refunds/export, M12 branches/payment links/AI, M13
KHQR/Bakong, iOS acceptance, production deployment. If the user asks for any of
these, plan them separately.

---

## 9. Reporting template (use at every checkpoint)

```
Milestone / step:
Built:
Tests: backend X/X, Customer Y, Merchant Z, fixture N renders, analysis clean?
Not done / not verified:
Decisions I made (with reason):
Committed? (no unless asked)
Next step:
```
