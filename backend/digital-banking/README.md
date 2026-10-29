# Digital Banking Backend

For the next session, read the [current project handoff](../../docs/CURRENT_PROJECT_HANDOFF.md)
first. It records the latest schema, implementation, checks, and stopped runtime state.

Customer authentication now supports unified email OTP and Telegram continuation,
with server-enforced profile onboarding. Migration V10 preserves existing users
and banking data. See [unified authentication setup](../../docs/UNIFIED_AUTH_SETUP.md)
for the new routes, browser-origin settings, identity linking, and verification.
Legacy password routes remain available for existing integrations and staff QA.

Spring Boot backend for AI Digital Banking and Smart Wallet.

## Foundation setup and handoff (F1–F5)

The basic customer banking foundation is described in the
[implementation plan](../../docs/BACKEND_COMPLETION_PLAN.md).
Use the [local setup guide](../../docs/FOUNDATION_LOCAL_SETUP.md) and
[Swagger walkthrough](../../docs/FOUNDATION_SWAGGER_WALKTHROUGH.md).
Use the [F5 handoff](../../docs/FOUNDATION_F5_HANDOFF.md) for final regression,
migration/restart evidence and platform limits, and the
[demo checklist](../../docs/FOUNDATION_DEMO_CHECKLIST.md) for presentation.

Live OTP delivery uses Gmail SMTP and a real recipient inbox. Configure the
sender address and its app password in the ignored `.env`, following
[Gmail email setup](../../docs/GMAIL_EMAIL_SETUP.md). The `local` profile inherits
Gmail SMTP defaults; preserve an existing `.env` and replace assignments rather
than adding duplicates. Mailpit is no longer required for live development/QA.
In Swagger, select the **foundation** API group. Its JSON contract is available at
`http://localhost:8080/v3/api-docs/foundation`.

F1 is verified after review: **78 passing tests**, launcher regressions in both
PowerShell 7 and Windows PowerShell 5.1, plus schema and live workflow checks.
See the [F1 delivery report](../../docs/FOUNDATION_F1_IMPLEMENTATION.md) and
[F1 review/QA](../../docs/FOUNDATION_F1_CODE_REVIEW_QA.md) for scope/evidence.

Phase 1 financial correctness and automatic auditing are implemented. See
[Phase 1 implementation](../../docs/PHASE_1_IMPLEMENTATION.md) for migration V8,
required financial idempotency headers, currency rules, pagination, and verification.
The [Phase 1 code review and QA report](../../docs/PHASE_1_CODE_REVIEW_QA.md)
records six corrected defect groups, migration V9, and 74 passing backend tests.

Phase 0 authentication and API readiness are implemented. See
[Phase 0 implementation and setup](../../docs/PHASE_0_IMPLEMENTATION.md)
for contracts, environment settings, local fixtures, and verification.
See the [Phase 0 code review](../../docs/PHASE_0_CODE_REVIEW.md) for fixes,
architecture and algorithm checks, migration V7, and remaining financial-workflow risks.

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
See [F3 delivery and QA](../../docs/FOUNDATION_F3_IMPLEMENTATION.md).
