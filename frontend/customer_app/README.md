# Digital Banking Customer App

F2 implements customer registration, email OTP login, session restoration,
refresh, read-only identity, and logout using the existing Spring Boot API.
Biometric authentication is excluded. Accounts and balances begin in F3;
transfers and history follow in F4.

## Run against the local backend

Start one backend on port 8080 and Mailpit on ports 1025/8025 using
[the local setup guide](../../docs/FOUNDATION_LOCAL_SETUP.md). From the repository root:

```powershell
cd frontend/customer_app
flutter pub get
flutter devices
flutter run -d emulator-5554
```

Use the available Android device ID from `flutter devices`. Android emulator
development defaults to `http://10.0.2.2:8080/api/v1`; desktop defaults to
`http://localhost:8080/api/v1`. Physical devices need the backend computer’s LAN address:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.25:8080/api/v1
```

Create a profile with a unique username and email. With local Mailpit, a test address
such as `my.customer@example.test` works without a real mailbox. Open
[the local inbox](http://127.0.0.1:8025), find that recipient’s latest SIGNUP or LOGIN
email, and paste its six-digit code into the app. A real SMTP configuration instead
delivers to the real email address you supply. The app never reads the inbox itself.
Signup signs you in and does not create a bank account.

## Explicit demo preview

```powershell
flutter run --dart-define=APP_MODE=demo
```

Demo mode displays a permanent banner, sends no email or API requests, and accepts
OTP `123456`. It is a UI simulation, not banking evidence. Real API failures never
activate demo mode. APP_MODE defaults to api; demo is rejected in APP_ENV=prod.

Browser preview:

```powershell
flutter run -d chrome --web-port=8081
```

Port 8081 matches the default backend CORS origin. Browsers use an explicitly
in-memory session: reload requires sign-in. Native Android uses secure storage.
The browser preview is not the acceptance target for persistent mobile sessions.

## Session behavior

- Only the refresh token and random installation identifier persist in native
  secure storage. Access tokens remain in memory; passwords and OTPs are never
  persisted or logged. Pending credentials are discarded on cancel, successful
  authentication, or ten minutes of waiting for OTP.
- Restoration rotates the refresh token and verifies the server identity before
  showing private content. A shared renewal serves concurrent expired reads.
- A refresh token is removed locally before sending it. If the response is lost,
  sign in again: replaying the old token could revoke the server session.
- Online logout revokes the server session and clears local state. Offline logout
  clears local state and reports that remote revocation was not confirmed.
- Native secure-storage failures block authentication with a retry screen; they
  never cause a plain-text or in-memory fallback.
- Storage namespaces separate backend URLs and demo/API mode. The installation
  identifier survives ordinary logout and is not hardware or biometric identity.

Release builds default to APP_ENV=prod and require an explicit HTTPS endpoint:

```powershell
flutter build apk --dart-define=API_BASE_URL=https://your-bank.example/api/v1
```

Development cleartext is allowed only by the existing Android debug/profile
manifests. Apple/Linux runners remain scaffolding and need their platform setup
and device verification before support is claimed.
Release signing still uses the Flutter template debug key; deployment signing
and store publication are outside this local foundation milestone.

## Verification

```powershell
flutter analyze
flutter test
# Requires the local backend and Mailpit; creates an unfunded QA customer:
flutter test tool/live_backend_qa.dart
# Also requires a running Android emulator and native build dependencies:
flutter test integration_test/auth_flow_test.dart -d emulator-5554
# Three fresh native app processes; the script preserves installation with --no-uninstall:
.\tool\verify_native_restart.ps1 -Device emulator-5554
# Optional screenshots in ignored .local/qa (FLUTTER_ROOT must identify the SDK):
flutter test tool/visual_qa.dart
```

Live tests use only unique QA identities, do not touch fixture balances, and never
print credentials, OTPs, or tokens. Unit tests cover HTTP errors, native-storage
contracts, renewal concurrency, privacy cleanup, validation, navigation, semantics,
and small-screen/large-text layouts. See [F2 delivery and QA](../../docs/FOUNDATION_F2_IMPLEMENTATION.md).

## Structure

- `lib/main.dart`: configuration and dependency composition.
- `lib/app/`: Material theme, declarative public navigation, session guard.
- `lib/core/`: environment, HTTP envelopes, errors, and secure storage.
- `lib/features/auth/`: API/demo gateways, session controller, auth screens.
- `lib/shared/widgets/`: loading, error/notice, and pending-submission controls.
- `test/`, `tool/`, `integration_test/`: local, live API, visual and device QA.

The package is customer_app; Android application ID is com.bank.customer_app.

F2 native authentication and all three restart phases passed on the isolated
Android 14/API 34 emulator `Codex_F2_API34` (port 5556), stored under
`D:\CodexQa\AiDigitalBankingF2\avd-api34`. The restart check verifies the same
customer/session and installation, refresh-token rotation, and persistent logout.
The script force-stops and checks process termination between phases. Running
without `--no-uninstall` would delete app data instead of testing persistence.
See the [F2 QA evidence](../../docs/FOUNDATION_F2_IMPLEMENTATION.md) for the
test-harness fixes and emulator limitations.

The older `Codex_F2_QA` emulator remains under
`D:\CodexQa\AiDigitalBankingF2\avd`; its failed system-service runs are not passing
evidence. Generated build output is on D: through a local build-directory
junction because C: ran out of space. These are ignored local artifacts, not
requirements for another checkout.
