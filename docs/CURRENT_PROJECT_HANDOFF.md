# Current project handoff — Kesor Bank

Updated 29 October 2026, Asia/Phnom_Penh (UTC+07:00).

## Read this first

The user requested that project terminals and background tasks be closed at the
end of this session. **The application is intentionally stopped.** Do not assume
the URLs mentioned in earlier conversations are still serving an application.

The latest feature is implemented unified customer authentication: one welcome
screen with **Continue with Telegram** and **Continue with Email**, automatic
new/returning profile handling, and onboarding. The main remaining acceptance
step is a successful live login approved by the user with their own Telegram
account. Do not describe that personal-account check as already completed.

Read [UNIFIED_AUTH_SETUP.md](UNIFIED_AUTH_SETUP.md) for the full current auth
contract and [FOUNDATION_F5_HANDOFF.md](FOUNDATION_F5_HANDOFF.md) for the older
banking foundation. F5's V9 schema, 14-route contract, and test counts are historical;
the current schema is **V10**, the foundation API has **23 paths**, and the latest
passing counts are **105 backend tests / 96 Flutter tests**.

## Repository and working state

- Root: `C:\Users\User\Documents\GitHub\AiDigitalBankingApp`.
- Backend: `backend/digital-banking` (contains `pom.xml`, `mvnw.cmd`, and `.env`).
- Flutter app: `frontend/customer_app`.
- Documentation: `docs`.
- Branch at handoff: `main`; HEAD `50eb059` (`add QR code`).
- There is extensive uncommitted/untracked work from multiple earlier milestones,
  including application source, tests, assets, and documents. No commit was created
  for this auth implementation or shutdown. Inspect changes before editing and
  preserve unrelated work. Do not run `git reset`, `git clean`, or replace the checkout.
- Root `AGENTS.md` points to this document and preserves the user's Cloudflare CLI rule.

## Technology and local configuration

Backend uses Spring Boot 4.1.1, Spring Security, Spring Data JPA, Flyway, PostgreSQL,
JJWT, Gmail SMTP, and springdoc/Swagger. Java compilation targets 21; this workstation
used JDK 24.0.2. Flutter was 3.47.5 / Dart 3.13.4 despite the SDK directory's older
version-looking name. Do not infer the active SDK version from the folder name.

The development database is the existing PostgreSQL 18 installation, normally
`localhost:5432/digital_banking_db`. The ignored backend `.env` already contains
database/JWT/Gmail and Telegram settings. Preserve those values, keep one assignment
per key, and never print credentials. Duplicate dotenv keys prevent startup.

Tests use isolated embedded PostgreSQL 14.22 and local SMTP fixtures; they do not
need Docker and must not be redirected to the development database.

## Existing banking foundation

The earlier F1–F5 work delivered:

- Email OTP and legacy password authentication, device binding, revocable server
  sessions, access JWTs, and rotating refresh tokens with reuse detection.
- Customer account listing/details and explicit zero-balance account opening.
- USD cents and KHR whole-unit money handling without floating-point rounding.
- Atomic financial commands, ownership checks, role restrictions, bounded locking,
  idempotent transfers/deposits, database integrity checks, and audit trails.
- Flutter account views, internal transfer review/confirmation/results, paginated
  transaction history/details, profile, session renewal, and logout.
- Native secure storage and restart-safe financial recovery. Unknown transfer
  outcomes preserve the original immutable request and idempotency key; retries
  require explicit user action. Do not clear this state or submit a new transfer
  merely to resolve an uncertain result.
- Gmail delivery setup and opt-in local staff QA fixtures. Existing customer roles,
  staff credentials, account balances, and financial history must be preserved.

Native API mode supports real internal transfer submission. Browser and explicit
demo previews retain the existing restriction against real transfer submission.
Explicit demo mode has its own banner and must never activate after an API error.

QR/payment, merchant, fraud, AI/Gemini, and audit modules also exist in source.
QR tests pass, but this is not evidence of official Bakong/KHQR certification or
external payment settlement. The payment webhook remains denied until provider
verification is implemented. Real Gemini calls were not validated in this session.
Do not label the entire platform production-ready or imply external bank/network
integration is complete.

Earlier in this session the backend could not compile because its QR controller
referenced missing `KhqrGenerateRequest`, `KhqrGenerateResponse`, and `generateKhqr`.
These were restored; the legacy endpoint delegates to the current QR generator and
retains decimal amounts. PostgreSQL was also stopped; the user started its Windows
service with administrator permissions.

## Latest implemented feature: unified continuation

The user explicitly wanted no separate Sign In / Sign Up choice. A verified
identity determines whether to open an existing profile or continue onboarding.

### Customer journeys

1. **Email:** enter an email, request a CONTINUE code, verify the code. Both new and
   returning customers use the same UI and OTP purpose. A request alone creates
   nothing and does not reveal account existence.
2. **Telegram:** approve through Telegram's authorization-code flow. There is no
   additional email/app OTP after Telegram authentication. Telegram may require
   its own login challenge, which our app cannot bypass.
3. Complete existing profiles open Home. Newly verified identities get a pending
   customer profile and a first/last name form. Telegram names prefill when available.
   Incomplete profiles resume that form after reauthentication/session restoration.
4. Completing a user profile does not automatically create a financial account.
5. Customers can connect Telegram from Profile after recent authentication or add
   a recovery email. A pending Telegram profile can verify an existing email and
   attach its Telegram identity to that existing customer. Only onboarding-only
   profiles take this path; complete profiles with independent histories are never
   automatically merged. The provisional profile is disabled and its sessions revoked.

### Backend changes and invariants

- Migration `V10__unified_auth_and_onboarding.sql` was **successfully applied to the
  existing development database**. It adds profile-completion state, a unique opaque
  Telegram subject, and expiring login-flow records; email/password become nullable.
  Existing profiles default to complete. No balance reset or destructive migration
  was performed. Do not edit V10 now that it is applied; use a new migration for changes.
- New users get internal generated usernames. Do not invent fake emails/passwords
  to satisfy legacy model constraints. Telegram does not supply an email claim.
- JWT authentication withholds banking authorities for incomplete profiles, while
  allowing authenticated onboarding routes. Keep this server-side enforcement;
  hiding Home in Flutter alone is insufficient.
- `/auth/me` includes `profileComplete`, `firstName`, `lastName`, `telegramLinked`,
  and nullable email. Flutter handles those fields and routes accordingly.
- Legacy password endpoints remain compatible. Customer passwordless continuation
  does not provide staff a shortcut around password-plus-OTP authentication.
- OTP attempt limits and one-use consumption stay in separate transactions; linking
  codes use a profile-bound purpose. Do not weaken these semantics during refactoring.
- Telegram uses S256 PKCE, random state/nonce, RS256 signature verification with
  Telegram's fixed JWKS endpoint, issuer/audience/expiration checks, and server-only
  client credentials. Keep BotFather's signing algorithm at RS256.
- A private start secret alone cannot collect an approval. The callback delivers a
  separate receipt only to its own opener with an exact target origin; the frontend
  checks callback origin, source window, and flow ID before exchanging it. App access
  and refresh tokens never appear in a callback URL or callback HTML.
- Successful exchange is one-use and expires after five minutes. An uncertain token
  exchange must not be automatically replayed. Expired flow rows are purged on start.

The new auth routes are documented in Swagger and in `UNIFIED_AUTH_SETUP.md`:
`/auth/email/request`, `/auth/email/verify`, `/auth/profile`,
`/auth/email/link/request`, `/auth/email/link/verify`, `/auth/telegram/start`,
`/auth/telegram/link/start`, `/auth/telegram/callback`, and `/auth/telegram/exchange`.
All are under `/api/v1`.

### Main implementation files

Backend under `src/main/java/com/bank/digital_banking/module/auth`:
`controller/ContinuationController.java`, `dto/ContinuationDtos.java`,
`service/ContinuationPersistence.java`, `service/TelegramContinuationService.java`,
`service/TelegramOidcClient.java`, `service/TelegramProperties.java`, and the new
Telegram flow entity/repository. Existing User/session/security/OTP code was adapted.
New test classes: `ContinuationAuthTests` and `TelegramTokenTests`.

Flutter: `lib/features/auth/presentation/continuation_pages.dart`,
`lib/features/auth/data/auth_gateway.dart`, `lib/features/auth/session_controller.dart`,
the conditional `telegram_window*` helpers, `lib/app/banking_app.dart`, and profile
linking controls. `test/widget_test.dart` covers the new journeys;
`test/browser_auth_test.dart` covers installation identity and onboarding restoration.

### Visual reference and browser-specific fixes

The welcome screen follows the supplied illustration, Kesor logo, gold Telegram
button, secondary email button, and simple tagline. The supplied reference is
retained unmodified at `assets/auth/welcome-reference.png`; layout clips it to show
only the illustration. All actual controls and text are accessible Flutter widgets.
The existing logo is reused; the Telegram SVG comes from Telegram's official site.
New assets remain part of the uncommitted working tree and must not be discarded.

Two browser regressions were found and fixed during real compiled-browser checks:

- `MemorySessionVault.installationId()` uses 24 secure random bytes, avoiding
  `Random.nextInt(1 << 32)`, which failed under JavaScript integer behavior.
- Cross-origin popup windows must be compared with JavaScript
  `event.source.strictEquals(_window).toDart`, not Dart overloaded equality. The
  latter attempted forbidden Dart dispatch-property access on WindowProxy and
  blocked the approval response. Keep origin/source/flow validation intact.

Browser sessions intentionally use memory, not native secure storage: a browser
reload requires continuation again. Native sessions retain their existing secure
storage behavior. Native Telegram SDK integration was not implemented; this feature's
Telegram acceptance target is the browser.

## Telegram / Cloudflare setup and restart

- Bot username: **@kesorbankbot**. The bot already exists and the user configured
  Telegram login credentials and a redirect URL in BotFather.
- BotFather's actual UI labels are **Add redirect URLs**, **Trusted Origins**, and
  **Native App**. This redirect-based browser implementation uses the first; it
  does not require the embedded login-widget origin setting or Native App mode.
- Required server `.env` keys: `TELEGRAM_CLIENT_ID`, `TELEGRAM_CLIENT_SECRET`,
  `TELEGRAM_REDIRECT_URI`. The secret is not the bot token.
- `TELEGRAM_FRONTEND_ORIGIN` defaults to `http://localhost:8081` without a trailing
  slash. Browser CORS defaults to that same exact origin. Do not substitute
  `127.0.0.1`, a different port, or another domain without updating both settings.
- The registered callback must exactly be
  `https://CURRENT-TUNNEL-HOST/api/v1/auth/telegram/callback`.
- The previous Quick Tunnel was intentionally stopped for this handoff. Its old
  hostname is no longer a usable endpoint. A new Quick Tunnel gets a new hostname:
  update both BotFather and `.env`, then restart the backend to load it.
- Installed connector: `%LOCALAPPDATA%\Programs\cloudflared\cloudflared.exe`,
  version 2026.10.5, checksum verified; its directory is on user PATH.
- The `cf` CLI is also installed. Follow the root AGENTS rule for Cloudflare account
  operations; `cloudflared` is the separate local tunnel connector. No domain was
  purchased and no production hosting was deployed.

Typical restart commands, each long-running command in its own terminal:

```powershell
# From repository root; first ensure PostgreSQL is running.
cd backend/digital-banking
.\mvnw.cmd spring-boot:run

# In another terminal, from repository root:
cd frontend/customer_app
flutter run -d chrome --web-port=8081

# In another terminal, for local Telegram HTTPS callback testing:
cloudflared tunnel --url http://localhost:8080
```

If starting a new tunnel, obtain its hostname and update the existing redirect
assignment before the backend's final restart. Preserve all other `.env` values.
PostgreSQL service name is `postgresql-x64-18`. If stopped, the current non-admin
agent terminal may lack service-control permission; the user previously ran
`Start-Service -Name postgresql-x64-18` in administrator PowerShell.

For a static local development web build, explicitly use
`flutter build web --dart-define=APP_ENV=dev`. A default release build uses production
configuration and correctly rejects an HTTP API. Do not remove that production guard.

## Verification and remaining limits

Last completed checks in this session:

- Backend `./mvnw.cmd test`: **105 passed**, no failures/errors/skips. Includes
  migration/restart, new/returning email, onboarding authorization, OTP/exchange
  one-use behavior, linking, staff restrictions, and token-verification negatives.
- `flutter analyze`: **no issues found**.
- `flutter test`: **96 passed** (VM/widget tests, including the added browser-auth cases).
- Development web build and Wasm compatibility dry run: succeeded. Final popup fix
  was compiled and checked in Chromium.
- Browser-context fixtures exercised email/code/information/Home without sending
  real email or creating real profiles. Fixture routes were removed afterward.
- Telegram cancellation used the real HTTPS tunnel and backend callback with only
  provider navigation simulated. The receipt returned to the original window and
  produced the expected cancellation message with **zero browser errors**.
- After removing fixtures, the real Telegram authorization page recognized
  kesorbankbot and the callback configuration. **No personal account was approved.**
- Optional standalone Chrome test runner stalled before running its tests and was
  stopped; do not report it as passing. Compiled Chromium interaction is the browser
  evidence. Native live-Gmail/restart harnesses were adapted where needed but were
  not rerun during this browser-focused auth task.
- No new packaged backend JAR or native APK acceptance was established for this auth
  feature. Older artifacts/evidence are historical, not automatically current.

Next recommended work is the user-operated successful live Telegram login, then
live email continuation with a controlled recipient if requested. Check new-user
information, subsequent return-to-Home, and optional identity linking. Never ask the
user to paste secrets or OTPs into chat. Do not send real email without authorization.

Before any production release, replace the short in-app service/privacy descriptions
with operator-approved policies and address release signing, infrastructure, and
financial-service requirements. These are not completed by this local auth change.

## Shutdown state

Stopped the project's Spring Boot JVM, its Maven JVMs/launcher, the local Python web
preview, and the cloudflared tunnel. Closed the dedicated tunnel PowerShell and
the AiDigitalBankingApp VS Code integrated terminal. Confirmed **8080, 8081, and 8082
are not listening** and no matching project server/tunnel processes remain.

PostgreSQL's shared Windows service remains running. Editor language services,
Codex tooling, and the shared ADB server were not killed. No emulator process was
found. No database, native app data, saved financial safety record, source file,
installed CLI, or credential file was deleted.

Local ignored evidence is in `backend/digital-banking/.local` (backend logs,
task-specific npm cache) and `backend/output/playwright` (screenshots and browser-only
fixture scripts). The Playwright QA session was closed and its mocks are not active.
