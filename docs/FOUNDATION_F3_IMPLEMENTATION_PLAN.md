# F3 implementation proposal — accounts, balances, and basic profile

Prepared and approved 19 October 2026. **Status: implemented and verified.**
The initial review performed no account creation, email delivery, or feature
implementation. The user subsequently authorized implementation and confirmed
the live Gmail aliases. See [F3 delivery and QA](FOUNDATION_F3_IMPLEMENTATION.md)
for the completed gates and retained local QA data.

## 1. Which “Phase 3” this plan covers

The repository uses several numbering systems:

| Label | Meaning | Current status |
| --- | --- | --- |
| Foundation F3 | Accounts, balances, and basic profile | Next milestone; this proposal |
| Flutter Phase 3 | Authentication and session integration | Delivered in F2 |
| Flutter Phase 4 | Home and accounts | Main Flutter work covered by F3 |
| Old backend Phase 3 | Fraud detection and employee review | Deferred advanced roadmap |

This proposal follows the next foundation milestone in
[BACKEND_COMPLETION_PLAN.md](BACKEND_COMPLETION_PLAN.md). It does not restart
completed authentication work or introduce advanced fraud features.

## 2. User outcome and scope

After signing in, a customer can see their own accounts, explicitly open a
zero-balance account, select an account, view its current balance and status,
review a small recent-activity list, view their profile, and sign out.

F3 includes:

- Home, Activity, and Profile navigation.
- Own-account list and account details, including account number, type, currency,
  balance, and ACTIVE/FROZEN/CLOSED status.
- Account opening with SAVINGS selected by default. Preserve existing CHECKING
  and PAYROLL options; supported currencies remain USD and KHR.
- A read-only recent-activity preview for the selected account.
- Read-only username/email identity and sign-out.
- Empty, loading, error, retry, refresh, and uncertain-creation states.

F4 retains transfer entry/confirmation/submission, full paginated transaction
history, transaction-detail pages, and transfer receipts/results. Staff deposits
and account status changes remain Swagger/test operations. Profile editing,
password recovery, currency conversion, external funding, QR payments, AI, and
other advanced features remain outside F3. Biometric authentication is excluded.

## 3. Existing backend contracts to reuse

All paths below start with `/api/v1`. No new account/dashboard API or database
table is planned.

| App behavior | Existing API | Implementation detail |
| --- | --- | --- |
| List own accounts | `GET /accounts/me?page=0&size=20` | Returns an array, not a page-metadata envelope; support loading further pages |
| Read selected account | `GET /accounts/{accountNumber}` | Backend enforces ownership; unavailable/foreign accounts return 404 |
| Open account | `POST /accounts` | Send account type, currency, and `initialDeposit: 0`; success is 201 |
| Recent activity | `GET /transactions/account/{accountNumber}?page=0&size=5` | Read the existing page envelope's `content`; label it as recent activity |
| Profile | `GET /auth/me` | Username/email and customer identity remain server-derived |
| Sign out | `POST /auth/logout` | Reuse F2 cleanup, revocation, and navigation behavior |
| Staff test funding | `POST /transactions/deposit` | Swagger only; staff authorization and an `Idempotency-Key` are required |

Account responses already provide `id`, `accountNumber`, `accountType`,
`currency`, `balance`, `status`, and `createdAt`. The backend already rejects
nonzero account-opening deposits and customer attempts at staff-only actions.

## 4. Proposed screens and behavior

Use the existing Material 3 theme, colors, typography, and reusable notices.

| Screen/area | Proposed content and actions |
| --- | --- |
| Home | Greeting, own-account selection/list, selected balance and currency, status, account details, refresh, Open account action |
| Open account | Account type and currency selectors, explicit zero opening balance, submit progress, confirmation or uncertain-outcome notice |
| Account details | Full selectable account number, type, currency, balance, status, and creation date |
| Activity | Latest five entries for the selected owned account, amount/currency, date, reference, status, and incoming/outgoing/deposit labels |
| Profile | Server username/email, refresh identity, sign out |

Account selection is shared between Home and Activity. A new customer sees an
explanation and Open account action. An account with no postings shows a real
empty activity state. Frozen/closed accounts remain visible with explicit text
labels. There are no inactive transfer/deposit controls in the customer UI.

Support pull-to-refresh and an accessible refresh button. On a failed refresh,
keep any existing in-memory data visibly marked as last updated; do not imply it
is current. Account selection changes must not display another account's late
response. Avoid mixed-currency totals; each balance always has its currency.

Keep controls usable on narrow screens, in landscape, with large text and dark
mode. Use native semantic controls, descriptive labels, Android-sized touch
targets, safe areas, keyboard-safe forms, and reduced-motion behavior.

## 5. Implementation sequence

### Step 1 — Typed data and exact money handling

- [x] Add account and recent-activity DTOs plus gateway contracts.
- [x] Preserve monetary precision from the JSON response. Use integer minor
  units or an exact decimal representation; do not route money through lossy
  floating-point calculations.
- [x] Format USD with two decimal places and KHR with whole units.
- [x] Validate response shapes and provide safe behavior for unsupported values.
- [x] Add safe query-parameter support to the existing HTTP client for pagination.

Deliverable: tested DTO mapping, monetary formatting, and API gateway calls.

### Step 2 — Shared authorized requests and feature state

- [x] Compose authentication/account gateways with the shared API client.
- [x] Generalize F2's protected-read path for accounts/activity while preserving
  coordinated refresh and its one-retry limit for safe reads.
- [x] Keep account creation on a mutation path that never automatically replays
  its POST after a timeout, connection loss, or authentication response.
- [x] Add feature state using the existing ChangeNotifier/Listenable approach.
- [x] Scope account/activity state to the signed-in user/session; clear it on
  logout or invalidation, and ignore late responses from an old session.

Deliverable: session-safe account loading and creation without a second state
framework or new token persistence.

### Step 3 — Home, account selection, and account opening

- [x] Replace the signed-in identity-only landing page with Home.
- [x] Implement paginated own-account loading, selection, detail refresh, and
  loading/empty/error states.
- [x] Add the opening form with SAVINGS/USD defaults and zero initial deposit.
- [x] Disable repeated submissions and select the newly created account after
  a confirmed success.
- [x] On an uncertain outcome, explain that creation may have completed and
  refresh the owned-account list before any further creation attempt.

Account creation has no server idempotency contract. A list refresh alone cannot
prove that a timed-out POST failed. Do not show an automatic Retry creation
action or silently submit a new POST on reopening/restarting the app. Preserve
an uncertainty marker scoped to the user across a process restart; clear it
through reconciliation or an explicit new-account decision.

Deliverable: a new customer can explicitly open and view a real zero-balance
account without automatic duplicate creation.

### Step 4 — Recent Activity and Profile

- [x] Add the three-destination navigation shell and predictable Back behavior.
- [x] Load the selected account's latest five postings, with independent retry
  and refresh states. Determine direction relative to the selected account.
- [x] Move existing identity/sign-out functionality into Profile.
- [x] Keep demo behavior behind explicit `APP_MODE=demo`, with clearly labelled
  sample account/activity data; API errors never activate demo mode.
- [x] Preserve immediate privacy cleanup across every tab on logout.

Deliverable: useful read-only activity and profile views within F3 scope.

### Step 5 — QA, documentation, and handoff

- [x] Add meaningful data/controller/widget tests and update F2 assertions for
  the new signed-in navigation while retaining their original privacy guarantees.
- [x] Run Flutter analysis/tests and the existing backend regression suite.
- [x] Verify the two-customer account journey on the stable Android 14 QA emulator
  using the real backend and Gmail for live OTP delivery.
- [x] Recheck process restart, restoration, and logout with account data visible.
- [x] Build and launch-check the normal debug APK after device testing.
- [x] Record commands, actual results, limitations, and outstanding issues in an
  F3 delivery/QA report. Mark F3 complete only after its gate passes.

## 6. Gmail and live-QA prerequisites

Real Gmail inbox delivery has passed. Gmail-based completion of registration and
login has not yet been established by that delivery-only test. F3 live QA must
perform those flows using recipient-controlled inboxes and the actual app/API.

Before live acceptance, designate two customer QA identities and a staff QA
identity with reachable Gmail recipients. Controlled Gmail aliases may be used
after confirming the chosen addresses; do not create accounts or send messages
as part of reviewing this proposal.

The current employee fixture uses `employee.demo@example.test`, which cannot
receive the new live Gmail OTPs. Prefer an existing authorized staff QA session
if available. Otherwise, provision a separate configurable staff QA identity
through an explicit local-only fixture option, retaining the existing
`local & !prod` restriction. Preserve existing users, their emails, and fixture
balances. Do not add a public role-assignment API.

Staff funding will use Swagger and new QA accounts only, with stable idempotency
keys. Test funds are local internal balances, not external bank deposits.
Automated regressions retain isolated fixtures; live testing uses Gmail and does
not start Mailpit or run the legacy captured-inbox drivers against Gmail.

## 7. Acceptance checklist

| Scenario | Required result |
| --- | --- |
| New customer with no accounts | Clear empty state; no invented balances |
| Open USD savings account | One explicit POST, 201, USD 0.00, selected account visible |
| KHR account and existing account types | Supported types map correctly; KHR displays whole units |
| Multiple accounts and pagination | Owned accounts remain accessible beyond the first page; selection is consistent |
| Staff test deposit | Refreshed balance and recent activity agree with the confirmed posting |
| Another customer's account/history | Backend rejects the read; the app shows no private data |
| Frozen or closed account | Status is explicit; displayed data remains owner-scoped |
| Slow/offline/malformed response | Understandable loading/error/retry states; no fake success or fallback data |
| Lost account-creation response | Unknown outcome is visible; no automatic duplicate POST, including after restart |
| Concurrent expired reads | One coordinated renewal; safe reads may resume without refresh loops |
| Logout while requests are pending | All account/profile/activity state disappears; late responses cannot restore it |
| Process restart | Restored identity loads fresh owned accounts; persistent logout remains signed out |
| Narrow/landscape/large text/dark mode | Usable layout, readable values, and accessible controls |

## 8. Expected change areas and boundaries

Primary Flutter changes will be in `lib/features/accounts/`, a small recent
activity reader, `lib/features/profile/`, shared money formatters, the API/session
request layer, and app composition/navigation. Reuse existing auth/storage/theme
code and create feature folders only when they contain working implementation.

Backend work is limited to demonstrated contract gaps, focused regressions, and
the Gmail-reachable local QA fixture if needed. Reuse existing account/posting,
ownership, audit, and migration safeguards. No migration is currently planned;
never modify applied V2–V9 files.

All pre-existing uncommitted Gmail/setup/QA changes were preserved. Implementation
started after user approval, and the automated, Gmail Android, restart, and normal
APK build/launch gates passed. Transfers and full history remain in F4.
