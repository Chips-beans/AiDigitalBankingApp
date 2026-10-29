# Backend QA — 19 October 2026

**Later email follow-up:** actual Gmail inbox delivery was verified separately
after this baseline QA run. See [Gmail email setup](GMAIL_EMAIL_SETUP.md) for the
new live defaults, recipient-confirmed delivery, and its verification scope.

**Result: passed. No functional defect was reproduced in the tested foundation
scope.** A clean build passed all **78 tests**, with **0 failures, 0 errors, and
0 skipped tests**. The packaged application also passed the local banking
workflow and independent OpenAPI contract validation. No production source,
configuration, credential, or migration changes were needed.

## Environment and scope

- Repository baseline: `ddba82e` (`F1 and F2 Plan Implementation`); working tree
  was clean before QA.
- Backend: `backend/digital-banking`, Spring Boot 4.1.1, Java 21.0.8 on Windows.
- Automated integration tests: isolated embedded PostgreSQL 14.22 and local SMTP.
- Packaged application: existing local PostgreSQL 18.6 database and Mailpit
  1.31.5 on loopback ports 1025/8025.
- Reviewed authentication/session handling, authorization, account ownership,
  financial posting/idempotency, error handling, and the existing regressions.
  Deferred external payments, AI/fraud integrations, production load, and Flutter
  acceptance were outside this run.

Existing `.env` assignments were checked without printing secret values; no
duplicate assignments were found. Startup validated all eight migrations V2–V9.
The configured database was already at V9, and no migration was necessary.

## Clean build and regression tests

Executed the Maven wrapper with Java 21:

```powershell
.\mvnw.cmd --batch-mode --no-transfer-progress clean verify
```

For this low-memory workstation, the QA invocation capped Maven at 512 MB and the
test JVM at 768 MB, and placed temporary PostgreSQL files on D:. These were
process-local settings, not repository changes.

| Test suite | Passed |
| --- | ---: |
| Application context | 1 |
| Foundation API/readiness contracts and workflow | 4 |
| JWT validation | 1 |
| Financial correctness/concurrency | 18 |
| Phase 1 migrations | 2 |
| Phase 1 review migrations | 4 |
| Financial/audit review regressions | 13 |
| Authentication, authorization, ownership, and validation | 34 |
| Phase 0 migration | 1 |
| **Total** | **78** |

Coverage includes refresh rotation/reuse, logout, disabled/revoked identities,
OTP consumption/throttling, customer/staff restrictions, concurrent spending,
duplicate and conflicting idempotency keys, monetary constraints, audit failure
rollback, and migration preservation/refusal checks.

## Packaged application and live API checks

The rebuilt jar started successfully against the configured local database.
The existing local QA drivers in `backend/digital-banking/.local` then exercised
real HTTP requests and captured OTP emails. They created two uniquely named QA
customers and new accounts; existing fixture balances were not used as sources.

| Check | Result |
| --- | --- |
| Missing access token | 401 |
| Real signup OTPs, registration, zero-balance account creation | Passed; 201 for registration/account opening |
| Staff login with real LOGIN OTP | Passed |
| Customer attempts at staff funding/status actions | 403 |
| Cross-customer account/history reads | 404 |
| Staff local test deposit | USD 100.00 |
| Transfer from frozen account | 409; staff restored ACTIVE |
| Internal transfer | USD 25.00 posted once |
| Identical transfer retry | Original reference returned; no duplicate debit |
| Changed payload with the same key | 409 |
| Final sender/receiver balances | USD 75.00 / USD 25.00 |
| Account histories and transaction details | Matched the postings and ownership rules |
| Refresh and logout | Passed; access and refresh rejected after logout |

Independent JSON Schema validation passed for **65 schema definitions**, **160
published examples**, **19 live request bodies**, and **36 live response bodies**
across the full and foundation OpenAPI documents.

Live run `0df9c0bd4c` completed at **14:50:55 UTC+07:00** on 19 October 2026.
QA accounts: `8629872899` and `9766502115`. Transfer reference:
`TXN-0b10ac5868bf4da8ad9b518497277e24`. These local test financial/audit records
were retained, and the QA driver logged out its sessions. Passwords, OTPs, and
tokens are not included in this report.

## Warnings and interpretation

The following non-blocking warnings were observed:

- Hibernate reports that explicitly setting `PostgreSQLDialect` is redundant
  because it can detect PostgreSQL automatically.
- Test compilation reports deprecated API usage in `FoundationReadinessTests`.
- Mockito/Byte Buddy reports dynamic Java-agent attachment that will need an
  explicit agent configuration with a future JDK policy change.
- Springdoc reports enabled Swagger/API-doc endpoints, consistent with the
  current local development setup.

SQL constraint violations, lock timeouts, and rejected migration messages in the
automated test log are deliberate negative-test cases. The final Surefire XML
reports and Maven summary confirm zero test errors or failures. No unexpected
application error was found in the successful live workflow.

## Evidence and handoff

Logs and nonsensitive machine-readable results are retained at
`D:\CodexQa\AiDigitalBankingBackend\2026-10-19`:

- `maven-clean-verify.log` and `test-summary.json`
- `backend.stdout.log`, `backend.stderr.log`, and `mailpit-start.log`
- `live-workflow-contracts.log`
- `f1-runtime-verification.json` and `f1-qa-contract-results.json`

Surefire reports are also available in the backend's ignored
`target/surefire-reports` directory. Earlier local F1 reports were backed up before
the live QA drivers ran and restored afterward. The API and Mailpit started for
this run were stopped on completion, returning their ports to the initial state;
the existing PostgreSQL service remains running. The only repository addition is
this QA report; no commit was created.
