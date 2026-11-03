# Kesor Bank — Customer App and banking backend

Updated 4 November 2026. Status, rules, setup and commands are in
[PROJECT_PROGRESS_AND_AGENT_GUIDE.md](PROJECT_PROGRESS_AND_AGENT_GUIDE.md); the Merchant App is in
[MERCHANT_APP.md](MERCHANT_APP.md). Screen-level design notes remain in
`frontend/customer_app/docs/` (design system, email auth screens, Home, Scanner, Settings,
Transfer, Wi-Fi development). Old per-feature reports: `git show ccc10bd:docs/<NAME>.md`.

Stack: Flutter customer app (`frontend/customer_app`), Spring Boot 4.1 / Spring Security / JPA /
Flyway / PostgreSQL backend (`backend/digital-banking`). All API paths below are under `/api/v1`
and use the envelope `{success, data, message, timestamp}` with `no-store` on sensitive routes.

## 1. What the Customer App does

Email/Telegram sign-in → profile → 4-digit PIN → Home with USD and KHR wallets, manual transfers,
QR receive/scan/pay, history and receipts, Monthly Analytics, a read-only AI assistant, Settings,
English/Khmer, light/dark/system theme. It also approves Merchant App sign-in and owner transfers
(§9). Money is exact decimal everywhere: USD two decimals, KHR whole units; ownership, idempotency
and recovery of uncertain requests are enforced on every financial operation.

## 2. Authentication and onboarding

- **Entry points:** *Continue with Telegram* or *Continue with Email*. New and returning identities
  share each flow. Legacy password routes remain for old integrations and staff QA but are hidden
  in the customer UI. Staff keep password + OTP.
- **Email:** expiring, rate-limited, single-use CONTINUE code (5 minutes). Requesting a code never
  creates a user or reveals whether a profile exists. Enter codes manually (no QA bridge).
- **Telegram (browser):** authorization-code flow with S256 PKCE, state and nonce; server-only client
  credentials; signature/issuer/audience/expiry validation. `POST /auth/telegram/start` → open
  `authorizationUrl` → private approval receipt back to the initiating window →
  `POST /auth/telegram/exchange`. No token in any URL. Flow secrets are one-use, 5 minutes.
- **Telegram (native Android):** registered with @kesorbankbot for `com.bank.customer_app`; return URI
  `https://app937652339-login.tg.dev/tglogin` (verified App Link, debug certificate). Endpoints
  `POST /auth/telegram/native/start`, `/native/link/start`, `/native/exchange`. The native callback
  may omit `state` (Telegram's SDK sends none); a conflicting state is rejected, and the S256 PKCE
  verifier plus nonce bind the code to the active attempt. The flow is committed as consumed before
  the provider exchange; an uncertain result needs a fresh approval, never an automatic retry.
  iOS is not implemented.
- **Onboarding:** a verified identity creates an onboarding-only profile; banking authorities are
  withheld until first and last names are submitted (`PATCH /auth/profile`). `/auth/me` reports
  `profileComplete`, names and `telegramLinked`. A profile does not open a financial account itself.
- **Connecting methods:** an email customer can connect Telegram within 10 minutes of recent
  authentication; a new Telegram user can attach to an existing email profile by proving the email
  (the provisional profile is disabled, sessions revoked); a Telegram user can add a recovery email.
  Complete profiles with independent banking history are never merged automatically.
  Routes: `/auth/email/request`, `/auth/email/verify`, `/auth/email/link/request|verify`,
  `/auth/telegram/link/start`, `/auth/telegram/callback`.
- **Profile photo (V12):** authenticated own-photo GET/PUT; JPG/PNG ≤ 5 MB; normalized server-side.
  The shell shows a live initial until a photo exists.

## 3. App PIN (V13)

- After sign-in and profile completion the app requires Create + Confirm PIN, or Enter PIN. Four digits,
  leading zeros valid, account-level; each installation keeps its own revocable session ticket.
- Five wrong submissions lock PIN verification until identity recovery. The budget is persisted on the
  server across restarts, concurrency and fresh logins; there is no client cooldown to bypass it.
  The same budget is shared by transfer proofs, PIN change, and Merchant approvals.
- **Forgot PIN:** discards the ticket; verified email/Telegram, then a new PIN. A freshly verified
  session that has never unlocked may recover for 10 minutes. Reset revokes other sessions.
- Routes `POST /auth/pin/prepare | status | setup | unlock | discard`: the opaque 256-bit ticket (hashed in
  PostgreSQL, session/device bound, never in a URL) is the credential. Unlock advances an access-token
  epoch so older tokens die. PIN hash = BCrypt over domain-separated HMAC-SHA256(customerId, pin) with
  server-only `app.pin.pepper`. PIN change: `POST /auth/pin/change` (verifies the current PIN, revokes
  other sessions); profile edit of completed profiles: `PUT /auth/profile/details`.
- **Client behavior (Phase 4.5):** launch with an existing PIN shows a masked Home (`$••••`, no accounts
  or transactions); any feature, the bottom bar or the balance toggle opens the PIN pad; back returns to
  the masked Home. A session locks after **3 minutes** idle or away; transfers always ask the PIN again
  at confirm. A partially typed PIN clears when backgrounded; the privacy cover hides content while
  inactive. Web uses memory-only storage. The native vault stores only the ticket, never the PIN or a
  PIN-enabled refresh token.

## 4. Accounts and test funding

- Every customer gets exactly one USD and one KHR `WALLET` automatically at signup and profile completion
  (V16, user decision, same transaction). Legacy customers without wallets use **Open accounts**.
- `POST /accounts/pairs` (`Idempotency-Key`, `{accountType:"SAVINGS"}`) creates only missing wallets and
  always returns the full pair, USD then KHR, never a third wallet and never tops up an existing one.
  `testFundingApplied` is true only when every returned wallet carries its opening credit.
  `GET /accounts/opening-policy` reports the funding policy. Legacy `POST /accounts` stays zero-funded.
- With `TEST_OPENING_FUNDING_ENABLED=true` (local/dev/test/staging only): new USD wallet 200.00, KHR wallet
  100,000, as DEPOSIT with operation `TEST_OPENING_CREDIT`; shown as income in Analytics. Restart, login,
  refresh and replay never add funds. The public deposit endpoint is staff-only.
- Native paired-opening requests are saved in secure storage before sending so a lost response is
  retried with the same key.

## 5. Transfers (manual) and recipients

- Exact-decimal internal transfers between Kesor accounts, with `Idempotency-Key`. **Cross-currency both
  ways at a fixed 1 USD = 4,000 KHR; KHR→USD credit rounds down to whole cents.** `GET` quote endpoint
  previews conversion on the review screen.
- The transfer PIN is asked at confirm and on retry; the backend issues one-time transfer PIN proofs and
  enforces them in dev (`TRANSFER_PIN_REQUIRED`).
- `GET /accounts/lookup?number=` resolves another active Kesor account to the holder's full profile name
  and photo (rate-limited, audited; business wallets are never resolved). Home and saved
  recipients show names/photos instead of numbers.
- History names the counterparty ("Kesor Bank" with the logo for bank postings, "Between your accounts").
  Remarks and account numbers are no longer titles.
- The unresolved-payment safety journal persists across PIN locks and restarts; an unknown outcome is
  never resubmitted automatically — the user retries the exact original request and key. Only one
  unresolved manual/QR payment at a time.
- Home **Favorite Recipients** shows only favorites added manually (10–20 digit number, optional name ≤ 40
  chars, stored per user on the device). Transfer-screen "Save to Favorites" bookmarks stay separate.

## 6. QR payments (internal Kesor QR only)

- **Receive:** *My QR* opens a full-screen dark sheet with a wallet drop-down, reusable static QR, and
  **Request an amount** for a one-time fixed request (distinct server reference each time). Save (MediaStore
  `Pictures/Kesor Bank`, Android 10+) and Share (FileProvider) render the card PNG. QR modules stay dark on
  white because inverted codes scan unreliably.
- **Scan:** camera or local JPG/PNG import (≤ 5 MB, ≤ 16 MP); decoding is local, only QR text goes to the API,
  no scanned URL is opened. Camera stops after detection, inactivity and navigation.
- **Routes** (`/payments`): `POST /qr/generate`, `POST /qr/scan` (validates, returns verified recipient, moves
  no money), `POST /qr/transfer` (`Idempotency-Key`; returns the transaction receipt),
  `GET /verify/{hash}` (owner-only fixed-request status; polled only while visible and unlocked).
- Fixed requests are locked while settling, so concurrent payers cannot both succeed; static QR is never
  consumed. Static payments need an entered amount; fixed requests cannot be altered. Business wallets are
  refused here (`MERCHANT_QR_IN_MERCHANT_APP`).
- A scanned **Merchant** QR returns `merchant {merchantId, storeName, categoryCode, hasLogo, verified}`; the
  screen shows the shop name, logo and a *Verified Kesor shop* badge (§9).
- No Bakong/KHQR certification or external settlement is claimed.

## 7. Monthly Analytics

`GET /analytics/monthly-overview?year&month&currency` (customer token; owner from the token). Combines the
customer's accounts in the currency, including frozen/closed history; only `SUCCESS` transactions count;
income = money from outside the customer's accounts, expense = money out; transfers between the customer's
own accounts are excluded; fees are zero; no conversion or cross-currency total. Month bounds use
`Asia/Phnom_Penh` (inclusive start, exclusive next month). Response: `month`, `currency`, `timeZone`,
`totalIncome`, `totalExpense`, and a complete ordered `daily[]`. Legacy `/daily`, `/monthly-summary`,
`/semester-comparison` keep their shapes.

App: injectable `AnalyticsGateway` (API or explicit demo, never an error fallback); defaults to the current
Phnom Penh month, USD, Expense; at most 24 snapshots cached in memory; cache invalidated by transfers and
account opening. Chart is a `CustomPainter` (no chart package) with exact integer scaling, accessible daily
values, tap/hover details and keyboard arrows. The large faded lotus area at the top is intentional.

## 8. AI assistant (read-only)

Interprets questions, retrieves the authenticated customer's data, renders verified cards, and may add a
short Gemini explanation. It **cannot** prepare or submit a payment.

- **Capabilities:** balances (customer-wide totals + up to ten account links per currency); transaction search
  (date, currency, exact amount, direction, type, status, reference, account; default current month, ranges
  ≤ 366 days); receipt details; monthly cash flow (reuses Analytics); approved EN/KM help from
  `backend/digital-banking/src/main/resources/ai/kesor-help-v1.json`. Category spending, budgets, goals, voice,
  conversion and payment execution are out of scope.
- **Provider:** Gemini via Spring `RestClient`, `x-goog-api-key`, stateless, no redirects, no agent loop.
  At most two provider calls per turn (intent extraction, optional explanation); 25 s overall deadline,
  10 s read, 3 s connect, no retries, 2,048 output tokens, two concurrent calls per instance. Limits:
  2,000 chars/question, 10 turns/min and 100/day per customer. Full account numbers/references use opaque
  aliases; names, emails, phones, links and tokens are stripped; labelled PIN/OTP/password input is rejected.
  Explanations may only reference verified fact placeholders; on failure verified cards are returned with
  `explanationStatus=FALLBACK`. Flags default off: `GEMINI_ENABLED`, `GEMINI_CUSTOMER_CONTEXT_ENABLED`
  (operator assertion that billing/data handling is reviewed).
- **Routes:** `GET /ai/capabilities`; `GET|POST /ai/conversations`; `PATCH|DELETE /ai/conversations/{id}`;
  `GET|POST /ai/conversations/{id}/messages` (POST needs `Idempotency-Key`, `{message, locale en|km, context}`,
  201 or 202 while pending); `GET /ai/conversations/{id}/requests/{key}` (never calls Gemini);
  `GET /transactions/search`. Card types `BALANCE MONTHLY TRANSACTION HELP MORE`; actions are server-created
  (`ACCOUNT ACCOUNTS TRANSACTION ANALYTICS HELP_SCREEN MORE`). Errors: `AI_UNAVAILABLE AI_TIMEOUT
  AI_INVALID_RESPONSE AI_RATE_LIMITED AI_PROVIDER_RATE_LIMITED AI_BUSY AI_SENSITIVE_INPUT
  AI_IDEMPOTENCY_CONFLICT AI_REQUEST_IN_PROGRESS AI_REQUEST_INTERRUPTED`. Legacy `/ai/chat` is kept.
- **Persistence (V15):** `ai_conversations`, `ai_requests`, `ai_messages`, `ai_usage_limits`; one pending turn per
  conversation; pending older than 2 minutes reported interrupted; messages expire after 30 days with daily
  cleanup. Flutter uses a 35 s AI client, saves only the pending question/key before sending, recovers lost
  responses by status reads, polls every 2 s (≤ 30 s) while visible, and never auto-resends.
- **Live status:** several Gemini models stalled or returned 503 (provider capacity). `gemini-3.5-flash-lite`
  answered in ≤ 3.6 s; six Khmer turns completed correctly (balance cards, help, refusal of out-of-scope advice).
  Unverified: any `explanationStatus=AI` prose, an English-locale turn, a monthly summary, a payment-request
  refusal. Config availability is not provider health. Keep the key private.

## 9. Merchant touchpoints in the Customer App

- **Sign-in approval:** `kesorbank://merchant/approve` → approval screen naming Kesor Merchant and the device,
  fresh PIN, Approve / Cancel. Survives sign-in, onboarding and PIN gates and process recreation; an active
  request is never overwritten. PIN input clears on privacy/lifecycle changes.
- **Owner-transfer approval:** `kesorbank://merchant/transfer` → exact amount, shop, masked source/destination,
  countdown, *Approve with PIN* / *Decline*. A sibling coordinator, separate from sign-in. Details in
  [MERCHANT_APP.md](MERCHANT_APP.md) §7.
- **Settings → Merchant sessions:** list and revoke the user's own Merchant sessions
  (`GET /auth/merchant-sessions`, `POST /auth/merchant-sessions/{id}/revoke`).
- **Paying a shop:** verified shop name/logo/badge (`GET /payments/merchants/{merchantId}/logo`); expired,
  cancelled, already-paid requests and inactive shops are refused at scan and pay. Receipts/history show the
  shop name for business wallets.

## 10. Home, Wallet, Settings, scanner (UI notes)

- **Home:** three equal actions (Transfer, Scan QR, My QR); balance/transaction amounts stay on one line and
  scale down; Favorite Recipients; recent activity with photo/initial + counterparty name + amount + time.
  Header keeps the Figma layout (logo, inbox, My QR) with no profile slot.
- **Wallet & Accounts** (`WalletAccountsScreen`): navy total-balance card with KHR/USD totals and hide toggle,
  actions (Transfer, My QR, Open accounts), wallet tiles with status chips, selected-wallet card.
- **Settings** (Figma `320:308`): profile name/photo/contact editing, PIN change, local Android alert
  preferences with test alert, English/Khmer, System/Light/Dark, FAQ/AI help, support email, demo policy readers,
  confirmed sign-out. Alerts are local and carry no account values; background push does not exist.
- **Scanner:** full camera area, gold viewfinder, Flash and Upload QR pills; QR → verified Transfer handoff.
- Design source: Kesor Bank Figma; Poppins / Google Sans / Noto Sans Khmer bundled; 20 px gutters.

## 11. Android platform notes (do not regress)

- `MainActivity` is `singleTask`; `KesorApplication` owns one lazy, process-scoped Flutter engine and bridges so a
  recreated activity (Samsung has *Don't keep activities* on) reattaches. Telegram, Merchant links, image picking
  and sharing are routed separately.
- `ImagePickerBridge.kt` (channel `com.bank.customer_app/image_picker`) holds the pending Dart result across
  activity recreation (JPG/PNG ≤ 5 MB, copied to `cacheDir/picked-images`). The gallery makes the app *inactive*,
  which raises the privacy cover; a trusted selection is accepted while the cover is up (the 60-second lease and
  lock still apply). `ShareBridge.kt` (`com.bank.customer_app/share`) saves/shares PNGs.
- Process death discards an unfinished Telegram login.
- Camera permission and the iOS camera purpose are declared; iOS code exists but is not built or accepted.

## 12. Schema history (Flyway, additive only)

V2–V9 foundation: users/roles/devices, accounts, transactions, merchants/fraud/AI/audit tables, sessions + OTP,
review hardening, financial integrity + audit, non-finite money rejection (there is no V1). V10 unified auth and
onboarding · V11 native Telegram flows · V12 profile photos · V13 app PIN · V14 account pairs + internal QR requests ·
V15 AI assistant · V16 automatic user wallets + merchant account category · V17 cross-currency + transfer PIN proofs ·
V18 Merchant approval sessions · V19 shop registration · V20 collections + payment requests · V21 owner transfers.

## 13. Verification record and what is still unproven

Last full evidence (4 Nov 2026): backend 234/234, Customer 273/273, analysis clean. Earlier per-feature counts
(PIN 123 backend tests, Analytics 114 backend + 134 Flutter, etc.) are superseded by those totals.
Automated tests use embedded PostgreSQL, a local SMTP fixture and a fake/loopback Gemini; they never send real mail
or use a paid provider.

User-confirmed on device: native Telegram return, Settings appearance/navigation, corrected transfer icons/flags,
the Analytics screen. **Not personally verified:** notification delivery, PIN change/recovery, gallery photo,
camera QR, fresh signup, masked-Home/idle-lock flow, Favorite Recipients, new Home/Wallet UI, live Gemini prose,
iOS, production deployment.
