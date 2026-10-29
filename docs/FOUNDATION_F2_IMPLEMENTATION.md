# F2 — Flutter authentication and session foundation

F3 now builds on this session foundation with accounts, balances, recent activity,
and Profile. Its separate non-authentication opening-uncertainty flag and current
Gmail/native acceptance are documented in [F3 delivery](FOUNDATION_F3_IMPLEMENTATION.md).

Implemented 17 October 2026 in `frontend/customer_app`.

**Live email update, 19 October 2026:** use [Gmail email setup](GMAIL_EMAIL_SETUP.md)
for current live runs. Mailpit-based commands and results below describe the
historical F2 acceptance environment. The captured-inbox test drivers use generated
`@example.test` recipients and must not run against the Gmail backend.

Implementation, local/live API QA, and Android emulator acceptance are complete.
Native authentication and the three-process persistence/rotation/logout check
passed on 17 October 2026 using the isolated Android 14 (API 34) QA emulator.
Physical-device and other-platform acceptance are not claimed.

## Delivered behavior

The counter app is replaced by welcome, registration, email/password login, OTP,
session restoration, and a signed-in identity screen. Signup signs the customer
in immediately. The identity screen deliberately contains no fabricated accounts
or balances; account opening and balance screens belong to F3.

Requests use the existing `/api/v1/auth` endpoints: request-otp, register, login,
refresh, me, and logout. OTP submission carries the original credentials and
installation information to register/login. There is no separate verification
endpoint. The backend remains responsible for OTP eligibility, lifetime, attempts,
resend throttles, credentials, current roles, and session/device revocation.

Presentation depends on an AuthGateway contract. HttpAuthGateway is the default;
DemoAuthGateway is explicitly selected with APP_MODE=demo in development and
always displays a banner. API errors never switch to demo data. Production
configuration rejects demo mode and requires HTTPS.

The UI uses Material controls, light/dark themes, persistent labels, paste and
autofill support, password visibility, keyboard-safe scrolling, submission guards,
and accessible notices. Resend and expiry feedback follow server-provided
durations. Unsupported password recovery, account editing, biometric, payment,
assistant, and transfer actions are absent.

## Session and privacy decisions

- Native storage uses flutter_secure_storage defaults without biometric access
  controls. Android backup is disabled. Only a refresh token and a random 192-bit
  installation identifier are stored; namespaces isolate backend URLs and modes.
- Access tokens stay in memory. Credentials remain in a pending OTP draft for at
  most ten minutes, and are discarded on cancellation or authentication. Form
  password/confirmation controllers clear when the draft moves to OTP.
- Startup reads native storage, rotates the saved refresh token, and verifies
  current identity through me before showing protected content. Staff-only
  profiles are rejected and the issued session is revoked where reachable.
- Renewal is shared across concurrent expired reads. Delayed TOKEN_INVALID
  responses reuse the already renewed token instead of rotating again.
- The refresh token is consumed locally before the refresh POST. An uncertain
  result returns to sign-in instead of replaying a potentially used token.
  This intentionally favors avoiding refresh-reuse revocation over offline
  restoration. No POST is automatically retried by the HTTP client.
- Logout hides private content immediately, clears the refresh token, and calls
  server logout. If an expired access token prevents logout, one fresh renewal
  may obtain an access token for revocation. An in-flight renewal is never replayed.
  If offline, the app states that server sign-out could not be confirmed; the
  server session remains subject to its configured expiry/revocation policy.
- Storage failures present a blocking retry screen. No plain-text or memory
  fallback is used on native devices. Browser preview deliberately uses memory
  only and requires login after reload; persistent mobile acceptance is Android.
- Invalid sessions, disabled customers, and revoked devices clear private state.
  Declarative navigation prevents returning to private content after logout.

## Run and test

Follow [local setup](FOUNDATION_LOCAL_SETUP.md), then from `frontend/customer_app`:

```powershell
flutter pub get
flutter run -d emulator-5554
```

Use your actual device ID. Android defaults to `http://10.0.2.2:8080/api/v1`.
Use a unique username/email in registration. Local test email can be an
`@example.test` address: read the latest SIGNUP or LOGIN message for that recipient
at [Mailpit](http://127.0.0.1:8025). The app does not access Mailpit. Real SMTP
requires a real inbox. See the [app README](../frontend/customer_app/README.md)
for physical devices, browser/demo previews, HTTPS release configuration, and
verification commands.

## QA evidence and corrections

| Check | Result |
| --- | --- |
| `flutter analyze` | Passed, no issues |
| `flutter test` | 41 passed, no failures or skips |
| `flutter test tool/live_backend_qa.dart` | Passed against the running local Spring Boot API and Mailpit |
| `flutter test tool/visual_qa.dart` | Passed; rendered welcome, register, OTP, and identity screens for inspection |
| Android APK compilation and installation | Passed using the native secure-storage plugin |
| Normal application debug APK (Android x64 emulator) | Passed with cached Gradle dependencies; kernel includes lib/main.dart and no integration-test listener |
| Android native UI/session integration | Passed on Android 14/API 34: real signup/login through the screens, secure vault recreation, rotation, logout/back guard, and server revocation |
| Cross-process native restart | Passed: seed, restore/rotate/logout, and signed-out phases in three separately terminated app processes |

The live contract QA creates a unique unfunded customer and verifies real OTP
delivery, incorrect-code rejection followed by successful signup, restoration
with token replacement, concurrent renewal, online logout invalidation, incorrect
password rejection, a later successful login, and access rejection after logout.
It uses an in-memory vault, so it does not establish native storage persistence.

Local tests cover HTTP envelopes, malformed responses, safe error messages,
Retry-After, timeouts/no automatic retries, native storage keys and namespace
isolation, pending credential expiry, resend limits, refresh uncertainty, storage
failures, customer-only identity, disabled/revoked sessions, logout concurrency,
screen transitions, validation, and protected back navigation. Widget tests cover
375×667 and 667×375 with 2× text, dark mode, reduced motion, Android touch-target
guidelines, and semantics labels. This is automated accessibility coverage, not a
claim of manual TalkBack testing.

Review corrected late-response null-token access after logout, refresh replay
during logout, redundant rotation from delayed concurrent 401 responses, late
identity responses after automatic invalidation, safe return to welcome after a
storage failure, and pending-draft expiry enforcement at submission/resend.
Tests also corrected their
async-zone setup and screenshot capture; those test harness changes did not
require production workarounds.

The opt-in Android integration test is designed to exercise native secure-storage
controller/vault recreation and server revocation through the actual screens.
Recreation is distinct from a full operating-system process restart. Run
`tool/verify_native_restart.ps1 -Device <device-id>` for three separate app
processes: persist a signed-in QA session, restore it and sign out, then confirm
that another launch remains signed out. The restore phase verifies the same user,
server session, and installation ID, and checks that the saved refresh token
changes. No token is copied into QA evidence or printed. All three phases passed.
Apple/Linux runner setup, physical-device behavior, and release deployment are
outside the verification performed on this Windows host. Historical F1 backend verification
remains 78 passing tests; backend sources were not changed or rebuilt for F2.

## Workstation build notes

The original Pixel_6a emulator had almost no installation space, and the host C:
drive reached zero free space during SDK/Gradle preparation. Only task-created
temporary distribution archives were removed. The existing emulator's apps/data
were preserved. A separate Codex_F2_QA emulator was created under
`D:\CodexQa\AiDigitalBankingF2\avd`; generated Flutter build output was moved to
`D:\CodexQa\AiDigitalBankingF2\build`, with a junction at the original ignored
build path. This is local workspace configuration, not a repository requirement.
Gradle now uses a 2 GB heap and two workers to fit this 8 GB development machine.
The isolated emulator was stopped after verification attempts to release memory.

The normal app APK is at `frontend/customer_app/build/app/outputs/apk/debug/app-debug.apk`
(locally `D:\CodexQa\AiDigitalBankingF2\build\app\outputs\apk\debug\app-debug.apk`).
It is a debug **x64 emulator** build using the real API mode and emulator host
alias; it is not a phone release build. The successful build used the existing
Gradle cache to avoid intermittent network fetch failures:

```powershell
cd frontend/customer_app/android
# JAVA_HOME must identify the compatible Android Studio JBR (Java 21 here).
.\gradlew.bat --offline --console=plain '-Ptarget=lib/main.dart' '-Ptarget-platform=android-x64' '-PskipDependencyChecks=true' assembleDebug
```

Use the standard `flutter run`/`flutter build apk --debug` commands when online;
physical devices also need their reachable API_BASE_URL as described in the README.

APK compilation and installation succeeded. A low-memory emulator showed a
System UI “isn't responding” dialog; a retry with more RAM and a smaller display
showed the Android Bluetooth service repeatedly crashing. The QA emulator's
virtual Bluetooth service was disabled during diagnosis. None of these system
failures establishes an application defect, and neither establishes successful
native end-to-end acceptance. Kotlin/AGP template deprecation warnings remain;
deployment signing still needs configuration outside this local milestone.

### Successful native acceptance retry — 17 October 2026

The Android 36.1 retry again encountered System UI and other system-service ANRs.
It is retained as failed environment evidence, not passing acceptance. A separate
`Codex_F2_API34` emulator was then created at
`D:\CodexQa\AiDigitalBankingF2\avd-api34` using the Android 14 AOSP x64 revision 4
image. Its archive checksum was verified against the SDK repository metadata.
The image and emulator data reside on D:. The emulator ran headless with a
480×960 display, 1536 MB RAM, two virtual CPUs, and software rendering. Virtual
Bluetooth crashed during initial boot and was disabled in this QA emulator.
There were no ANRs during the successful acceptance runs. Existing Pixel_6a and
Codex_F2_QA data were preserved.

Native execution exposed two test-harness issues, both corrected without changing
production authentication behavior:

- Back from Welcome correctly exits Android. The authentication test now opens
  Sign in before exercising Back to Welcome, keeping the remaining test in the
  foreground while checking that protected content cannot return.
- This Flutter SDK uninstalls integration apps after tests by default. The restart
  script now passes `--no-uninstall` to preserve app data and Keystore material,
  explicitly force-stops the app, and checks that no app process remains between
  phases. Reinstalling from scratch is not a process-restart test.

The authentication run finished with `All tests passed!`; restart phases `seed`,
`restore`, and `signedout` each finished with `All tests passed!`, followed by the
script's overall success message. Local logs are retained under
`D:\CodexQa\AiDigitalBankingF2\logs` as `api34-native-auth-fixed.log` and
`api34-native-restart-fixed.log`. The local regression suite also passed all 41
Flutter tests and analysis reported no issues. This closes the F2 Android
emulator gate; it does not establish manual TalkBack, physical-device, iOS, or
release acceptance.

After acceptance, the ordinary `lib/main.dart` x64 debug APK was rebuilt,
installed, and visually checked at Welcome. The output path above therefore
contains the normal app, not the integration harness. The QA emulator and Gradle
daemon were stopped afterward to release workstation memory; the backend and
Mailpit remain running. Build/launch evidence is in `normal-app-final.log` and
`normal-app-welcome.png` in the same local log directory.

All work remains uncommitted. Existing F1/backend changes are preserved. F3
(accounts, balances, and basic profile) is the next feature milestone.
