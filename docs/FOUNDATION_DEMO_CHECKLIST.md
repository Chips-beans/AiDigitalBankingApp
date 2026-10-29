# Foundation demo checklist

Use [local setup](FOUNDATION_LOCAL_SETUP.md) to start one backend and the normal
Flutter Android app. The [Swagger walkthrough](FOUNDATION_SWAGGER_WALKTHROUGH.md)
provides the exact JSON and authorization steps. This is a local internal-balance
demo. Biometric authentication and the advanced roadmap are outside this demo.

## Before presenting

- [ ] Confirm PostgreSQL and one backend on 8080, `local` profile, Flyway V9.
- [ ] Confirm Gmail sender configuration and controlled customer/staff inboxes.
- [ ] Use the ordinary `lib/main.dart` app in API mode on the API34 emulator.
- [ ] Identify two customer identities and a separate staff identity. Keep tokens,
  passwords, codes, and local QA configuration out of screen recordings.
- [ ] Record starting account numbers, currencies/statuses, balances, and any
  unresolved intent. Check an earlier attempt before sending or funding again.

The approved Gmail aliases are already registered. Log in with their existing
passwords and fresh LOGIN codes; do not rerun signup/seed for those identities.
For a new registration demonstration, use a separate controlled unused address.
Do not delete users/accounts or reset balances to make a demo repeatable.

Last read-only F5 checkpoint on 20 October 2026:

| Identity | Accounts/balances |
| --- | --- |
| `sengsovaneach+f3customer1@gmail.com` | Active savings USD 18.50; active checking USD 1.00; active payroll KHR 0 |
| `sengsovaneach+f3customer2@gmail.com` | Active savings USD 6.00; earlier checking KHR 0 remains closed |
| `sengsovaneach+f3staff@gmail.com` | Existing separate staff identity |

These are checkpoints, not targets to restore. Capture fresh balances for each
presentation. Existing Gmail harness seed phases spend/add test funds and create
records; they are not reset scripts. Read [F3](FOUNDATION_F3_IMPLEMENTATION.md)
and [F4](FOUNDATION_F4_IMPLEMENTATION.md) before using their opt-in harnesses.

## Two-customer journey

For a new demonstration, the illustrative 100.00 funding and 25.00 transfer below
assume two newly opened, active zero-balance USD accounts. If using existing
accounts, calculate the expected deltas from their actual starting balances.

| Step | Action and expected result | Acceptance evidence |
| --- | --- | --- |
| 1 | Register a fresh customer with SIGNUP OTP from their inbox; Profile shows the verified identity, Home is empty | F3 real Gmail Android; F5 isolated HTTP |
| 2 | Explicitly open savings USD; number appears, balance is 0.00, status active | F3 Android; F5 HTTP |
| 3 | Register/log in as customer 2 and open a separate zero-balance USD account; retain its number | F3 Gmail Android; F5 HTTP |
| 4 | Staff logs in through Swagger with LOGIN OTP and deposits USD 100.00 using one saved Idempotency-Key; owner refresh shows deposit and balance | F3 staff API + Android refresh; F5 HTTP |
| 5 | Customer 1 selects the owned active source, enters customer 2's number and USD 25.00; review shows both numbers, USD, zero fee, total | F4 Android and widget tests |
| 6 | Review alone sends nothing; Confirm and send creates a success reference; duplicate taps/replay cannot post again | F4 Android; Flutter tests; backend race/replay tests |
| 7 | Sender balance is 75.00, receiver balance 25.00 for the illustrative new-account scenario; sender history includes deposit plus outgoing transfer | F5 HTTP; F4 native balance deltas |
| 8 | Customer 2 sees the incoming transfer and same reference; detail direction follows the selected account | F4 Android; F5 HTTP details/history |
| 9 | Restart without uninstalling/clearing data; refresh rotates and the same identity/session, balances/history restore | F3/F4 native process restarts; F5 server-context restart |
| 10 | Sign out each customer; private content and Back navigation clear; another process launch stays signed out | F3/F4 native restart; Flutter privacy tests; F5 persisted server logout |

Keep one key and immutable payload for each intended financial operation. Save
its reference and expected balance delta before proceeding. A new intended
operation needs a new key; a missing response requires the original key.

## Failure and recovery acceptance

The evidence below is the completed acceptance matrix. Destructive fault injection
belongs in isolated tests; do not alter development OTP/session/database rows to
recreate those faults during a presentation.

| Scenario | Expected behavior | Verified by |
| --- | --- | --- |
| Wrong/expired/used OTP | Structured rejection; no session; resend respects countdown/limits | Backend PhaseZeroIntegrationTests; Flutter auth tests; F2 wrong-code UI |
| Empty accounts | Clear empty Home; explicit opening at zero; no invented money | F3 Gmail Android; Flutter account widgets; F5 HTTP |
| Nonzero opening balance | VERIFIED_FUNDING_REQUIRED; staff deposit is separate | Backend financial tests and Swagger workflow |
| Insufficient funds | Rejected; both balances/history unchanged | F4 Gmail API assertions; backend financial tests |
| Frozen/closed account | Sending rejected; refreshed status visible; staff controls remain separate | F3 Android statuses; F4 closed-account rejection; backend frozen/race tests |
| Wrong currency/precision | Reject USD/KHR mismatch, fractional KHR, invalid amount | F4 Gmail API; exact-money Flutter/backend tests |
| Customer staff operations | Funding/status return 403; app exposes neither control | F3/F4 and backend role tests; F5 funding rejection |
| Cross-customer private reads | Foreign account/history/unrelated reference denied; participants may read their shared transfer | F3/F4 Android/API; backend ownership tests; F5 source/history rejection |
| Duplicate transfer/key conflict | Same key+payload returns same reference; changed payload gives conflict; no double debit | F4 Gmail; backend concurrent duplicate/conflict tests; F5 post-restart replay |
| Lost transfer response | Show unknown; retain secure immutable intent; restart sends nothing; explicit retry returns one posting | F4 Gmail native process sequence; Flutter journal/controller tests; F5 server replay |
| Lost account-opening response | Retain uncertainty, refresh accounts, require explicit new decision; never auto-replay | F3 native restart sequence; Flutter account tests |
| Expired/revoked session | Coordinated refresh or sign-in; clear private state when invalid; logout persists | Backend expiry/rotation tests; Flutter session tests; F3/F4/F5 restart checks |
| Network/storage failure | Labeled stale read data or retry; no fake success or unsafe secure-storage fallback | Flutter API/account/journal/session tests |

For lost-response demonstrations, the Gmail harness deliberately suppresses the
response after a real local commit. It preserves its intent and records. This is
controlled injection, not a physical-network-outage claim. Follow the documented
continuation phase after an interrupted run instead of restarting seed.

## End the presentation

- [ ] Acknowledge definite transfer results; retain unresolved safety records.
- [ ] Sign out test sessions and clear Swagger's saved authorization.
- [ ] Retain financial/audit data and note changed test balances.
- [ ] If an integration APK was used, rebuild/install the normal entrypoint APK.
- [ ] Stop only task-started bridges/backends/shells when no longer needed.

Current evidence covers the Android 14 x64 emulator and isolated backend tests.
Physical devices, iOS/desktop, TalkBack, production deployment, release signing,
and external funding/payment networks require separate acceptance.
