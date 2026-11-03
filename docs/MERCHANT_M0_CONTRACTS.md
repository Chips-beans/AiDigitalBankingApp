# Merchant M0 — audit, decisions and implementation contracts

31 October 2026, Asia/Phnom_Penh. This is the implementation baseline for the
[milestone plan](MERCHANT_APP_IMPLEMENTATION_PLAN.md). Routes/data below are
contracts to implement, not a claim that those endpoints already exist.

M2 update: backend approval/session routes in section 5 are now implemented; read
[MERCHANT_M2_SECURITY.md](MERCHANT_M2_SECURITY.md) for exact fields, routes,
recovery/rotation rules and the M3 integration boundary. Verification and live
activation state are tracked in [MERCHANT_APP_PROGRESS.md](MERCHANT_APP_PROGRESS.md).
The audit snapshots below remain historical evidence.

M4 update: section 6 routes are implemented; see [MERCHANT_M4_SHOP.md](MERCHANT_M4_SHOP.md).
Decision: the legacy `GET /merchants/me/accounts` keeps Customer-session behaviour
until M5 replaces it with the Merchant-session `/merchants/me/accounts` contract.

## 1. Evidence and preservation

Checkout: `kesor-phase4-fixes`, HEAD `e1a9da2`. Preserve uncommitted scanner and
planning work. Current source migrations end at V17. The live read-only audit
also reports V17. Development backend listens on 8080 (PID 18612); Samsung
R9TXB0G1VKT is connected with reverse 8080. Do not replace that runtime for M0/M1.

Read-only development database aggregates, 31 October 2026:

| Measure | Result |
| --- | --- |
| Shops / owners with multiple shops | 0 / 0 |
| Merchant accounts / duplicate merchant-currency groups | 0 / 0 |
| Merchant accounts missing shop / shops missing currency pair | 0 / 0 |
| Internal QR records linked to merchant accounts | 0 |
| Personal wallet duplicate user-currency groups | 3; unchanged |

Evidence: ignored `backend/digital-banking/.local/merchant-m0-db-audit.json`.
The query used a READ ONLY transaction and selected no customer identities,
credentials, account numbers or balances. Tests use embedded PostgreSQL/random
ports and local SMTP as enforced by `PostgresIntegrationTest`; no live DB test.
Final baseline results are recorded in `MERCHANT_APP_PROGRESS.md`.

## 2. Adopted first-release decisions

These resolve the plan's proposed defaults within the authorized internal pilot.

1. One owner, one shop, same-device Android approval. No separate Merchant identity,
   password, email/Telegram sign-in, or Merchant PIN enrollment.
2. Customer approval requires an enabled, fully onboarded customer and the existing
   PIN/five-attempt budget. Sign-in approval and money-movement approval are
   different purposes; neither proof can authorize the other.
3. Existing Customer sessions retain their current behavior. Merchant gets a
   separate audience/purpose and secure storage. Merchant sign-out revokes Merchant
   only; user-wide PIN reset/security revocation also invalidates Merchant access.
4. New internal demo onboarding completes into ACTIVE shop status. Existing legacy
   register/status APIs retain their current PENDING/admin behavior. Gate the new
   self-service activation policy to local/dev/test; do not silently enable it in
   production. This is not production business verification.
5. Create exactly one KHR and one USD MERCHANT wallet atomically with the shop,
   at zero opening balance even when customer development funding is enabled.
6. Shop name/logo are the business identity; no personal-profile overwrite. Allow
   a shop-initial fallback so missing/failed logo selection cannot lose registration.
7. Internal QR payments only, separate currency totals; preserve current customer
   conversion behavior. Same-currency owner transfers only in the first release.
8. Foreground payment status polling for v1. Push/voice, staff, refunds, branches,
   external settlement and read-only AI remain later milestones.
9. No real payments, PIN entry, migration application, runtime replacement, commit,
   push or merge merely to perform this audit/scaffold work.

## 3. Identity, links and configuration

| Item | Contract |
| --- | --- |
| Customer Android package | Existing `com.bank.customer_app` |
| Merchant Android package | `com.bank.merchant_app` |
| Registered Merchant client ID | `kesor-merchant-android` |
| Merchant vault namespace | `kesor.merchant.v1`, isolated by API origin and installation |
| Development approval URI | `kesorbank://merchant/approve` |
| Development return URI | `kesormerchant://auth/callback` |
| Development transport | Explicit package-targeted intents; exact scheme/host/path; verify expected installed signing certificate before sending private handoff data |
| Current customer debug certificate SHA-256 | `ae861749ac17ba744e16064146dc0320e27bdde8b5f61b55939c90baf1cbc2b4` (public certificate fingerprint) |
| Release links | Verified HTTPS App Links on a user-controlled domain, exact per-app paths and assetlinks package/certificate associations |

No user-controlled release domain or release certificate was supplied/discovered.
Telegram's `app937652339-login.tg.dev` belongs to the provider flow and must not
be repurposed. This is an explicit M3 verified-release-link dependency, not a
blocker to the app shell/backend protocol or package-targeted development flow.
Do not publish an invented domain or claim App Links are verified before testing.
Keep dev custom schemes out of production's callback allowlist.

Configure API origin, registered callbacks, activation policy and certificate
allowlists separately per environment. A public mobile client has no embedded
client secret. Development HTTP is explicit; production API/links require HTTPS.
Installed-package metadata is not proof of customer approval; backend validation
and PKCE remain mandatory.

## 4. Session access matrix — M2/M3

| Capability | Customer session | Merchant session before shop | Merchant session with shop |
| --- | --- | --- | --- |
| Personal accounts/history/AI/profile/PIN APIs | Existing customer rules | Deny | Deny |
| View/approve/deny Merchant sign-in | Customer + fresh PIN for approval | Deny | Deny |
| Register/recover own shop | Deny through new Merchant-only path | Allow | Return existing or conflict; never another shop |
| Read own shop/profile/status | Through existing rules only | Minimal onboarding status | Allow |
| Read business balances/sales/report/receipts | No blanket new access | Deny | Own shop only |
| Generate request/static QR | Existing customer wallet rules | Deny | Own ACTIVE shop/account only |
| Pay a QR | Existing customer transfer/PIN rules | Deny | Deny in v1 |
| Owner transfer | Fresh purpose-bound Customer approval only | Deny | Exact approved intent only |
| Refresh/logout | Own session only | Own Merchant session only | Own Merchant session only |
| Revoke Merchant session | Own customer identity | Own session only | Own session only |
| Admin approval/audit/operations | Existing roles/rules | Deny | Deny |

Enforce purpose in both token/session authentication and API/service guards. Do
not simply add ROLE_MERCHANT to personal routes. A user with both roles still
cannot use a Merchant token as a Customer token. Shop suspension gates collection
and financial writes, while a restricted owner view remains available for support.

## 5. Approval protocol — backend M2, both apps M3

Use existing API envelopes and no-store responses. Money is decimal text; dates
are ISO-8601 with offset. Private attempt credentials are sent in request bodies,
never query parameters, logs or analytics.

### Start, approval, exchange and recovery

1. Merchant generates 32-byte random PKCE verifier, state, private attempt secret
   and a stable per-attempt exchange key; persists them in its own secure vault.
2. `POST /api/v1/merchant-auth/attempts` accepts registered client ID, exact
   redirect URI, state, S256 challenge, hash of attempt secret, installation ID
   and device display name. Server enforces sizes/allowlist/rate limit and returns
   attempt ID, server expiry and Customer approval link. Client names shown in
   approval come from server registration, not untrusted request text.
3. Customer opens the exact attempt, authenticates if needed, then
   `GET /api/v1/merchant-auth/attempts/{id}` returns minimal approval details under
   Customer authentication. Require the opaque handoff token supplied by start
   for this view; the UUID alone is not a credential. New requests cannot silently
   overwrite an already visible pending approval.
4. `POST .../{id}/approve` takes handoff token + PIN. The service uses the shared
   persistent PIN counter, locks the attempt and binds the approving customer.
   A transfer PIN proof must not be accepted as a sign-in approval proof.
5. The server returns the exact registered callback containing one-use code and
   original state. Denial returns an allowlisted cancellation callback with state,
   no authorization code. Customer opens it with the registered Merchant package.
6. Merchant checks pending attempt, exact URI, unique allowed query parameters,
   no fragments and constant-time matching state, then
   `POST /api/v1/merchant-auth/exchange` with code, verifier, attempt secret and
   exchange key. The backend consumes approval and creates one Merchant session.
7. An exchange replay with the same immutable exchange key/credentials may recover
   that same session only during a short recovery window. Use a short-lived
   encrypted response receipt or equivalent server-side safe recovery; do not
   store plaintext refresh tokens or create a second session. Different keys,
   credentials, consumed attempts outside recovery, or cancelled/revoked attempts fail.
8. Merchant reads onboarding state with its own token, then routes to Register
   Shop/Home/restricted status. Tokens are not placed in callbacks.

Attempt states: PENDING → APPROVED → CONSUMED. DENIED/CANCELLED/EXPIRED are
terminal. Approval attempts expire after two minutes; issued codes expire within
that bounded attempt. Recovery receipt lifetime is independently bounded and
cannot resurrect a revoked session. Cancellation must also revoke any session
created in a cancellation-vs-exchange race for that attempt.

`POST .../{id}/status` and `POST .../{id}/cancel` require the private attempt
secret. Status returns only state/expiry, never code or token. No automatic
approval or automatic resend of an uncertain exchange. Refresh uses rotating
Merchant refresh credentials; reuse revokes the affected Merchant session.

Named errors: `MERCHANT_AUTH_EXPIRED`, `MERCHANT_AUTH_DENIED`,
`MERCHANT_AUTH_CANCELLED`, `MERCHANT_AUTH_INVALID`, `MERCHANT_AUTH_USED`,
`MERCHANT_SESSION_REQUIRED`, `MERCHANT_AUTH_RATE_LIMITED`, plus existing PIN and
session errors. Authentication rejection exposes no foreign identity details.

## 6. Shop and logo contracts — M4

New `POST /api/v1/merchants/me/registration`, Merchant onboarding session only,
requires `Idempotency-Key`. Body: storeName (1-150), categoryCode (server allowlist),
phone (normalized valid international form), city (1-100), address (1-255), optional
description (0-500), optional owned stagedLogoId. Reject ownerUserId, merchantId,
status, arbitrary QR aliases and openingBalance as client-controlled fields.

Return 201 on creation, 200 on same-key replay, 409
`MERCHANT_REGISTRATION_CONFLICT` for a changed body/key conflict. Lock owner,
claim request, create shop + both wallets, attach valid logo and save response
receipt in one database transaction. Server-generated merchant code/QR alias
is stable. Database and request journal, not a disabled button, prevent duplicates.

`GET /api/v1/merchants/me` returns `onboardingState` (SHOP_REQUIRED, READY,
RESTRICTED, RECOVERY_REQUIRED), minimal owner identity, shop if any and dedicated
wallets. Existing multi-shop owners are not silently collapsed or reassigned;
return recovery/support state until a later explicit migration policy is adopted.

`PATCH /api/v1/merchants/me/profile` edits allowed shop fields with a version
precondition to prevent lost updates. `POST /api/v1/merchants/me/logo-uploads`
accepts JPG/PNG up to 5 MB/16 million pixels, decodes/normalizes to a bounded
server image, strips metadata and returns an owned staged ID. No arbitrary URL
fetching. Attach through registration/profile update; delete abandoned staged
objects after retention. Shop logo serves only through an authorized or deliberately
minimal public payment-preview route; do not expose owner personal photos.

Wallet response: accountNumber, category=MERCHANT, merchantId, currency KHR/USD,
status, balance decimal string. No initial credit. Errors include
`MERCHANT_ALREADY_REGISTERED`, `MERCHANT_REGISTRATION_PENDING`,
`MERCHANT_LOGO_INVALID`, `MERCHANT_LOGO_TOO_LARGE`, `MERCHANT_PROFILE_CONFLICT`,
`MERCHANT_INACTIVE`; foreign resources return unavailable without identity leaks.

## 7. Read/collection/finance contracts and milestone ownership

All proposed routes below are under `/api/v1/merchants/me` and derive shop/owner
from the Merchant session, not a caller-supplied owner ID.

| Milestone | Capability | Contract |
| --- | --- | --- |
| M5 backend + Merchant UI | `GET /dashboard`, `/accounts`, `/accounts/{number}` | Shop identity, separately typed KHR/USD balances and recent confirmed collections; owned category/status checked |
| M6 backend + Merchant UI | `POST /payment-requests` | Idempotency-Key; receiving currency, positive amount string, optional orderReference (max 50); server unique reference/expiry; immutable request |
| M6 backend + Merchant UI | `GET /payment-requests/{id}` | WAITING/PAID/EXPIRED/CANCELLED plus server time/expiry; paid returns confirmed receipt reference |
| M6 backend + Merchant UI | `POST /payment-requests/{id}/cancel` | Atomic with financial claim; already PAID returns authoritative paid state, never hides money |
| M6 backend + Merchant UI | `GET /qr?currency=KHR|USD` | Registered reusable QR for the owned wallet; Save/Share locally; no order-matching claim |
| M6 backend + Customer UI | Existing `/payments/qr/scan`, `/payments/qr/transfer` | Add verified merchant name/logo + shop status without breaking customer fields/precision/PIN/idempotency |
| M7 backend + Merchant UI | `GET /sales`, `/sales/{reference}` | Bounded stable pagination; date/currency/status/reference filters; own-shop confirmed receipts only |
| M7 backend + Merchant UI | `GET /reports/collections` | Daily/monthly date range, per-currency gross collections/count; optional later refund/net fields |
| M8 backend + both apps | Owner transfer intents/approve/submit/status | Idempotent immutable source/destination/currency/amount; Customer approval bound to intent hash; exact same-owner same-currency wallets only |
| M8 Merchant UI | Settings/support | Shop edit, EN/KM, system/light/dark, honest foreground alert controls, sign-out and support |
| M3 backend + Customer UI | `GET /auth/merchant-sessions`, `POST .../{id}/revoke` | Customer can inspect/revoke only their own Merchant sessions; no refresh secrets returned |

Every write rechecks owner, session and shop/account status inside the financial
transaction. Financial posting uses the existing journal/ledger; role checks
must be explicitly adapted for owner transfers, not bypassed.

Payment credit is denominated in the QR's receiving currency; preserve current
USD↔KHR customer quote/rounding. Persist both sides and rate where applicable.
Unknown communication outcome is not a failed payment; reconcile by reference.

Report definition: sum successful merchant QR transaction credits, by receiving
currency and Asia/Phnom_Penh timestamp boundaries. Exclude DEPOSIT/test opening
credit, owner transfers and failed/unconfirmed requests. Collections are not profit.
Do not sum USD and KHR or count a transfer twice. Snapshot receipt shop identity
and exact amounts at payment time; profile edits must not rewrite receipts.

## 8. Additive data/migration design

- Reserve next version only when implementation begins; source/live currently V17.
- M2 migration: session purpose/client metadata with CUSTOMER backfill/default;
  separate approval attempts, hashed codes/secrets, PKCE challenge, expiry/state,
  approving customer, session/exchange linkage and bounded encrypted recovery.
- M4 migration: shop fields/version/logo attachment, registration receipts;
  unique `(merchant_id,currency)` for MERCHANT accounts after preflight. Do not
  add personal `(user_id,currency)` uniqueness: three existing groups conflict.
- One-shop rule: use owner locking and a partial v1-onboarding uniqueness rule;
  preserve potential legacy multi-shop records and block new duplicate v1 shops.
  Recheck actual data in each target database before constraints, not only this PC.
- M6 migration: payment request expiry/shop/currency/order linkage, confirmed
  transaction/identity snapshot and durable event identity; serialized state changes.
- M7: indexes for shop/credit time/currency/reference and stable pagination.
- M8: purpose-bound approval intents, immutable request hashes/receipts; original
  transfer journal remains authoritative. No new parallel ledger.
- Existing applied V1-V17 are immutable. Test on empty and upgraded isolated
  schemas. Halt a migration with a clear preflight error on conflicting legacy data;
  never repair by deleting or changing balances automatically.

## 9. Baseline/security acceptance map

M0 baseline: full existing backend suite, full Customer Flutter suite and analysis;
read-only schema/legacy audit; link/certificate inventory. No feature is declared
working from static inspection alone.

M2/M3: forged/expired/cancelled/replayed links, wrong verifier/state/callback,
refresh reuse, role/audience isolation, PIN failure persistence, cancellation and
exchange races, app death and missing Customer App. Test server + real Android.

M4: double/concurrent registration, second-wallet rollback, response loss/restart,
owned logo limits, zero merchant opening credit with customer funding enabled,
legacy-data preservation and immutable ownership.

M5-M8: cross-shop enumeration, status races, fixed-QR alteration/expiry/duplicate
payment, exact conversion, report reconciliation, restricted transfer purposes,
network recovery, session revoke and receipt consistency in both apps.

M9: full sequential regressions, accessible visual renders, normal-entrypoint APKs,
package/assets/secret checks and user-owned personal PIN acceptance. Preserve
the tablet's accessibility and Don't keep activities settings.

## 10. References

- [Implementation milestones](MERCHANT_APP_IMPLEMENTATION_PLAN.md)
- [Progress and baseline evidence](MERCHANT_APP_PROGRESS.md)
- [Android App Links](https://developer.android.com/training/app-links)
- [Native-app authorization and PKCE](https://www.rfc-editor.org/rfc/rfc8252)
- [NBC QR integration](https://bakong.nbc.gov.kh/en/download/KHQR/integration/QR%20Payment%20Integration.pdf)
