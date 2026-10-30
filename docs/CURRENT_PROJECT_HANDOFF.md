# Current project handoff — Kesor Bank

Updated 30 October 2026, Asia/Phnom_Penh (UTC+07:00).

## Latest: customer QR transfers and funded account pairs

Implemented 30 October 2026. Read [QR_CUSTOMER_FLOW.md](QR_CUSTOMER_FLOW.md)
before changing account opening, QR payments, or their recovery/lifecycle code.
The customer app's **Open accounts** now explicitly creates a USD/KHR pair of the
selected type. With opt-in test funding, opening credits are **USD 200.00** and
**KHR 100,000**, recorded as DEPOSIT history/income with `TEST_OPENING_CREDIT`.
Creation, credits, audit and replay receipt are atomic. Lost responses retry the
same saved request; existing single-account uncertainty markers remain separate.
The legacy single-account API remains compatible and zero-funded.

Home **My QR**, account-detail QR and **Scan QR** are connected to real APIs.
Reusable account codes, distinct one-time fixed-amount requests, recipient review,
camera capture and local JPG/PNG import are implemented. QR payments share the
manual-transfer safety journal; old v1 records remain readable and new QR v2
records retain their immutable payload/key. Persistent backend claims handle
concurrent attempts and replay before checking paid state. Static QR codes remain
reusable. Server-registered internal codes, ownership, exact money and matching
currencies are enforced. The bounded picker lease also covers QR image import;
ordinary background/PIN locking is preserved. English/Khmer and both themes use
the existing Kesor design system. Browser/demo transfer restrictions remain.

Source schema is **V14**, with **34 foundation paths**. Additive V14 introduces
pair-opening/QR replay records and QR type/settlement metadata; V1–V13 were not
changed. A read-only PostgreSQL check confirmed development is still **V11**.
Its next ordinary backend startup applies V12, V13 and V14. No development
customer, account, balance or history was changed and no real email was sent.

The ignored backend `.env` now explicitly enables
`TEST_OPENING_FUNDING_ENABLED=true` for the user's development testing. Other
assignments/credentials were preserved and not printed. Source/example defaults
remain false. Enabling the flag requires local/dev/test/staging and rejects
prod/production, including mixed profiles. No credit is applied to old accounts.

Verification: **133 backend tests** passed, including real HTTP USD 10/KHR 10,000
journeys between controlled customers in isolated PostgreSQL, concurrent attempts,
atomic rollback, currency/ownership/precision negatives and restart replay.
The final backend QR subset also passed after adding payload-size validation.
The complete Flutter regression passed **166 tests**, followed by a passing
10-test QR widget rerun that adds an inactive-account refresh regression (**167
unique tests**). Analysis is clean. The additional QR visual fixture passed and
generated **60** fixture views with representative images visually inspected
across English/Khmer, light/dark, reference/narrow/large-text/landscape
variants. Camera calls in widget tests are faked; this is not physical camera
acceptance. API-mode web build and Wasm dry run succeeded. Logs/screenshots are
ignored under the backend `.local/qr-*` and Flutter `.local/qr-*` / `.local/qa/qr/`.
The final normal-entrypoint Android debug APK built successfully in API mode with
`APP_ENV=dev` and `API_BASE_URL=http://127.0.0.1:8080/api/v1`. It is **245,014,308
bytes**, SHA-256
`54193f802411ef11b12fe085e1d95825df6c7666a3a03a246005f01f0ddc55c0`.
It supersedes the prior PIN APK at
`frontend/customer_app/build/app/outputs/flutter-apk/app-debug.apk`. A user-facing
copy is `C:\Users\User\Documents\Codex\2026-10-30\project-kesor-bank-ai-digital-banking\outputs\KesorBank-QR-Test.apk`.
Packaging verification found no backend `.env` or unique configured secret values.
A common numeric byte-pattern match was independently located in unchanged Dart
SDK encoding/number tables and absent from application source; no credential value
was printed. No device installation occurred. Temporary build daemons exited;
ports 8080–8083 and emulator state were rechecked as stopped.

The checkout started clean on `main` at `c814d6d`; the implementation is
uncommitted. Preserve it. No ordinary backend or emulator was started; shared
PostgreSQL was left running. Personal Telegram/email/PIN acceptance, physical
camera/file-picker testing and native iOS build/device acceptance remain pending.
External bank/Bakong settlement and production deployment remain out of scope.

## Previous handoff history

## Read this first

Latest implementation: the normal Flutter customer app now requires a **4-digit
PIN** after profile completion, with Create/Confirm and returning Enter PIN screens
from live Figma section `280:1494`. Read [APP_PIN.md](APP_PIN.md) before changing
authentication or lifecycle behavior. Background/relaunch locks, persistent
five-attempt limits, fresh verified identity recovery, hashed server verification,
private session tickets and access-token epochs are implemented. Source is **V13**
with **32 foundation API paths**. Development PostgreSQL remains V11: the next
ordinary startup applies V12 photos and V13 PIN tables. Backend and emulator remain
stopped; no live customer login, financial operation or migration was performed.
Verification: **123 backend tests** and **149 Flutter checks** passed across full
regression/visual fixtures and the corrected lifecycle-fixture rerun; analyzer
clean, API-mode web build and Wasm dry run successful. Native Flutter screenshots
at 440×999 and adaptive English/Khmer variants are in ignored `.local/qa/pin/`.
Physical-device and complete live identity/PIN acceptance remain pending.
The normal-entrypoint Android debug APK now includes PIN protection and built
successfully in API mode with `APP_ENV=dev` and localhost port 8080. It supersedes
the older email-auth APK described below. No emulator/device installation was
performed. The temporary build daemon was stopped after the build.

Latest implementation, 30 October 2026: the three Flutter email-auth screens now
match live Figma section `253:1457` (email entry, OTP verification, create profile).
Read [EMAIL_AUTH_SCREENS.md](../frontend/customer_app/docs/EMAIL_AUTH_SCREENS.md).
The existing continuation/session behavior is preserved. The user additionally
requested persistent profile-photo upload: authenticated own-photo GET/PUT,
JPG/PNG validation, normalized private PostgreSQL storage, an audit event, OS file
selection, saved-avatar reload and replacement are implemented. Source is now
**V12**, with **27 foundation API paths**. The existing development database is
still V11; no development backend startup or live migration occurred in this task.
Its next ordinary startup applies the additive V12 photo table migration.

Verification: **117 backend tests / 139 Flutter checks passed**, analyzer clean,
API-mode web build, Wasm dry run and normal-entrypoint Android debug APK succeeded.
The APK uses `APP_ENV=dev` and `API_BASE_URL=http://127.0.0.1:8080/api/v1`; it
supersedes the older Analytics APK below. Flutter screenshots were inspected
at 440×956, in both themes/languages and responsive variants. Evidence is ignored
under `frontend/customer_app/.local/qa/email-auth/` / `.local/email-auth-*`.
Personal login, physical file-picker interaction and live photo acceptance remain
unverified. The “Create Account” design label completes a profile only; financial
accounts still require explicit account opening. No funds or customer data changed.

Latest runtime state: the user requested shutdown. The backend launcher/JVM tree
was identity-checked and stopped; port 8080 was confirmed closed. The emulator was
already stopped and ADB had no devices. PostgreSQL was left running. The older
“left running” runtime records below are historical; never reuse their PIDs
without verifying identities. No emulator or development server was started for
this design task.

Latest runtime update, 30 October 2026: the user requested the complete project
for manual flow testing. PostgreSQL was already running. Started source Spring
Boot with Maven in `local` mode on 8080; normal Flyway startup successfully applied
V11 to the existing development database. It is now V11 (older V10 statements
below are historical). Swagger returned 200 and protected accounts returned 401
without a token. No customer login, OTP request or financial posting was performed.

Pixel_6a exists but has only 455 MB free inside Android and rejected the APK for
insufficient storage. Its apps/data were preserved and that emulator was closed.
The two older Codex F2 AVD entries point to missing directories. Created a separate
`Kesor_Bank_Test` AVD at `D:\CodexQa\KesorFullFlow\Kesor_Bank_Test.avd`, reusing the
installed API 36.1 Play Store x86_64 system image, with an 8 GB data partition.
No system image download was needed. It booted, and the current Analytics debug
APK installed successfully. App launched using `com.bank.customer_app/.MainActivity`.
ADB reverse forwards emulator localhost:8080 to host:8080. This is API mode.

The workstation has 8 GB RAM and was under memory pressure; first Android boot
took about 192 seconds and System UI briefly became unresponsive. At setup,
C: had about 5.8 GB free and D: about 33 GB. No unrelated apps were closed.
The fresh emulator has no Telegram login configured; email continuation is the
immediate manual test path. Native Telegram link verification was requested from
Android but successful personal provider acceptance remains unverified.

Backend and emulator are intentionally left running. Launcher details/logs:
`backend/digital-banking/.local/full-flow-backend.json` and
`frontend/customer_app/.local/full-flow-emulator.json` / `full-flow-runtime.json`.
Backend launcher PID 9300/JVM 30996, emulator launcher PID 8188. Recheck process
identity before stopping these; PIDs can be reused. Browser/tunnel were not started.
The Kesor welcome screen was visually confirmed open, with both continuation
buttons visible. No authentication or OTP was entered by the agent.

Latest implementation: the Flutter **Monthly Analytics** tab is implemented from
live Kesor Figma node `166:177`, replacing its placeholder. Read
[MONTHLY_ANALYTICS.md](MONTHLY_ANALYTICS.md) for financial meaning, API contract,
interaction, verification commands and limitations before continuing this feature.
It covers all owned accounts within USD or KHR, excludes own-account transfers,
and shows monthly income/expense plus a switchable daily chart. Dates consistently
use `Asia/Phnom_Penh`. Amounts stay exact; cards are sums of the same daily snapshot.

The new authenticated customer route is
`GET /api/v1/analytics/monthly-overview?year=2026&month=10&currency=USD`.
The original three account-level analytics routes retain their wire formats and
ownership checks, with incoming-transfer classification and date projection fixed.
The new chart uses Flutter CustomPainter, without an additional chart package.
The screen follows theme/language preferences and uses original exported assets.
Its source motif shares Home's existing SVG/progressive-blur renderer; Home's
default rendering geometry is preserved. Figma reauthentication succeeded.

No migration, development-database startup, credentials change, live financial
posting, external email, emulator, device installation, tunnel, or preview was
performed for Analytics. Source remains V11; foundation route count remains 26.
Verification used isolated PostgreSQL/local SMTP and Flutter fixtures. All prior
native Telegram work remains intact and uncommitted. No commit was created.

Analytics final verification: **114 backend tests / 134 Flutter checks passed**
(133 tests plus the visual fixture); Flutter analysis clean. The normal-entrypoint
Android debug APK built with `APP_ENV=dev` and
`API_BASE_URL=http://127.0.0.1:8080/api/v1` for later USB `adb reverse` testing.
The development web build and its Wasm dry run succeeded. Reference and small/2x
text screenshots were reviewed in both languages/themes; additional tests cover
375px, landscape/tablet, reduced motion and navigation clearance. Screenshot/log
evidence is ignored under `frontend/customer_app/.local/qa/analytics/` and
`.local/analytics-*`. Runtime preview/backend ports 8080–8083 remain closed.
The new Analytics debug APK SHA-256 is
`a9a2f9c8c828ea056ece8ad81e26c5995500b88a10b9fcb5854d53c6489b5bd8`;
this supersedes the historical native-login APK hash below.

Previous implementation update: Android native Telegram login is implemented using
the registered App Link `https://app937652339-login.tg.dev/tglogin`. The user
registered the native app and explicitly chose **prepare the build; test the phone
later**. No device is connected and no personal Telegram approval was performed.
Read [NATIVE_TELEGRAM_SETUP.md](NATIVE_TELEGRAM_SETUP.md) before continuing native
work; it records the protocol choice, backend contract, build, USB test sequence,
and remaining live-provider/device checks.

Native login uses an Android platform bridge and separate start/link/exchange
routes. State, nonce and S256 PKCE remain backend-owned; returned codes are checked
against the active app flow. Exchanges are consumed before contacting Telegram and
are not automatically retried. The browser popup/receipt flow remains separate.
The official SDK's source protocol is used because its public API exposes no
state/nonce hook. Native provider compatibility still needs live acceptance; nonce
validation was not weakened. Activity/process recreation during approval requires
a fresh login; secure completed sessions retain existing restoration behavior.

Current source schema is **V11**, with **26 foundation API paths**. V11 is new;
V10 was not edited. The existing development database remains at V10 because its
backend was not started; the next normal startup will apply V11. Isolated tests
verify fresh V11, V10-to-V11 preservation, and server restarts. Final validation:
**110 backend tests / 120 Flutter tests passed**, Flutter analysis clean, normal
Android debug APK built, web build and Wasm dry run succeeded. The initial full
backend attempt failed only on an outdated migration-count assertion; it was
updated and the full final run passed.

The ignored backend `.env` now includes one `TELEGRAM_NATIVE_REDIRECT_URI` assignment.
Other credential/browser settings were preserved. The APK's package, verified-link
manifest, and signing certificate were inspected; Telegram's public association
lists the same package/certificate. Credential packaging checks found no `.env`
or Telegram/JWT/email secret values. No credential value was printed.

The prepared normal-entrypoint debug APK uses explicit `APP_ENV=dev` and
`API_BASE_URL=http://127.0.0.1:8080/api/v1` for later USB `adb reverse` testing.
It is not a production build. Its SHA-256 is
`41cca7c500ffb2be7d5bcbf624045583a1c0330d0094dfe7b06c8b496a847454`.
It is at `frontend/customer_app/build/app/outputs/flutter-apk/app-debug.apk`.
No development backend, tunnel, emulator, or browser preview was started. Only
isolated test servers ran; ports 8080–8083 remain closed. No commit was created.
This task started at HEAD `8a8c988` with a clean status; all native work is now
uncommitted. The older branch/hash and evidence below remain historical.

Latest runtime update: the user asked to close the review preview. The dedicated
Flutter/Chrome demo process tree (launcher PID 6228) was stopped and port 8081 was
confirmed no longer listening. The stale launcher PID file was removed. Other
Chrome windows were not targeted. No backend or emulator was started.

Latest update: the user asked to close Chrome and correct inconsistent component
sizes, typography, spacing, and screen overflow against the Kesor Figma file.
The dedicated Flutter/Chrome demo process tree was stopped. The preview is closed;
no emulator, backend, tunnel, real email, or financial operation was started.

The consistency pass uses the original bundled Figma SVGs/PNGs and earlier node
measurements. The live Kesor Bank file was also inspected in the user's Figma
Windows app with Computer Use: Home is 440×999 and dark login is 440×956. Figma's
connector currently reports reauthentication required; desktop inspection does
not repair that connector. No Figma document content was changed.

Welcome, auth forms and the signed-in root now share a 440px content frame and
20px gutters. Theme changes preserve action font/geometry; welcome actions use
Google Sans 15/28, 52px minimum height, 16px radius and 16px icon-label spacing.
The source capsule remains visually 44px high with transparent 48px hit targets.
Footer links preserve the source's compact visual lines with full hit targets.
Home card positions match the source at reference size; the scroll viewport ends
above the floating navigation on smaller screens, and recipient names are bounded
and ellipsized. Bottom-bar font weight is explicit in both modes. Read
[HOME_SCREEN.md](../frontend/customer_app/docs/HOME_SCREEN.md) for limitations,
measurements, and validation details. Existing Analytics/Settings/assistant
placeholders remain as previously requested; this pass does not implement their
full designs.

Validation: analyzer clean; **114 tests passed**, including reference geometry,
long names, desktop centering, theme changes, large text, and continuation target
size/label checks. Render fixtures cover English/Khmer and light/dark at reference
and narrow sizes. Logs/screenshots are ignored under
`frontend/customer_app/.local/qa/`. The prior browser-based functional verification
remains historical; this pass used widget rendering and desktop Figma inspection.
The full demo web build and Wasm dry run also succeeded. The final geometry/
render subset passed after adding narrow-screen scrolled-footer captures. The
Figma GLASS effect remains a Flutter approximation (see Home notes).

The existing authentication feature is unified customer authentication: one welcome
screen with **Continue with Telegram** and **Continue with Email**, automatic
new/returning profile handling, and onboarding. The main remaining acceptance
step is a successful live login approved by the user with their own Telegram
account. Do not describe that personal-account check as already completed.

Read [UNIFIED_AUTH_SETUP.md](UNIFIED_AUTH_SETUP.md) for the full current auth
contract and [FOUNDATION_F5_HANDOFF.md](FOUNDATION_F5_HANDOFF.md) for the older
banking foundation. F5's V9 schema, 14-route contract, and test counts are historical;
that earlier schema was **V10**, the foundation API had **23 paths**, and that auth
handoff recorded **105 backend tests / 96 Flutter tests**. Current Home verification
is recorded above.

## Repository and working state

Colors/typography update, 29 October 2026: the Flutter app now imports the current
Kesor Figma color primitives, Light/Dark tokens, and English/Khmer text styles.
See [Flutter design system](../frontend/customer_app/docs/DESIGN_SYSTEM.md) for
source frames, APIs, Material mappings, font provenance, and verification commands.
This update is limited to Flutter colors/typography; the runtime remains stopped.
Verification after this import: Flutter analysis clean; 103 tests passed including
the design-system contract/visual tests; light/dark specimens inspected; development
web build and Wasm dry run succeeded. Bundled font weights were verified in the build.

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
storage behavior. At the original auth handoff, native Telegram integration was
not implemented. Android was subsequently added as described in the latest update
above; the successful native personal-account acceptance check remains pending.

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
