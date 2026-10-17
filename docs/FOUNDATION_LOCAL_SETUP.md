# Foundation local setup (F1)

Windows instructions for the basic banking backend. Run commands from
`backend/digital-banking`, which contains `pom.xml`, `.env`, and `mvnw.cmd`.
Use Java 21 or a compatible newer JDK and a running PostgreSQL service. Docker,
a real email account, Bakong credentials, and an AI API key are not needed.

## 1. Prepare the database and configuration

Use your installed PostgreSQL tools. For example, if PostgreSQL 18 is installed:

```powershell
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -U postgres -d postgres -c "SELECT datname FROM pg_database WHERE datname = 'digital_banking_db';"
```

If the database is absent, create it once:

```powershell
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -U postgres -d postgres -c "CREATE DATABASE digital_banking_db;"
```

The commands prompt for the PostgreSQL password. Use your actual installation
path and database user. Do not recreate or reset an existing database.

Copy `.env.example` only if `.env` does not exist:

```powershell
if (-not (Test-Path -LiteralPath .env)) { Copy-Item -LiteralPath .env.example -Destination .env }
```

Edit the existing assignments in `.env`; duplicate keys prevent startup.

| Setting | Local foundation value |
| --- | --- |
| DB_HOST / DB_PORT | localhost / 5432 |
| DB_NAME / DB_USER | digital_banking_db / your PostgreSQL user |
| DB_PASSWORD | Your database password |
| JWT_SECRET | Base64-encoded random signing key, at least 32 bytes |
| JWT_EXPIRATION_MS | 900000 (15 minutes) |
| JWT_REFRESH_EXPIRATION_MS | 604800000 (7 days) |
| SPRING_PROFILES_ACTIVE | local |
| SERVER_PORT | 8080 |
| DEV_SEED_ENABLED | true |
| DEV_SEED_PASSWORD | A chosen local demo password of at least 12 characters |
| MAIL_HOST / MAIL_PORT | 127.0.0.1 / 1025 |
| MAIL_USERNAME | wallet@example.test (sender label; no real inbox needed) |
| MAIL_PASSWORD | Empty for local capture |
| MAIL_SMTP_AUTH / MAIL_STARTTLS | false / false |

Keep real credentials in the ignored `.env`. If it already contains Gmail
credentials, use the local host/port/auth/TLS settings above to select Mailpit;
credentials alone do not select an SMTP server. Environment variables and command
line overrides can supersede file settings, so remove conflicting overrides.

Generate a signing secret locally, then paste it into JWT_SECRET without logging
or committing it:

```powershell
$jwtBytes = [byte[]]::new(32)
$jwtRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$jwtRng.GetBytes($jwtBytes)
$jwtRng.Dispose()
[Convert]::ToBase64String($jwtBytes)
```

## 2. Start the local OTP inbox

```powershell
.\scripts\start-local-mail.ps1
```

If script execution is blocked by your Windows policy, use a process-scoped
invocation (this does not change the machine's policy):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local-mail.ps1
```

The launcher downloads the official Mailpit **v1.31.5 Windows AMD64** release once,
checks its pinned SHA-256 digest, and stores it under ignored `.local/mailpit`.
Initial download requires internet access; later launches use the cached archive.
No administrator installation or Docker is required.

The cached executable is checked against that verified archive on every run.
An invalid executable is repaired before starting; invalid archives are rejected.
Downloads use a temporary file, so an interruption does not poison the cache.

- Inbox: [http://127.0.0.1:8025](http://127.0.0.1:8025).
- SMTP capture: `127.0.0.1:1025`, authentication/TLS disabled.
- Both listeners bind only to this computer's loopback address.
- Any valid test address, such as `alice.demo@example.test`, can receive captured
  mail. It does not need to exist at an email provider. Mailpit does not deliver
  these messages to real external inboxes in this setup.
- Re-running the launcher reuses its existing inbox. Conflicting port owners cause
  a clear error; the script does not terminate them.
- Reuse requires both expected listeners and a healthy Mailpit API. Concurrent
  launchers cannot start duplicate inboxes. A child that fails readiness is stopped.
- Nonempty `MP_*` environment overrides are rejected because they can enable mail
  forwarding/relay or change listeners. Clear those overrides in the launching
  shell; the error does not print their values. Empty variables are ignored.
- The launcher prints the PID and a `Stop-Process -Id <PID>` command. Stop that
  specific inbox when finished. Captured mail is temporary and disappears on stop.

See the official [installation](https://mailpit.axllent.org/docs/install/),
[SMTP](https://mailpit.axllent.org/docs/configuration/smtp/), and
[web inbox](https://mailpit.axllent.org/docs/configuration/http/) documentation.

## 3. Start one backend

Check the default port first:

```powershell
Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, OwningProcess
```

If a backend is already running, use it. To apply code or configuration changes,
stop that instance in its owning terminal with Ctrl+C, then restart. If it was
launched as a background Java process, identify its PID and executable before
stopping that specific process. Do not terminate unrelated Java applications.

When the port is free:

```powershell
.\mvnw.cmd spring-boot:run
```

Confirm the startup log reports the `local` profile and a successful server start
on 8080. Flyway validates and applies pending migrations. The current foundation
includes V2–V9; do not edit applied migration files.

- [Swagger UI](http://localhost:8080/swagger-ui/index.html): select **foundation**.
- [Foundation OpenAPI JSON](http://localhost:8080/v3/api-docs/foundation).
- The full legacy document remains at `/v3/api-docs`; advanced modules there are
  outside foundation acceptance.

Confirm the actual database migration version using PostgreSQL:

```sql
SELECT version, description, success
FROM flyway_schema_history
ORDER BY installed_rank;
```

The latest successful migration should be 9. If startup fails, inspect the cause
before starting another copy. A schema error is not fixed by occupying a new port.

## 4. Demo identities and funds

With `local` and DEV_SEED_ENABLED=true, missing fixtures are created idempotently.
Their initial password is DEV_SEED_PASSWORD. Existing fixture passwords and
balances are preserved; changing that setting does not reset an existing user.

| Username | Email | Role | Initial fixture account |
| --- | --- | --- | --- |
| alice.demo | alice.demo@example.test | CUSTOMER | 9000000001, USD 1250.00 |
| bob.demo | bob.demo@example.test | CUSTOMER | 9000000002, USD 500.00 |
| empty.demo | empty.demo@example.test | CUSTOMER | None |
| employee.demo | employee.demo@example.test | BANK_EMPLOYEE | None |

The repository also has admin and merchant fixtures, but they are not needed for
the basic walkthrough. Production configuration does not activate local seeding.

These opening balances are demonstration fixtures, not external deposits or
fabricated historical transactions. After transfers, balances naturally change;
do not expect the initial amounts after every restart. New customer registration
creates no account, and new account opening starts at zero. For a newly opened
account, use an employee's staff-only deposit API to add local demo funds.

## 5. Verify the foundation

Follow [the Swagger walkthrough](FOUNDATION_SWAGGER_WALKTHROUGH.md) for the actual
requests and expected results, including customer/staff boundaries.

Run the backend regression suite:

```powershell
.\mvnw.cmd clean verify
```

Tests start isolated PostgreSQL and SMTP on temporary ports. They do not require
Docker, use the configured development database, or send external email. They
include checks that the published request examples execute successfully and
that public auth, response statuses, schemas, role boundaries, and idempotency
agree with the implementation.

**On Windows, stop a server running from target/*.jar before clean verify:** the
JVM locks that jar, which prevents Maven's clean task from deleting it. Identify
and stop that specific backend, run the build, then start one updated instance.
The isolated tests themselves do not need port 8080. To test without replacing
the packaged jar, use `.\mvnw.cmd test`; restart the server after code changes
before validating Swagger manually.

Run the dependency-free launcher regression checks after its initial download:

```powershell
.\scripts\test-local-mail.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-local-mail.ps1
```

These checks cover failure/recovery and readiness in isolated `.local/launcher-qa`
fixtures. Process/network operations are mocked; the tests preserve the running
inbox and do not send email. Live SMTP/API checks are recorded separately in the
[F1 review and QA report](FOUNDATION_F1_CODE_REVIEW_QA.md).

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Address already in use | Inspect 8080 owner; stop/reuse that instance |
| Duplicate .env key | Edit the existing assignment; keep each key once |
| Database does not exist / login fails | Check database, user, password, host and port |
| Startup rejects signing key | Replace JWT_SECRET with a valid Base64 signing key |
| Startup rejects demo password | Replace the placeholder with at least 12 characters |
| OTP request returns 503 | Start Mailpit; confirm local mail host/port/auth/TLS and restart backend |
| OTP request returns 200 but inbox is empty | SIGNUP requires an unused email; LOGIN requires an existing enabled user; confirm the intended mail configuration |
| OTP request returns 429 | Wait for Retry-After; do not reset database counters to bypass it |
| Fixture login fails | Use the password originally used to create that fixture; seeding does not reset it |
| Swagger still shows old responses | Restart the backend with current code, then reload the UI |
| Android cannot reach localhost | Android emulator uses http://10.0.2.2:8080/api/v1; localhost refers to the emulator |
