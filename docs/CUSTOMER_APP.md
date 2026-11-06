# Kesor Bank — Customer App and banking backend

Updated 6 November 2026. Status, rules, setup and commands are in
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
- **Client behavior (6 November 2026):** a returning customer starts on Home with the latest five
  personal-wallet transactions (names, dates, direction/status; amounts masked) and device-local manual
  favorites. Both USD/KHR balances remain masked. Every protected feature, other tab, transaction,
  favorite, Inbox and balance reveal requests PIN; success continues to the selected destination.
  Back/cancel clears that destination. Normal background visits and 3-minute foreground inactivity lock
  the app; trusted bounded image selection remains supported. Backgrounding clears partial PIN input
  and invalidates in-flight unlock results. Transfers still ask for a confirmation PIN.
- `POST /auth/pin/home-preview` accepts the existing opaque ticket in the JSON body, validates its
  customer/session/device/expiry and configured, non-recovery PIN, and returns at most five distinct
  personal-wallet transactions. The response contains only reference, counterparty name, timestamp,
  direction, type and status; never amounts, balances, account numbers or remarks. It grants no banking
  tokens, changes no PIN attempts and uses `no-store`. No schema migration.
- Preview transactions stay in memory; favorites use existing per-owner secure storage, saved labels
  and initials (masked account suffix if unnamed). Live name/photo lookups wait until unlock. Loading,
  empty and retry states are separate. Native storage still keeps only the PIN ticket; no PIN or
  PIN-enabled refresh token. Web remains memory-only.


## 4. Accounts and test funding

- **Linked merchant wallets (6 November 2026):** Wallets shows actual personal accounts, followed by
  the owner's merchant KHR/USD accounts from `GET /accounts/me?category=MERCHANT&page=&size=20`.
  No shop/business wallets means no merchant cards or placeholder; signing into Merchant before
  shop registration is not enough. Merchant sign-out does not remove shop ownership. Separate
  read-only controllers keep merchant selection/history out of personal transfer and QR flows.
  Details and receipts are available in Customer; merchant QR and owner-transfer initiation stay
  in Merchant. Loading, retry, stale-balance notice, per-account copy and actual wallet counts are
  supported. See §22 for evidence; the §21 APK does not yet include this source change.
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

- **Receive:** *My QR* opens a full-screen dark overlay over a blurred Home, with separate wallet selector rows, reusable static QR, and
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
values, tap/hover details and keyboard arrows. The 4 November Figma redesign (§14) replaces the earlier
large faded lotus header with a flat title and currency selector.

4 November 2026: generated `frontend/customer_app/assets/analytics/khmer-money-planning.png`
as an optional Analytics header illustration: a Khmer woman reviewing a journal and chart beside
the Phnom Penh riverside, matching the existing watercolor artwork and navy/gold accents.
The PNG has transparent edges. Asset delivered separately; screen integration remains unchanged.

5 November 2026: generated `frontend/customer_app/assets/analytics/monthly-money-overview.png`
with the built-in image generator for the whitespace above the month selector. Prompt: isolated
navy wallet, gold coins and a miniature bar/line chart, pale lavender/cream accents, compact
landscape composition, transparent background, no text. Delivered as a separate optional asset;
not wired into the screen.

5 November follow-up: `monthly-money-overview-watercolor.png` is a separate transparent
1536×1024 variant, redrawn with the built-in image tool to match the user's watercolor
Phnom Penh reference. Prompt: preserve wallet, coins and chart; use fine hand-drawn details,
pigment washes, paper texture within painted shapes and soft transparent edges. Original
preserved; neither variant is integrated into the screen.

5 November color revision: `monthly-money-overview-watercolor-gold.png` changes the purple/blue
background wash and lavender chart baseline to light gold, preserving the watercolor subjects
and transparent edges. Built-in image edit prompt: change only the background wash to pale
champagne gold and the baseline to gold; preserve composition and details. Separate 1536×1024
RGBA PNG; previous variants preserved; no screen integration.

## 8. AI assistant (read-only)

Interprets questions, retrieves the authenticated customer's data, renders verified cards, and writes a
short model-written answer. It also answers **general money questions** (education + budgeting tips) with no
customer data. It **cannot** prepare or submit a payment.

- **General guidance (5 Nov 2026):** intent adds `TOTALS`, `COMPARE`, `GENERAL` and a `general` flag.
  `GENERAL` turns read **no** customer data and send the model only the sanitized question; the server appends
  "General information only, not financial advice." and sets `Answer.mode=GENERAL`. A data question that also asks
  for tips (`general=true`) is `MIXED`: verified cards plus brief tips, same disclaimer. Specific stocks, crypto,
  loans, insurance, tax actions, payments and off-topic requests stay `UNSUPPORTED`. `Answer.mode` is null for
  data/help answers and for answers stored before the field existed (Flutter treats null as the old behaviour).
- **Number checking (`AssistantEngine.render`):** the composer returns text with `{{fact}}` placeholders. With
  customer facts, prose may contain **no digits (Latin or Khmer), `%`, currency symbols/codes, status words or
  magnitude words**, and needs at least one placeholder; every figure, change and percentage is computed by the
  server (`TOTALS`/`COMPARE` facts). `GENERAL`-only text may use ordinary numbers (e.g. 50/30/20) but no
  placeholder and no 6+ digit run. All modes reject links, `@`, braces, directives to send money/contact someone,
  and any sentence that mentions a PIN/OTP/password without a negation. Failure: data turns fall back to verified
  cards (`FALLBACK`); a `GENERAL` turn returns `AI_INVALID_RESPONSE` (nothing verified to show). Known limit:
  spelled-out small numbers in prose cannot be detected reliably; the prompt forbids them.
- **New tools:** `TOTALS` sums the Monthly Analytics daily rows over a date range (≤ 366 days, per currency, never
  mixed), so it always matches Analytics; facts `<CUR>_income|outgoing|net|avg_daily_outgoing`. `COMPARE` compares a
  month with the previous one (`<CUR>_*_change`, `_outgoing_change_pct` only when the previous outgoing is non-zero,
  `current_month_note` while the month is open). Largest/count per period and counterparty names are not yet included.

- **Capabilities:** balances (customer-wide totals + up to ten account links per currency); transaction search
  (date, currency, exact amount, direction, type, status, reference, account; default current month, ranges
  ≤ 366 days); receipt details; monthly cash flow (reuses Analytics); approved EN/KM help from
  `backend/digital-banking/src/main/resources/ai/kesor-help-v1.json`. Category spending, budgets, goals, voice,
  conversion and payment execution are out of scope.
- **Provider (changed 5 Nov 2026: Gemini removed):** any **OpenAI-compatible chat-completions gateway**, by default **Groq**
  (`https://api.groq.com/openai/v1`, model `qwen/qwen3.8-27b`, `POST {base}/chat/completions`, `Authorization: Bearer <key>`),
  via Spring `RestClient` (`GatewayAdapter`), stateless, no redirects, no agent loop. `AI_JSON_MODE=schema` (default) sends
  `response_format` strict `json_schema` (Groq supports it on qwen/gpt-oss models), `object` sends `json_object`, `prompt` only
  instructs; a markdown fence/preamble or inline `<think>…</think>` is stripped, and every reply is still validated strictly.
  `AI_REASONING_EFFORT` (default `none`, fastest on qwen; gpt-oss accepts only `low|medium|high`; blank = not sent). The key is
  only sent over HTTPS or to a loopback host. `model` must exactly match an id from `GET {base}/models`. Model choice: Qwen3
  officially lists Khmer; a third-party model card reported heavy language bleed for gpt-oss-120b in Khmer (thin evidence).
- **Language check (`AssistantEngine.requireLanguage`):** a `km` answer must be mostly Khmer script (Khmer letters ≥ 2× Latin
  letters, so terms like PIN/QR are fine); an `en` answer must contain no Khmer; any other script (Thai, Chinese, Cyrillic…)
  rejects the answer. Rejection = `FALLBACK` to verified cards, or `AI_INVALID_RESPONSE` for a general-only turn.
  At most two provider calls per turn (intent extraction, optional explanation); 25 s overall deadline,
  10 s read, 3 s connect, no retries, 2,048 output tokens, two concurrent calls per instance. Limits:
  2,000 chars/question, 10 turns/min and 100/day per customer. Full account numbers/references use opaque
  aliases; names, emails, phones, links and tokens are stripped; labelled PIN/OTP/password input is rejected.
  Text about customer figures may only reference verified fact placeholders (see *Number checking* above); on failure verified cards are returned with
  `explanationStatus=FALLBACK`. Settings (backend `.env`): `AI_API_URL`, `AI_API_KEY`, `AI_MODEL`, `AI_ENABLED`, `AI_CUSTOMER_CONTEXT_ENABLED` (flags default off;
  the second is the operator assertion below)
  (operator assertion that billing/data handling is reviewed).
- **Routes:** `GET /ai/capabilities`; `GET|POST /ai/conversations`; `PATCH|DELETE /ai/conversations/{id}`;
  `GET|POST /ai/conversations/{id}/messages` (POST needs `Idempotency-Key`, `{message, locale en|km, context}`,
  201 or 202 while pending); `GET /ai/conversations/{id}/requests/{key}` (never calls the provider);
  `GET /transactions/search`. Card types `BALANCE MONTHLY TRANSACTION HELP MORE`; actions are server-created
  (`ACCOUNT ACCOUNTS TRANSACTION ANALYTICS HELP_SCREEN MORE`). Errors: `AI_UNAVAILABLE AI_TIMEOUT
  AI_INVALID_RESPONSE AI_RATE_LIMITED AI_PROVIDER_RATE_LIMITED AI_BUSY AI_SENSITIVE_INPUT
  AI_IDEMPOTENCY_CONFLICT AI_REQUEST_IN_PROGRESS AI_REQUEST_INTERRUPTED`. Legacy `/ai/chat` is kept.
- **Persistence (V15):** `ai_conversations`, `ai_requests`, `ai_messages`, `ai_usage_limits`; one pending turn per
  conversation; pending older than 2 minutes reported interrupted; messages expire after 30 days with daily
  cleanup. Flutter uses a 35 s AI client, saves only the pending question/key before sending, recovers lost
  responses by status reads, polls every 2 s (≤ 30 s) while visible, and never auto-resends.
- **Live status:** history with Gemini (now removed): several models stalled or returned 503; `gemini-3.5-flash-lite` answered
  Khmer intent turns in ≤ 3.6 s. **Groq has not been called live yet** (Rayu Code was dropped: its API needs a paid plan) (adapter proven only against a loopback
  fixture). Unverified: latency, JSON reliability and Khmer quality of the chosen model, any `explanationStatus=AI` prose,
  English turns, `TOTALS`/`COMPARE`/`GENERAL`. Config availability is not provider health. Keep the key private.

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

- **Home:** three equal actions (Wallet, Scan QR, Transfer); balance/transaction amounts stay on one line and
  scale down; Favorite Recipients; recent activity with photo/initial + counterparty name + amount + time.
  Header keeps the Figma layout (logo, inbox, My QR) with no profile slot.
- **Wallet** (`WalletAccountsScreen`): personal KHR/USD cards, account copy controls, and the owner's
  actual merchant KHR/USD cards when registered (§22), plus per-currency guidance. Tap a wallet for details; existing
  profile, account-opening and activity actions remain below the cards.
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
Automated tests use embedded PostgreSQL, a local SMTP fixture and a fake/loopback AI gateway; they never send real mail
or use a paid provider.

User-confirmed on device: native Telegram return, Settings appearance/navigation, corrected transfer icons/flags,
the Analytics screen. **Not personally verified:** notification delivery, PIN change/recovery, gallery photo,
camera QR, fresh signup, masked-Home/idle-lock flow, Favorite Recipients, new Home/Wallet UI, live gateway prose,
iOS, production deployment.

## 14. Customer Figma section redesign — 4 November 2026

Source: Kesor Bank file `Mkhqgqnt1SQoq4pn9INLY5`, section `387:6034`.
All five frames were inspected with high-fidelity design context and source renders:

| Figma frame | Flutter implementation |
| --- | --- |
| Home `387:6035` | Existing `KesorHomeScreen`: Wallet / Scan QR / Transfer actions, refined glass tiles, current motif and navigation artwork. My QR remains in the header. |
| Wallet `387:6617` | `WalletAccountsScreen` and `FigmaWalletCard`: KHR then USD cards, balance and number copy, Merchant Wallet explicitly unconfigured, currency information. Tap a live card for account details. Existing profile, activity and account-opening actions remain below the main content. |
| Analytics `166:177` | Flat white page, title/subtitle, KHR/USD segmented control, month controls, pale summary cards, interactive daily chart and cash-flow rows. Existing exact amounts, cache, stale/error states and daily-value access remain. |
| AI Assistant `385:2708` | Standalone page with Back, centered emblem, live first name, welcome headline, three working suggestions, ambient gold glow and inset composer. Floating navigation is hidden here. Conversation history opens from the welcome emblem; history/new-chat controls appear during a conversation. Recovery, privacy and PIN-lock behavior remain. |
| My QR `328:458` | Real Home backdrop blurred behind the dark overlay, gold/navy QR card, optional amount, both live wallet selector rows, Save/Share and Close. QR is generated from the server payload, never from the Figma sample code. |

Assets: 28 unchanged SVG exports (~53 KB) in `assets/figma`; exact matching original
Home assets reused. The folder README maps exports to source frames. Static source
screenshots are not bundled or rendered as UI. No temporary Figma URLs are runtime dependencies.

Data limits: the monthly API has income/expense and daily totals, **not payment-method
categories**. The two breakdown rows therefore show real income/expense totals rather
than inventing QR-payment percentages from the sample design. The Merchant Wallet
placeholder does not assert that a shop wallet is configured or expose Merchant-session APIs.

Responsive evidence lives in `tool/customer_figma_visual_qa.dart`, covering every frame,
English/Khmer, both themes, 1×/1.3×/2× text, phone/landscape/tablet and scrolling to the
bottom. Automated result: **273/273 Customer tests**, plus focused checks after final spacing
adjustments; **300 responsive renders without layout exceptions**, and clean analysis. Evidence logs and renders:
`frontend/customer_app/.local/qa/figma-redesign/`.

Uncommitted. No APK build/install, backend restart, live database action or real payment.
Native device appearance and personal acceptance remain pending.

## 15. Transfer success screen — 5 November 2026

Updated the existing success screen against current Figma frame `308:740` (440 × 956):
148 × 126 gold seal slot, 64px amount, original receipt, navy Home action and secondary
transfer action. The existing transparent seal artwork and corrected currency flags are reused.
This supersedes the older 440 × 978 success measurements in the screen-level transfer notes.

Success has no page scroll. Status/bottom safe areas and both actions remain outside the
content fitting transform; action targets stay at least 48px tall. Short screens reduce
decoration/receipt spacing first, then fit the complete confirmation, receipt and recovery
messages into the remaining height. Long names, references and remarks wrap without truncation.
Landscape uses confirmation/receipt and actions side by side. Extreme height/text combinations
necessarily shrink receipt text to retain the requested single-screen presentation; device
font/accessibility settings are unchanged. Review and transfer entry retain their scrolling.

Verification: updated `tool/transfer_flow_visual_qa.dart` checks full-screen visibility,
receipt/action separation, unscaled action target sizes, no success page scroll and taps on both
actions, including native safe insets, EN/KM, USD/KHR, both themes, 1×/1.3×/2× text, long details,
small phones, landscape and tablet. Local renders/logs are in `.local/qa/transfer-flow/` and
`.local/transfer-success-*.log`. Automated results are recorded in the progress guide.
Final result: **276/276 Customer tests**, **60 fixture renders** (20 success variants),
and clean analysis/diff checks. Representative final images were inspected against Figma.

Uncommitted. No APK build/install, device acceptance, backend restart, database change or payment.


## 16. Separate QR entry and Analytics Figma redesign — 5 November 2026

Implemented the two frames in Figma section `413:6086`, file
`Mkhqgqnt1SQoq4pn9INLY5`: QR transfer `404:901` (440 × 957) and Analytics
`413:5956` (440 × 956). Source remains **uncommitted**.

- **QR entry:** `QrTransferScreen` is a dedicated view within the existing transfer host.
  Camera/gallery verified handoff keeps `TransferPrefill`; manual/favorite entry keeps its
  previous design. Navy recipient header, real person/shop identity and imagery, cream
  amount panel, KHR/USD paying-wallet selection, available balance, remark dialog, decimal
  keypad and disabled-at-zero Transfer follow the reference. USD precision is two decimal
  places; KHR is whole units. Changing a static payment's currency clears its debit entry.
  Fixed requests are immutable, use `exactDebitFor`, and block inexact conversion. Review,
  PIN proof, persisted original-key retry, owner cleanup and receipt remain shared. Pending
  payments and secure-storage recovery retain the existing recovery UI rather than being
  replaced by a new scan. Merchant verification badge and its existing test identifier remain.
- **Analytics:** pale header, exact Figma wallet illustration at the 236 × 157 reference slot,
  navy selected currency pill, white panel with 36px top corners, paired totals and bordered
  daily chart. Removed the extra cash-flow rows absent from this frame. Existing monthly
  API/controller, integer-based chart scale, currency/month/series state, cache/invalidation,
  loading/error/stale/empty states, accessible daily-value sheet and keyboard/tap chart
  interactions remain. Tap the title (Refresh tooltip) to refresh without page scrolling.
  The shell owns the single navigation bar; Analytics caps it to 400px and reserves its
  bottom clearance. Tall tablets retain the chart's reference height instead of stretching it.
- **Fit policy approved by user:** no page scrolling or new stacked rows on either screen;
  compact spacing, decoration and locally fitted text. QR keypad/Back/Transfer targets are
  at least 48px in the tested portrait sizes. The user explicitly approved **smaller QR
  keypad targets in short landscape windows** to preserve readable details without scrolling
  (about 18–21px in the tested native-inset landscape fixtures). Wallet/currency/remark rows
  also compact with their containing details area. Tablet QR composition is centered with
  a 440 × 957 maximum. Native safe areas are respected; fake system chrome is fixture-only.
- **Assets:** exact illustration and QR back/wallet/chevron/backspace assets bundled locally.
  Analytics uses screen-specific Home/disclosure exports where earlier assets differed.
  All 16 used static assets are nonempty; 11 existing/reference SVG hash comparisons are
  exact. No temporary Figma asset URLs are used at runtime. Audit and source references:
  `.local/qa/customer-section-2/asset-audit.json` and `source-comparison.json` in Customer App.

**Automated evidence:** Customer full suite **284/284**; affected Analytics/QR/merchant-payee
checks **25/25** rerun after visual refinements; analyzer and diff checks clean. New fixture
`tool/customer_section2_visual_qa.dart`: **144 renders**, no layout exceptions or page scroll,
paired cards remain in one row, no chart/navigation overlap, portrait main targets ≥48px,
landscape keypad exception checked, keypad → review → edit exercised across sizes/themes.
Matrix: 320×568, 375×812, 440×956/957, 667×375, 844×390, 800×1280; EN/KM, light/dark,
1×/1.3×/2× text, native insets, both currencies, fixed requests and long recipient names.
Existing Analytics fixture also passed (16 PNGs, including series/month variations).
Logs: `.local/section2-all-tests.log`, `section2-final-focused.log`, `section2-final-visual.log`,
`section2-analyze.log`, `section2-diff-check.log`. Reference comparisons and 144 screenshots:
`.local/qa/customer-section-2/` (`comparison.png`, `qr-contact.png`, `analytics-contact.png`).
Screenshots use offline controller fixtures, not live banking values or device evidence.

**Not done:** APK build/install, native device acceptance, camera/gallery hardware round trip,
real payment, backend/DB/live deployment or commit. Existing transfer-success fixes, optional
artwork and Merchant changes were preserved. Next: user visual review, then separately
approved packaging/device acceptance under the project rules.

## 17. Home preview and PIN continuation — 6 November 2026

Implemented the user-approved Home preview behavior in §3. Protected destination handoff covers
balances, tabs, Wallet, Transfer, QR, transaction details, favorite transfer/add/manage and Inbox.
Every normal reopen returns to preview, including a departure during PIN entry. Trusted image-selection
leases, recovery, server attempt budgets, one-time transfer proofs and Merchant approval gates remain.

Source is uncommitted. No APK build/install, deployment, backend restart, live database migration or
real payment. Automated evidence and outstanding device acceptance are recorded in the progress guide.

Verification: Customer full **286/286**, final PIN/preview **11/11**, then font-complete preview
matrix rerun **2/2** (12 EN/KM × light/dark × phone/landscape/tablet renders). Representative renders
inspected. Analyzer and diff check clean. Backend affected auth/contract suites **28/28** after fixing
the new fixture and route-count assertion; initial full run was 259/261 and was not repeated in full.
Logs and native/device acceptance limits are recorded in the progress guide.

6 November deployment follow-up: the backend endpoint is now live on Railway, deployment
`8fc7d198-bdc9-4a93-bd16-793b8c6b9668` (SUCCESS), after a clean **261/261** full backend run.
Schema remains V21. Live OpenAPI, unauthorized account access and invalid-ticket/no-store checks pass.
No authenticated/device acceptance or Customer APK rebuild/install yet. Details: DEPLOYMENT.md §9.

## 18. Transaction and Wallet Detail Figma designs — 6 November 2026

Designed two editable **440×956** screens in the user's Figma working section `422:2062`,
file `Mkhqgqnt1SQoq4pn9INLY5`. Review board: `426:868`; Transaction Detail: `426:993`;
Wallet Detail: `426:877`. Original reference rectangles `422:2057` and `422:2060` remain intact.

- **Transaction Detail:** dimmed USD account history behind a white receipt sheet, merchant icon,
  amount, completion indicator, transaction ID/date/original amount/approval code, View more,
  Share and Download actions. The sheet follows the supplied reference layout.
- **Wallet Detail:** navy balance header with Kesor logo, owner/account identity, available and
  account balances, KHR activity grouped by date, semantic debit/credit colors and Sort transactions.
- **Design system:** existing vector logo, Poppins and Google Sans text styles, bound Kesor
  color variables, local icon/button/payment-row instances; one reusable metadata-row component
  `426:1120` beside the board. No full-screen raster images inside either screen.
- **Evidence:** final composition visually inspected after spacing/action alignment refinements;
  local preview `.local/figma-detail-design/final.png`, ledger `.local/figma-detail-design/state.json`.

These are **Figma designs only**, with illustrative reference content. Flutter implementation,
interactive behavior, runtime tests, builds, device acceptance and deployment were not part of
this task. Existing application work was preserved; documentation is uncommitted.

## 19. Figma Section 3 Flutter implementation — 6 November 2026

Implemented the current section `431:2446` in `Mkhqgqnt1SQoq4pn9INLY5`: Wallets `421:1965`,
Wallet Detail `426:877`, Transaction Detail `426:993`, Customer splash `420:752`. Merchant
splash `418:6159` is recorded in MERCHANT_APP.md §15. This supersedes §18's Figma-only delivery.
The user's subsequent removal of detail-header logos, completion badge and Wallet Detail Sort
action was followed.

- **Wallets:** `wallet_accounts_screen.dart` / `figma_wallet_card.dart` match the reference cards,
  original icons, currency note and copy geometry, with 48px copy targets. Existing Profile,
  Open accounts and Activity controls remain below the reference's trailing space. The Merchant
  card remains honestly unconfigured; no business balance is manufactured.
- **Wallet Detail:** new `wallet_detail_screen.dart` uses the selected owned account and existing
  paginated history controller. Navy owner/balance header, date groups and signed semantic amounts;
  refresh, copy, account information and My QR in the account menu. Loading, unavailable, empty,
  frozen/closed and refresh-error states remain visible. Dates use Asia/Phnom_Penh (UTC+7).
- **Receipt:** new `transaction_detail_screen.dart` overlays real wallet history. Reference/date/
  original amount, expandable status/fee/accounts/remark/conversion information, dismissal/back and
  PNG Share/Download use existing services. Non-success status is visible without expanding.
  The API has no approval-code field, so that row says **Unavailable**. Wallet-side and original
  debit currencies stay distinct. Export waits for paint, rechecks the session/reference and
  disposes its image. No new payment operation or backend contract was introduced.
- **PIN continuation:** account/Home initialization completes before an initial receipt lookup.
  The newly authorized Home posting identifies its owned wallet and currency, including KHR.
  A gated-load regression test covers the non-default-wallet case.
- **Splash:** exact exported logo on navy with `.Bank` lettering. Shared `KesorBrandSplash`
  follows the 2-second loop: 120ms hold, opacity complete at 850ms, scale .88→1 at 1050ms.
  Production startup shows it for at least 1100ms and until restoration finishes. Reduced motion
  uses the final static mark. Android pre-Flutter backgrounds use the same navy.
- **Assets/layout:** 29 unique original SVG exports checked across both apps; five Wallet exports
  match existing assets byte-for-byte and are reused. No temporary Figma runtime URLs, full-screen
  raster assets, dependency upgrades or credentials. Native safe areas and scrolling support
  short windows and enlarged text; the device supplies system chrome.

**Automated evidence:** Customer full **294/294** (`.local/section3-all-tests-verified.log`),
analysis clean (`section3-analyze-final.log`); `tool/wallet_details_visual_qa.dart` produced
**288 renders without layout exceptions**, with receipt-action reachability checked: six viewports,
EN/KM, light/dark, 1×/1.3×/2× text. PNGs: `.local/qa/section3/`; log: `section3-visual-verified.log`.
Reference and representative compact/large-Khmer views inspected. New tests cover date grouping,
row navigation, exact converted/pending amounts, metadata expansion, error/retry/export gating,
actual PNG bytes through mocked Android save/share, PIN continuation, motion and reduced motion.
Existing navigation tests follow the new controls while retaining exact data and sign-out checks.
Splash XML parses; diff check clean. Asset/context evidence: repository `.local/figma-detail-design/`.

**Acceptance limits:** source is uncommitted. No APK build/install, physical-device launch or
MediaStore/share-sheet check, real payment, backend restart, migration or deployment. Fixture
images contain illustrative data; they are not device captures or a certified pixel-diff baseline.
Next: user visual review and separately approved APK/device acceptance.

## 20. AI Assistant Figma redesign — 6 November 2026

Implemented the current `385:2708` in `Mkhqgqnt1SQoq4pn9INLY5`, reference 440×999.
Welcome copy, Poppins Light headline, updated original identity SVG, faint gold glows and
bottom composer follow the design. Exact reference anchors are asserted: emblem y154,
question carousel y821, composer y887. The 44px Back circle keeps a 48px touch target;
its title aligns at x72. Native system chrome is not painted into the app.

Exactly three horizontally scrollable suggestions are shown, with localized Khmer equivalents:

- How much did I spend this week?
- How does the 50/30/20 rule work?
- Show my biggest payment this month

Each tap sends immediately through the existing assistant controller. Tests assert the exact
request message, response rendering and rapid-tap duplicate prevention. Existing availability,
pending-request recovery, history, privacy, keyboard and PIN-lock behavior remain. The full
privacy disclosure is available in conversation history; the reference security reminder stays
below the composer. Short windows and large text retain the same vertical/horizontal ordering
with bounded scrolling; all three questions remain reachable. Tablet composition stays centered
at the reference width. No backend/model/gateway changes or manufactured answers were added.

**Evidence:** full Customer **298/298**, focused assistant **16/16**, analysis clean, diff check
clean. `tool/assistant_visual_qa.dart` rendered **72 variants** across six sizes, EN/KM,
light/dark and 1×/1.3×/2× text with no overflow and all suggestion targets reachable.
Original assets are nonempty and exact; reference and compact/large-Khmer PNGs inspected.
Logs: `.local/assistant-redesign-all-tests.log`, `assistant-redesign-analyze.log`,
`assistant-redesign-focused.log`, `assistant-redesign-visual.log`, final repeat
`assistant-redesign-final-check.log`. PNGs and asset audit: `.local/qa/assistant-redesign/`.

Source is uncommitted. No APK build/install, native-device or live-provider acceptance,
backend restart, migration or deployment. Existing in-progress work was preserved.

## 21. Updated Railway APK — 6 November 2026

User authorized building both updated APKs. Customer debug build succeeded with `APP_ENV=dev`,
`APP_MODE=api` and `API_BASE_URL=https://backend-production-18646.up.railway.app/api/v1`, using
the current uncommitted source (base `e6c58b6`). Includes the latest Assistant, Wallets,
Wallet/Transaction Detail, QR/Analytics, transfer-success, Customer splash and PIN Home preview work.

- Current APK: `frontend/customer_app/.local/apk/Kesor Bank.apk`; versioned copy:
  `frontend/customer_app/.local/apk/20261106-055520/Kesor Bank.apk`.
- Size: **245,521,948 bytes** (234.15 MiB); SHA-256:
  `6F74DCEED6FCB7CA10030E9B2B784D469BBEF1B26DE10ED3C867A803D433A214`.
- Package `com.bank.customer_app`, version `1.0.0+1`; signature valid and matches the prior APK.
  Railway URL, all three exact suggested questions, detail-screen/splash classes and selected original
  design assets verified inside the package; old Wi-Fi IP absent, zero `.env` entries, ZIP CRC clean.
- Previous APK preserved under `.local/apk/archive/20261106-055520-previous-d57d261ebee8/` in this app.
  Shared build evidence: repository `.local/apk-refresh-20261106-055520/`, including source manifests,
  build/signature/package logs and `verification.json`. All 550 recorded app/shared inputs unchanged.

Existing test baseline remains **298/298** with clean analysis (§20); no source changes or test rerun
were needed for packaging. Gradle stopped after the build. Railway read-only probes passed
(Swagger 200, accounts without authentication 401). No installation, native/device or live-provider
acceptance, backend change, migration, payment or commit. This supersedes earlier APK-pending notes;
device acceptance is still outstanding.

## 22. Linked merchant wallets in Customer — 6 November 2026

Removed the unconditional empty Merchant Wallet card and hardcoded extra wallet count. Real
business wallets appear after personal wallets, KHR then USD, with merchant/currency labels,
exact balances, account status and functional account-number copying. Account parsing retains
`accountCategory` and `merchantId`, defaults older personal fixtures to `WALLET`, and rejects
invalid merchant data. No backend API, authorization, schema or Merchant App source change.

`MerchantWalletSource` provides paged reads through the existing Customer-session accounts route;
`MerchantWalletGateway` validates merchant-only results and rejects account creation. The shell
uses independent account/history controllers, an in-memory unused creation store and separate
merchant detail/receipt routes. Personal Home, transfers and QR keep their original controllers.
Merchant details retain account information, activity pagination, receipts and back navigation;
personal My QR is absent. Lists refresh on Wallets entry and pull-to-refresh; failed reads retain
old values with an explicit stale notice and separate retry. Session invalidation clears memory
and request generations ignore delayed results. Empty complete refreshes remove old merchant cards.

- Full Customer suite **307/307**; new merchant-wallet tests **9/9**. Covers exact HTTP category,
  auth/paging and money parsing; unregistered/registered states and entry refresh; merchant read-only
  enforcement; separate selection; pagination; errors/retry; masking/copy; sign-out and out-of-order
  responses; both currencies' detail → receipt → detail → Wallets and personal-history isolation.
- Analyzer clean; diff check clean. Visual fixture **96 renders**, linked/unlinked/business-scroll/
  merchant-detail states at 320×568, 393×852 and 800×1280, EN/KM, light/dark, 1×/2× text. No layout
  exceptions; all four contact sheets and representative full-size images inspected.
- Evidence in this app: `.local/merchant-wallets-{focused,all-tests,analyze,visual}.log`,
  `.local/qa/merchant-wallets/`; reproducible fixture `tool/merchant_wallets_visual_qa.dart`.
- Uncommitted. Existing APKs unchanged; no build/install, authenticated live/device acceptance,
  backend restart, migration, deployment, payment, commit or push. Backend/Merchant suites were
  not rerun because their source and contracts are unchanged. Next: separately authorized Customer
  APK packaging and device verification against the same owner's live Merchant wallets.

## 23. Shared Merchant sign-in diagnostics — 6 November 2026

The shared `HandoffApi` preserves HTTP status on malformed/non-JSON responses. Both Android
Merchant bridges return distinct missing-app, signature-mismatch, unsupported-build and
app-opening errors while retaining the existing pinned certificate/package/debug/URI checks.
Customer approval/PIN rules and backend contracts are unchanged; Merchant's error classification,
safe Copy error details action and retry fixes are documented in Merchant §18.

Customer handoff/payment tests **38/38** pass (`merchant_approval`, `merchant_resume`,
`merchant_transfer`, `merchant_payee`); Customer analyzer clean. Native `:app:compileDebugKotlin` succeeds without Flutter
compilation or APK assembly. Gradle daemons stopped; existing deprecation warnings remain.
Evidence in this app: `.local/merchant-auth-{customer-handoff,analyze,kotlin}.log`. Full Customer
**307/307** remains the preceding wallet-change baseline; it was not rerun for this transport-only
change. Merchant's current full suite is **144/144**, with **192** responsive error-screen renders.

Uncommitted; no backend changes, APK packaging/install, device/live acceptance, deployment or
real authentication/payment. Existing APKs are unchanged and do not include these fixes or §22's
wallet change. The friend's exact failure needs reproduction with the updated diagnostic UI.
