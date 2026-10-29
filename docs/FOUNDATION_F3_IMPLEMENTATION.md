# F3 — Accounts, balances, recent activity, and basic profile

Implemented and verified 19 October 2026. **F3 is complete.** Automated
regressions, Gmail Android acceptance, native restart/uncertainty checks, and the
normal debug APK build/launch gate passed.

## Delivered behavior

After authentication, Home loads the customer's existing accounts from the API.
Customers can load additional pages, select an account, view its balance, status,
currency, type, creation date, and full selectable account number, and explicitly
open a zero-balance SAVINGS, CHECKING, or PAYROLL account in USD or KHR.

Activity shows only the selected account's latest five postings, with reference,
date, direction, amount, fee when present, and the backend's status. Profile shows
verified username/email, identity refresh, and sign-out. Back returns from details
or opening to the current tab, and from Activity/Profile to Home.

Transfers, full paginated history, transaction-detail screens, profile editing,
external funding, and biometric authentication remain outside F3. Staff deposits
and status changes remain administrative QA/API operations.

## Data, session, and privacy decisions

- The HTTP layer preserves JSON decimal number lexemes before `jsonDecode`.
  Money uses bounded `BigInt` minor units, rejects floating-point DTO values,
  unsupported currencies, fractional KHR, excessive precision, and overflow.
  USD has two decimal places; KHR has whole units. There are no mixed-currency totals.
- Safe reads share F2's coordinated refresh and retry once on `TOKEN_INVALID`.
  Mutations may renew before sending but are never replayed after sending.
- Account/activity state is scoped to the signed-in user and server session.
  Logout/invalidation clears it immediately. Request generations reject responses
  from old selections, superseded refreshes, and ended sessions.
- Refresh failures retain last-known data with timestamps and failure notices.
  An inaccessible selected account is removed. API failures never enable demo mode.
- Account opening requires HTTP 201 and a valid zero-balance response. A secure,
  backend/mode/user-scoped uncertainty flag is written **before** the POST. It
  survives process death and logout. A confirmed success or definite rejection
  can resolve it; a refresh by itself cannot prove a timed-out POST failed.
- After an uncertain outcome the customer must refresh/review accounts and make
  an explicit new-account decision before submitting another opening request.
  There is no automatic retry, including after restarting. Secure-store failure
  blocks account opening. No accounts or balances are persisted on disk.
- Browser preview uses memory-only stores and does not claim native persistence.
  Explicit demo mode uses labelled simulated data and clears accounts on logout.

## Verification

| Check | Result |
| --- | --- |
| Flutter regression suite | 66 passed, no failures or skips |
| Flutter analysis | Passed, no issues |
| Java 21 Maven `verify` | 83 passed, zero failures/errors/skips |
| Screenshots | Home, opening, Activity, and Profile rendered and inspected |
| Layout/accessibility | Portrait 375×667, landscape 667×375, tablet 1024×768; 2× text, dark mode, reduced motion; Android touch-target and label checks passed |
| Gmail Android journeys | Passed: two customers, registration and later login, separate staff login, funding, ownership, KHR/types, statuses |
| Native process restart/uncertain creation | Passed: seed, uncertain, restore, and signedout in four separately terminated app processes |
| Normal debug APK build and launch | Passed: ordinary main entry, QA harness/secrets absent, installed and visibly launched at Welcome |

Automated tests cover exact money and malformed responses, actual API envelopes,
pagination, explicit opening, duplicate-submit prevention, persistent uncertainty,
storage failure, late response suppression, stale data, session renewal,
mutation non-replay, logout privacy, responsive screens, and navigation.

Backend changes add only an opt-in separate local staff fixture and five fixture
regressions. Existing account/posting APIs and applied V2–V9 migrations are
unchanged. The fixture requires `local & !prod`, defaults to disabled, and refuses
username/email/password/role conflicts instead of editing existing users. Set
`QA_STAFF_ENABLED`, `QA_STAFF_USERNAME`, `QA_STAFF_EMAIL`, and `QA_STAFF_PASSWORD`
only for deliberate local provisioning. Existing demo users and balances remain.

## Live Gmail evidence — 19 October 2026

The user explicitly approved three controlled Gmail aliases for the two customer
identities and the separate staff fixture. The sender remained the configured
Gmail sender. Four actual inbox codes were supplied by the user: customer 1
SIGNUP, staff LOGIN, customer 2 SIGNUP, and customer 2 LOGIN. No captured inbox,
OTP override, direct OTP-database read, or Mailpit was used.

On the stable Android 14/API34 emulator `Codex_F2_API34` (port 5556):

- Customer 1 registered through the screens, saw a real empty account list,
  explicitly opened a USD savings account at USD 0.00, and viewed details and
  empty activity. A staff API test deposit of USD 25.50 then appeared in the
  refreshed balance and recent activity with status SUCCESS.
- Customer 2 registered through the screens and opened a CHECKING/KHR account at
  KHR 0. The opposite customer's account/detail and history reads returned 404.
  Staff changes to FROZEN and CLOSED appeared on owner-scoped refreshes.
- Customer 2 signed out, logged in again through the app using a fresh real Gmail
  LOGIN code, and signed out. Customer 1 also opened a zero-balance PAYROLL/KHR
  account, covering the remaining supported type.
- A separate process restored customer 1 and deliberately created a CHECKING/USD
  account through the real API while dropping the response in the QA gateway.
  Exactly one POST was sent; another opening was blocked, and the secure flag
  remained set. This is controlled response-loss injection, not a claim of a
  physical network outage.
- The next process restored the same customer/session and installation, rotated
  the refresh token, read the persisted uncertainty flag and unchanged account
  count, blocked another opening, and loaded the USD 25.50 balance/activity
  freshly. An explicit new-account decision cleared the flag without creating
  another account. Logout removed private content and Back remained public.
- The final process remained signed out with no saved refresh token.

The run retained two new customer users, one separate staff fixture, and four
new local QA accounts (including the deliberate response-loss account). The
test sessions were signed out; existing users, emails, balances, and audit history
were preserved. The second customer's test account remains CLOSED, as tested.
These are local internal test balances; no external money moved.

Logs are retained under `D:\CodexQa\AiDigitalBankingF3`: `maven-verify.log`,
`maven-verify-final.log` (83 tests against the final source/configuration),
`flutter-tests.log`, `flutter-analyze.log`, `visual-qa.log`, `native-seed.log`,
`native-restart.log`, and `normal-app-build.log`. Screenshots from the render
tool are in ignored `frontend/customer_app/.local/qa`. Codes, passwords, tokens,
and SMTP credentials are excluded from this report.

This establishes Android emulator acceptance. Physical-device, iOS, TalkBack,
release signing, and production deployment acceptance are not claimed.

## Repeating manual Gmail/native QA

Use confirmed, controlled Gmail recipients. The test creates real **local** QA
users/accounts and retains their audit trail. Its seed phase expects unused
customer identities; do not blindly rerun seed against an already populated set.
Staff funding uses a stable idempotency key for the new QA account only.

Create an ignored `frontend/customer_app/.local/f3-qa.json` containing
`QA_F3_CUSTOMER1`, `QA_F3_CUSTOMER2`, `QA_F3_STAFF`, `QA_F3_PASSWORD` (a separate
random local test password), and `QA_F3_BRIDGE_KEY` (a random shared secret).
Configure the staff fixture with the same staff email and test password. The
customer usernames are `f3.gmail.customer1` and `f3.gmail.customer2`; use a fresh
local QA data set or adapt the harness deliberately for another named run.

With the Gmail backend running, from `frontend/customer_app`:

```powershell
python tool/gmail_qa_bridge.py --config .local/f3-qa.json
# In another terminal, with the stable API34 emulator booted:
.\tool\verify_f3_restart.ps1 -Device emulator-5556
```

The authenticated, loopback-only bridge does not read a mailbox or send email.
The test requests a code through the real application/API; an operator supplies
the actual Gmail code using authenticated `POST /code` with the pending request
`id` from `GET /status`. Codes remain in memory, are consumed once, expire after
five minutes, and are never logged. The bridge is used only by the integration
test; production app code has no bridge dependency.

`seed` covers two customers, registration/login through screens, zero opening,
staff funding, balances/activity, KHR/types, ownership rejection, and statuses.
`uncertain` commits one deliberate test opening then injects a lost response.
`restore` starts a new process, verifies token rotation, fresh balances/activity,
persistent uncertainty and no repeated opening, then resolves the flag through an
explicit decision and signs out. `signedout` verifies persistent logout in a new
process. Each phase retains native app data with `--no-uninstall`; the launcher
force-stops and verifies process termination between phases.

Do not run the historical captured-inbox drivers against Gmail or start Mailpit.
After native tests, rebuild the ordinary `lib/main.dart` debug APK so the output
does not contain the integration listener or embedded QA configuration.

All work remains uncommitted. Pre-existing Gmail/setup/QA edits were preserved.

## Final artifact and workstation cleanup

The ordinary Android x64 debug APK is
`frontend/customer_app/build/app/outputs/flutter-apk/app-debug.apk`
(75,117,769 bytes). Its SHA-256 is
`4039a2d2d0c7bcfbf5ce61d0de344a6e7498655fa7868ecf398c5d3b2d78f529`.
Package inspection confirmed `lib/main.dart` and excluded the integration listener,
Gmail QA test source, bridge key, and local QA password.

The installed app visibly rendered Welcome with the public controls and was the
resumed activity, with no AndroidRuntime error for its process. The first ADB
launch-wait timed out while it started; a follow-up foreground intent returned
Status: ok. This is launch evidence, not a startup-performance benchmark.
`normal-apk-evidence.json`, `normal-launch-evidence.json`, `normal-app-ui.xml`,
and `normal-app-welcome.png` are retained in the same D: QA directory.

The task-started backend, manual code bridge, QA emulator, and task-started Gradle
daemon were stopped after verification. PostgreSQL remains running. The regular
app APK remains installed in the preserved emulator data. No commit was created.
