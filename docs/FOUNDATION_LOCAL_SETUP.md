# Foundation local setup and handoff

The local banking foundation includes F1–F5: email OTP authentication, native
sessions, accounts, exact USD/KHR balances, internal transfers, history, and
read-only Profile. Biometric authentication is excluded. See the
[handoff and regression report](FOUNDATION_F5_HANDOFF.md) and
[demo checklist](FOUNDATION_DEMO_CHECKLIST.md).

## Prerequisites

- Java 21 target, Maven wrapper, and PostgreSQL. The F5 workstation used JDK
  24.0.2 and PostgreSQL 18; the isolated tests use embedded PostgreSQL 14.22.
- Flutter and the Android SDK for the customer app. F5 used Flutter 3.47.5 and
  Dart 3.13.4. Native acceptance is on Android 14/API 34, x64 emulator.
- A configured Gmail sender with an app password, plus recipient inboxes you
  control. Docker, external banking credentials, and an AI API key are unnecessary.

Run backend commands from `backend/digital-banking`, which contains `pom.xml`,
`.env.example`, and `mvnw.cmd`. The Maven wrapper downloads its dependencies on
first use. Keep all passwords, tokens, and OTPs out of source control and logs.

## 1. Configure PostgreSQL and the backend

Use your actual PostgreSQL installation and role. For PostgreSQL 18 on Windows:

```powershell
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -U postgres -d postgres -c "SELECT datname FROM pg_database WHERE datname = 'digital_banking_db';"
# Only if absent:
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -U postgres -d postgres -c "CREATE DATABASE digital_banking_db;"
if (-not (Test-Path -LiteralPath .env)) { Copy-Item -LiteralPath .env.example -Destination .env }
```

Do not recreate an existing database. Edit the existing assignments in `.env`;
duplicate keys prevent startup. Environment and command-line overrides can also
affect configuration.

| Setting | Value |
| --- | --- |
| DB_HOST / DB_PORT | localhost / 5432, or your PostgreSQL listener |
| DB_NAME / DB_USER / DB_PASSWORD | digital_banking_db / your role / its password |
| JWT_SECRET | Base64-encoded random key, at least 32 bytes before encoding |
| JWT_EXPIRATION_MS / JWT_REFRESH_EXPIRATION_MS | 900000 / 604800000 |
| SPRING_PROFILES_ACTIVE / SERVER_PORT | local / 8080 |
| DEV_SEED_ENABLED / DEV_SEED_PASSWORD | true / chosen local password of at least 12 characters |
| MAIL_HOST / MAIL_PORT | smtp.gmail.com / 587 |
| MAIL_USERNAME / MAIL_PASSWORD | Sender address / Google app password |
| MAIL_SMTP_AUTH / MAIL_STARTTLS | true / true |
| JPA_SHOW_SQL / JPA_FORMAT_SQL | false / false |

Generate a signing secret locally and paste it into the ignored `.env`:

```powershell
$jwtBytes = [byte[]]::new(32)
$jwtRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$jwtRng.GetBytes($jwtBytes)
$jwtRng.Dispose()
[Convert]::ToBase64String($jwtBytes)
```

Follow [Gmail email setup](GMAIL_EMAIL_SETUP.md) for sender configuration and inbox
verification. The recipient is supplied separately during registration/login.
`@example.test` fixtures cannot receive real Gmail delivery. HTTP 200 from the
OTP endpoint is intentionally generic and alone does not prove delivery.

## 2. Start one backend

```powershell
Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, OwningProcess
# When the port is free:
.\mvnw.cmd spring-boot:run
```

Reuse an existing healthy backend. To apply a build/configuration change, stop
that specific instance and restart it; never terminate unrelated Java processes.
Confirm `local` and successful startup on 8080 in the log.

- [Swagger UI](http://localhost:8080/swagger-ui/index.html): select **foundation**.
- [Foundation OpenAPI JSON](http://localhost:8080/v3/api-docs/foundation).
- API prefix: `http://localhost:8080/api/v1`.

Flyway applies V2–V9 and Hibernate validates the resulting schema. There is no V1;
V2 is the first migration. Check the actual database using psql:

```sql
SELECT version, description, success
FROM flyway_schema_history
ORDER BY installed_rank;
```

Expect eight successful rows, ending at version 9. Never edit applied migrations
or run Flyway clean on the development database. See the F5 report for tested
fresh installations, upgrades from V6/V7/V8, and invalid legacy-data rejection.

## 3. Prepare customer and staff identities

Register customers through the app or [Swagger walkthrough](FOUNDATION_SWAGGER_WALKTHROUGH.md)
using controlled inboxes and fresh SIGNUP codes. New registration creates no bank
account; account opening explicitly starts at zero. Existing customers log in
using a fresh LOGIN code. Preserve their existing passwords and financial data.

With `local` and `DEV_SEED_ENABLED=true`, the idempotent historical fixtures are:

| Username | Email | Role | Initial fixture account |
| --- | --- | --- | --- |
| alice.demo | alice.demo@example.test | CUSTOMER | 9000000001, USD 1250.00 |
| bob.demo | bob.demo@example.test | CUSTOMER | 9000000002, USD 500.00 |
| empty.demo | empty.demo@example.test | CUSTOMER | None |
| employee.demo | employee.demo@example.test | BANK_EMPLOYEE | None |

Those addresses belong to the earlier captured-mail workflow. Their initial
password is `DEV_SEED_PASSWORD`; changing it does not reset existing users.
Opening fixture balances are demo funds and are not deposit history.

For Gmail staff QA, use the existing approved separate staff identity. For a
**new** local QA installation only, configure `QA_STAFF_ENABLED=true`,
`QA_STAFF_USERNAME`, `QA_STAFF_EMAIL`, and `QA_STAFF_PASSWORD` in the ignored `.env`
using a controlled staff inbox and a strong separate password. Restart the backend.
This fixture defaults to disabled, runs only under `local & !prod`, and rejects
conflicts instead of promoting/editing a customer. Preserve an existing fixture's
credentials. Funding and status changes use staff Swagger APIs, never the customer UI.

## 4. Run the Flutter customer app

From the repository root, in a separate terminal while the backend runs:

```powershell
cd frontend/customer_app
flutter pub get
flutter devices
flutter run -d emulator-5556
```

Replace the device ID with one shown by `flutter devices`. Android emulator debug
builds default to `http://10.0.2.2:8080/api/v1`; `localhost` on Android refers to the
emulator. No QA JSON file or OTP bridge is needed for the normal app. Enter the
real inbox code manually. See the [customer README](../frontend/customer_app/README.md)
for explicit API endpoints, demo mode, browser preview, and storage behavior.

Native storage retains the refresh token and user-scoped transfer safety record.
Restart never sends a pending transfer automatically. An unknown result requires
**Retry this exact transfer**, using its original key/payload. Account opening has
no idempotency contract: refresh accounts after an uncertain result before making
an explicit new opening decision.

## 5. Verify and demonstrate

```powershell
# backend/digital-banking
.\mvnw.cmd clean verify
# frontend/customer_app
flutter analyze
flutter test
```

On Windows, stop a server running from `target/*.jar` before `clean verify`
because Java locks that file. Tests use temporary PostgreSQL and local SMTP;
they do not reset the development database or send external email. First run
requires dependency downloads; embedded PostgreSQL must be permitted to launch.
F5 adds a fresh-database HTTP journey across actual server-context restarts.

Use the [demo checklist](FOUNDATION_DEMO_CHECKLIST.md) for the two-customer flow
and failure/recovery scenarios. The [Swagger walkthrough](FOUNDATION_SWAGGER_WALKTHROUGH.md)
contains exact JSON, response envelopes, status codes, funding, and idempotency
examples. Historical Gmail/native harnesses are opt-in and modify local QA data;
read their F3/F4 reports before running them. Do not repeat a completed seed phase.

## Troubleshooting and scope

| Symptom | Check |
| --- | --- |
| Address already in use | Inspect port 8080 owner; reuse/stop that specific backend |
| Duplicate .env key | Replace the existing assignment; each key occurs once |
| Database login/startup failure | Check database, role, password, host/port and migration error |
| Invalid signing key/demo password | Replace placeholders with valid local values |
| OTP request 503 | Check Gmail host, app password, auth/STARTTLS and outbound connectivity; restart after changes |
| OTP 200 but no email | Check eligibility, exact address, Inbox/Spam, sender settings; LOGIN needs an enabled existing user |
| OTP 429 | Respect Retry-After and resend countdown; never reset counters to bypass it |
| Staff login/fixture conflict | Use the existing staff credentials; do not promote a customer |
| Android cannot connect | Use 10.0.2.2 for the emulator; verify one backend is listening |
| Uncertain transfer | Preserve its safety record and retry the exact intent explicitly |
| Secure-storage failure | Resolve storage/retry setup; do not clear app data to bypass an unresolved transfer |

Mailpit launch/capture tooling remains in `backend/digital-banking/scripts` for
historical F1 evidence and explicitly isolated captured-mail setups. Current live
QA uses Gmail; the Maven suite uses its own local SMTP fixture.

Android 14 emulator evidence does not establish physical-device, iOS, desktop,
or release acceptance. Release signing remains the Flutter template debug key;
production infrastructure and publication are outside this foundation.
