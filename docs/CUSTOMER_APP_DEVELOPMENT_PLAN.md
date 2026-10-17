# Flutter Customer App Development Plan

Prepared 15 October 2026.

Scope revised 17 October 2026: the active milestone is the basic foundation in
[BACKEND_COMPLETION_PLAN.md](BACKEND_COMPLETION_PLAN.md). Complete this plan through
Phase 5: authentication, accounts, internal transfers, history, and read-only
profile. Phases 6–7 are deferred reference material and do not block acceptance.
Backend foundation milestones F1–F5 and the Flutter phases below use different
numbering; historical backend Phase 1 financial safeguards are already delivered.

Backend F1 was verified 17 October 2026; see
[F1 setup, Swagger and verification](FOUNDATION_F1_IMPLEMENTATION.md).
F2 now delivers Flutter Phases 1–3 below, verified on the Android 14 QA emulator; see
[F2 delivery and QA](FOUNDATION_F2_IMPLEMENTATION.md) for verification evidence
and platform limitations. F3 (accounts and balances) is the next feature milestone.

## Objective and current state

Build the customer mobile application for AI Digital Banking and Smart Wallet in
`frontend/customer_app`, using the Spring Boot backend in `backend/digital-banking`.
The Flutter project contains the authentication/session foundation, validated API
configuration, API/demo gateways, native secure storage, and automated QA.
Biometric authentication is excluded from project scope. Remaining backend work
is tracked in the [backend completion plan](BACKEND_COMPLETION_PLAN.md).
Phase 0 backend and API readiness and the F2 authentication implementation are
delivered. Accounts, transfers, and activity remain planned.

The first milestone is:

**Register with OTP → sign in with OTP → view own accounts or an empty state → sign out.**

Registration already returns tokens, so a successful signup may open the home screen
directly. A separate login must also work after signing out. A new user may have no
accounts; signup must not assume that the backend automatically creates one.

## Delivery order

| Phase | Deliverable | Completion criterion |
| --- | --- | --- |
| 0 | Completed 16 October 2026 | Auth, identity, OTP, logout, account isolation, fixtures, and API configuration are implemented and verified |
| 1 — Implemented in F2 | Flutter foundation | Theme, declarative routing, configuration, and shared UI states |
| 2 — Implemented in F2 | Authentication screens | Explicitly selected demo gateway and tested forms/OTP flow |
| 3 — Verified in F2 | Real authentication and sessions | Local/live API checks, native authentication, and three-process restart/rotation/logout pass on Android 14; platform limits remain in F2 QA |
| 4 | Accounts and home | Authenticated customer sees only their accounts, with correct loading and empty states |
| 5 | Transaction history and transfers | Customer can inspect history and confirm a transfer without accidental duplicate submission |
| 6 — Deferred | QR payments | Outside the active foundation milestone |
| 7 — Deferred | Assistant and other services | Outside the active foundation milestone |

Complete and verify each phase before treating the next dependent feature as integrated.
UI work can proceed with mock data while backend prerequisites are completed. Mock mode
must be clearly identified and must never silently replace a failed real API request.

## Phase 0 Backend and API readiness

- [x] Complete `JwtAuthenticationFilter` and attach it to `SecurityConfig`.
- [x] Resolve authenticated users into the principal expected by account controllers;
  reject disabled users, invalid tokens, and inappropriate roles.
- [x] Enforce access-token versus refresh-token use and define refresh rotation/revocation.
- [x] Add server logout or session revocation. Clearing tokens on the device alone
  does not invalidate an issued token.
- [x] Define session identity fields. Token responses include userId, email, username,
  roles, and sessionId; protected identity comes from the server session.
- [x] Confirm signup and login payloads and standardize errors the app must display.
- [x] Add OTP request throttling and validation attempt limits; ensure expiry and reuse
  behavior are consistent. A resend countdown in Flutter is only user feedback.
- [x] Implement shared-device identity using per-user installation records, without
  transferring another user's record or reactivating revoked devices.
- [x] Establish development test users, an empty-account user, accounts, and SMTP settings.
- [x] Configure a reachable development API base URL for emulator and physical-device
  testing; keep environment configuration outside feature widgets.

**Gate:** protected account requests accept a valid customer access token and reject
unauthenticated requests. A second customer's data is inaccessible. Server logout
revokes the relevant session. These are backend tasks, not Flutter-only changes.

Implemented and verified 16 October 2026. See [Phase 0 implementation](PHASE_0_IMPLEMENTATION.md) for the agreed contracts, configuration, fixtures, and test results.
The [Phase 0 code review](PHASE_0_CODE_REVIEW.md) records subsequent fixes,
the 37-test backend verification, and remaining work in later financial phases.

## Phase 1 App foundation

- [x] Replace the counter demo with the application bootstrap and session-loading screen.
- [x] Extend the Phase 0 development/production API configuration with explicit mock
  mode and wire it into the API client.
- [x] Define gateways for authentication and session storage so screens
  can use demo or real implementations without changing presentation logic. Account
  repositories are deferred to F3.
- [x] Choose one approach for shared application state and declarative routing.
  Pin compatible package versions when implementing; avoid duplicate state frameworks.
- [x] Create a shared API client with timeouts, response parsing, safe error messages,
  and support for authenticated requests. Never put API credentials in the app.
- [x] Create theme tokens for colors, text, spacing, input fields, buttons, and surfaces.
- [x] Add reusable loading, error/retry, and submission controls. Account empty states
  are deferred to F3.
- [x] Add navigation guards for signed-out, restoring-session, and signed-in states.

Proposed code layout:

```text
lib/
  main.dart
  app/
    app.dart
    router/
    theme/
  core/
    config/
    network/
    storage/
    errors/
  features/
    auth/
      data/
      presentation/
    accounts/
      data/
      presentation/
    transactions/
    transfers/
    payments/
    assistant/
    profile/
  shared/
    widgets/
    formatters/
```

Create feature folders as their work begins; do not fill them with unused placeholders.
Widgets handle presentation, repositories handle data access, and shared state manages
the session. Keep money formatting and API DTO mapping outside screen layout code.

**Gate:** the app starts on an emulator; unauthenticated navigation cannot reveal
protected screens; API and mock implementations can be selected through configuration.

## Phase 2 Authentication screens

| Screen | Required behavior |
| --- | --- |
| Session loading | Restore session or move to welcome/login without flashing private content |
| Welcome | Explain the app briefly and offer sign in or registration |
| Registration | Username, email, password, confirmation, optional first/last name; inline validation |
| Login | Email and password initially; using email avoids a separate username-to-email lookup for OTP delivery |
| OTP entry | Six-digit entry; show destination email, resend feedback, expiry errors, and edit/back actions |
| Signed-out state | Return to authentication after explicit sign-out or an invalid session |

- [x] Validate username length 3–50 and password minimum 8 to match the current backend.
- [x] Request OTP after validating the form and let OTP submission complete signup/login.
- [x] Keep the pending password only in short-lived memory; discard it on cancellation,
  successful submission, or session cleanup. Do not persist or log passwords or OTPs.
- [x] Use visible field labels, password visibility controls, accessible names, and
  touch targets suitable for mobile. Support text scaling and keyboard safe areas.
- [x] Allow password-manager autofill, paste, and complete OTP paste; avoid requiring
  manual transcription into six separate inaccessible fields.
- [x] Show field errors, offline errors, request progress, rejected OTP, expired OTP,
  resend failure, and duplicate registration feedback. Preserve non-secret form input
  where appropriate and prevent repeated taps while a request is pending.
- [x] Do not expose a working-looking password reset action until supported.

**Gate:** the mock flow handles success, failure, expiry, back navigation, and resending.
Mocks are testable examples; they do not demonstrate working backend authentication.

## Phase 3 Authentication and session integration

All paths below use the backend prefix `/api/v1`.

| Step | API or action | Important detail |
| --- | --- | --- |
| Signup OTP | `POST /auth/request-otp` | Send email and purpose `SIGNUP` |
| Complete signup | `POST /auth/register` | Send registration fields and `otpCode`; include agreed device fields |
| Login OTP | `POST /auth/request-otp` | Send email and purpose `LOGIN` |
| Complete login | `POST /auth/login` | Send email as `usernameOrEmail`, password, `otpCode`, device fingerprint/name/type |
| Renew session | `POST /auth/refresh` | Send refreshToken; handle rejection by clearing the local session |
| Sign out | POST `/auth/logout` plus local cleanup | Revoke remotely and clear local tokens, cached private data, and protected navigation |

There is no standalone OTP verification endpoint in the current backend. OTP is
validated inside registration and login; the OTP screen submits the complete pending
request rather than calling an invented verification API.

- [x] Map `ApiResponse.data` into typed token/session objects.
- [x] Keep the access token in memory and persist only the session material needed
  for restoration in platform secure storage. Never use plain-text preferences for tokens.
- [x] Attach the access token to protected requests only.
- [x] Allow one coordinated refresh attempt for simultaneous expired requests;
  prevent refresh loops and clear the session if renewal fails.
- [x] Retry only requests that are safe to repeat. Never automatically replay a
  financial mutation unless the server supports an idempotency contract.
- [x] On restart, restore a valid session or return to login without exposing stale data.
- [x] On sign-out without connectivity, clear local data immediately, communicate any
  remote-revocation failure, and follow the agreed backend session expiry policy.
- [x] Show understandable responses for invalid credentials, disabled users, OTP
  failures, unavailable server, revoked device, and expired session.

**Gate:** registration and login both work with real OTPs; app restart restores a valid
session; refresh failure returns to login; sign-out removes private data and protected
back-navigation history. Online sign-out also invalidates the server session.

## Phase 4 Home and accounts

- [ ] Build a home screen with greeting, account selection, balances, and recent activity.
- [ ] Fetch own accounts using `GET /accounts/me`.
- [ ] Fetch selected account details using `GET /accounts/{accountNumber}`.
- [ ] Show currency next to every balance. Keep totals separated by currency until a
  supported conversion feature is available.
- [ ] Provide no-accounts, loading, offline/error, retry, and pull-to-refresh states.
- [ ] Add navigation for Home, Activity, and Profile initially. Introduce payment or
  assistant destinations when their features are ready; keep bottom navigation to five or fewer items.
- [ ] Add profile/session information and sign-out. Do not claim profile editing or
  device management works before the relevant backend APIs exist.
- [ ] Include account opening using `POST /accounts` with an initial deposit of
  zero. After an uncertain creation response, refresh the list before trying again;
  this endpoint has no idempotency contract. Local demo funding uses the existing
  staff-only deposit API through Swagger, outside the customer app.

**Gate:** customer A sees only customer A's accounts; customer B cannot access them;
an empty account list is handled correctly; a frozen or closed account is labelled clearly.

**Milestone one is complete when Phases 0–4 pass their gates using the real backend.**

## Phase 5 Transactions and transfers

- [ ] Add paginated account history with `GET /transactions/account/{accountNumber}`.
- [ ] Add transaction details with `GET /transactions/{referenceNumber}`, using
  the backend's existing ownership enforcement.
- [ ] Build transfer entry, confirmation, progress, and final result screens.
- [ ] Show source, destination, amount, currency, fee, and total before submission.
- [ ] Integrate `POST /transactions/transfer`; refresh balances/history after confirmation.
- [ ] Integrate the delivered backend concurrency protection, ownership checks,
  and idempotency. Test same-account, inactive-account, currency, and
  insufficient-funds rejection. Advanced fraud scoring is deferred for this milestone.
- [ ] Create one `Idempotency-Key` per confirmed transfer intent. Retain it and the
  unchanged payload securely for unresolved requests across app restarts. After a
  timeout, show an unknown outcome and retry using that original key/payload; the
  backend returns the saved result if it committed. Use the transaction reference
  for detail lookup once known. Never create a new key merely because a response
  was lost.
- [ ] Keep deposits out of the customer app until a verified funding workflow exists.

**Gate:** concurrent or duplicate submissions cannot debit twice; transaction details
remain private; success, rejection, and uncertain outcomes display correctly.

**The foundation is complete when Phases 0–5 and backend F1–F5 pass their gates.**

## Phase 6 QR payments — deferred

This section is retained for later planning and is outside foundation acceptance.

- [ ] Display receive-money KHQR using `POST /payments/khqr/generate`.
- [ ] Add camera permissions, scanning, and QR validation with clear permission-denied states.
- [ ] Define supported merchant QR fields and confirm recipient, amount, and currency
  before any payment action.
- [ ] Define a payment-initiation contract. The current backend generates receive QR
  and checks status; it does not provide a complete outgoing merchant-payment flow.
- [ ] Check status through `GET /payments/verify/{md5Hash}` with bounded polling and
  a resumable pending state. The mobile client must not call the provider webhook itself.
- [ ] Complete backend webhook verification, payment ownership, amount/currency checks,
  expiry, and account/transaction posting before calling this an integrated wallet payment.
- [ ] Add receipts once a confirmed backend payment record and receipt contract exist.

**Gate:** validated payment status drives the UI; scanning alone cannot mark a payment
successful; delayed, failed, expired, duplicate, and interrupted cases are handled.

## Phase 7 Remaining customer features — deferred

This section is retained for later planning and is outside foundation acceptance.

| Feature | Customer app work | Backend dependency |
| --- | --- | --- |
| Beneficiaries | Add, edit, remove, and select recipients | Beneficiary APIs and ownership |
| Scheduled transfers | Create, review, cancel schedules | Schedule persistence and execution; current job is empty |
| Statements | Select period and download/share securely | Authorized statement generation/export |
| AI assistant | Chat, loading, failure, and history behavior | User-scoped data tools; current chat has no transaction access |
| Spending analytics | Period/category views with currency-aware totals | Transaction categorization and verified aggregation |
| Bill payments | Select biller, review, pay, and show result | Biller/provider integration and idempotent payment processing |
| Mobile top-up | Number/operator/amount and confirmation | Top-up APIs and provider processing |
| Notifications | Inbox, read state, optional push registration | Notification storage/events and push setup |
| ATM and branch locator | Search/list, map, and location-permission fallback | Location dataset/API |
| Currency exchange simulation | Rate, quote expiry, review, simulated result | Quote and exchange-simulation APIs |
| Password reset | Request, verify, and set new password | Reset API, expiry, attempt limits, session policy |
| Devices and disputes | Review/revoke sessions and submit/track disputes | Authorized device/session and dispute APIs |

Merchant, employee, and administrator dashboards are separate applications and are
outside this customer app plan. Customer-facing dispute access may be added once
the bank employee dispute workflow exists.

## Verification and completion

- Run `flutter analyze` and the relevant Flutter tests for each completed feature.
- Test validation, API mapping, session restoration/refresh, and guarded navigation.
- Use backend integration tests for ownership, revocation, transfer concurrency,
  and idempotency; widget tests cannot prove these properties. Verified payment
  callbacks belong to the deferred QR milestone.
- Check narrow screens, large text, TalkBack labels, keyboard overlap, slow network,
  loss of connectivity, background/resume, and app restart.
- Start with Android emulator/device validation. Validate iOS separately on a supported
  macOS/Xcode environment before claiming iOS readiness.
- Mark a feature complete only when its screen states and required backend behavior
  both pass. Keep unsupported actions hidden or explicitly unavailable.

## Immediate next work

1. F1 and F2 are verified; reuse the documented setup, API contracts, and Android
   authentication/restart evidence. Flutter Phases 0–3 are delivered.
2. Implement F3 / Flutter Phase 4: own accounts, zero-balance account opening,
   currency-aware balances, recent activity, and read-only profile.
3. Complete F4 / Flutter Phase 5 transfers and history, preserving the backend's
   ownership and idempotency contracts.
4. Verify the complete two-customer foundation journey in F5, then stop before
   deferred Flutter Phases 6–7.

This plan does not assign calendar dates. Each phase is sized and scheduled after
its dependencies and working behavior are verified.
