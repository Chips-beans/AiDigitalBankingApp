# Digital Banking Backend

Spring Boot backend for AI Digital Banking and Smart Wallet.

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

Configure PostgreSQL, local SMTP, and an ignored `.env` using `.env.example`.
Use the `local` profile for opt-in demo fixtures. Replace the database password,
signing-secret placeholder, and demo-password placeholder before startup.

```powershell
.\mvnw.cmd spring-boot:run
```

Default API prefix: `http://localhost:8080/api/v1`.
Swagger UI: `http://localhost:8080/swagger-ui.html`.
