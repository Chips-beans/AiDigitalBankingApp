# Phase 0 Backend and API Readiness

Implemented and verified 16 October 2026.

Review fixes, architecture and data-structure findings are documented in the
[Phase 0 code review](PHASE_0_CODE_REVIEW.md). This Markdown reflects those fixes;
`Phase_0_Implementation.docx` remains the initial implementation snapshot.

## Result

Phase 0 is complete. The backend authenticates customer requests, resolves the
current user, isolates account access, rotates refresh tokens, revokes sessions,
and limits OTP requests and verification attempts. Development fixtures and mobile
API configuration are available for the next Flutter phases.

Verification passed: **37 backend tests** and Maven packaging after review.
The initial implementation also passed **6 Flutter tests** and **Flutter analysis**;
Flutter source was not changed or retested during the backend review.
Backend integration tests use real HTTP, an isolated PostgreSQL 14.22 database,
Flyway migrations, and a local SMTP capture server. They send no external email.
Flutter banking screens and an API client are subsequent phases; the UI remains
the generated starter app.

## Implemented features

| Area | Implemented behavior |
| --- | --- |
| Request authentication | JWT filter runs in Spring Security; rejects malformed, forged, expired, wrong-type, disabled-user, revoked-device, and revoked-session requests |
| Current identity | Database user is the principal expected by account controllers; token responses and `GET /auth/me` expose userId, username, email, roles, and sessionId |
| Authorization | Customers access customer routes; staff/admin roles access their designated operations routes; unmatched routes are denied |
| Account isolation | Own-account reads, history, transfer source, and transaction-reference lookups enforce ownership; unavailable resources return 404; status changes require bank staff/admin |
| Merchant isolation | Merchants access/edit their own records; administrators alone approve merchants, change status, and list by status |
| Login throttling | Ten attempts per fixed 15-minute window, persisted by user identity; username/email aliases share a counter; unknown identities are also limited |
| Token lifecycle | Signed tokens carry issuer, immutable user ID, session ID, unique token ID, expiry, and explicit access/refresh type |
| Session storage | New `auth_sessions` table stores device/user binding, absolute expiry, revocation time, and a SHA-256 refresh-token hash |
| Refresh rotation | Each successful refresh replaces the stored token hash; old-token reuse revokes that session, including its access tokens |
| Server logout | `POST /auth/logout` revokes the current session; other devices remain signed in |
| OTP | Six-digit code, five-minute expiry, BCrypt storage, latest-code-only validation, one-time consumption, request limits, and persisted failure counts |
| Email delivery | SMTP failures return a structured 503 response and roll back the new code; codes and credentials are not logged |
| Shared devices | Device uniqueness is per user plus installation fingerprint; two users can share an installation without transferring device ownership |
| Development setup | Opt-in local fixtures, SMTP settings, ignored `.env` configuration, and Android/desktop API defaults |
| Database readiness | V6 adds sessions and OTP limits; V7 adds login limits, indexed account/latest-OTP lookup, and one-unrevoked-session-per-user/device enforcement; Hibernate validates the Flyway schema |

AI endpoints now derive record ownership from the authenticated user rather than
trusting a submitted user ID. QR generation and payment-status lookup also require
the requesting user's own account. Customer account creation accepts zero initial
funds; customers cannot call the staff deposit route. The unsigned payment webhook
is blocked until provider verification is implemented in the payment phase.

## Authentication API contract

All paths below use `/api/v1`. Protected calls send
`Authorization: Bearer <accessToken>`.

| Method and path | Access | Request or result |
| --- | --- | --- |
| POST `/auth/request-otp` | Public | email, purpose SIGNUP or LOGIN; returns expiresInSeconds and resendAfterSeconds |
| POST `/auth/register` | Public | Registration fields, OTP, and device fields; returns a token pair and identity |
| POST `/auth/login` | Public | usernameOrEmail, password, OTP, and device fields; returns a token pair and identity |
| POST `/auth/refresh` | Public | refreshToken; returns a replacement token pair for the same session |
| GET `/auth/me` | Valid access token | Current user and session identity |
| POST `/auth/logout` | Valid access token | Revokes current session and returns success |
| GET `/accounts/me` | Customer access token | Own account list, including an empty list for a new customer |

There is no separate OTP verification API. The app requests a code first, then
submits the code with the complete registration or login request.

### Required fields

Registration: `username` (3–50 characters, letters/digits/underscore/dot/hyphen),
`email` (maximum 100), `password` (8–72 characters and at most 72 UTF-8 bytes),
`otpCode` (six digits), `deviceFingerprint` (maximum 255), and `deviceName`
(maximum 100). `firstName`, `lastName`, and `deviceType` are optional.

Login: `usernameOrEmail`, `password`, `otpCode`, `deviceFingerprint`, and
`deviceName`; `deviceType` is optional. Email-only login is the planned Flutter
starting point because OTP delivery needs the email address. Email values are
normalized to lowercase for new registrations and OTP requests. Lookup also accepts
mixed-case emails stored before Phase 0; V7 enforces case-insensitive email uniqueness.

Example login body:

```json
{
  "usernameOrEmail": "alice.demo@example.test",
  "password": "your_local_demo_password",
  "otpCode": "123456",
  "deviceFingerprint": "random-persisted-installation-id",
  "deviceName": "Android emulator",
  "deviceType": "ANDROID"
}
```

Use the code actually delivered to the configured local SMTP inbox. The example
does not define a fixed OTP. Generate a random installation identifier on the
device in the Flutter authentication phase; do not use a hardware identifier.

Successful token responses keep the existing `ApiResponse` envelope:

```text
success, message, timestamp,
data: accessToken, refreshToken, tokenType, expiresInMs,
      refreshExpiresAt, sessionId, userId, username, email, roles
```

### Session and device policy

- Access tokens default to 15 minutes; a session has a fixed seven-day lifetime.
  Rotation does not extend the absolute session expiry.
- Access tokens cannot be used as refresh tokens, and refresh tokens cannot access
  protected resource endpoints. Legacy JWTs without the new claims are rejected.
- Refreshing changes the refresh token. The Flutter client must coordinate one
  refresh request at a time; concurrent reuse can revoke the session.
- Signing in again on the same user/installation replaces the previous session
  for that combination. Another installation is unaffected.
- A shared physical device has separate records for separate users. A revoked or
  untrusted record is not reactivated by login, and its existing sessions are rejected.
- Logout revokes access and refresh use on subsequent requests. Already authorized
  in-flight work is not cancelled. If the access token has expired, refresh first
  before calling logout. The app must also clear local private state.

### OTP and error policy

Defaults: five-minute expiry, 60-second resend cooldown, five requests per 15-minute
window per normalized email/purpose, and five verification attempts per code.
Request counters and attempt counters persist in PostgreSQL; concurrent requests
are serialized using database locks. Resending supersedes earlier codes, and a
consumed latest code cannot fall back to an older unconsumed one.

Login also permits ten attempts per fixed 15-minute window, including wrong
passwords and successful logins. Username and email aliases share the user counter.
Unknown identities have their own normalized counter. The server returns
`LOGIN_RATE_LIMITED` and `Retry-After` when this limit is reached.
Latest OTP selection uses insertion ID under the identity lock, independent of
application-server creation timestamps. Password validation happens before OTP use;
successful OTP verification remains consumed if later session creation fails.

OTP requests return the same acceptance data for eligible and ineligible addresses.
Only eligible addresses receive a message. OTPs are never returned by the API.

Errors use `success=false`, `error` (stable code), `message`, `status`, `path`,
`timestamp`, `fieldErrors`, and `retryAfterSeconds`. Rate limits also return the
HTTP `Retry-After` header. Null retry values and empty field maps are normal.

| HTTP status | Examples of error codes |
| --- | --- |
| 400 | VALIDATION_FAILED, INVALID_REQUEST, VERIFIED_FUNDING_REQUIRED |
| 401 | AUTHENTICATION_REQUIRED, AUTHENTICATION_FAILED, TOKEN_INVALID, SESSION_INVALID, REFRESH_REUSED, USER_DISABLED, DEVICE_REVOKED, OTP_INVALID, OTP_USED, OTP_EXPIRED, OTP_ATTEMPTS_EXCEEDED |
| 403 | ACCESS_DENIED |
| 404 | RESOURCE_NOT_FOUND |
| 409 | IDENTITY_UNAVAILABLE, RESOURCE_CONFLICT |
| 405 / 406 / 415 | METHOD_NOT_ALLOWED, NOT_ACCEPTABLE, UNSUPPORTED_MEDIA_TYPE |
| 429 | OTP_RATE_LIMITED, LOGIN_RATE_LIMITED |
| 503 | OTP_DELIVERY_UNAVAILABLE |

## Local development setup

Use Java 21 or a compatible newer JDK and PostgreSQL. The verification run used
JDK 24 with Java 21 compilation targets. Run backend commands from
`backend/digital-banking`.

1. Create the PostgreSQL database `digital_banking_db` for the configured database user.
2. Copy `.env.example` to `.env` only if `.env` does not already exist. Set the
   database password, a signing secret, and a local demo password of at least 12
   characters. Placeholder values must be replaced.
3. Start a local SMTP capture service on `localhost:1025`, or configure an SMTP
   service you control. View OTP messages in that service's inbox.
4. Set `SPRING_PROFILES_ACTIVE=local`. The local profile enables idempotent fixtures,
   with SMTP authentication and STARTTLS disabled for the local capture service.
5. Run `./mvnw.cmd spring-boot:run`. Flyway applies V2 through V7 and Hibernate
   validates the resulting schema. Open `http://localhost:8080/swagger-ui.html`.

Generate a fresh signing secret in PowerShell:

```powershell
$jwtBytes = [byte[]]::new(32)
$jwtRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$jwtRng.GetBytes($jwtBytes)
$jwtRng.Dispose()
[Convert]::ToBase64String($jwtBytes)
```

Place the result in `JWT_SECRET` in the ignored `.env`. Existing sessions and legacy
OTPs do not carry forward into the new authentication policy. Do not edit already
applied V2–V6 migrations; V7 adds the review fixes. Previously unmanaged schemas
need migration review before upgrade.

| Setting | Default or use |
| --- | --- |
| DB_HOST, DB_PORT, DB_NAME, DB_USER | localhost, 5432, digital_banking_db, postgres |
| DB_PASSWORD, JWT_SECRET | Required configuration |
| DEV_SEED_PASSWORD | Required when local fixtures are enabled; at least 12 characters |
| DEV_SEED_ENABLED | True in local profile; set false to skip fixtures |
| MAIL_HOST, MAIL_PORT | Local profile: localhost, 1025; standard profile: smtp.gmail.com, 587 |
| MAIL_USERNAME, MAIL_PASSWORD | Sender and SMTP credentials; local capture does not require a password |
| MAIL_SMTP_AUTH, MAIL_STARTTLS | False in local profile, true in the standard profile |
| MAIL_CLIENT_HOSTNAME | localhost; avoids development machine reverse-DNS delays |
| CORS_ALLOWED_ORIGINS | http://localhost:8081; comma-separated browser origins |
| JWT_EXPIRATION_MS, JWT_REFRESH_EXPIRATION_MS | 900000 and 604800000 |
| OTP_RESEND_SECONDS, OTP_MAX_REQUESTS | 60 and 5 |
| OTP_WINDOW_MINUTES, OTP_MAX_ATTEMPTS | 15 and 5 |
| LOGIN_MAX_ATTEMPTS, LOGIN_WINDOW_MINUTES | 10 and 15 |

For authenticated external SMTP, explicitly set its host, port, credentials,
`MAIL_SMTP_AUTH=true`, and `MAIL_STARTTLS=true` as required by the selected service.
Bakong and AI credentials are not needed to test Phase 0 authentication.

### Development fixtures

All fixture emails are `<username>@example.test`. They use the password from
`DEV_SEED_PASSWORD`. The seeder creates missing fixtures and leaves existing users
and balances unchanged. The `prod` profile prevents it from activating even if
`local` is also selected.

| Username | Role | Account |
| --- | --- | --- |
| alice.demo | Customer | 9000000001, USD 1250.00 |
| bob.demo | Customer | 9000000002, USD 500.00 |
| empty.demo | Customer | No account; exercises the empty state |
| employee.demo | Bank employee | No customer account |
| merchant.demo | Merchant | No customer account |
| admin.demo | Administrator | No customer account |

## Flutter connection configuration

`frontend/customer_app/lib/core/config/app_config.dart` supplies the API base URL
outside the screens. Startup validates it. Android development defaults to
`http://10.0.2.2:8080/api/v1`; other targets default to
`http://localhost:8080/api/v1`. Physical devices require the backend computer's
reachable LAN address and the same network. A third-party emulator may require
its own host alias instead of `10.0.2.2`.

Run these from `frontend/customer_app`:

```powershell
# Android emulator default
flutter run
# Physical Android device example; replace the address
flutter run --dart-define=API_BASE_URL=http://192.168.1.25:8080/api/v1
# Browser origin matching the default CORS configuration
flutter run -d chrome --web-port=8081
# Production configuration example; replace with the deployed HTTPS API
flutter build apk --dart-define=APP_ENV=prod --dart-define=API_BASE_URL=https://api.example.test/api/v1
```

Android INTERNET permission is configured. Cleartext HTTP is allowed in debug and
profile manifests for development. Release defaults to the production environment,
which rejects non-HTTPS URLs and therefore requires an explicit HTTPS API URL.
The source configuration and URL selection are tested; physical-device connectivity
and a networked Flutter login UI are exercised when those UI phases are implemented.

## Verification and next work

Backend: run `./mvnw.cmd test` from `backend/digital-banking`. No separately installed
PostgreSQL, Docker, SMTP account, or `.env` is needed for this test command. Test-only
PostgreSQL binaries are resolved through Maven and started on a temporary port;
SMTP is captured on loopback. Reports are in `target/surefire-reports`.

The 37 passing backend tests cover context/schema startup, real registration/login
and email delivery, identity, empty accounts, cross-customer account/history/reference/payment
access, role boundaries, token signatures/expiry/type, refresh rotation/reuse and
concurrency, logout isolation, fixed session expiry, disabled users, device revocation,
shared installations, repeated login, OTP attempt persistence, expiry/reuse/supersession,
request limits and concurrency, SMTP failures, validation errors, server-owned AI
identity, fixtures, production seed exclusion, and OpenAPI availability. Review
regressions additionally cover login throttling/reset/concurrency, merchant and
staff authorization, UTF-8 password boundaries, constrained connection pools,
missing JWT claims, clock-skew OTP ordering, framework error statuses, and V6-to-V7
migration preservation and constraints. Legacy email login and concurrent merchant
profile edits versus administrator suspension are also covered, along with bounded
login-counter keys for Unicode identities.

Flutter: run `flutter analyze` and `flutter test` from `frontend/customer_app`.
Analysis passed. Five configuration tests and the original widget test passed.

Next: implement Phase 1 application structure, routing, theme, repositories, and API
client; then build the Phase 2 authentication screens. Password reset, biometrics,
device-management UI, transfer concurrency/idempotency, merchant payment verification,
and the remaining financial features stay in their later phases. Authentication
readiness does not mark those workflows complete.

Dependency references: [springdoc Spring Boot compatibility](https://springdoc.org/#what-is-the-compatibility-matrix-of-springdoc-openapi-with-spring-boot)
and [embedded PostgreSQL documentation](https://github.com/zonkyio/embedded-postgres).
The project uses springdoc 3.1.1 and test-only embedded-postgres 2.2.2.
