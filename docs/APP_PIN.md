# Customer app PIN

Implemented 30 October 2026 from live Figma section `280:1494`: Create your PIN
(`264:630`), Confirm PIN (`253:1161`) and Enter PIN (`253:1309`). Original SVGs,
Poppins weights, source geometry and blurred decorative Home layers are used.
All fields start empty; a gold outline indicates focus, not an entered digit.

## Customer journey

After verified email/Telegram continuation and profile completion, the normal
Flutter entrypoint requires four digits and a matching confirmation before Home.
Returning customers with an existing PIN see Enter PIN. Leading zeroes are valid.
The PIN is account-level; each installation keeps its own revocable session ticket.

A cold native launch restores only the locked ticket. Backgrounding clears banking
tokens and partial PIN input; resuming requires another PIN entry. Inactive state
covers private content immediately. The app's own OS profile-photo picker has a
bounded 60-second handoff so selecting a photo remains possible; exceeding that
lease locks the app. Web uses memory-only storage and locks on hidden lifecycle.

Five incorrect PIN submissions lock PIN verification until identity recovery.
The budget is persisted on the server across app/server restarts, concurrent
requests and fresh logins. A successful unlock resets the budget. There is no
client clock cooldown that can bypass the server budget.

Forgot PIN discards the previous ticket and requires verified email or Telegram,
then Create and Confirm a replacement PIN. A session that has just verified its
identity can recover directly for ten minutes, provided it has never unlocked
with a PIN. Initial enrollment also requires this fresh identity. Recovery intent
is bound to the original customer. Reset revokes their other sessions. Expired or
revoked tickets require full continuation again. OTPs remain entered in the app.

## Server and storage

Additive Flyway **V13** introduces `customer_app_pins` and `app_pin_locks`; V12
contains the previously implemented profile photos. The existing development
database remains V11 until its next normal source startup applies V12 and V13.
No migration was manually applied and no real customer or balance was changed.

POST routes under `/api/v1/auth/pin`:

| Route | Credential | Result |
| --- | --- | --- |
| `/prepare` | Authenticated customer access token | Locks session; issues opaque ticket and challenge |
| `/status` | Ticket in JSON body | Locks session; returns configuration and attempt status |
| `/setup` | Ticket, `pin`, `confirmPin`, `reset` | Fresh identity enrollment/recovery; unlocked token pair |
| `/unlock` | Ticket and PIN | Checks persistent attempt budget; unlocked token pair |
| `/discard` | Ticket | Revokes its session |

Responses use the existing envelope and no-store headers. Ticket routes are
public in the bearer filter because the private ticket is their credential.
Tickets are random 256-bit values, hashed in PostgreSQL, session/device bound,
and inherit normal session expiry/revocation. They are never URL parameters.

PIN verification uses BCrypt over domain-separated HMAC-SHA256 of customer ID
and PIN. Server-only `app.pin.pepper` defaults to the existing JWT signing secret;
keep it stable, private and backed up. Rotating it invalidates existing PIN hashes
and requires verified recovery. No new secret is embedded in Flutter. PINs and
tickets are not written to application/audit logs; audit records contain metadata.

The secure native vault stores the ticket and minimal challenge metadata, never
the PIN or a PIN-enabled banking refresh token. Unlocked tokens live in memory.
Prepared sessions cannot use banking endpoints or refresh while locked. Every
unlock advances an access-token epoch so an earlier token stays invalid after
subsequent unlocks. Legacy raw refresh credentials migrate through preparation.
The normal `main.dart` always injects the PIN gateway; legacy primary-auth API
clients remain backward compatible until they opt into `/prepare`.

Explicit demo mode uses an in-memory demonstration gateway; it is not persistent
server security and is never selected as a fallback for an API failure.

## Verification and evidence

Backend integration checks use isolated PostgreSQL and local test mail, including
leading zeroes, format validation, locked banking/refresh access, token epochs,
five persistent failures, parallel guesses, verified reset and server restart.
Flutter checks cover setup/confirmation, restart, attempt lock, recovery, another
customer, late responses, keypad editing and lifecycle privacy/partial clearing.
`tool/pin_visual_qa.dart` renders native Flutter controls at 440×999 plus narrow,
large-text, Khmer, landscape and tablet sizes and asserts reference geometry.
Evidence is ignored under `frontend/customer_app/.local/qa/pin/`.

Verification: **123 backend tests** passed. The full Flutter regression and both
PIN/email visual fixtures covered **149 checks**; the lifecycle fixture was
corrected to use valid Flutter state transitions and its nine-test file rerun
successfully. Flutter analysis reports no issues. These checks do not establish
physical-device acceptance.

The API-mode web build and Wasm dry run succeeded using `APP_ENV=dev` and
`API_BASE_URL=http://127.0.0.1:8080/api/v1`. The browser build retains memory-only
session storage, as before; persistent cold-launch PIN restoration targets native.
The normal-entrypoint Android debug APK also built successfully with those API
defines at `build/app/outputs/flutter-apk/app-debug.apk` (204,601,646 bytes).
It supersedes the earlier email-auth/Analytics builds. The temporary build daemon
was stopped after completion to release memory on this 8 GB workstation.

Physical-device acceptance and a complete live email/Telegram/PIN journey remain
pending. Development backend/emulator remain stopped; PostgreSQL was left running.
