# Kesor Merchant — product, contracts and build record

Updated 4 November 2026. Status, rules, setup and commands: [PROJECT_PROGRESS_AND_AGENT_GUIDE.md](PROJECT_PROGRESS_AND_AGENT_GUIDE.md).
The Customer App side (approval screens, paying a shop) is summarized in [CUSTOMER_APP.md](CUSTOMER_APP.md) §9.
Old milestone reports (M0–M8, remaining-work plan): `git show ccc10bd:docs/<NAME>.md`.

All API paths are under `/api/v1`, use the standard envelope and `no-store`, and money is exact decimal text
(USD 2 decimals, KHR 0). Day boundaries are Asia/Phnom_Penh; USD and KHR are never summed.

## 1. Requirements and adopted decisions

- Separate Android-first Flutter Merchant App sharing the Spring Boot backend and PostgreSQL with the Customer App.
- **Only sign-in:** *Continue with Kesor Bank* → approve in the Customer App with the customer PIN → return. No Merchant
  email/Telegram/password/PIN and no second identity.
- First sign-in → register a shop; returning owners open their shop. Registration creates **exactly one KHR and one USD
  business wallet** (zero balance, no development opening credit). Shop name/logo are the merchant profile and never
  change the owner's personal name/photo.
- Decisions: one owner = one shop (v1); same-device approval; separate revocable Merchant session; demo activation
  (shop ACTIVE at registration) only for local/dev/test; internal Kesor QR payments only (no KHQR/Bakong yet);
  same-currency owner transfers only (no external withdrawal, no merchant FX); foreground status polling (no push yet);
  sign-in approval and money-movement approval are different purposes and neither proof authorizes the other.
- Navigation: **Home / Collect / Sales / More**; Wallets and Reports reachable from Home/Sales. English + Khmer,
  system/light/dark, phone and tablet, large text, safe areas; UI reuses Kesor design-system widgets.
- A "sale" is only a confirmed QR credit to the shop's business wallet (`merchant_collections`). Deposits, manual
  transfers in, owner transfers and unpaid requests are never sales. Collections are not profit.

## 2. Architecture and identity

| Item | Value |
| --- | --- |
| Customer / Merchant packages | `com.bank.customer_app` / `com.bank.merchant_app` |
| Registered client ID | `kesor-merchant-android` |
| Merchant secure vault namespace | `kesor.merchant.v1`, isolated by API origin and installation |
| JWT claims | Merchant audience `kesor-merchant`, purpose `MERCHANT`, client `kesor-merchant-android`, access life ≤ 5 min; Customer audience `kesor-customer` |
| Shared packages | `kesor_design_system` (theme copied exactly from Customer), `kesor_auth_handoff` (links, exact matching, native bridge) |
| Merchant app layout | `lib/features/{auth,shop,collect,sales,feed,transfer}`, `lib/core/merchant_strings.dart`, `lib/core/platform/image_share.dart` |
| Business-wallet debit | `FinancialPostingService.postOwnerTransfer` is the **only** path; every other debit hits `MERCHANT_WALLET_RESTRICTED` |

## 3. Links and configuration

| Item | Contract |
| --- | --- |
| Sign-in approval link | `kesorbank://merchant/approve` (`attemptId`, `handoffToken`) → `com.bank.customer_app` |
| Sign-in callback | `kesormerchant://auth/callback` (`code`, `state` only) → `com.bank.merchant_app` |
| Transfer approval link | `kesorbank://merchant/transfer` (`intentId`, `handoffToken`) |
| Transfer callback | `kesormerchant://transfer/callback` (`intentId`, `state`, optional `error=access_denied|failed`) |
| Transport | Debug-only custom schemes; fixed-component intents that check the peer package **and** installed signing certificate in both directions (debug SHA-256 `ae861749ac17ba744e16064146dc0320e27bdde8b5f61b55939c90baf1cbc2b4`, a public fingerprint). Non-debuggable builds reject it. |
| Config keys | `app.merchant-auth.*` (clients, callbacks, `transfer-*-uri`, env `MERCHANT_TRANSFER_*_URI`), `app.merchant.self-service-activation`, `app.merchant.payment-request-ttl-seconds` (300, bounded 60–1800), `app.merchant.owner-transfer-ttl-seconds` (300, clamped 60–900). Blank transfer links outside development disable only transfers (`503 MERCHANT_TRANSFER_UNAVAILABLE`). Enabling self-service activation outside development fails startup. |
| Release | Verified HTTPS App Links need a user-controlled domain and release certificate; none supplied. Do not reuse Telegram's domain or claim App Links are verified. Dev custom schemes must stay out of production allowlists. |

## 4. Sessions and the sign-in protocol (M2 + M3)

### Access matrix
Customer session: existing personal rules only. Merchant session **before** a shop: onboarding/identity only.
Merchant session **with** a shop: that owner's shop resources only. A Merchant token can never reach personal wallets,
history, payments, AI, profile/PIN, admin or the legacy merchant APIs, even if the owner also has a Customer role
(`SessionPurposePolicy.SHOP_ROUTES` is the allowlist). Merchant sign-out revokes Merchant only; PIN reset or user-wide
revocation also revokes Merchant sessions. A suspended shop keeps read access but cannot collect or transact.

### Routes (V18; OpenAPI group `merchant-auth`)

| Route | Credential / behaviour |
| --- | --- |
| `POST /merchant-auth/attempts` | Public registered client. Body: `clientId, redirectUri, state, codeChallenge (S256), attemptSecretHash, installationId, deviceName`. Returns `attemptId, expiresAt, approvalUri, customerPackage`. |
| `GET /merchant-auth/attempts/{id}` | Unlocked Customer token + `X-Merchant-Handoff`; minimal server-owned details. |
| `POST .../{id}/approve` | Customer token; `{handoffToken, pin}` (shared 5-attempt PIN budget); returns the exact registered callback. |
| `POST .../{id}/deny` | Customer token; callback has `error=access_denied` and the state, no code. |
| `POST .../{id}/status`, `/cancel` | Private attempt secret; cancel also revokes any derived session atomically. |
| `POST /merchant-auth/exchange` | Code + S256 verifier + attempt secret + stable exchange key + state → one Merchant session. |
| `POST /merchant-auth/refresh` | Rotating refresh token; reuse revokes the session. |
| `GET /merchant-auth/session` | Session identity and `onboardingState`: `SHOP_REQUIRED`, `READY`, `RESTRICTED`, `RECOVERY_REQUIRED`. |
| `POST /merchant-auth/logout` | Revokes that Merchant session. |
| `GET /auth/merchant-sessions`, `POST /auth/merchant-sessions/{id}/revoke` | Customer inspects/revokes own Merchant sessions. |

Rules: attempts last 120 s (PENDING → APPROVED → CONSUMED; DENIED/CANCELLED/EXPIRED terminal); codes are 256-bit,
stored as SHA-256; the attempt UUID is never a credential (the 256-bit handoff token is needed to view/approve).
Verifier, state, attempt secret and exchange key are 32 random bytes, base64url, generated by the Merchant app and
saved in its secure vault before the handoff. Attempt mutations take an advisory lock before owner/attempt/session
rows. The first exchange stores a 60-second AES-256-GCM encrypted response so the *same immutable body* can recover the
*same* session after response loss or a server restart; a changed key can never create another session. A scheduled
sweep (1 min, ≤ 200 rows/phase) expires attempts and erases ciphertext. Tokens, PINs, verifier, secrets and exchange
keys never appear in links, logs or audit text. Named errors: `MERCHANT_AUTH_EXPIRED|DENIED|CANCELLED|INVALID|USED|
RATE_LIMITED`, `MERCHANT_SESSION_REQUIRED`.

### App behaviour
Exact callback URI, unique allowed parameters, pending attempt and constant-time state checks precede exchange.
Uncertain exchange allows only an explicit identical-body recovery within 60 s. Cancellation persists a tombstone,
reaches the server and suppresses late results across app death. Refresh is marked before sending; an uncertain
rotation cannot restore identity. Customer keeps one bounded approval request through sign-in/onboarding/PIN gates
and process recreation. Both apps use retained engines, `singleTask` activities and separate Telegram/Merchant/image
routing. **User-confirmed on device (31 Oct):** approve → return → Register Shop / existing shop, also after reopening.

## 5. Shop registration, profile and wallets (M4, V19)

- `GET /merchants/me` → `onboardingState`, owner `{id, displayName}` (first name only), shop, wallets (KHR then USD).
- `POST /merchants/me/registration` — `Idempotency-Key` required; 201 created, 200 same-key replay,
  409 `MERCHANT_REGISTRATION_CONFLICT` (changed body) / `MERCHANT_ALREADY_REGISTERED`. Body: `storeName` (1–150),
  `categoryCode`, `phone`, `city` (1–100), `address` (1–255), optional `description` (≤ 500), `stagedLogoId`.
  **Any other field is 400** (`ownerUserId`, `merchantId`, `status`, `openingBalance`, `bakongAccountId`…). Phone is
  normalized to E.164 (Cambodian 8–9 national digits, `MERCHANT_PHONE_INVALID`). Categories → MCC: FOOD_DRINK 5814,
  GROCERY 5411, RETAIL 5399, FASHION 5651, BEAUTY 7230, ELECTRONICS 5732, HEALTH 5912, SERVICES 7299, EDUCATION 8299,
  TRANSPORT 4121, OTHER 5999.
- One transaction under the owner lock: journal check → existing-shop check → staged-logo lock → shop (server code
  `MCH-XXXXXXXX`, QR alias `m.xxxxxxxx@kesor`) → KHR then USD CHECKING MERCHANT wallets at zero → attach logo → journal
  row → audit `SHOP_REGISTERED`. The owner is not given `ROLE_MERCHANT`. ACTIVE → `READY`, otherwise `RESTRICTED`.
  Legacy multi-shop owners surface as `RECOVERY_REQUIRED`; nothing is repaired automatically.
- `PATCH /merchants/me/profile` (partial edit with `version`; 409 `MERCHANT_PROFILE_CONFLICT`; 403 `MERCHANT_INACTIVE`),
  `POST /merchants/me/logo-uploads` (multipart `logo`; JPG/PNG ≤ 5 MB / 16 MP; re-encoded ≤ 512 px, metadata stripped;
  ≤ 5 staged per owner, swept after a day), `GET /merchants/me/logo`.
- Schema: `merchants` gains `onboarding` (`LEGACY|SELF_SERVICE`), category, phone, address, description, `profile_version`;
  partial unique indexes enforce one self-service shop per owner and one MERCHANT account per `(merchant_id, currency)`
  (a preflight halts V19 on conflicting legacy data); tables `merchant_logos`, `merchant_registration_requests`.
- App: registration form (province picker EN/KM, category picker, optional logo with initial fallback). The draft and
  idempotency key are saved to the secure store **before** sending; uncertain results lock the form to the saved draft
  with *Check registration status* or *Discard and edit*. The privacy cover overlays instead of replacing the screen so
  a half-filled form survives the file picker.

## 6. Dashboard, collection and sales (M5–M7, V20)

### Routes (`/merchants/me`, Merchant session only)

| Route | Behaviour |
| --- | --- |
| `GET /dashboard` | Profile + `today[{currency,count,gross}]` + `recent[10]` + `businessDate`, `serverTime` |
| `GET /wallets/{accountNumber}?page=` | Own business wallet + read-only activity (20/page); anything else 404 |
| `GET /qr?currency=` | Stable reusable shop QR (payee = shop name); Save/Share |
| `POST /payment-requests` | `Idempotency-Key`; `{currency, amount, orderReference?≤50}`; 201 / 200 replay / 409 `IDEMPOTENCY_CONFLICT`; fixed amount, expires in 5 min, payable once |
| `GET /payment-requests/{id}` | Status + `serverTime/expiresAt`; QR only while WAITING; `receipt` when PAID |
| `POST /payment-requests/{id}/cancel` | WAITING → CANCELLED (or EXPIRED); PAID stays PAID |
| `GET /payment-requests` | Request history (`status`, keyset cursor, ≤ 50 due rows settled per call); no QR strings |
| `GET /sales` | `from,to` (ISO, inclusive, default today, ≤ 366 days), `currency`, `q` (1–50 chars: transaction suffix, request reference or order note), `size` 1–50, opaque cursor → `{items,nextCursor,totals}` where totals cover the whole filter |
| `GET /sales/{reference}` | Snapshot receipt (shop name, payer first name, masked account, wallet, rate, request/order refs, `paidAt`); foreign → 404 |
| `GET /reports/collections` | `period=DAY` (≤ 92 days) or `MONTH` (≤ 24 months), zero-filled buckets for both currencies + separate grand totals |

Legacy `GET /merchants/me/accounts` stays Customer-session (wallets live at `/merchants/me/wallets/…`).

### Payment safety
- Tables: `merchant_payment_requests` (one registered DYNAMIC `payments` row per request; WAITING/PAID/EXPIRED/CANCELLED,
  per-owner idempotency, expiry; checks tie PAID to a transaction) and `merchant_collections` (one immutable snapshot per
  confirmed QR credit: received and paid amounts/currencies, rate, reference, request, shop name, payer first name, masked
  account). `transactions` stays the only ledger — no second ledger.
- The customer payment locks the registered payment row, then the request row, then accounts; cancel and expiry lock the
  payment row first, so exactly one of *paid* or *cancelled* wins (tested with real races). A scheduled sweep expires
  stale requests and reads settle lazily. A KHR request paid from a USD wallet uses the fixed rate (2.50 USD → 10,000 KHR).
- `/accounts/lookup` never resolves business wallets; `/payments/qr/generate` refuses them. Expired, cancelled, paid
  requests and inactive shops are refused at scan and pay.
- Sales keyset order is `(created_at DESC, transaction_id DESC)`, cursor = base64url `<epochMicros>:<transactionId>`; no
  OFFSET. List/report queries run REPEATABLE_READ so page and totals share a snapshot. Rare contention returns
  `409 CONCURRENT_UPDATE` and the app offers *Try again*. Rate lanes `sales-list` 120/min, `sales-report` 60/min.
  Receipt time is the UTC instant + 7 h (`2026-11-02T17:30:00Z` → `03/11/2026 00:30`); the rate line shows e.g.
  `1 USD = 4,000 ៛` from the stored string, never derived.

### App
- **Home:** shop card, today's collections per currency, both wallet balances (kept separate from collections), latest payments.
- **Collect:** amount keypad + currency + optional order note → live fixed QR with server-clock countdown, 2 s status poll,
  *Payment received* only after the server says PAID (payer first name, masked account, converted amount, reference, time);
  active request ID saved per owner so a restart resumes; a lost create reuses the same key. **Shop QR** per currency.
- **Sales:** Today/Yesterday/7 days/This month/Custom, All/KHR/USD, debounced search, whole-filter summary, rows grouped
  by Phnom Penh day (loaded counts labelled *shown*), infinite scroll + Load more + pull-to-refresh. **Receipt:** copy
  reference, save/share PNG and text. **Reports:** Daily/Monthly, one currency at a time, zero-filled bars + table,
  labelled "received payments, not profit". **Requests:** history with status filter; waiting opens Collect, paid opens the receipt.
- **Sharing:** native `kesor/merchant_share` channel, cache-only FileProvider, gallery `Pictures/Kesor Merchant`; no tokens,
  full payer accounts or internal IDs in shared text.

## 7. Payment alerts and owner transfers (M8, V21)

### M8a — live feed (Merchant app only, no backend route)
`PaymentFeedController` (per owner) polls `GET /merchants/me/dashboard` every 10 s (30 s after 3 failures) only while the
app is resumed, uncovered and the shop is READY. The first load only records references (history never alerts); a new
reference shows one in-app banner (`+25,000 ៛ from Sophea`, or `N new payments received`; tap opens Sales), refreshes the
shop and plays the system alert + medium haptic if enabled. A payment the Collect screen already confirmed is marked seen
via `CollectController.onReceipt`. **More → Payment alerts:** Sound and Vibration toggles (device-local, default on) with
the honest note that alerts work only while the app is open (background notifications are M10).
Known limit: a feed poll that lands before Collect's own 2 s poll can show one duplicate banner.

### M8b — owner transfers (business wallet → the same owner's personal wallet)
Flow: Merchant creates an intent → opens `kesorbank://merchant/transfer` → the Customer App shows the exact intent and the
owner approves with a fresh PIN → the **same database transaction** posts the transfer and completes the intent → Customer
opens `kesormerchant://transfer/callback` → Merchant polls authenticated status. The callback is only a nudge; the answer
always comes from the server. Denial, cancel and expiry move no money.

| Route | Session | Notes |
| --- | --- | --- |
| `POST /merchants/me/owner-transfers` | Merchant | `Idempotency-Key`; body only `{sourceAccountNumber, amount}`. The server picks the destination: the owner's earliest ACTIVE personal wallet in that currency (`409 OWNER_WALLET_REQUIRED`; `409 INSUFFICIENT_FUNDS` up front). Returns `approvalUri` + `state`; a same-key replay of a waiting intent returns the same intent with a **fresh** handoff secret. One open intent per owner. |
| `GET .../owner-transfers/{id}`, `POST .../{id}/cancel` | Merchant | Lazy expiry; cancel after approval returns `COMPLETED`. |
| `GET /merchant-transfers/{id}` | Customer | `X-Merchant-Handoff`; owner-only; shop name, masked wallets, exact amount, expiry. |
| `POST /merchant-transfers/{id}/approve`, `/deny` | Customer | Approve takes `{handoffToken, pin}`. |

`merchant_owner_transfers` (V21): statuses `PENDING COMPLETED DENIED CANCELLED EXPIRED FAILED`; SHA-256 of key, request,
intent and handoff secret; callback `state`; 5-minute expiry; `transaction_id UNIQUE`; CHECKs tie COMPLETED to its
transaction and FAILED to a code; a partial unique index allows one open intent per owner.

`approve` order: owner lock → intent `FOR UPDATE` → handoff secret → valid unlocked Customer session → replay if already
COMPLETED (callback, no PIN) → pending and not expired → recomputed `intent_hash` (tamper check) → shop still ACTIVE →
shared-budget PIN check (`AppPinService.verifyForOwnerTransfer`; failures commit via `noRollbackFor`; five wrong digits lock
Customer PIN gates) → `postOwnerTransfer` → COMPLETED. Short funds commit the intent as `FAILED/INSUFFICIENT_FUNDS` (HTTP
200, no money moved). Owner transfers are not in `merchant_collections`, so never in sales/reports; they show as
`TRANSFER_OUT` in wallet activity and as an incoming transfer named after the shop in the owner's history
(`operation=OWNER_TRANSFER`). No `idempotency_records` row for approval: the row lock, `status='PENDING'` guard and
`transaction_id UNIQUE` already make a second posting impossible.

Customer app: `MerchantTransferApproval` + screen are a sibling of the sign-in coordinator (own storage slot; a transfer link
stays untaken while a sign-in request is active). Lost approval response → reload the request (`OWNER_TRANSFER_COMPLETED`),
never re-approve. FAILED waits for *Return to Kesor Merchant*. Merchant app: wallet detail → **Transfer to my wallet** →
`OwnerTransferPage` (amount, waiting with countdown, *Continue in Kesor Bank*, *Cancel*, result states); controller saves
`{id, key, source, amount, state}` (never the handoff secret), resumes after restart, polls every 2 s, reuses the key after an
uncertain create and refreshes the shop on completion.

### G items
G1 riel sign: `AmountText` draws ៛ in the Khmer face at 1.3× and `CurrencyBadge` is 24 (Merchant only). G2/G4: see Known limits.

## 8. Conventions specific to Merchant work
Backend and Flutter conventions are in the progress guide §7. Highlights: derive owner/shop from the session only; register
routes in `SHOP_ROUTES`; idempotency keys on every money/record write; lock order payment → request → accounts; lane names
≤ 15 chars; foreign resources are 404; never auto-resend an uncertain money request.

## 9. M9 — integrated acceptance and pilot APKs (next; needs the user's yes)

Ask first before restarting the dev backend or building/installing. Plan: full sequential automated run; inspect the owner of
port 8080; restart with the ignored launcher; confirm Flyway applied V19–V21 and the new paths in OpenAPI; confirm the PC's
Wi-Fi IP; build both debug APKs with the dev/API defines; verify (no `.env`, API origin, SHA-256); install with
`adb install -r` on the user's go-ahead; keep the device settings. Name outputs `KesorMerchant-M9-Pilot.apk` and
`KesorBank-M9-Pilot.apk`.

**User acceptance script (performed privately by the user; record their answers verbatim):**
1. Merchant → *Continue with Kesor Bank* → approve in Customer → returns.
2. Register shop (with logo) → Home shows two zero wallets.
3. Collect 1,000 ៛ → pay from the Customer USD wallet → Merchant shows *Payment received*.
4. Shop QR → pay $1.00 from Customer → alert appears on Merchant.
5. Sales shows both; open a receipt; share it; Reports shows today.
6. Transfer to my wallet → approve in Customer with PIN → balances update.
7. Cancel a waiting QR; let one expire; confirm the Customer cannot pay them.
8. Close and reopen both apps mid-request; the state is recovered.

**Exit gate:** all automated checks green, both APKs installed, user confirms the script, and a short M9 entry (automated vs
personal evidence, remaining production dependencies) goes into the progress guide.

## 10. Deferred (do not start without a plan)
- **M10** durable event outbox, Android push (FCM), token rotation/preferences, optional voice; committed payments survive
  delivery failure and never replay sounds.
- **M11** individually authenticated cashiers, permission matrix, shift closing, CSV export, full/partial refunds linked to
  the original payment, never exceeding the refundable amount, owner-approved.
- **M12** branches/counters, invoices and payment links (minimal public data), read-only sales assistant with no write power.
- **M13** KHQR/Bakong provider integration, status verification, settlement/reconciliation, external refunds (needs provider access).
- Also out of scope: iOS acceptance, inventory, payroll, loans, loyalty, external-bank payouts, production deployment.

## 11. Known limits and evidence

- **Not compiled/verified:** Kotlin in both `MerchantLinkBridge.kt` files and the debug manifests (transfer filters); no Merchant APK
  with M4+ exists; V19–V21 unapplied to dev; no device payment, transfer approval, sound/vibration, sharing or process-death restore.
- Uncertain-create process death → `OWNER_TRANSFER_IN_PROGRESS` until the first intent expires (≤ 5 min).
- Legacy `GET /merchants/me/accounts` is unchanged (G2; removal is the user's decision). EMV tag 59 truncates long/Khmer shop names
  to 25 bytes (G4); the scan screen shows the verified full name. Customer ៛ glyph still small.
- Concurrent updates may show `CONCURRENT_UPDATE` with *Try again*.
- Merchant payments are internal Kesor payments, not KHQR/Bakong certified.
- Latest automated evidence (4 Nov 2026): backend 234/234 (V21), Merchant 106/106, Customer 273/273, Merchant fixture 232 renders,
  Customer transfer-approval fixture 24 renders, analysis clean. Earlier: M2 backend 191/191, M3 Customer 247 + Merchant 28,
  M4 backend 203/Merchant 42, M5/M6 backend 211/Merchant 53, M7 backend 220/Merchant 73. Visual fixtures render EN/KM,
  light/dark, phone, 320 px, 2× text, landscape and tablet.
