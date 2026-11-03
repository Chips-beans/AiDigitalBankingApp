# Kesor Merchant — implementation plan and milestones

Date: 31 October 2026, Asia/Phnom_Penh.
Status: M0-M3 complete for development; M4 source/automated complete (device acceptance pending); M5-M9 not started; M10-M13 deferred.
Audit decisions and contracts: [MERCHANT_M0_CONTRACTS.md](MERCHANT_M0_CONTRACTS.md).
Current evidence/checkpoint: [MERCHANT_APP_PROGRESS.md](MERCHANT_APP_PROGRESS.md).
This plan does not authorize production deployment. Milestone evidence and acceptance limits are recorded in the progress/handoff documents.
Current customer-app work remains on `kesor-phase4-fixes`, based on `e1a9da2`.

## 1. Agreed product requirements

- Separate Android-first Flutter Merchant App, sharing the existing Spring Boot
  backend and PostgreSQL database with the Customer App.
- The only merchant sign-in entry is **Continue with Kesor Bank**. Open the
  Customer App, show explicit approval, confirm with the existing customer PIN,
  then return to Merchant. No Merchant email, Telegram, password, or independent
  identity-registration flow.
- After first sign-in, register a shop. Returning owners open their existing shop.
- Successful shop registration creates exactly one KHR and one USD business
  wallet. Personal wallets remain separate.
- Shop name and shop logo are the merchant profile throughout the app. Editing
  them must not change the customer's personal name or photo.
- Use Kesor colors, fonts and artwork; support English/Khmer, phone/tablet,
  large text, safe areas and reduced motion.
- Build necessary collection, confirmation, sales, receipts, reports, wallet,
  settings and support features around this journey.

## 2. Proposed first-release defaults

These are implementation recommendations, distinct from the requirements above.
Record any changes in M0 before the affected work begins.

| Decision | Proposed default |
| --- | --- |
| Owners/shops | One shop per customer for v1; cashier and branch support later |
| Sign-in device | Both apps on the same Android device; cross-device pairing later |
| Session | Separate revocable Merchant session; reuse it until expiry/revocation |
| Sign-in attempt | Two-minute approval/code lifetime; expiry/cancellation starts a fresh attempt |
| Shop fields | Required name, category, phone, city/address; optional description; logo upload with shop-initial fallback |
| Wallet balances | Zero at opening; no automatic customer-style test credit for merchant wallets |
| Shop activation | Internal demo: activate after completed registration; retain suspend/inactivate controls. Reconcile this explicitly with existing PENDING behavior in M0. Production verification policy is a separate future decision |
| Payment network | Internal Kesor payments first; external KHQR/Bakong acceptance later |
| Currency | Separate KHR and USD requests/totals; preserve current customer conversion rules when paying a merchant QR |
| Owner transfers | Same-currency merchant wallet to the owner's personal Kesor wallet; no external withdrawal or merchant FX in v1 |
| Sensitive actions | Fresh, transaction-bound approval using the existing Customer App/PIN; no separate merchant PIN enrollment |
| Confirmation | Foreground status polling first; background push/voice is a later milestone |
| Navigation | Home / Collect / Sales / More; Wallets and Reports accessible from Home |

No delivery dates are promised. Estimate effort after the M0 audit. A milestone
is complete only when its acceptance checks pass, not when its screens exist.

## 3. Existing implementation and gaps

Historical M0 source inspection, not end-to-end merchant acceptance. M2 now closes
the approval/session gap; remaining shop/payment gaps belong to later milestones:

- `module/merchant` has registration, profile reads/updates, account lists,
  administrator status changes and QR configuration.
- Registration assigns ROLE_MERCHANT and calls `createDefaultMerchantAccounts`.
  That method creates dedicated MERCHANT CHECKING accounts for USD and KHR.
- Existing registration accepts an owner ID and merchant QR alias from the client.
  The new owner flow should derive ownership from the authenticated identity and
  allocate the internal alias server-side.
- Registration currently starts PENDING. Actual enum values are PENDING, ACTIVE,
  SUSPENDED, INACTIVE; some controller descriptions use outdated names.
- Merchant wallet creation currently calls the funding service. Audit and separate
  this from the customer's development test-funding behavior.
- Customer account/history routes generally require ROLE_CUSTOMER. Adding Merchant
  access requires session-purpose and account-ownership checks, not blanket role
  expansion across personal APIs.
- Merchant QR configuration is not evidence that the customer scan/payment path
  resolves and settles a merchant account correctly. Prove that in M6.
- Customer Android already uses a retained Flutter engine and `singleTask` for
  Telegram/activity recreation. Extend intent routing without breaking that flow.
- Shop-logo storage, merchant sign-in approval, merchant sessions and merchant
  sales/report APIs are not established by the existing merchant module.

## 4. Milestone register

| ID | Section / deliverable | Depends on | Status |
| --- | --- | --- | --- |
| M0 | Audit, business rules, contracts and baseline | None | Complete |
| M1 | Merchant Flutter shell and shared foundations | M0 | Complete |
| M2 | Backend sign-in approval and Merchant sessions | M0 | Complete (source and isolated verification) |
| M3 | Customer approval and complete app-to-app sign-in | M1, M2 | Complete: automated/APK checks and user-confirmed native round trip + restore |
| M4 | Shop registration, logo/profile and paired wallets | M3 | Source + automated complete; V19 live apply and device acceptance pending ([details](MERCHANT_M4_SHOP.md)) |
| M5 | Dashboard, wallets and navigation | M4 | Not started |
| M6 | QR collection and verified payment confirmation | M5 | Not started |
| M7 | Sales, receipts and collection reports | M6 | Not started |
| M8 | Owner transfers, security and settings | M5, M6 | Not started |
| M9 | Integrated regression, device acceptance and pilot APKs | M7, M8 | Not started |
| M10 | Background push and optional voice | M9 | Deferred |
| M11 | Cashiers, closing/export and controlled refunds | M9 | Deferred |
| M12 | Branches, invoices/payment links and read-only AI | M9; relevant M11 permissions | Deferred |
| M13 | External KHQR/Bakong integration and reconciliation | M9; provider access | Deferred |

Recommended sequence: M0 → M1 → M2 → M3 → M4 → M5 → M6 → M7 → M8 → M9.
M1 and M2 have independent contracts; this plan does not require parallel agents.

## 5. M0 — Audit and contract baseline

**Deliverables**

- Read current handoffs and relevant auth/PIN, QR, account and transaction code.
- Record actual tests, database migrations, active runtimes and working-tree state.
  Historical evidence is 230 Flutter tests and 161 backend tests; recheck rather
  than assume either count remains current.
- Finalize the proposed defaults above, session scope matrix, merchant activation
  rule, registration recovery and financial reporting definitions.
- Specify app IDs, allowed link hosts/paths, callback allowlist and separate
  debug/release signing associations. Reuse a suitable user-controlled domain if
  available; document the real domain requirement before verified-link testing.
- Map existing merchant QR aliases to internal accounts; audit legacy shops and
  wallet duplicates before adding uniqueness constraints.
- Write request/response/error contracts and migration design. Do not assign
  migration versions until the current highest version is checked.

**Acceptance / exit gate**

- Every first-release feature has a contract and milestone owner (backend,
  Customer App or Merchant App), with no independent Merchant sign-in route.
- Existing customer behavior and data preservation requirements are documented.
- Any baseline failure has a recorded cause; no destructive data cleanup is used.

## 6. M1 — Flutter shell and shared foundations

**Deliverables**

- Create `frontend/merchant_app` with its own Android package, app label, icon,
  secure-storage namespace and environment configuration.
- Add Welcome/Continue, sign-in waiting/retry, Register Shop, and the four-tab shell.
- Reuse Kesor palette, type, logo, exact money formatting and networking. Extract
  shared packages incrementally only when necessary; avoid rewriting Customer App.
- Handle loading, empty, offline, unavailable and expired-session states explicitly.
- Keep demo fixtures outside live API-mode success paths.

**Acceptance / exit gate**

- Merchant APK installs alongside Customer App; their storage does not collide.
- The only sign-in action is Continue with Kesor Bank.
- Shell renders in both languages/themes, phone/tablet, landscape and 2x text
  without hidden controls or overflow; Android touch targets are at least 48dp.

## 7. M2 — Backend approval and session protocol

Implementation contract: [MERCHANT_M2_SECURITY.md](MERCHANT_M2_SECURITY.md).
Complete: full backend suite passes 191/191, including 30 new M2 checks and actual
restart recovery. V18 is tested on fresh/upgraded isolated databases; the active
Wi-Fi development backend was not restarted or migrated. M3 loads the migration
for device integration. Exact evidence and runtime boundaries are in the progress report.

**Deliverables**

- Add a server-owned approval attempt bound to the registered Merchant client,
  S256 PKCE challenge, exact callback and expiry. Merchant stores the verifier
  and unpredictable state securely for this bounded attempt.
- Attempt lifecycle: PENDING → APPROVED → CONSUMED; DENIED, CANCELLED and EXPIRED
  are terminal. Define atomic transitions and exchange-response-loss recovery.
- Customer-authenticated APIs show request details and approve/deny. Approval
  requires fresh customer PIN verification and records the approving identity.
- Issue a short-lived, single-use code. Merchant exchanges code + verifier for
  its own access/refresh session. Never send customer tokens or PINs in links.
- Before shop registration, limit Merchant sessions to onboarding/profile/status
  capabilities. After registration, authorize only that owner's merchant resources.
- Enforce session purpose/audience server-side even when the user also has
  ROLE_CUSTOMER. A Merchant token must not inherit personal-wallet access.
- Add refresh rotation, logout/revocation, rate limits and safe audit events.
  No static client secret embedded in either APK.

**Acceptance / exit gate**

- Wrong verifier/state, arbitrary callbacks, expired/denied/cancelled attempts,
  duplicate approvals, reused codes and concurrent exchanges cannot grant access.
- Unauthenticated approvals and approvals without valid fresh PIN proof fail.
- Cancellation/revocation races cannot leave a usable unauthorized session.
- Logs omit approval secrets, codes, tokens, PINs and full callback URLs.

## 8. M3 — Customer approval and app-to-app return

**Deliverables**

- Merchant creates an attempt and opens Customer App using verified App Links.
- Customer App routes the request separately from Telegram and image-picker intents.
- If signed out, complete the existing customer sign-in/onboarding/PIN flow and
  then resume the pending approval while it remains valid.
- Show a clear approval screen naming Kesor Merchant and the customer identity;
  provide Approve and Cancel and use the existing PIN verification.
- Return the one-use code and state to the exact Merchant callback, then exchange.
- Resolve server onboarding status: existing shop → Home; none → Register Shop;
  interrupted registration → safe recovery; suspended shop → restricted status view.
- Provide missing-Customer-App guidance and retry. No alternate Merchant login.
- Add a Customer App view to inspect/revoke Merchant sessions. Merchant sign-out
  revokes its session without signing the customer out of their banking app.
- Support existing-session restore without launching Customer App on every opening.
  Apply privacy cover/re-authentication without creating new Merchant credentials.

**Acceptance / exit gate**

- Real-device round trip works for new/returning/signed-out customers, cancellation,
  expiry, cold start, interrupted return and activity recreation.
- Test with the tablet's existing Don't keep activities setting enabled; leave
  developer/accessibility settings unchanged.
- Unsolicited callbacks, wrong state and replayed links cannot sign in.
- Revoked Merchant sessions lose access; Telegram login and image selection regressions pass.

## 9. M4 — Shop registration, profile and two wallets

**Deliverables**

- Form: shop name, category, phone, city/address, optional description and logo.
  Use the shop initial until a logo exists; edit shop identity independently.
- Owner comes from the approved backend identity. Allocate merchant code and
  internal QR alias server-side; do not require a real Bakong account ID for v1.
- Use an idempotency key for registration; store immutable pending intent securely
  and recover uncertain results without automatically submitting a new shop.
- Save shop + exactly one KHR wallet + exactly one USD wallet atomically. Add
  appropriate database uniqueness/locking after the legacy-data audit.
- Enforce one-shop-per-owner v1 under concurrency, while preserving legacy records.
- Keep merchant opening funding separate from customer development credits.
- Add owner-scoped validated logo upload with limits, normalized storage, preview,
  failure recovery and cleanup of abandoned staged uploads. Blob upload and the
  database transaction are separate operations; only valid owned uploads attach.
- Derive activation/status from server policy, not a client form field.

**Acceptance / exit gate**

- Successful registration returns one shop and two distinct business account numbers.
- Double taps, network loss, restart and concurrent requests create no duplicates.
- Failure creating the second wallet rolls back shop/wallet database changes.
- Merchant wallets start at zero in the normal flow; customer wallets are untouched.
- Invalid/foreign logo references and ownership overrides fail. Shop changes never
  overwrite personal name/photo. Successful edits remain after relaunch.

## 10. M5 — Dashboard, wallets and navigation

**Deliverables**

- Home: shop logo/name, KHR and USD wallet balances, Collect shortcut, recent
  payments and today's collections; distinguish balances from sales.
- Wallet details: currency, account number, balance and read-only activity.
- Home / Collect / Sales / More navigation, Reports entry and status restrictions.
- Use merchant-scoped backend queries. Handle stale/partial data visibly and
  clear private state on logout, revocation or owner replacement.

**Acceptance / exit gate**

- An owner sees only their shop and merchant wallets, never personal or other-shop
  balances through a Merchant session. Server tests reject changed resource IDs.
- Loading/failure never substitutes sample balances. Refresh and navigation retain
  correct business context; inactive shops cannot access collection actions.

## 11. M6 — QR collection and verified confirmation

**Deliverables**

- Collect: amount keypad, USD/KHR selector and optional order reference.
- Backend creates a unique expiring fixed-amount payment request linked to shop,
  receiving wallet, currency and reference. Define idempotent create/recovery.
- Display shop identity, amount/currency, readable QR, expiry and waiting status.
- My Shop QR: reusable QR per currency with Save/Share. Reusable codes identify
  the destination; they do not uniquely match a particular sale/order.
- Adapt customer scan/review so merchant name/logo and registered destination are
  verified server-side. Retain customer transfer PIN, conversion and idempotency.
- Commit payer debit, merchant credit, confirmed receipt, request status and
  durable event together. Amount/currency and merchant status are server-enforced.
- Poll authenticated status while visible, stop on background/expiry/navigation,
  and reconcile from the backend when returning. No client mark-paid endpoint.
- Define PAID, WAITING, EXPIRED, CANCELLED and verification-unavailable UI distinctly.
  Server-side payment-vs-expiry/cancellation races must have one authoritative result.
- Show success/foreground sound only after confirmed payment; deduplicate alerts
  by payment/event ID. A receipt screenshot or notification cannot prove payment.

**Acceptance / exit gate**

- Controlled Customer App → Merchant App USD and KHR journeys post once, show
  matching references and conserve the appropriate account balances.
- Concurrent payment attempts, lost responses and retries never double-credit.
- Inactive/foreign/unregistered destinations and altered fixed amounts fail.
- Foreground/background/restart correctly recover a paid request without new payment.
- Test customer currency conversion into merchant QRs with existing exact rounding.
- Show internal Kesor acceptance honestly; do not claim external KHQR certification.

## 12. M7 — Sales, receipts and reports

**Deliverables**

- Merchant-scoped paginated Sales with date, currency, status and reference filters.
- Receipt details/share: shop identity, confirmed amount, currency, reference,
  timestamps and payer information limited to what the merchant needs.
- Separate payment-request status from completed financial transaction history.
- Daily/monthly collection totals and successful payment count; define time
  boundaries in Asia/Phnom_Penh. Keep USD/KHR totals separate.
- Exclude test funds, owner transfers and wallet funding from sales. Label metrics
  as collections; they are not profit or full accounting revenue.
- Preserve original receipt amounts and transaction-time identity; profile edits
  must not rewrite historical financial records.

**Acceptance / exit gate**

- Filters/pagination do not omit or duplicate payments; cross-shop access is denied.
- Reports reconcile to confirmed payments across day/month boundaries and currencies.
- Unknown/failed requests are not counted as collected money; no invented FX totals.
- Receipts use server-confirmed data and remain consistent between both apps.

## 13. M8 — Owner transfers, security and settings

**Deliverables**

- Transfer merchant funds only to the same owner's personal Kesor wallet in the
  same currency for v1. Confirm source, destination, currency and exact amount.
- Obtain fresh approval in Customer App bound to the specific transfer details;
  do not expose broad customer tokens/PINs to Merchant. Cancellation sends no money.
- Reuse the immutable transfer journal, idempotency, balance locking, receipts and
  unknown-outcome recovery. Recheck ownership/status at financial commit.
- Resolve uncertain results by status lookup; retry only the original intent/key.
  An expired authorization never permits a different/new payment.
- More/settings: shop editing, English/Khmer, appearance, notification preferences,
  support, safe session restore, privacy cover and sign-out.
- Keep background-notification options honest until M10 is implemented.

**Acceptance / exit gate**

- Wrong owner/currency/destination, insufficient funds, missing/expired or altered
  approval and repeated requests cannot move unauthorized or duplicate money.
- Confirmed transfers balance both accounts and appear as transfers, not sales.
- Logout/owner replacement clears private views and ignores late responses.
- Existing Customer App security, profile, wallet and transfer behavior passes regression.

## 14. M9 — Integrated acceptance and pilot delivery

**Deliverables**

- Run relevant backend tests in isolated test infrastructure, full Flutter suites
  and analysis for both apps, sequentially on this approximately 8 GB machine.
- Render new screens across English/Khmer, light/dark, small phone, tablet,
  landscape, large text and reduced motion; visually inspect representative renders.
- Exercise one full owner journey: approve → register → wallets → collect →
  customer payment → merchant confirmation → receipt/report → owner transfer.
- Test cancellation, denied camera/gallery permission, connection loss, expiry,
  replay, app death, activity recreation, session revoke and suspension races.
- Build normal API/dev APKs for both apps; inspect packaged assets/environment,
  record checksums and install with `adb install -r` when device testing is authorized.
- Deliver APKs, visual examples, verification notes and updated handoffs. Separate
  automated/fake-platform evidence from personal PIN and physical-device acceptance.

**Acceptance / exit gate**

- All required milestone checks pass, both APKs install together and customer
  regressions are green. No secret or test-only endpoint is shipped as live behavior.
- User privately completes authentication/PIN confirmation and accepts the visible
  flow; the agent never requests or enters the user's PIN or personal login codes.
- Pilot readiness is documented separately from production/external-network readiness.

## 15. Later milestones

| ID | Scope | Completion gate |
| --- | --- | --- |
| M10 | Durable event outbox, Android push delivery, token rotation/preferences, optional foreground Khmer/English voice | Committed payments survive event delivery failure; duplicate/out-of-order messages reconcile against backend and do not replay sound |
| M11 | Individually authenticated cashiers, permission matrix, shift closing, CSV export and full/partial refunds | Cashiers lack owner powers; refunds link to original payer/payment, cannot exceed remaining refundable amount under concurrency, require owner approval and never erase original entries |
| M12 | Branch/counter attribution, invoices, payment links and read-only sales assistant | Scoped access and totals reconcile; public links reveal minimal data; AI has no financial write capability |
| M13 | Authorized KHQR/Bakong provider integration, status verification, settlement/reconciliation and external refunds | Provider access/acceptance requirements met; independently verified external events reconcile without duplicate credit; sandbox/demo evidence is not represented as production certification |

M10-M13 are excluded from first-release completion. iOS native acceptance, inventory,
payroll, loans, loyalty and external-bank payouts are also outside the initial scope.

## 16. Draft API and data checklist

M2 approval/session paths are now implemented as specified in
`MERCHANT_M2_SECURITY.md`. Remaining shop/payment paths below are proposals for
later milestones and are not existing API claims.

| API capability | Proposed route / reuse |
| --- | --- |
| Start sign-in | `POST /api/v1/merchant-auth/attempts` |
| Customer view/approve/deny | `GET /merchant-auth/attempts/{id}`, `POST .../{id}/approve`, `POST .../{id}/deny` under `/api/v1`; authenticated Customer App only |
| Cancel/exchange | `POST /api/v1/merchant-auth/attempts/{id}/cancel`, `POST /api/v1/merchant-auth/exchange`; possession-bound, never authorized by public ID alone |
| Session lifecycle | Reuse/extend session APIs with Merchant audience, refresh rotation and revocation |
| Current shop/register | `GET /api/v1/merchants/me`; adapt existing `POST /api/v1/merchants/register` |
| Profile/logo | Owner-scoped merchant profile update and logo upload/read |
| Wallets/dashboard | Extend merchant account routes; add shop dashboard aggregate |
| Request/static QR/status | Extend existing QR services with merchant-specific authorization and payment linkage |
| Sales/receipts/reports | Merchant-scoped read APIs; avoid personal-history route widening |
| Owner transfer approval/submit/status | Extend authorization + transfer services with resource-bound Merchant permissions |

Data additions: approval attempts/code claims; session purpose/client metadata;
shop contact/logo fields; registration idempotency; wallet uniqueness; merchant
payment request/receipt linkage; reporting indexes; durable payment events.
Reuse existing entities where they satisfy the contract; do not create a second
financial ledger for the Merchant App. Add new Flyway migrations only, with a
plan for existing rows and safe backfill. Never edit already-applied migrations.

## 17. Working and evidence rules

- Preserve the current scanner edits and all other uncommitted/untracked work.
  No reset/clean, live data reset or device data clearing for setup.
- Prefer the suitable current checkout; do not commit, push or merge unless asked.
- Keep credentials in ignored backend configuration, never logs, docs or APKs.
- Do not restart an active backend or apply development database changes merely
  to write this plan; inspect the listener and migration effects before later work.
- Run heavy checks/builds sequentially; stop build daemons when finished and leave
  requested testing runtimes/USB forwarding available.
- Cloudflare: use cf CLI unless the project has a Wrangler configuration file.
- Each completed milestone records changed areas, check commands/results, device
  evidence, remaining limitations and relevant API/schema changes in the handoff.
- The original planning task changed documentation only. Current implementation
  progress is recorded in the milestone register and progress report above.

## References

- [Current project brief](NEXT_SESSION_BRIEF.md)
- [Customer implementation history](IMPLEMENTATION_PLAN.md)
- [Customer QR flow (read later Phase 4 updates for conversion behavior)](QR_CUSTOMER_FLOW.md)
- [Android App Links](https://developer.android.com/training/app-links)
- [Native-app authorization protections and PKCE](https://www.rfc-editor.org/rfc/rfc8252)
- [NBC QR payment integration](https://bakong.nbc.gov.kh/en/download/KHQR/integration/QR%20Payment%20Integration.pdf)
