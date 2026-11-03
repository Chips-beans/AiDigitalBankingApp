# Merchant M7 — sales history, receipts, reports and sharing

3 November 2026, Asia/Phnom_Penh. Implements section 3 of
[MERCHANT_REMAINING_WORK_PLAN.md](MERCHANT_REMAINING_WORK_PLAN.md) on top of
[M5/M6](MERCHANT_M5_M6_COLLECTION.md). M8 and M9 are not part of this run.

## Status

Source and F1–F6 follow-up verification complete: backend **220/220**, Merchant
**73/73**, Merchant analysis clean, **220** visual renders without overflow.
Customer source is unchanged; its original M7 **251/251** and clean analysis are
prior evidence, not rerun in this follow-up.
No APK was built,
no development backend was restarted, and no development database was accessed.
No migration is added: the existing V20 collection index covers keyset ordering.
This implementation and F1–F6 follow-up are included in the user-authorized M7
commit on `merchant-m4-shop-registration`, with Codex credited in
`../CONTRIBUTORS.md` and the co-author trailer. No push or merge is included.
Earlier uncommitted statements below describe the verification checkpoints.

## F1–F6 follow-up — 3 November 2026

- **F1:** audited receipt, Sales and wallet time displays and shared text. They
  already use `shortTime` → `businessTime` (UTC instant plus seven hours). Added
  the exact `2026-11-02T17:30:00Z` → `03/11/2026 00:30` regression, plus an
  equivalent offset instant; no device-local time conversion is used.
- **F2:** receipt cards and share text use one exact-string rate formatter:
  `1 USD = 4,000 ៛` / `1 ដុល្លារ = 4,000 ៛`. The server stores KHR per USD in both
  payment directions. Group digits and trim fractional trailing zeros only;
  never derive, invert or invent a rate. Missing rates and unconverted payments
  omit the line. Fractional precision is preserved.
- **F3:** one `paymentCount` helper supplies English singular/plural and the
  Khmer count form to Home/filtered totals, loaded-day headings and report totals/
  rows. The day count still says “shown” so partial pages remain explicit.
- **F4:** request-history expiry work is capped at 50 rows **in total per call**.
  Filters use effective status: due WAITING rows are excluded from WAITING and
  included in EXPIRED before persistence. Reserve the budget for due rows on the
  returned page, fill it from an oldest-first `ORDER BY r.payment_id LIMIT 50`
  query, then lock/settle the union by ascending payment ID. This prevents page
  settling from exceeding the cap or returning expired rows as WAITING. The
  scheduled sweep handles the backlog. Added a bulk-SQL 160-request regression
  for the cap, unfiltered history and complete EXPIRED keyset pagination.
- **F5:** kept REPEATABLE_READ and owner/session locking. Added a localized
  CONCURRENT_UPDATE notice. Sales retries refresh from page one even when a later
  page hit contention; Reports uses its refresh action. Both have retry tests.
- **F6:** Sales heading now uses `mText(context,20,28,weight:FontWeight.w600)`;
  all four controller methods have concrete ApiResponse response types,
  endpoint Operation summaries and the Merchant sales and reports Tag.

Follow-up checks ran sequentially, without a development runtime/database or APK:

| Check | Result | Log |
| --- | --- | --- |
| Focused MerchantSalesTests | 9 passed, zero failures/errors/skips | `backend/digital-banking/.local/merchant-m7-fixes-focused.log` |
| Full `./mvnw.cmd -o test` | 220 passed (219 baseline + 1 F4), zero failures/errors/skips | `backend/digital-banking/.local/merchant-m7-fixes-backend.log` |
| Merchant `flutter analyze` | No issues | `frontend/merchant_app/.local/merchant-m7-fixes-analyze.log` |
| Merchant `flutter test test --concurrency=1` | 73 passed (66 baseline + 7 follow-up tests) | `frontend/merchant_app/.local/merchant-m7-fixes-tests.log` |
| Merchant visual fixture | 1 passed, 220 PNGs, no overflow | `frontend/merchant_app/.local/merchant-m7-fixes-visuals.log` |
| `git diff --check` | Passed | `backend/digital-banking/.local/merchant-m7-fixes-diff-check.log` |

Opened and visually inspected the updated `receipt-phone-light-bottom.png`,
`receipt-tablet-km-dark.png`, `sales-phone-light.png`,
`reports-day-phone-light.png` and `home-phone-light.png` in `.local/qa/m7/`.
Human rates, localized text, singular counts and title hierarchy were checked.
`git diff --stat -- frontend/customer_app` is empty. No Customer suite rerun was
required by this follow-up; no existing test/assertion or money value was changed.

## Known limits

Rare concurrent owner updates under REPEATABLE_READ may return `409 CONCURRENT_UPDATE`; Sales and Reports offer **Try again** to refresh safely without changing isolation.

## What a shop can do now

- **Sales:** Today, Yesterday, 7 days, This month or a custom inclusive date range;
  All/KHR/USD; reference/request/order-note search (400 ms debounce). The summary
  covers the whole server filter. Rows group by Phnom Penh business day; each day
  labels its loaded count and per-currency sums as **shown**, so a partial page
  cannot masquerade as a full-day total. Scroll loads another page; Load more and
  pull-to-refresh are also available.
- **Receipt:** open from Sales, Home, QR wallet activity or a paid request. The
  card uses payment-time shop/payer snapshots, exact received and paid amounts,
  order/request references, full transaction reference, rate and UTC+07 time.
  Copy reference, save PNG to gallery, or share PNG plus text.
- **Reports:** Daily/Monthly, one currency at a time, default last seven days or
  last six calendar months through today, custom range, zero-filled bars and
  count/gross table. Collections are explicitly labelled as received payments,
  not profit.
- **Requests:** separate history of WAITING/PAID/EXPIRED/CANCELLED requests, status
  filter, keyset paging and refresh. Waiting requests revalidate server status and
  open in Collect; paid requests open the confirmed receipt. Unpaid requests
  never become sales.
- **Shop QR:** save/share only the QR card. The share sheet is user initiated.

Every new screen/control/message has English and Khmer and uses the existing
Merchant/Customer design-system widgets. Money remains decimal text/BigInt;
floating point is used only for bar heights after exact integer scaling.

## Backend

`MerchantSalesService`, `MerchantSalesController`; shared collection mapper/SQL
and request expiry helpers are package-visible in `MerchantCollectionService`.
`SessionPurposePolicy.SHOP_ROUTES` includes every new path; the legacy
`GET /merchants/me/accounts` remains Customer-session only.

All routes below are under `/api/v1/merchants/me`, Merchant-session only, derive
the owned shop after `sessions.merchant`, and return the normal no-store envelope.
Suspended shops retain read access. No caller-supplied ownership is accepted.

| Route | Contract |
| --- | --- |
| `GET /sales` | `from`, `to`: ISO dates, inclusive, default today, at most 366 days. Optional currency KHR/USD, literal case-insensitive `q` (1–50 chars): transaction suffix, request reference, or order-note substring. `size` 1–50 (default 20), opaque cursor. `{items,nextCursor,totals}`; both currency totals cover the whole filter. |
| `GET /sales/{reference}` | Owned snapshot receipt including storeName, walletAccountNumber, exchangeRate, requestReference, orderReference and paidAt. Foreign/missing reference is generic 404. |
| `GET /reports/collections` | DAY (at most 92 days) or MONTH (at most 24 touched calendar months), inclusive ISO date bounds. Every bucket and both currencies, including zero buckets, plus separate grand totals. |
| `GET /payment-requests` | Optional status, cursor, size. Uses effective expiry status and settles at most 50 due rows under the existing payment-row lock before mapping. List items contain no QR string. |

Sales order is `(created_at DESC, transaction_id DESC)`. Cursor is canonical
base64url `<epochMicros>:<transactionId>`. Request history has no transaction ID
until paid, so its independent cursor uses `<epochMicros>:<request UUID>` and
`(created_at DESC,id DESC)`. Invalid cursors, status/currency/query/ranges return
400. No OFFSET paging is introduced. Date bounds become business-zone midnight
and the following exclusive midnight. SQL groups reports with `date_trunc` in
Asia/Phnom_Penh, then Java fills every date/month and currency.

List/report queries use REPEATABLE_READ so page/buckets and grand totals share a
snapshot if another customer confirms a payment between queries. Later pages are
new snapshots under the original keyset boundary; newly arriving newer payments
appear on refresh. Rate lanes: `sales-list` 120/min, `sales-report` 60/min.

The sole sales/report source remains `merchant_collections`: confirmed QR credits
in the receiving currency. Deposits, manual transfers and unpaid requests are
excluded. No ledger posting code, debit guard, original migration or money
expectation is changed.

## Merchant app and Android

- New `features/sales/`: `sales_controller.dart`, `sales_view.dart`,
  `receipt_page.dart`, `reports_page.dart`, `requests_page.dart`.
- Models/gateway methods in `features/collect/merchant_collect.dart`, HTTP in
  `features/shop/merchant_shop_api.dart`; defensive parsing rejects malformed
  enums/money/time and unmasked payer accounts. SalesController belongs to one
  owner, clears on disposal, deduplicates overlapping pages and ignores stale
  success/error/finally paths after filter changes. Reports/requests have the same
  generation protection. Search timers and scroll controllers are disposed.
- `app/merchant_app.dart` owns SalesController alongside shop/collect; pushed
  screens use the existing session navigation/privacy cover. Home and wallet QR
  rows now open receipts. Collect can reopen a request without an old poll
  overwriting it.
- `core/platform/image_share.dart` ports the Customer bridge, with channel
  `kesor/merchant_share`, card-only RepaintBoundary capture, explicit action/busy
  state and localized unavailable/Android-before-10 errors. Receipt text includes
  no token, internal ID or full account; wallet display in the PNG is masked too.
- Merchant `ShareBridge.kt`, retained-engine registration, activity attach/detach,
  non-exported FileProvider, and cache-only `res/xml/share_paths.xml`. Gallery is
  `Pictures/Kesor Merchant`; PNG plus localized chooser title/text use ACTION_SEND.
  No sharing plugin or storage permission is added. Android 10+ is required only
  for gallery saving; older Android can still share.

## Original M7 evidence (before F1–F6)

All heavy checks ran sequentially, with embedded PostgreSQL only:

| Check | Result | Log |
| --- | --- | --- |
| `./mvnw.cmd -o test` | 219 tests, zero failures/errors/skips (211 baseline + 8 M7), final run includes REPEATABLE_READ | `backend/digital-banking/.local/merchant-m7-full-backend.log` |
| Merchant `flutter analyze` | No issues | `frontend/merchant_app/.local/merchant-m7-analyze.log` |
| Merchant `flutter test test --concurrency=1` | 66 passed (53 baseline + 13 M7) | `frontend/merchant_app/.local/merchant-m7-tests.log` |
| Customer `flutter analyze` | No issues | `frontend/customer_app/.local/merchant-m7-analyze.log` |
| Customer `flutter test test --concurrency=1` | 251 passed, source unchanged | `frontend/customer_app/.local/merchant-m7-tests.log` |
| Merchant `flutter test tool/merchant_visual_qa.dart --concurrency=1` | 1 passed, 220 PNGs, no overflow | `frontend/merchant_app/.local/merchant-m7-visuals.log` |
| `git diff --check` | Passed | `backend/digital-banking/.local/merchant-m7-diff-check.log` |

`MerchantSalesTests` contains all eight required backend cases: >2 keyset pages
with equal timestamps and a new arriving payment; currency/date/note/request/
reference-suffix filters; whole-filter totals; Phnom Penh midnight; DAY/MONTH
zero-fill and reconciliation; excluded deposit/manual-transfer/unpaid requests;
foreign references/purpose isolation/invalid inputs; immutable shop snapshot and
exact USD-to-KHR receipt. It also checks restricted read access, no-store and
request history expiry/filtering/paging without QR strings. Focused eight-test log:
`backend/digital-banking/.local/merchant-m7-focused.log` (before the final isolation
review; the full log above verifies final source).

`test/merchant_sales_test.dart` adds thirteen checks: overlap deduplication, stale
filter success/error/disposal, strict snapshot receipt parsing, exact large sums
and business dates, HTTP filters/auth, zero-filled daily/monthly rendering,
snapshot/privacy receipt UI/text, EN/KM unavailable/Android<10 share messages,
real PNG capture, offline unknown-total rendering and Sales/receipt/request navigation. Reopening history also
tests that neither success nor failure from an older request poll can replace
the current request. Error-message tests mock the native bridge and capture
dependency; a separate real render captures a PNG and checks its signature.

Fixture output: `frontend/merchant_app/.local/qa/m7/`. Includes populated/empty
Sales, receipt, daily/monthly reports and requests in all six original size/text/
language variants and both themes. Phone lower-page captures include QR/receipt
sharing actions and report tables. Seven renders were opened and visually
inspected: `sales-phone-light`, `receipt-phone-dark-bottom`,
`reports-day-phone-light`, `reports-month-large-km-dark`,
`requests-large-km-dark`, `sales-empty-large-km-dark`, and
`collect-shop-qr-phone-light-bottom` (all `.png`). Khmer 2x text and dark mode
remain scrollable; actions, tables, snapshot identity and masking were checked.

Initial backend fixture setup had an invalid same-currency conversion-field combination
and a Windows text-encoding error; both were fixed without changing expected
money/assertions. Share-test fake-clock handling and visual-fixture navigation
were corrected (scroll to ReceiptRow by type, then pump before tapping). No
existing assertion or test was removed or weakened.

## Not done / not verified

- M8 alerts/owner transfers/settings and M9 runtime/APK/device acceptance are not
  started. Business-wallet debits stay blocked.
- V19/V20 remain unapplied to development by this task. No real payment or private
  credential was requested, entered or logged. Native Android compilation and
  device acceptance were not run; no APK was built.
- Native gallery destination, Android chooser/receiving app behavior and physical
  Android <10 errors require later device verification. Flutter bridge mocks and
  visual PNGs do not establish those device results.
- Release verified App Links still need the user's domain/release certificate.
  Existing EMV tag 59 truncation to 25 bytes is unchanged; scans show the verified
  full shop name. Customer riel glyph and other gap work remain out of scope.

## Decisions

1. Reuse V20 snapshots/index; no speculative migration or parallel sales ledger.
2. Request cursors use UUID tiebreakers because unpaid requests lack transaction
   IDs. Effective expiry filters and bounded page-first settling keep
   EXPIRED/WAITING lists honest without unbounded writes.
3. Monthly date bounds are inclusive dates, consistent with Sales; first/last
   buckets can be partial months and the selected range stays visible. Limit 24
   touched calendar months. Omitted backend report bounds default to today; app
   requests send their explicit seven-day/six-month defaults.
4. Day headings explicitly say “shown” for loaded items; the main summary remains
   the authoritative whole-filter total. KHR and USD are never added.
5. Receipt PNG uses a masked receiving wallet; share text omits wallet numbers.
   PNG and text are shared together through the copied native bridge. This keeps
   sharing useful without exposing account identifiers or session state.
6. Repeatable-read list/report transactions prevent contradictory totals inside
   a response during concurrent collection, without locking financial accounts.
7. Follow section 3 only; do not apply unrelated G/M8 changes or build APKs.
8. Sales uses the requested segmented currency selector at normal sizes, with
   wrapped choices on narrow screens/large text so Khmer labels remain readable.
9. History opening revalidates request status; an in-flight create/cancel must
   finish first, and stale polls cannot replace or mark the newly opened request
   offline. This preserves authoritative request outcomes.
10. Receipt parsing requires the payment-time shop identity/receiving wallet and
    rejects unmasked payer accounts, malformed money/enums/time or missing fields
    as INVALID_RESPONSE rather than inventing private or financial details.
11. Loading/failed initial Sales reads display unknown amounts and a generic
    payment label, not zero totals. A real successful empty filter still shows
    zero. This avoids reporting invented financial results while offline.
12. Search treats SQL wildcard characters as literal text. Omitted backend report
    period defaults to DAY, with today as the bounded default range; the app sends
    its explicit dates. These are conservative choices for unspecified inputs.
