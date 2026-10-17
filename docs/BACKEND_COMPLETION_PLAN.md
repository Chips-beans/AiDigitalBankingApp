# Digital Banking Foundation Implementation Plan

Revised 17 October 2026 for the basic application scope.

## Goal and stopping point

Deliver a working customer journey:

**Register with email OTP → sign in → open an account → receive staff demo funding
→ view balance → transfer to another internal account → inspect history → sign out.**

This milestone uses the existing Spring Boot backend and Flutter customer app.
It is a local/test demonstration with internal balances. Live external funding and
payment-provider integration are outside this milestone.

The previous nine-phase plan is preserved in the
[deferred advanced roadmap](BACKEND_ADVANCED_ROADMAP.md). Its unfinished phases
are not prerequisites here. F1–F5 below are new foundation milestones, distinct
from historical backend phase numbers.

## Existing implementation to reuse

| Area | Current state | Remaining foundation work |
| --- | --- | --- |
| Registration/login | Password, email OTP, validation, request limits | Setup, Swagger examples, Flutter integration |
| Sessions | Access/refresh tokens, rotation, identity, server logout | Client storage, coordinated refresh, restoration, cleanup |
| Accounts | Zero-balance creation, own-account list/detail, staff status changes | Customer screens and verified demo journey |
| Transfers/deposits | Atomic posting, locks, idempotency, ownership, money checks | Transfer UI, retry handling, staff demo instructions |
| History/details | Owner-scoped reads and bounded history pagination | Activity and detail screens |
| Audit/database | Automatic auditing and migrations V2–V9 | Preserve behavior and verify startup/upgrade |
| Flutter | F2 authentication, OTP, guarded identity and session foundation | Accounts/balances, transfers and activity |

Historical verification: **74 backend tests passed** in the Phase 1 QA run.
Existing reports support that record; this planning revision is not a new test
run. See [Phase 1 delivery](PHASE_1_IMPLEMENTATION.md) and
[Phase 1 QA](PHASE_1_CODE_REVIEW_QA.md).

**F1 completed and verified 17 October 2026:** local database/inbox readiness,
Swagger corrections, and the live core workflow passed. The updated clean build
passed 78 tests after [F1 review and QA](FOUNDATION_F1_CODE_REVIEW_QA.md).
See [F1 delivery and evidence](FOUNDATION_F1_IMPLEMENTATION.md),
[local setup](FOUNDATION_LOCAL_SETUP.md), and
[Swagger walkthrough](FOUNDATION_SWAGGER_WALKTHROUGH.md).
F2 is implemented and verified on the Android 14 QA emulator, including native
authentication and process-restart persistence. See
[delivery and QA](FOUNDATION_F2_IMPLEMENTATION.md) for evidence and platform
limits. F3–F5 remain planned.

Retain the Spring Boot modular monolith, PostgreSQL, Flyway, Maven wrapper, Java 21
target, and /api/v1 prefix. Existing money, ownership, session, idempotency, and
audit safeguards remain requirements even for the basic application.

## Included scope

- Email OTP registration/login, token refresh, current identity, and logout.
- Open a savings account at zero; view own accounts, balance, currency, and status.
  Preserve the backend's existing account types.
- Internal transfers between active accounts in the same supported currency.
- Paginated history and transaction detail/result screens.
- Read-only profile identity and sign-out.
- Staff-only deposits and freeze/reactivation through Swagger for local testing.
- Existing validation, authorization, financial correctness, auditing, and tests.
- Reproducible local setup, Swagger walkthrough, and Android emulator integration.

## Deferred scope

Password recovery, password/profile editing, device/session management screens,
administrator user/role/configuration APIs, staff/merchant dashboards, fraud
scoring and investigation, QR/Bakong payments, provider adapters, settlements,
AI/chat, spending analytics, beneficiaries, recurring transfers, PDF/CSV statements,
downloadable receipts, notifications/push, bills, top-ups, maps/locators, exchange,
disputes, and refunds.

**Biometric authentication is excluded from the project, not merely deferred.**

Keep unsupported features out of the foundation UI and demo checklist. Existing
advanced modules may remain in the repository; their presence does not establish
working features. Preserve the blocked unsigned payment webhook.

## Delivery sequence

| Milestone | Deliverable | Backend work | Completion gate |
| --- | --- | --- | --- |
| F1 — Verified | Local setup and core API baseline | Delivered local inbox/setup, Swagger contracts and verification | One server, working database/OTP, usable API examples; 78 tests passed after review |
| F2 — Verified | Customer authentication and sessions | Existing APIs integrated | Local/live API checks, native authentication, and three-process restart/rotation/logout pass on Android 14 (see F2 QA) |
| F3 | Accounts, balance, basic profile | Integrate existing APIs; fix demonstrated gaps | Customer opens an account and sees only their own data |
| F4 | Internal transfers and activity | Integrate existing financial APIs | One transfer posts once; balances/history agree; retries are safe |
| F5 | Verification and handoff | Targeted fixes and regression checks | Complete two-customer journey works against the real backend |

No speculative new backend modules or tables are required. Add a migration only
when an actual foundation change needs one; allocate the next free version and
never modify applied migrations.

## F1 — Local setup and API baseline

- Confirm PostgreSQL configuration and digital_banking_db. Inspect the actual
  Flyway version instead of assuming the older V7 handoff still describes it.
- Check port 8080 before startup. Reuse the running backend or deliberately restart
  it; avoid a second instance.
- Document one reproducible local SMTP capture setup on port 1025, including how
  to start it and open its inbox. Real SMTP is optional.
- Keep credentials in the ignored .env. Document variable names/examples without
  real secrets; preserve existing local configuration.
- Verify opt-in fixtures: two customers, an empty-account customer, and staff.
  Clearly identify preloaded balances as demo opening balances.
- Correct Swagger's public-auth lock indicators, actual success statuses such as
  registration's 201, and common error documentation.
- Add a foundation Swagger walkthrough: OTP, authorization, account creation,
  staff funding, transfer, history, refresh, and logout. Document the exact request
  fields and response envelopes.

**Gate:** a developer can run one backend, read an OTP from the documented inbox,
and exercise the core APIs. Customers cannot invoke staff funding/status operations
or read another customer's private account data.

## F2 — Authentication and session integration

- Replace Flutter's counter screen with bootstrap, routing, shared API handling,
  and loading/error/empty components. Use the
  [customer app plan](CUSTOMER_APP_DEVELOPMENT_PLAN.md) through its Phase 5 only.
- Build registration, login, and OTP entry. Request SIGNUP or LOGIN OTP, then
  submit it with the complete registration/login payload. There is no separate
  OTP-verification API.
- Registration already returns tokens and signs the customer in. Account opening
  remains a separate customer action.
- Persist a stable random installation identifier for deviceFingerprint; it is
  not a hardware identity or biometric credential.
- Keep pending passwords/OTPs only in short-lived memory. Store the refresh token
  in platform secure storage; keep the access token in memory where practical.
- Coordinate one refresh operation for concurrent expired requests. Replace both
  tokens after refresh; reuse of an old refresh token revokes the session.
- Restore valid sessions on restart. Clear private state on invalid sessions or
  sign-out. Online logout calls the backend; offline logout clears locally and
  explains that remote revocation could not be confirmed.
- Handle wrong credentials, OTP expiry/reuse, resend limits, unavailable mail,
  network errors, and expired sessions. Hide unsupported recovery/edit actions.

**Gate:** signup, later login, restoration, refresh, and logout work against the
real backend. Private screens cannot be revisited after sign-out.

## F3 — Accounts, balance and profile

- Add Home, Activity, and Profile navigation; show /auth/me identity in Profile.
- Display own accounts and a clear empty state.
- Add explicit account opening through POST /accounts, defaulting to SAVINGS
  and initialDeposit: 0. Do not automatically retry creation after an uncertain
  response; refresh the list first because creation has no idempotency contract.
- Support existing USD/KHR rules: USD up to two decimal places, KHR whole units.
  Show each currency separately; do not add currency conversion or a mixed total.
- Display account number, type, balance, currency, and status, with refresh and
  understandable offline/error states.
- Document staff demo funding through POST /transactions/deposit with an
  Idempotency-Key. These are test funds, not evidence of an external deposit.
  Deposit controls stay outside the customer app.
- Show recent activity using the existing history API; no new dashboard API
  is needed.

**Gate:** a new customer opens an account at zero, a staff deposit appears in
balance/history, and a second customer cannot read those private records.

## F4 — Internal transfers and activity

- Build transfer entry, confirmation, submitting state, result, history, and detail.
- Select an owned source account; enter destination account number, amount, and
  optional remark. Use known recipient fixture numbers for the demo. Do not use
  another customer's private account endpoint to resolve recipient names.
- Show source/destination, currency, amount, and the current zero-fee policy before
  confirmation. Use exact monetary parsing and formatting.
- Create one Idempotency-Key per confirmed transfer intent. Retain the same key
  and unchanged payload for retries. Disable duplicate taps while preserving
  server-side duplicate-posting protection.
- Retain unresolved submission details securely, scoped to the signed-in user,
  so an app restart does not silently create a new attempt/key.
- For a lost response, show an unknown outcome and retry the identical request
  with the original key. If it already committed, the backend returns its saved
  result. A timeout alone proves neither success nor failure. Use the existing
  replay contract and transaction reference when known; no new status API is
  required for this milestone.
- Handle insufficient funds, inactive/unavailable accounts, currency mismatch,
  invalid amounts, and idempotency conflicts.
- Refresh balances/history after success. Use backend pagination and reference
  lookup for details. Determine incoming/outgoing display relative to the selected
  account because each transfer contains a source and destination.
- Preserve locking, ownership checks, atomic posting, currency validation, and
  audit writes. Advanced fraud scoring is not a dependency of this limited
  internal-transfer foundation.

**Gate:** a transfer updates both balances correctly and creates one financial
record. Repeated submissions do not double-post; rejected requests change no
balances; transaction details remain owner-scoped.

## Existing API inventory

All paths start with /api/v1.

| Area | Existing routes |
| --- | --- |
| Auth | POST /auth/request-otp, /auth/register, /auth/login, /auth/refresh; GET /auth/me; POST /auth/logout |
| Accounts | POST /accounts; GET /accounts/me; GET /accounts/{accountNumber} |
| Transfers | POST /transactions/transfer; Idempotency-Key required |
| Activity | GET /transactions/account/{accountNumber}; GET /transactions/{referenceNumber} |
| Staff demo tools | POST /transactions/deposit with Idempotency-Key; PATCH /accounts/{accountNumber}/status |

Use the existing envelopes and stable error codes. Account lists and paginated
transaction history have different data shapes; map their actual contracts.
Protected calls use the access token. Refresh receives the refresh token in JSON.

## F5 — Verification and definition of done

1. Run the backend regression suite with **.\mvnw.cmd clean verify** from
   backend/digital-banking. Preserve financial race, rollback, ownership, session,
   idempotency, and migration coverage. Tests use isolated PostgreSQL/local SMTP
   and must not reset the development database. On Windows, stop an instance
   running from target/*.jar before cleaning because the JVM locks that file.
2. Add meaningful tests for changed behavior only. Run Flutter analysis and
   relevant API-mapping, session, transfer-retry, and UI tests.
3. Demonstrate registration, account opening at zero, staff demo funding, transfer
   to another customer, both customers' history views, restart, and sign-out.
4. Demonstrate wrong/expired OTP, empty accounts, insufficient funds, frozen
   account, wrong currency, duplicate submission, lost response/retry, expired
   session, and rejection of cross-customer reads and customer staff operations.
5. Verify a fresh test database and supported migration upgrades. Restart the app
   and confirm data persists. Record actual test results and remaining limits.
6. Deliver setup instructions, Swagger walkthrough, API examples, demo checklist,
   test evidence, and the Flutter Android foundation. Verify other platforms
   separately before claiming support.

**Stop when F1–F5 pass.** Deferred advanced features are not required for acceptance.
These are planned tasks; completed status requires implementation and verification.

## Immediate next task

F1 is verified. Start **F2: Flutter foundation, authentication, and session
integration**. Use the F1 setup and Swagger contracts; reuse the existing backend
and address only demonstrated integration gaps required for the basic milestone.
