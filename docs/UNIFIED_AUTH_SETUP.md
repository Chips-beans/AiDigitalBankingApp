# Unified customer authentication

30 October PIN update: after verified continuation and profile completion, the
normal Flutter app requires Create/Confirm PIN or Enter PIN before banking.
Five wrong attempts require verified recovery; reopening/backgrounding locks.
Read [APP_PIN.md](APP_PIN.md) for ticket/token lifecycle, recovery and V13 schema.
Legacy primary-auth API clients remain compatible until `/auth/pin/prepare`.

30 October 2026 UI update: email entry, verification and onboarding now follow
Figma section `253:1457`. The user requested persistent profile photos as well;
authenticated own-photo GET/PUT and additive schema V12 are implemented. Read
[EMAIL_AUTH_SCREENS.md](../frontend/customer_app/docs/EMAIL_AUTH_SCREENS.md) for
the photo contract, validation, screenshots and current acceptance limits. The
development database remains V11 until the next normal startup. “Create Account”
in the new design completes a profile and does not open a financial account.

Customers enter through Continue with Telegram or Continue with Email. New and returning identities share each flow. Legacy password endpoints remain available for existing integrations and staff QA, but are not shown in the customer welcome UI.

Native Android support was subsequently added; see [NATIVE_TELEGRAM_SETUP.md](NATIVE_TELEGRAM_SETUP.md).
Its verified App Link delivers the code to the installed app, and separate native
endpoints preserve state/nonce/PKCE and one-use exchange. Physical-device approval
is deferred. The browser implementation and its historical verification below
remain separate. iOS integration is not implemented.

## Routing and access

Email uses an expiring, rate-limited, single-use CONTINUE code for both new and returning customers. Merely requesting a code never creates a user or reveals whether a profile exists. Passwordless continuation is limited to customer identities; staff authentication keeps its existing password and OTP requirements.

Telegram uses the authorization-code flow with S256 PKCE, random state and nonce, server-only client credentials, and signature/issuer/audience/expiration validation. Keep BotFather signing at RS256. No additional application OTP is requested. Telegram can require its own authentication challenge.

A newly verified identity creates an onboarding-only profile. The server withholds banking authorities until first and last names are submitted. `/auth/me` supplies `profileComplete`, names, and `telegramLinked`. Interrupted onboarding resumes after session restoration. Existing profiles stay complete under migration V10; no user or balance is reset. A customer profile does not itself open a financial account.

## Local configuration

In the ignored backend `.env`, set `TELEGRAM_CLIENT_ID`, `TELEGRAM_CLIENT_SECRET`, and `TELEGRAM_REDIRECT_URI`. The client secret is not the bot token and must never be put in Flutter settings. The callback is `https://YOUR-HOST/api/v1/auth/telegram/callback`; register that exact URL with BotFather. Blank credentials disable Telegram gracefully while email remains available. `TELEGRAM_FRONTEND_ORIGIN` defaults to `http://localhost:8081`; open the frontend at exactly that origin, or explicitly configure another allowed origin without a trailing slash.

The browser stays at `http://localhost:8081`, which is already a permitted backend CORS origin. A temporary HTTPS tunnel may forward the Telegram callback to the local backend on 8080. Keep its process running; if its hostname changes, update both BotFather and `.env`, then restart the backend. The redirect-based flow does not embed Telegram's JavaScript widget and needs no Trusted Origin entry. Android uses the separate native flow documented above; the shared email flow also supports native clients.

## Browser approval exchange

POST `/api/v1/auth/telegram/start` with deviceFingerprint, deviceName, and optional deviceType. Open the returned authorizationUrl in a window created synchronously on the user's click. Keep flowId and exchangeSecret in that initiating browser's memory. The callback sends a private approvalReceipt only to its browser opener using an exact target origin. The opener validates the callback origin, source window, and flow ID. Exchange flowId, exchangeSecret, and approvalReceipt via POST `/auth/telegram/exchange`. The start secret alone cannot collect another browser's approval. PENDING can be polled; COMPLETE issues app tokens once. Never replay a token exchange after an uncertain response. Restart approval instead.

The HTTPS callback displays a return-to-app message and delivers its private receipt through a nonce-protected script. No app access/refresh token is placed in a URL or callback HTML. Flow secrets are one-use, expire after five minutes, and stale rows are purged when a new flow starts. Closing or cancelling an approval does not automatically create a profile; a successful private exchange does.

## Connecting methods

After recent authentication (within ten minutes), an email customer can connect Telegram from Profile. New Telegram users can choose Connect an existing email profile before completing onboarding. An email code bound to that pending profile proves email ownership; the Telegram identity then attaches to the existing email customer, preserving banking data. The provisional profile is disabled and its sessions revoked. Complete profiles with independent banking histories are never automatically merged. Telegram users can also add a previously unused recovery email from Profile. A profile already containing an email cannot silently replace it.

## Contracts

| Method | Path under /api/v1 | Access |
| --- | --- | --- |
| POST | /auth/email/request | Public; request CONTINUE code |
| POST | /auth/email/verify | Public; consume code and obtain session |
| PATCH | /auth/profile | Authenticated; finish onboarding |
| POST | /auth/email/link/request | Authenticated; request profile-bound email code |
| POST | /auth/email/link/verify | Authenticated; connect verified email |
| POST | /auth/telegram/start | Public; start approval |
| POST | /auth/telegram/link/start | Authenticated and recent; connect Telegram |
| GET | /auth/telegram/callback | Provider browser redirect |
| POST | /auth/telegram/exchange | Public route; private flow secret required |

Swagger's foundation group includes these nine new paths. Sensitive authentication responses are not cacheable.

## Verification

Backend: `./mvnw.cmd test` from backend/digital-banking. Isolated PostgreSQL/SMTP tests cover new/returning email, onboarding restrictions and completion, token rotation, Telegram cancellation/expiry, bound one-use exchanges, identity linking, staff restrictions, and RSA token verification failures. They do not send real email or approve a real Telegram account.

Flutter: `flutter analyze`, `flutter test`, and `flutter build web` from frontend/customer_app. Widget tests cover the two-option welcome, OTP mistakes, onboarding, returning users, sign-out, text scaling, landscape/tablet layouts, and accessible target sizes. Native live Gmail and restart harnesses remain opt-in; their historical evidence does not establish acceptance of this new browser flow.

The supplied reference is retained unmodified in assets/auth; the welcome layout clips it to show only its illustration, then renders real accessible logo/text/buttons below. The Telegram SVG comes from telegram.org/img/t_logo.svg. The short in-app service/privacy descriptions should be replaced with operator-approved full policies before a production release.

### Local verification, 29 October 2026

- All 105 backend tests passed, including migration/restart and the new continuation/security cases.
- Flutter analysis is clean; all 96 VM/widget tests passed. The development web release build and Wasm compatibility dry run succeeded.
- Inspected the compiled welcome, email, code, and information screens in Chromium. Browser-context fixtures exercised email continuation through Home without sending real mail or creating a real profile. The browser installation-ID regression was fixed after this check exposed a JavaScript integer-shift difference.
- Exercised Telegram cancellation through the real HTTPS tunnel and backend callback, with only the provider navigation simulated. The callback receipt returned to the original window and produced the expected cancellation state with no browser errors. The source-window comparison uses JavaScript strict identity, avoiding cross-origin Dart dispatch-property access.
- Removed the browser fixtures and opened the real Telegram authorization page; it recognized kesorbankbot and the callback configuration. No personal Telegram account was approved. The final successful personal-account login remains a user-operated live check.
- The optional standalone `flutter test --platform chrome test/browser_auth_test.dart` runner stalled before executing tests on this workstation and was stopped. It is not recorded as passing; actual compiled-browser checks above provide the browser evidence.
