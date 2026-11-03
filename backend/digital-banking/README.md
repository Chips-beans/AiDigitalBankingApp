# Digital Banking Backend

For current status, setup and conventions read the
[progress and agent guide](../../docs/PROJECT_PROGRESS_AND_AGENT_GUIDE.md); the banking
features and API contracts are in [CUSTOMER_APP.md](../../docs/CUSTOMER_APP.md) and the Merchant
contracts in [MERCHANT_APP.md](../../docs/MERCHANT_APP.md).

Spring Boot backend for AI Digital Banking and Smart Wallet.

## Setup

Environment settings, PostgreSQL, Gmail SMTP (sender app password), live OTP checks, the
seed fixtures and troubleshooting are in guide section 4
([PROJECT_PROGRESS_AND_AGENT_GUIDE.md](../../docs/PROJECT_PROGRESS_AND_AGENT_GUIDE.md)).
In Swagger select an API group such as **foundation**; its JSON contract is at
`http://localhost:8080/v3/api-docs/foundation`. Mailpit is no longer required for live
development/QA.

## Verify

```powershell
.\mvnw.cmd clean verify
```

The tests start an isolated PostgreSQL instance and local SMTP capture server.
They do not need an existing database, `.env`, Docker, or external email service.
On Windows, stop a backend running from `target/*.jar` before cleaning because
Java locks that file. The F5 test also boots a fresh database and restarts the
server contexts to verify persisted money, idempotency, sessions, and logout.

## Run

Run commands from `backend/digital-banking`, which contains `pom.xml`, `.env`,
and the Maven wrapper. From the `backend` directory, first run `cd digital-banking`.
The wrapper works without a separate Maven installation; Java 21 or a compatible
newer JDK must be available.

Configure PostgreSQL, Gmail SMTP, and an ignored `.env` using `.env.example`.
Use the `local` profile for opt-in demo fixtures. Replace the database password,
signing-secret placeholder, demo-password placeholder, and Gmail sender/app-password
placeholders before startup.

```powershell
.\mvnw.cmd spring-boot:run
```

Default API prefix: `http://localhost:8080/api/v1`.
Swagger UI: `http://localhost:8080/swagger-ui.html`.

## Startup troubleshooting

- `IllegalStateException: Duplicate key MAIL_USERNAME` (or another environment
  key): `.env` contains repeated assignments. Keep exactly one assignment per key.
  The dotenv loader rejects duplicates before Spring Boot starts.
- `mvn` is not recognized: use `.\mvnw.cmd spring-boot:run` from the project
  directory.
- Gmail uses `MAIL_HOST=smtp.gmail.com`, `MAIL_PORT=587`, `MAIL_SMTP_AUTH=true`,
  and `MAIL_STARTTLS=true`, with `MAIL_USERNAME` and `MAIL_PASSWORD` for the
  sender account. An older `.env` that still specifies `127.0.0.1:1025` overrides
  these defaults and must be updated. Restart the backend after configuration changes.
### Separate local staff identity for Gmail QA

An additional staff identity can be provisioned with `QA_STAFF_ENABLED=true`,
`QA_STAFF_USERNAME`, `QA_STAFF_EMAIL`, and `QA_STAFF_PASSWORD`. This fixture runs
only under `local & !prod`, defaults to disabled, and requires a separate strong
local test password. It refuses conflicts with existing usernames, emails, roles,
or passwords; it never promotes or edits an existing customer. Existing demo
users and balances are preserved. Keep values in ignored local configuration.
See the progress guide, section 4.
