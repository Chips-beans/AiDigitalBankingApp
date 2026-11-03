# Merchant M5 + M6 — dashboard, wallets and QR collection

3 November 2026, Asia/Phnom_Penh. Implements M5 and M6 of
[MERCHANT_APP_IMPLEMENTATION_PLAN.md](MERCHANT_APP_IMPLEMENTATION_PLAN.md) on top
of [M4](MERCHANT_M4_SHOP.md). Contracts follow
[MERCHANT_M0_CONTRACTS.md](MERCHANT_M0_CONTRACTS.md) section 7 with the route
change noted below.

## Status

- Source complete with automated verification (see Evidence). V19 and V20 are
  **not** applied to the development database, no APK is built or installed and
  no device payment has been made. A real end-to-end payment needs: backend
  restart (applies V19+V20), new Merchant and Customer APKs, and a customer paying
  a shop QR with their own PIN.

## What a shop can do now

- **Home:** shop card, today's collections per currency (Asia/Phnom_Penh day),
  both wallet balances (kept separate from collections), the latest payments.
- **Wallet details:** balance, copyable account number, read-only activity
  (QR payments with payer, transfers, deposits), 20 per page.
- **Collect → Enter amount:** KHR or USD amount + optional order note → a
  fixed-amount QR valid 5 minutes and payable once. The screen polls every 2 s,
  counts down on the server's clock, and shows **Payment received** with payer
  first name, masked account, converted amount, reference and time — only after
  the server reports PAID. Cancel is safe: if a payment won the race, the answer
  is PAID and the payment is shown.
- **Collect → Shop QR:** the reusable QR per currency; customers type the amount.
- **Sales:** today's totals and the latest 10 confirmed payments. Full history,
  filters and reports are M7.
- Suspended/pending shops keep read access but cannot create QR codes.

## Customer side

- Scanning a Merchant QR returns `merchant {merchantId, storeName, categoryCode,
  hasLogo, verified}` and, for fixed requests, `expiresAt`. The payee name is the
  **shop name**; the owner's personal name is never shown.
- The transfer screen shows the shop with a *Verified Kesor shop* badge and its
  logo (`GET /payments/merchants/{merchantId}/logo`, JSON like recipient photos),
  instead of a person lookup. PIN, idempotency and conversion are unchanged.
- Expired, cancelled or already-paid requests and inactive shops are refused at
  scan and at payment (`PAYMENT_REQUEST_EXPIRED`, `PAYMENT_REQUEST_CANCELLED`,
  `PAYMENT_ALREADY_COMPLETED`, `MERCHANT_INACTIVE`).
- Receipts and history show the shop name for business wallets (read-only Hibernate
  formula on `Account`).

## Backend

Migration `V20__merchant_collections_and_payment_requests.sql` (additive):

- `merchant_payment_requests`: one registered DYNAMIC `payments` row per request;
  WAITING/PAID/EXPIRED/CANCELLED; per-owner idempotency key; expiry; paid
  transaction. Checks tie PAID to a transaction and terminal states to a time.
- `merchant_collections`: one snapshot per confirmed QR credit to a business
  wallet — received amount/currency, paid amount/currency/rate, reference,
  request, shop name, payer first name, masked payer account. Profile edits never
  rewrite it. The `transactions` table stays the ledger.

Merchant-session routes (`SessionPurposePolicy.SHOP_ROUTES`):

| Route | Behaviour |
| --- | --- |
| `GET /merchants/me/dashboard` | profile + `today[{currency,count,gross}]` (KHR, USD) + `recent[10]` + `businessDate`, `serverTime` |
| `GET /merchants/me/wallets/{accountNumber}?page=` | own business wallet + activity (20/page); anything else 404 |
| `GET /merchants/me/qr?currency=` | stable reusable QR for the shop's wallet; payee = shop name |
| `POST /merchants/me/payment-requests` | `Idempotency-Key`; `{currency, amount, orderReference?}`; 201 / 200 replay / 409 `IDEMPOTENCY_CONFLICT` |
| `GET /merchants/me/payment-requests/{id}` | status + `serverTime`/`expiresAt`; QR only while WAITING; `receipt` when PAID |
| `POST /merchants/me/payment-requests/{id}/cancel` | WAITING → CANCELLED (or EXPIRED if past expiry); PAID stays PAID |

**Route change from the M0 contract:** M5 wallets are `/merchants/me/wallets/…`
because the legacy `GET /merchants/me/accounts` still serves Customer sessions.

Concurrency: the Customer payment locks the registered payment row, then the
request row, then the accounts; cancellation and expiry lock the payment row
first too. Exactly one of *paid* or *cancelled* wins — tested with real races.
A scheduled sweep expires stale WAITING requests; reads also settle expiry lazily.
TTL: `app.merchant.payment-request-ttl-seconds` (default 300, bounded 60–1800).

Other guards added:

- `FinancialPostingService` refuses debits from business wallets
  (`MERCHANT_WALLET_RESTRICTED`) until M8 owner transfers exist.
- `/accounts/lookup` no longer resolves business wallets (no owner name/photo).
- `/payments/qr/generate` refuses business wallets
  (`MERCHANT_QR_IN_MERCHANT_APP`), so no personal-name QR can point at a shop.

Collections definition (M7 reports build on this): confirmed QR credits to a
shop's business wallets in the receiving currency. Manual transfers into a
business wallet appear as wallet activity but are not collections. USD and KHR
are never summed; collections are not profit.

## Merchant app

- `features/collect/`: `merchant_collect.dart` (models, gateway),
  `collect_controller.dart`, `collect_view.dart` (amount entry, live request,
  shop QR, Customer-style dark QR card), `wallet_page.dart`.
- `MerchantShopGateway` now includes the collection API; `MerchantShopApi`
  implements both. `ShopController.refresh()` loads the dashboard.
- The active request ID is saved per owner (`collect-<ownerId>`), so a restarted
  app resumes watching it. A lost create response reuses the same key; a
  definite rejection or a different amount gets a new key.
- `qr_flutter ^4.1.0` added (same as the Customer App).

## Evidence

- Backend full suite: `backend/digital-banking/.local/merchant-m6-full-backend.log`.
  New `MerchantCollectionTests` (8, including the customer shop-logo preview): cross-currency fixed request (KHR request
  paid from USD: 2.50 USD → 10,000 KHR), single payment, dashboard/wallet/history,
  cancel and expiry (scan + pay), pay-vs-cancel races (3 rounds), idempotent and
  validated creation, reusable QR, shop isolation and suspension, business-wallet
  privacy and debit guard, scheduled expiry.
- Merchant Flutter: controller, API, and screen tests in
  `test/merchant_collect_test.dart` (11) plus existing suites.
- Customer Flutter: `test/merchant_payee_test.dart` (3); full suite 251 passing.
- Backend full suite: 211 passing.
- Merchant Flutter: 53 passing; visual fixture 146 renders.
- Visual fixture: `frontend/merchant_app/.local/qa/m6` (adds request waiting/
  paid/cancelled, shop QR, wallet detail, populated Home/Sales).
