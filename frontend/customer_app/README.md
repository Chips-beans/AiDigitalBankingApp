# Digital Banking Customer App

Start with the [progress and agent guide](../../docs/PROJECT_PROGRESS_AND_AGENT_GUIDE.md) for
the latest progress, verification limits, next steps, and restart instructions.

The Figma colors and English/Khmer typography are available through the shared
[design system](docs/DESIGN_SYSTEM.md) and are connected to `AppTheme`. The [Home integration](docs/HOME_SCREEN.md)
adds login language/theme controls, themed Home, Figma bottom navigation, and
authenticated balance/activity reads across all owned accounts.

The current welcome screen offers **Continue with Telegram** and **Continue with
Email**. Email uses a single verification-code flow for both new and returning
customers. Telegram browser approval needs no additional app OTP. New identities
complete their first and last names before banking access; existing profiles keep
their data. See [CUSTOMER_APP.md](../../docs/CUSTOMER_APP.md) section 2
for browser callback configuration, identity linking, and updated API contracts.
For a local release web build, use `flutter build web --dart-define=APP_ENV=dev`;
production builds continue to require an HTTPS API.

The foundation implements customer registration, email OTP login, native session
restoration, accounts, exact USD/KHR balances, internal transfer review and
confirmation, restart-safe recovery, paginated history, read-only Profile, and
logout using the existing Spring Boot API. Biometric authentication is excluded.
See the [progress and agent guide](../../docs/PROJECT_PROGRESS_AND_AGENT_GUIDE.md) (section 4) for setup and
[CUSTOMER_APP.md](../../docs/CUSTOMER_APP.md) for the feature contracts.

## Run against the local backend

Start one backend on port 8080 with
Gmail email settings (see the [guide](../../docs/PROJECT_PROGRESS_AND_AGENT_GUIDE.md), section 4). From the repository root:

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

Create a profile with a unique username and a real email address whose inbox you
can access. Read the latest SIGNUP or LOGIN message in that inbox (including Spam)
and paste its six-digit code into the app. The configured Gmail sender and the
recipient email are separate addresses. The app never reads the inbox itself.
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

- Session storage persists the refresh token and random installation identifier.
  Separate user-scoped safety records retain account-opening uncertainty and
  transfer recovery details in native secure storage. Access tokens remain in
  memory; passwords and OTPs are never
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

F3 adds Home, paginated own accounts, precise USD/KHR balances, explicit zero-balance
opening, account details/status, recent activity, and read-only Profile. Account
opening is never automatically replayed; uncertain outcomes are retained in secure
storage across native restarts and require account review plus an explicit new
decision. See [CUSTOMER_APP.md](../../docs/CUSTOMER_APP.md) section 4 for the current account behavior.

F4 adds internal transfer entry, review and explicit confirmation, durable secure
recovery using the original idempotency key, paginated history, and transaction
details. Unknown outcomes require an explicit identical retry; restarting never
sends automatically. Confirmed/rejected records remain until acknowledged, and
unresolved records survive logout without exposing private details. Sending is
available in native API mode. See [CUSTOMER_APP.md](../../docs/CUSTOMER_APP.md) section 5.

```powershell
flutter analyze
flutter test
# Optional screenshots in ignored .local/qa (FLUTTER_ROOT must identify the SDK):
flutter test tool/visual_qa.dart
flutter test tool/f4_visual_qa.dart
```

The historical `tool/live_backend_qa.dart`, `integration_test/auth_flow_test.dart`,
and `tool/verify_native_restart.ps1` rely on a captured-email API and generated
`@example.test` recipients. They were used for the earlier F2 evidence and must
not run against the current Gmail backend. Use a real inbox for live Gmail QA;
the ordinary local Flutter tests above remain independent of email providers.

Live tests use approved QA identities and their funded test balances, and never
print credentials, OTPs, or tokens. Unit tests cover HTTP errors, native-storage
contracts, renewal concurrency, privacy cleanup, validation, navigation, semantics,
and small-screen/large-text layouts. See the [progress and agent guide](../../docs/PROJECT_PROGRESS_AND_AGENT_GUIDE.md) for the test conventions.

## Structure

- `lib/main.dart`: configuration and dependency composition.
- `lib/app/`: Material theme, declarative public navigation, session guard.
- `lib/core/`: environment, HTTP envelopes, errors, and secure storage.
- `lib/features/auth/`: API/demo gateways, session controller, auth screens.
- `lib/features/accounts/`: account/activity gateways, session-scoped state, secure opening guard, and signed-in screens.
- `lib/features/profile/`: read-only verified identity and sign-out.
- `lib/features/transactions/`: exact transfer contracts, secure submission journal, explicit retry, paginated history, and details.
- `lib/shared/money.dart`: exact monetary parsing and USD/KHR formatting.
- `lib/shared/widgets/`: loading, error/notice, and pending-submission controls.
- `test/`, `tool/`, `integration_test/`: local, live API, visual and device QA.

The package is customer_app; Android application ID is com.bank.customer_app.

F2 native authentication and all three restart phases passed on the isolated
Android 14/API 34 emulator `Codex_F2_API34` (port 5556), stored under
`D:\CodexQa\AiDigitalBankingF2\avd-api34`. The restart check verifies the same
customer/session and installation, refresh-token rotation, and persistent logout.
The script force-stops and checks process termination between phases. Running
without `--no-uninstall` would delete app data instead of testing persistence.
Emulator limitations apply to this harness.

The older `Codex_F2_QA` emulator remains under
`D:\CodexQa\AiDigitalBankingF2\avd`; its failed system-service runs are not passing
evidence. Generated build output is on D: through a local build-directory
junction because C: ran out of space. These are ignored local artifacts, not
requirements for another checkout.
