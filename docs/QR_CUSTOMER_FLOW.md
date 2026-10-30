# Customer QR transfers and funded account pairs

Implemented 30 October 2026. This is the current customer implementation; older QR
engine documentation does not establish external Bakong/KHQR settlement.

## Opening accounts

After onboarding and PIN setup, **Open accounts** explicitly creates a USD and KHR
pair of the chosen type. Nothing is opened automatically during authentication.
`POST /api/v1/accounts/pairs` accepts `{ "accountType": "SAVINGS" }` and requires
an `Idempotency-Key`. The standard response envelope contains `accounts` (two
ordinary account DTOs) and `testFundingApplied`. Identical retries return the
original opening response, even if balances have subsequently changed. Refresh
account details for current balances. Changed requests under the same key conflict.

`GET /api/v1/accounts/opening-policy` returns `testFundingEnabled`,
`usdOpeningBalance`, and `khrOpeningBalance` in the normal envelope. The server
controls funding. With `TEST_OPENING_FUNDING_ENABLED=true`, a new USD account
receives **200.00 USD** and a new KHR account **100,000 KHR**. Without the flag,
both start at zero. The flag defaults to false in source. It is permitted only
with an explicit `local`, `dev`, `test`, or `staging` profile and causes startup
failure with `prod`/`production`, even when mixed with an allowed profile.
The user's ignored development `.env` now enables this flag for the next backend
startup; other settings and credentials are preserved. No existing balance was changed.

Pair creation, credits, history entries, request receipt and audit records commit
together. Credits are DEPOSIT transactions with operation `TEST_OPENING_CREDIT`
and a test-funds remark; they appear as income in Analytics. Existing accounts are
never topped up. Restart, login, refresh and idempotent replay do not add funds.
The public deposit endpoint remains staff-only. The legacy single-account
`POST /accounts` remains zero-funded and compatible; the Flutter opening UI uses
the pair endpoint exclusively.

Native paired-opening requests are saved in secure storage before submission.
Timeouts, response loss and process restarts retain the immutable key/type for an
explicit retry. Browser/demo records remain memory-only, shared across PIN gates
within the same app lifetime. Existing uncertain single-account markers stay in
their old namespace and block a new opening until reviewed; they are not retried
as paired requests.

## Receiving and paying

Home **My QR** and account details open the receiving screen. Select an active
owned account. The default QR is reusable and stable across repeat/concurrent
generation. **Request an amount** creates a distinct one-time fixed request; two
requests with the same amount have different server references. Payment status
polling runs only while that fixed request is visible and the session is unlocked.

Home **Scan QR** supports the Android/iOS camera and local JPG/PNG image import.
Image import is limited to 5 MB and 16 million pixels. Camera/image decoding is
local; only QR text is sent to the API. No scanned URL is opened. Camera capture
stops after detection, on inactivity, and on navigation. Image selection uses the
existing bounded 60-second trusted-picker handoff; ordinary backgrounding still
locks the app. Android camera permission and the iOS camera purpose are declared.

The server resolves the recipient from a registered internal account QR, checks
the exact stored payload and configured internal identifier, and enforces active
accounts and matching currencies. The app presents the recipient, account, source
account and amount before the customer confirms. Static payments require an
entered amount; fixed requests cannot be overridden. USD uses cents; KHR is whole
units. Cross-currency transfers and external bank QR payments are not supported.

Routes under `/api/v1/payments`:

| Route | Behavior |
| --- | --- |
| `POST /qr/generate` | Owned account, currency and STATIC/DYNAMIC type; fixed requests need a positive amount. Returns the existing QR DTO/envelope. The bill reference is server-generated. |
| `POST /qr/scan` | Validates registered QR text and returns verified recipient details; does not transfer money. |
| `POST /qr/transfer` | Required Idempotency-Key and immutable QR payment body. Returns the existing QR response plus `transaction`, the standard transaction receipt. |
| `GET /verify/{hash}` | Owner-only fixed-request status. Legacy flat fields remain; an additive `success: true` supports the shared Flutter client. |

QR payment claims are serialized before the paid check, so a successful replay
returns its original receipt. A different payment against a completed fixed
request fails. Fixed requests are locked while settling, so concurrent payers
cannot both succeed. Static QR codes are never consumed. Manual and QR financial
keys use separate operation namespaces.

QR payments share the existing transfer safety journal and controller. Native
version-2 records include the QR payload and recipient name. Existing version-1
manual records remain readable. Only one unresolved manual/QR payment is allowed.
Unknown outcomes persist through PIN locking and restart and are never
automatically resubmitted. Explicit retry sends the original request and key.
Browser/demo previews retain their restriction against payment submission.

## Schema, verification and acceptance

Additive V14 creates paired-opening and QR-request receipts and adds QR type and
settlement linkage metadata. Older migrations are unchanged. Development schema
V11 is intentionally not migrated by automated verification: its next ordinary
backend startup applies V12, V13 and V14. Keep backend `.env` values private.

Automated verification commands, run sequentially on this 8 GB workstation:

```powershell
# backend/digital-banking — isolated embedded PostgreSQL and local SMTP
.\mvnw.cmd test

# frontend/customer_app
flutter analyze
flutter test --concurrency=1
flutter test tool/qr_visual_qa.dart
flutter build web --dart-define=APP_ENV=dev --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
flutter build apk --debug --dart-define=APP_ENV=dev --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
```

Focused backend tests perform the real HTTP journey with two controlled customers
in isolated PostgreSQL: funded pairs, USD 10/KHR 10,000 payments, repeated static
payments, fixed-request settlement, histories, concurrent attempts and retries.
Restart checks preserve paired-opening and completed fixed-payment receipts.
Flutter tests cover storage, late responses, shared unresolved intents, camera
permission/capture lifecycle, image import/cancellation and adaptive Khmer UI.
Visual fixture renders are ignored under `.local/qa/qr/`; hardware camera calls in
widget tests use a fake platform. Test results/build status are recorded in the
latest project handoff.

Physical-device camera/file-picker acceptance and a complete personal live
email/Telegram/PIN journey remain separate manual checks. On Android, use the
prepared API-mode APK and `adb reverse tcp:8080 tcp:8080`. Confirm USD and KHR
payments between two controlled customer profiles and inspect both histories.
iOS code is included; native iOS build/device verification requires a Mac/device.
No external settlement, provider certification or production deployment is claimed.
