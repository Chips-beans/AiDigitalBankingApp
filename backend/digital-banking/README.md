# Digital Banking Backend

Spring Boot backend for AI Digital Banking and Smart Wallet.

## Foundation setup and Swagger (F1)

The active milestone is the basic customer banking foundation in the
[implementation plan](../../docs/BACKEND_COMPLETION_PLAN.md).
Use the [local setup guide](../../docs/FOUNDATION_LOCAL_SETUP.md) and
[Swagger walkthrough](../../docs/FOUNDATION_SWAGGER_WALKTHROUGH.md).

Start the local OTP inbox from this backend directory:

```powershell
.\scripts\start-local-mail.ps1
```

Read captured OTP emails at `http://127.0.0.1:8025`. No real email account is
required. Use the `local` profile and explicit local mail settings in `.env.example`;
preserve an existing `.env` and replace its assignments rather than adding duplicates.
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
.\mvnw.cmd test
```

The tests start an isolated PostgreSQL instance and local SMTP capture server.
They do not need an existing database, `.env`, Docker, or external email service.

## Run

Run commands from `backend/digital-banking`, which contains `pom.xml`, `.env`,
and the Maven wrapper. From the `backend` directory, first run `cd digital-banking`.
The wrapper works without a separate Maven installation; Java 21 or a compatible
newer JDK must be available.

Configure PostgreSQL, local SMTP, and an ignored `.env` using `.env.example`.
Use the `local` profile for opt-in demo fixtures. Replace the database password,
signing-secret placeholder, and demo-password placeholder before startup.

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
- With `SPRING_PROFILES_ACTIVE=local`, SMTP defaults to `localhost:1025` with
  authentication and STARTTLS disabled. To use Gmail SMTP in this profile, update
  the existing mail settings to `MAIL_HOST=smtp.gmail.com`, `MAIL_PORT=587`,
  `MAIL_SMTP_AUTH=true`, and `MAIL_STARTTLS=true`, and configure one
  `MAIL_USERNAME` and `MAIL_PASSWORD` (a Gmail app password). Adding Gmail
  credentials alone does not change the SMTP host.
