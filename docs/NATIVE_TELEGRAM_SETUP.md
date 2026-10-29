# Native Android Telegram login

Implemented 29 October 2026. Physical-device acceptance is deferred at the user's
request: prepare the build now and test the phone later.

## Registration

The user registered `com.bank.customer_app` with @kesorbankbot and supplied
`https://app937652339-login.tg.dev`. Telegram's Android instructions use the
`/tglogin` callback path, so the configured return URI is:

`https://app937652339-login.tg.dev/tglogin`

The domain's public `/.well-known/assetlinks.json` was retrieved and contains the
project's package and current development signing certificate. Android still needs
to verify that association on the installed physical device. Release signing must
be registered separately when the app stops using the current debug certificate.

## Implementation

The Android bridge uses Telegram's native authorization protocol, documented by
the official SDK source, with server-generated state, nonce, and S256 PKCE. It
requests Telegram's `/crossapp` authorization URL and opens the Telegram app. If
that flow is unavailable, it opens the same authorization request in the system
browser and receives the result through the installed app's verified App Link.
There is no embedded WebView or popup/opener dependency on Android.

The published SDK currently has no state/nonce configuration hook. Rather than
weakening the existing backend verifier, the bridge implements the protocol and
keeps the verifier and token exchange on the backend. No GitHub package-download
credential or extra Flutter dependency was introduced. Provider compatibility of
the native request's state/nonce must still be confirmed by live acceptance; a
missing or incorrect nonce fails closed.

New endpoints under `/api/v1`:

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/auth/telegram/native/start` | Public; create a five-minute native flow |
| POST | `/auth/telegram/native/link/start` | Authenticated, recent customer session; link Telegram |
| POST | `/auth/telegram/native/exchange` | Private flow secret and returned authorization code; one attempt |

The callback must match the registered HTTPS host/path and the active local state.
Unsolicited, duplicate-parameter, and unrelated callbacks cannot install a session.
The backend verifies Telegram's RS256 signature, issuer, audience, nonce, issued-at,
expiry, and subject before reusing the existing customer/session/onboarding logic.
Native and browser flows cannot be completed through each other's endpoints.

The native flow is committed as consumed before the outgoing provider exchange.
Failure or an uncertain response requires a fresh user-initiated approval. No
automatic retry of the code/token exchange occurs. A late session received after
local cancellation is revoked where possible instead of being installed.

Flow state stays in memory on Android. Killing/recreating the activity or process
during approval discards the local attempt; begin a new login. An unsolicited cold
start callback never signs the user in. Existing completed native sessions still
restore through secure refresh-token storage. No email/app OTP is added.

Migration `V11__native_telegram_flows.sql` adds native mode and a pinned return URI
to the existing flow table. V10 is unchanged. V11 is exercised by isolated backend
tests; the existing development database has NOT been started or upgraded for this
task. Its next normal backend startup will apply V11.

## Local configuration and prepared APK

The ignored backend `.env` now has a single assignment:

```dotenv
TELEGRAM_NATIVE_REDIRECT_URI=https://app937652339-login.tg.dev/tglogin
```

The existing client ID/secret, browser redirect, and frontend-origin settings are
preserved. No server credential is copied into Flutter or this document.

The development APK is built with:

```powershell
# From frontend/customer_app
flutter build apk --debug --dart-define=APP_ENV=dev --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
```

This build is for USB testing. Its local HTTP setting is explicit development
configuration; production's HTTPS guard remains enforced. It includes the normal
API entrypoint, not a demo or integration-test entrypoint.

## Physical-device test later

1. Connect the Android phone over USB, enable USB debugging, accept the computer
   authorization, and check `adb devices -l`. Have Telegram installed and signed in.
2. Keep PostgreSQL running. Start `./mvnw.cmd spring-boot:run` from
   `backend/digital-banking`. This applies V11 normally; preserve the existing data.
3. Run `adb reverse tcp:8080 tcp:8080` so the phone can use this APK's localhost API.
   This forwarding is needed again after reconnect/restart. No temporary callback
   tunnel is required: Telegram's registered domain returns directly to Android.
4. Install the prepared APK as an update (`adb install -r <apk-path>`). Do not
   uninstall or clear existing app data, secure sessions, or financial recovery.
5. Check the OS association with
   `adb shell pm get-app-links com.bank.customer_app`. The Telegram domain must be
   verified before relying on automatic return to the app.
6. Press Continue with Telegram and approve personally in Telegram. Enter all
   provider challenges there; do not paste codes or credentials into chat.
7. Verify return to the app, new-user names, subsequent return-to-Home, optional
   linking, cancellation, missing Telegram/browser fallback, expiry, and recovery
   after app termination/network interruption. Confirm refresh restoration/logout.

No physical-device approval, provider code exchange, or successful native live
login is claimed by automated fixture tests or an APK build. iOS is not implemented.
For use away from a USB-connected computer, configure a reachable HTTPS backend
and rebuild; hosted staging is a separate deployment step.

## References

Final verification: Flutter analysis clean; 120 Flutter tests passed; 110 backend
tests passed with zero failures/errors/skips, including isolated V10-to-V11
preservation and server restarts. Android debug APK, development web build and
Wasm dry run succeeded. The built Android manifest and signing certificate match
the registered package/link/certificate. No `.env` is packaged and configured
Telegram/JWT/email secret values were absent from the APK.
No personal-account approval, device link verification, or native live exchange
was performed. No development backend, tunnel, emulator, or preview is running.

APK: 179,119,467 bytes. SHA-256:
`41cca7c500ffb2be7d5bcbf624045583a1c0330d0094dfe7b06c8b496a847454`.

Local ignored evidence: `backend/digital-banking/.local/native-telegram-*` and
`frontend/customer_app/.local/qa/native-telegram-*`. The initial full backend run's
outdated migration-count assertion and the initial HTTP fixture's missing success
envelope were corrected; the final checks above passed.

## Source references

- [Telegram login](https://core.telegram.org/bots/telegram-login)
- [Official Android SDK setup](https://github.com/TelegramMessenger/telegram-login-android)
- [Native protocol source](https://github.com/TelegramMessenger/telegram-login-android/blob/main/TelegramLogin/src/main/java/org/telegram/login/TelegramLogin.kt)
