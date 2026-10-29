# F4: internal transfers and transaction history

Implemented 19 October 2026 for the basic Flutter customer application. Uses the
existing Spring Boot financial APIs; no backend schema or financial posting changes.
Biometric authentication and external payments remain outside this scope.

## Customer behavior

- Home opens a transfer form with an owned source account, destination account
  number, exact amount, and optional remark. Only active sources can send.
- Review displays both account numbers, currency, amount, zero fee, and total.
  Opening review sends nothing; **Confirm and send** explicitly submits.
- Results distinguish confirmed, rejected, and unknown outcomes. Confirmed
  transfers refresh balances and history and display their transaction reference.
- Activity loads the selected account's history in pages of 20. Details are read
  from the reference endpoint and show direction relative to that selected account,
  type, status, accounts, date, remark, and fee. Refresh failures retain labeled
  last-known data; private content clears on sign-out or session invalidation.
- USD uses exact cents and at most two entered decimal places; KHR uses whole
  units. Canonical decimal strings are sent without binary floating-point money.
  Account numbers and references can be selected and copied.
- Native API mode supports transfers. Explicit demo and browser previews do not
  offer real transfer submission or simulate financial success on API failure.

## Submission and restart safety

Confirmation generates a random idempotency key and saves the immutable request
in native secure storage **before** the POST. Storage is scoped to backend, mode,
and verified user. Duplicate taps and competing local claims cannot create another
pending intent. The original key and payload are retained until a definite result
is durably saved and the customer acknowledges it.

A timeout, malformed response, authentication failure, unexpected server error, or
idempotency conflict leaves the outcome unknown. Restart reads the saved intent;
it never automatically sends it. **Retry this exact transfer** explicitly reuses
the original key and unchanged payload, allowing the backend to return a previously
committed result without posting again. The screen explains that retry may complete
an unprocessed request. An unresolved intent cannot be discarded to start a new
payment. Logout hides its details while retaining the user-scoped safety record.

Known transactional rejections (including insufficient funds, inactive accounts,
currency mismatch, and invalid requests) are saved as rejected. Corrupt records or
secure-storage failures block sending and provide secure-setup retry. A lost save
after a successful POST preserves the original recovery record. Successful and
rejected records survive process termination until explicitly acknowledged.

This uses the existing server idempotency contract. It adds no payment-status API
and does not change F3's separate policy against replaying account creation.

## API contract

Paths below are relative to `/api/v1` and use the signed-in access token.

| Purpose | Existing API |
| --- | --- |
| Submit or explicitly retry | `POST /transactions/transfer`, original `Idempotency-Key` |
| Selected account history | `GET /transactions/account/{accountNumber}?page=0&size=20` |
| Reference details | `GET /transactions/{referenceNumber}` |
| Refresh balances | `GET /accounts/me`, `GET /accounts/{accountNumber}` |

The client validates envelopes, pagination, account participation, reference, exact
amount/currency, and transfer receipt fields. It never queries another customer's
private account API to discover a recipient name. Backend ownership, atomicity,
locking, audit, and idempotency remain authoritative.

## Automated verification

- Flutter analysis: clean.
- Flutter suite: 86 tests passed, including 20 new transfer/history/controller/UI
  tests. Covers exact HTTP payloads, duplicate taps, committed-response loss,
  restart recovery, storage failures, journal corruption and competing claims,
  authentication/logout privacy, ownership validation, and history pagination.
- Layout and accessibility: small portrait and landscape, large text, dark theme,
  reduced motion, semantics and Android tap targets. Visual fixtures rendered
  entry, review, confirmed result, history, and detail screens.
- Backend regression: 83 tests passed, zero failures/errors/skips. `mvnw test`
  preserved the already-running backend JAR; clean verification remains an F5 task.

Local commands from `frontend/customer_app`:

```powershell
flutter analyze
flutter test
flutter test tool/f4_visual_qa.dart
```

Visual QA requires `FLUTTER_ROOT`; screenshots are ignored under `.local/qa/f4`.
Logs are local artifacts under `D:\CodexQa\AiDigitalBankingF4`.

## Gmail and native acceptance

Real Gmail LOGIN completed for the existing customer aliases
`sengsovaneach+f3customer1@gmail.com` and
`sengsovaneach+f3customer2@gmail.com` on the Android 14/API 34 emulator
`Codex_F2_API34` (`emulator-5556`). A separate active USD recipient account was
opened for customer 2; no new customer or staff identity was created.

Verified against the already-running local backend:

- USD 5.00 sent through the review/confirm UI, with corresponding debit, credit,
  reference, and outgoing/incoming detail views.
- Replaying its identical key/payload returned the same reference and did not
  debit twice.
- Insufficient funds, currency mismatch, and a closed recipient were rejected
  without changing the source balance.
- A USD 1.00 own-account transfer remained inaccessible to the other customer;
  that customer also received 404 for the source account's history.
- A further USD 1.00 transfer committed while the test wrapper deliberately hid
  the response. The UI displayed an unknown outcome and retained its intent.
- After verified process termination, the same user/session and installation
  restored, the refresh token rotated, and no transfer POST occurred on startup.
  Explicit retry used the original key/payload and returned the original reference.
  Both balances remained unchanged and history contained one matching record.
- Both customers signed out. Another process launch confirmed both refresh tokens
  remained absent, the Welcome screen appeared, and QA evidence was removed.
- Customer 2's received total was USD 6.00. The source's debit total was USD 7.00,
  including USD 1.00 credited to its owner's other account.

The initial seed stopped after the successful ownership assertions because the
test still expected the old Transfer button label. A continuation then exposed a
test timing assumption during secure-storage loading. The harness was corrected
to wait for the intended action, and `response_loss` and `restore` passed without
repeating completed transfers or resetting data. The final `signedout` process
also passed. See `native-seed.log` (completed prefix) and
`native-recovery-final.log` (three passing continuation/restart phases) in the
local log directory. The normal application is rebuilt after this test APK.

The normal `lib/main.dart` debug APK was rebuilt for the emulator and installed.
Its kernel contains the normal entrypoint and no integration entrypoint/listener,
QA password, or bridge key (artifact checks passed). The visible app restored the
pre-existing normal customer-1 session, showing savings USD 18.50 and checking
USD 1.00; QA logout checks used their separate namespaces. The manual OTP bridge
was stopped. The visible emulator, pre-existing backend, PostgreSQL, and local
development changes were preserved. This x64 debug artifact verifies the emulator,
not a release or an ARM physical-device build.

The opt-in `integration_test/f4_gmail_test.dart` uses the approved F3 Gmail aliases,
the real backend, and a loopback manual OTP bridge. It never reads the mailbox,
captures SMTP, or bypasses OTP. Its `seed`, `restore`, and `signedout` phases use
separate application processes and isolated secure-storage namespaces. QA secrets
belong only in the ignored `.local/f3-qa.json`; never commit or distribute the test
APK. The normal application must be rebuilt and installed after acceptance.

```powershell
python tool/gmail_qa_bridge.py --config .local/f3-qa.json
# In another terminal with Flutter available:
./tool/verify_f4_restart.ps1
```

Seed creates a separate active USD recipient account and spends USD 7.00 from the
approved funded customer: USD 5.00 to the other customer, USD 1.00 to an own account,
and USD 1.00 whose committed response is deliberately hidden by the test wrapper.
It preserves all resulting financial records. Do not rerun seed against an
unfinished attempt; inspect the retained safety record and resume the appropriate
phase. The helper force-stops and verifies process termination between phases.
The optional `response_loss` continuation is only for a seed interrupted after
the confirmed receipt and ownership checks: it requires that saved success record,
reuses its two account numbers, and runs only the remaining USD 1.00 lost-response
scenario. It does not repeat the completed transfers or create another account.

## Remaining foundation scope

F5 covers the final end-to-end acceptance, clean backend verification and migration
checks, setup/demo handoff, and any targeted fixes those checks reveal. Android 14
emulator evidence does not establish untested device or platform support.
