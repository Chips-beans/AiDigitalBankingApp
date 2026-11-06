# Kesor Merchant — product, contracts and build record

Updated 6 November 2026. Status, rules, setup and commands: [PROJECT_PROGRESS_AND_AGENT_GUIDE.md](PROJECT_PROGRESS_AND_AGENT_GUIDE.md).
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

## 9. M9 — integrated acceptance (APK packaging complete; device work pending)

Both latest Railway APKs were built with explicit user authorization on 6 Nov (§16); installation and
integrated acceptance remain pending. Railway already has schema V21. The following is the separate
local-backend acceptance plan, if requested; do not restart the dev backend or install without approval.
Plan: full sequential automated run; inspect the owner of
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

- Both `MerchantLinkBridge.kt` files and debug manifests compiled in the 5 Nov Railway APK builds;
  latest M4+ and Figma/splash source packaged again on 6 Nov (§16). Railway has V21; V19–V21 remain
  unapplied to the local dev database. Device payment, transfer approval, sound/vibration, sharing and
  process-death restore remain unverified.
- Uncertain-create process death → `OWNER_TRANSFER_IN_PROGRESS` until the first intent expires (≤ 5 min).
- Legacy `GET /merchants/me/accounts` is unchanged (G2; removal is the user's decision). EMV tag 59 truncates long/Khmer shop names
  to 25 bytes (G4); the scan screen shows the verified full name. Customer ៛ glyph still small.
- Concurrent updates may show `CONCURRENT_UPDATE` with *Try again*.
- Merchant payments are internal Kesor payments, not KHQR/Bakong certified.
- Latest automated evidence (4 Nov 2026): backend 234/234 (V21), Merchant 106/106, Customer 273/273, Merchant fixture 232 renders,
  Customer transfer-approval fixture 24 renders, analysis clean. Earlier: M2 backend 191/191, M3 Customer 247 + Merchant 28,
  M4 backend 203/Merchant 42, M5/M6 backend 211/Merchant 53, M7 backend 220/Merchant 73. Visual fixtures render EN/KM,
  light/dark, phone, 320 px, 2× text, landscape and tablet.

## 12. Merchant UI refinement — 4 November 2026

**Later user-directed card restoration (4 Nov):** the attached reference selected the previous
Home shop card and its three action tiles. Restored the navy gradient, faded Kesor mark, 60 px shop
avatar, merchant-ID row and Collect/Sales/Edit shop tiles. `NavyCard.branded` opts Home into this
treatment; other navy surfaces retain the refined flat style. Today's collections returns to its
ordinary surface below the tiles. Other screen refinements and wallet keyboard/copy behavior remain.
The `Merchant App v2` export below is the snapshot from before this card restoration; current renders
are in `frontend/merchant_app/.local/qa/card-restore/` and the cropped preview is
`.local/qa/card-restore-preview.png` within that app. Changes remain uncommitted.
Verification for this adjustment: **18/18 targeted shop/accessibility tests**, **232 visual fixture
renders with no overflow**, analysis and diff checks clean. Compared the restored card in light/dark,
320 px, 2× Khmer and tablet renders against the supplied reference. Device acceptance remains unverified.

Screenshot export: `Flutter Screen/Merchant App v2/` contains all 28 catalog screens/states,
38 full-resolution PNGs including 10 scrolled views, `Overview.jpg` and `README.md`. Captured from
the current UI in English/light at 393×852 logical pixels (1179×2556 PNGs); catalog fixture passed
and every image's decoding/dimensions and numbered screen coverage were verified. Existing exports
were preserved. `tool/screen_catalog.dart` supports `SCREEN_OUTPUT_DIR` for separate versions and
waits for the welcome artwork to decode. This is controlled Flutter fixture evidence, not device capture.

Presentation-only refinement, **uncommitted**. The existing Kesor foundations in
`frontend/customer_app/docs/DESIGN_SYSTEM.md`, captured Figma tokens and
`frontend/packages/kesor_design_system` remain authoritative. No Customer code, shared package,
backend, routes, controllers, integrations or dependency versions changed.

The source and 232 baseline renders showed an oversized shop-ID panel and equal-weight action tiles
ahead of collections, a 560 px Home column on wide tablets, a pictogram-led welcome, and too many rows
of Sales controls. These were the first screens selected by the app audit.

- **Welcome:** one bundled, generated illustration of a Cambodian coffee-counter exchange, replacing
  the storefront pictogram and feature badges. The copy retains QR, riel and dollar information.
  Phone stacks artwork and copy; wide layouts place them side by side. Approval, failure, recovery,
  busy, language and appearance controls retain their behavior. Artwork is decorative in semantics.
- **Home (initial refinement, superseded above for the card/actions):** compact actual shop identity,
  category, ID and labelled status; navy today's-collections summary; one gold Collect action;
  secondary Sales/Edit actions; the two independent business wallets
  grouped on one surface. Tablet Home expands to 1040 px and uses equal columns when text size allows.
  Large text stacks the currency lanes; 320 px uses the existing titleL amount role without scaling
  text down through FittedBox. Both wallet balances are still distinct from collection totals.
- **Collect:** remove the redundant outer form card, use the existing hero role for the amount input,
  attach its label to the field, and let the optional order-note label wrap above its field. Its full
  semantic label remains attached to the editable value. Validation, currency/mode selection,
  uncertain-create recovery, QR presentation and all request outcomes are preserved.
- **Sales:** Requests and Reports share the title area; all five date choices scroll within one row.
  Currency/search/custom dates, totals, paging and receipt navigation remain. Shared payment rows now
  align amounts to the trailing edge, use tabular figures and theme ink for readable incoming amounts.
- **Merchant shared widgets:** reuse the existing SurfaceCard/NavyCard/AmountText/StatusChip/SectionTitle
  components. Navy emphasis is flat without the repeated watermark; section titles use source type
  roles and heading semantics. Status backgrounds retain their semantic tokens with high-contrast navy
  text and explicit state words. AmountText keeps the enlarged Khmer riel glyph on a stable baseline.
  Wallet rows use Material InkWell focus/hover/press/keyboard behavior and preserve separate Copy
  controls with snack-bar feedback. Material navigation, hit targets, safe areas and theme behavior stay.

Taste app-screen direction: **Achromatic ledger, seed 1244715967**, with `--keep palette,type`, no redraws.
Used for hierarchy and grouping, adapted to the user's priority order: Kesor gold primary/navy emphasis,
20/24 px shapes, existing fonts, semantic colours and Material selection controls override the sheet's
achromatic budget, radii and desktop control sizes. Compatible Apple principles applied: text adaptation,
standard control behavior, explicit labels, feedback and keyboard focus. Primary guidance checked:
[Apple accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

**Verification:** final Merchant suite **109/109** (106 existing plus three accessibility/feedback/error-state
checks); `flutter analyze --no-pub` clean; `git diff --check` clean. The existing visual fixture passed
before and after with **232 renders each**: 393×852 phone, 320×640 small, 375×812 Khmer at 2×,
812×375 landscape, 800×1280 Khmer tablet at 1.3×, 1280×800 tablet landscape, each light and dark.
All final images were inspected in 28 contact sheets, with representative images opened at full size.
Tests exercise wallet keyboard activation, independent copy/feedback, Android touch-target and labelled
target guidelines, order-note label/value semantics, and stale balances plus retry on refresh failure.
The fixture now accepts `MERCHANT_QA_OUT` and waits for welcome-image decoding before capture.

Ignored local evidence under `frontend/merchant_app/.local/`: `ui-tests.log`, `ui-analyze.log`,
`ui-visual-final.log`, `ui-critique.md`, `qa/ui-before/`, `qa/ui-after/`, `qa/ui-review/`.
The latter contains `home-before-after.png`, `welcome-before-after.png`, `sales-before-after.png`,
`collect-before-after.png` and `review-manifest.json`. No new live sample data was introduced; all
rendered Kesor Coffee/Dara/Sophea values remain controlled test fixtures, not claimed merchant activity.

**Limits:** Android/native builds, real device input, TalkBack/VoiceOver, native sharing and payment
integration were not verified in this UI task. No Android device was attached. `flutter build web`
could not run because the Merchant project has no web target; no platform was added. Taste's DOM/CSS
lint reported no supported Dart source files, so no browser-inspector or zero-DOM-failure claim is made.
Flutter renders and semantics tests are the evidence. Large accessibility text and short landscape
windows deliberately scroll; the complete content is not forced above the fold. M9 remains unstarted.

**Generated asset:** `frontend/merchant_app/assets/images/merchant-welcome.png`, built-in `image_gen`,
one generation, no source photo or external media credit. This is illustrative artwork, not a real shop
photograph. Final prompt:

> Use case: illustration-story. Asset: one landscape raster illustration for the Kesor Merchant Flutter welcome screen. Editorial illustration of a Cambodian small coffee shop owner at a counter, handing a takeaway coffee to a customer holding a phone, friendly everyday business scene, modest Phnom Penh shop with potted plant, coffee equipment and a blank small payment placard. Sophisticated flat painted illustration with delicate paper texture, calm clean composition, restrained deep navy #17253D and warm gold #CDA32F on a white/off-white backdrop, natural skin tones. Main subjects centered with generous crop safety on all sides, landscape aspect about 3:2. No text, no logos, no letters, no QR patterns, no graphs, no gradients, no floating icons, no decorative blobs. This is in-app supporting artwork, not a UI screenshot.


## 13. Figma Quiet v2 redesign — 4 November 2026

**Current presentation, uncommitted.** The user's explicit reference is
[Merchant Redesign v2 · Quiet, section 370:4356](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=370-4356).
This supersedes the presentation in §12, including the later navy Home-card restoration.
Earlier source work and screenshot exports were preserved; the generated welcome illustration
remains on disk but is no longer shown or bundled.

Read the full section, retrieved high-fidelity context for all 28 child screens and downloaded
51 SVG exports. Merchant-only type/theme overrides reuse the existing Poppins/Google Sans,
semantic palette and shared theme extensions. The Customer App and shared design package
are unchanged. Static SVGs retain their exported geometry; the sample QR is never used at
runtime. Shop logos, QR payloads, money, references, dates and account suffixes remain live data.

Implemented across the existing flows:

- Welcome, sign-in waiting/failures, account review, registration/recovery and restricted-shop states.
- Home/Collect/More tabs; drawer links for Home, Collect, Sales, Collections report, Payment requests,
  Business wallets and Shop QR. More owns profile, language/appearance, alerts, support and sign-out.
- Flat Home totals, independent wallet balances, masked account rows, recent payments and wallet activity;
  wallet detail retains full-account copying and owner-transfer entry.
- Currency/amount entry with a decimal-string keypad, optional order note, server-controlled QR/countdown,
  paid/expired/cancelled states; white QR cards and receipt Save image/Share/Copy reference actions.
- Owner-transfer form, approval/countdown and result layouts; sources/destinations remain server-verified.
- Sales date/currency/search filters, exact totals and paging; separate requests; daily/monthly reports with
  pale/navy bars and complete exact-value rows; compact shop forms and settings controls.

Registration's primary action is **Review shop**. The local review sheet sends nothing; **Register shop**
creates the request through the existing controller. An uncertain registration shows the immutable saved
summary and **Check status** reuses its original key. Other payment/session safety behavior is retained.
The sign-in UI reads remaining approval time through `MerchantApprovalTiming`; the existing API gateway
calculates it from its pending journal's expiry and injected clock. It does not alter expiry enforcement.

Layouts use scrolling stages, wrapping choices, flexible value columns and larger keypad rows as text grows.
Headers/safe areas remain native. Large text, narrow widths and short landscape windows scroll instead of
forcing all controls above the fold; large/long payment rows stack their amount. Small display links follow
the compact Figma geometry; no blanket claim about every touch target or assistive-technology acceptance.

**Verification complete:** Merchant tests **112/112** (106 pre-refinement, three existing accessibility/
feedback tests, two new keypad/keyboard regressions and one light/dark selected-filter contrast check). Financial/controller/API assertions remain intact;
navigation and presentation assertions now drive the three tabs, drawer and review sheet. The QR-currency
check asserts the actual payload instead of a full account number that the new screen no longer displays.
Final default visual fixture: **294 renders, no overflow**, covering 393×852 phone, 320×640 small phone,
375×812 Khmer at 2×, 812×375 landscape, 800×1280 Khmer at 1.3× and 1280×800 tablet landscape, each
light/dark. Includes drawer, separate language/appearance and alert pages, sign-out sheet, denied sign-in
and server-expired request. Inspected all renders through 19 contact sheets and representative full-size
images. The review found and fixed selected dark tab/filter contrast and dark status-icon visibility;
final full-size Home, Sales and approval renders confirm the fixes. Final Welcome spacing was rechecked
in 12 variants, and approval assets in two. The fixture warms SVG bytecode outside the fake clock.
`flutter analyze --no-pub` and `git diff --check` are clean.

Export: `Flutter Screen/Merchant App Figma Quiet/` — **34 states, 36 PNGs**, all verified to decode at
1179×2556 (393×852 logical), plus `Preview.jpg`, `Overview.jpg` and `README.md`. Earlier export folders
remain untouched. The fixture reserves the native status-bar inset; it does not draw a fake OS bar.
Balances, QR patterns, dates, references, logo presence and preference values vary with actual data;
the Figma sample values are not hardcoded into the app. Native sharing/camera, device rendering and
TalkBack remain unverified.

Local evidence: `frontend/merchant_app/.local/figma-quiet/` contains the retrieved contexts, reference renders,
asset audit and logs. Responsive renders are in `.local/qa/figma-final/` in that app. No backend restart,
database migration, real payment, APK build/install, native sharing or physical-device acceptance occurred.
Backend/Customer suites were not rerun for this Merchant presentation task. M9 remains unstarted.

## 14. Figma Change list redesign — 5 November 2026

**Implemented source, uncommitted; visual/device acceptance remains open.** The current reference is
[Merchant Redesign · Change list, section 363:3084](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=363-3084),
superseding Quiet (§13). The user selected matching at 393×852 with responsive adaptation rather than
reproducing clipped content, and requires Android device acceptance as well as automated evidence.

- Retrieved individual context for all 28 frames. `tool/merchant_figma_manifest.json` maps each node
  to its catalog capture; `tool/compare_figma.py` produces paired images, overlays and diagnostic diffs.
  References, contexts, the 80-file non-empty asset audit and logs are in `.local/figma-change/`.
- Merchant-only navy headers, gold pill actions, bordered cards, segmented filters, branded Home,
  wallet balances, QR cards, receipts, forms, results, drawer and settings replace the Quiet treatment.
  Welcome uses the exact bundled Figma illustration and logo, with the specified fading artwork.
  SVG source dimensions are retained. Live QR strings, identities, money and references remain dynamic.
- Home's Sales / Shop QR / Reports / Requests shortcuts open existing functional destinations.
  Collect is a full-screen flow without the bottom tab bar, matching the reference; Back returns Home,
  and the drawer remains available during entry. Home and More retain the three-tab navigation.
- Reuse existing controllers/gateways and all idempotency, approval, expiry and uncertain-request rules.
  No Customer App, backend, database, shared package or native integration changes. Design annotations
  listing alternate outcomes are represented by their actual runtime states rather than instructional UI.
- Headers measure scaled titles; narrow/large-text section actions stack, wallet cards reflow and stages
  scroll around keyboards and short landscape windows. Tests retain exact financial assertions.

**Automated evidence:** Merchant **118/118** (112 existing, four new actual Home destination tests and
two narrow/2× long-identity/maximum-money stress cases); analysis clean; responsive fixture **294 renders,
no layout exceptions** across English/Khmer, light/dark, phone, 320 px, 2× text, landscape and tablets.
The existing keyboard/Khmer test also passes. Test navigation now follows the real full-screen Collect
Back behavior. The collection status assertion identifies the live status row because the design repeats
the same label in the header. No financial assertions were removed. Heavy checks ran sequentially.

Screenshot export: `Flutter Screen/Merchant App Figma Change List/` — **34 states, 40 PNGs**, all decoded
and verified at 1179×2556, with Preview/Overview images, a manifest and 28 comparison boards. Comparison
evidence under the Merchant `.local/figma-change/` directory. These are controlled Flutter fixture
renders, not device captures. The initial baseline accidentally targeted the earlier default export;
its matching archived PNGs were restored from the existing untouched `Flutter Screen.zip`, and the
new baseline retained separately in `.local/figma-change/baseline/`. Later captures use separate folders.

**Acceptance limits:** comparison differences are diagnostic, not a certified ≤1-pixel visual pass.
An approved golden baseline and physical-device visual sign-off are still outstanding. No device was
attached when checked. No APK was built/installed, backend restarted, live payment submitted or
migration applied for this task. Native save/share, sound/vibration, Customer approval round trips,
process restoration and TalkBack remain device acceptance items. Pilot APKs already on disk predate
this redesign; see DEPLOYMENT.md before a separately approved rebuild.

Next: review the comparisons, resolve any remaining visual differences against the 28 references,
then obtain approval to build/install the updated Merchant APK and complete Android acceptance.

## 15. Figma Section 3 Merchant splash — 6 November 2026

Implemented `418:6159` in section `431:2446` of the Kesor Bank file. New
`core/merchant_splash.dart` keeps all twelve exported logo vector layers in their reference
positions on white, with navy dot and gold Merchant lettering. Shared `KesorBrandSplash`
provides the source fade/scale loop and reduced-motion final state. Production `main.dart`
passes session initialization into `MerchantApp`; the splash remains for at least 1100ms and
until restoration finishes, then yields to the existing auth/shop phase. Android pre-Flutter
backgrounds are white in light and dark system themes. Existing shop/payment flows are preserved.

**Automated:** Merchant full **119/119**, analysis clean. A startup test verifies that unresolved
restoration keeps the splash visible and completion opens the existing continuation flow.
`tool/splash_visual_qa.dart`: **30 renders**, five viewports × light/dark × 1×/1.3×/2× text,
no layout exceptions. Reference screenshot inspected. Logs: `.local/section3-all-tests.log`,
`section3-analyze-final.log`, `section3-visual.log`; PNGs: `.local/qa/section3/`. XML parses;
no dependency upgrades. Customer implementation/shared motion tests: CUSTOMER_APP.md §19.

Source is uncommitted. No APK build/install, native launch/device acceptance, backend restart,
migration, real payment or deployment. M9 remains a separately authorized step.

## 16. Updated Railway APK — 6 November 2026

User authorized building both updated APKs. Merchant debug build succeeded with `APP_ENV=dev`
and `API_BASE_URL=https://backend-production-18646.up.railway.app/api/v1`, using the current
uncommitted source (base `e6c58b6`). Includes the full Figma Change list redesign (§14), latest
white Merchant splash (§15) and existing M4–M8 functionality.

- Current APK: `frontend/merchant_app/.local/apk/KesorMerchant.apk`; versioned copy:
  `frontend/merchant_app/.local/apk/20261106-055520/KesorMerchant.apk`.
- Size: **205,414,739 bytes** (195.90 MiB); SHA-256:
  `EB495F273A84059DC4B568FFB123873CF1B125BE2B633646F3FF67EE394B6C01`.
- Package `com.bank.merchant_app`, version `0.1.0+1`; signature valid and matches the prior APK.
  Railway URL, splash classes and original splash/Change list assets verified in the package;
  old Wi-Fi IP absent, zero `.env` entries, ZIP CRC clean.
- Previous APK preserved under `.local/apk/archive/20261106-055520-previous-b3bd7eb04769/` in this app.
  Shared evidence: repository `.local/apk-refresh-20261106-055520/`, including source manifests,
  build/signature/package logs and `verification.json`. All 550 recorded app/shared inputs unchanged.

Existing baseline remains **119/119**, analysis clean (§15); not rerun for packaging. Builds ran
sequentially and Gradle stopped after each. No backend/configuration change, installation, native
device acceptance, payment or commit. This supersedes earlier APK-pending notes; M9's installation
and user acceptance gates remain open.

## 17. Customer visibility of linked business wallets — 6 November 2026

Customer Wallets now reads the owner's business accounts through the existing Customer-session
`GET /accounts/me?category=MERCHANT` route, with pagination. A registered shop's KHR/USD wallets
appear separately with real balances and numbers; no business accounts means no placeholder.
Approving Merchant sign-in before registering a shop does not create visible business wallets.
Merchant sign-out does not remove ownership or hide existing wallets from Customer.

Customer merchant details/activity/receipts are read-only, using separate controllers and routes;
personal transfer and QR source selection are isolated. Merchant QR creation and owner-transfer
initiation remain in Merchant, with existing Customer approval. No Merchant App, backend API,
authorization, database or session-policy change; the current §16 Merchant APK is unchanged.

Customer verification: **307/307** tests, new merchant-wallet coverage **9/9**, clean analyzer,
**96** responsive renders without layout exceptions (EN/KM, both themes, phone/tablet, 1×/2×).
Evidence and details: Customer document §22. Merchant/backend suites not rerun for this
Customer-only change. Uncommitted; no APK build/install, live/device acceptance, restart,
migration, deployment or real payment. M9 remains incomplete.

## 18. Sign-in diagnostics and retry recovery — 6 November 2026

User supplied a friend's Khmer generic sign-in error screen; both apps are installed on that
phone, but the failing step is unknown. Read-only Railway checks found the expected deployment
running, profile `dev`, Swagger 200 and unauthenticated Merchant session 401. Available logs did
not identify the incident; no phone was attached. The specific device cause is **not confirmed**.

Implemented the approved source plan:

- `MerchantAuthFailure` carries a safe diagnostic stage/code/HTTP status into `MerchantSession`.
  A closed code allowlist and enum stage generate the Copy error details report; no tokens, PINs,
  callback links, bodies, account data or raw exception text. Failure details clear on new work,
  success and cancellation. Late reopen errors cannot overwrite a cancelled/new session.
- Both Android bridges distinguish `PEER_SIGNATURE_MISMATCH`, `HANDOFF_UNSUPPORTED_BUILD`,
  `PEER_OPEN_FAILED` and the existing `PEER_MISSING`. Exact package/component, one signer, pinned
  certificate, debug-build and URI checks remain enforced. Shared `HandoffApi` now retains HTTP
  status for malformed/non-JSON envelopes, allowing 401/403/429/5xx to remain distinguishable.
- Existing error layout has EN/KM explanations for app mismatch/opening, unsupported builds,
  network, secure storage, backend rejection/unavailability and unreadable responses. Copy has
  success/failure feedback; secure-storage retry is labelled; unsupported builds offer Back/Copy.
- Failed start requests clear only their incomplete no-ID draft once settled. Explicit retry
  generates fresh credentials; known waiting attempts resume and can reopen Customer approval.
  Malformed token responses now enter explicit identical-body exchange recovery immediately,
  retaining the 60-second limit. Saved tokens survive a failed identity read so retry reads that
  same session. Cancellation tombstones and conservative uncertain-refresh handling are retained;
  storage failures/corrupt journals are identified without deleting saved auth data.

Verification:

- Full Merchant **144/144** (25 new diagnostics/retry tests); Customer handoff/payment suites
  **38/38**. Includes failed-start/cancellation races, malformed exchanges, identical recovery,
  saved-token retry, uncertain refresh, storage read/write/corruption, native error mapping,
  malicious error-code filtering, clipboard contents and late reopen failure suppression.
- Both app analyzers clean; diff check clean. Fixture `tool/merchant_auth_visual_qa.dart` produced
  **192 responsive renders**: eight error states × 320/393/800px widths × EN/KM × both themes ×
  1×/2× text. No layout exceptions; Retry/Recover, Copy and Back reachable with targets ≥48dp.
  All eight contact sheets and representative full-size PNGs inspected.
- Both Android `:app:compileDebugKotlin` checks pass, with Flutter compilation excluded (no APK
  assembly). Existing Gradle/plugin/platform deprecation warnings remain; daemons stopped.
- Merchant logs: `.local/merchant-auth-{all-tests,analyze,visual,kotlin}.log`; images and contact
  sheets `.local/qa/merchant-auth/`. Customer logs: `.local/merchant-auth-{customer-handoff,analyze,kotlin}.log`.

Uncommitted. Existing APK checksums are unchanged; no APK build/install, backend/configuration
change, migration, restart, deployment, real sign-in/payment, commit or push. Next: separately
authorized APK packaging and the friend's reproduction. If it fails, capture Copy error details;
verify Customer approval → Merchant return → registered shop before closing the incident. M9 stays open.
