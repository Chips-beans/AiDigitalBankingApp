# F1 delivery and verification

Verified 17 October 2026, approximately 10:30 Asia/Phnom_Penh (UTC+07:00).

**F1 is complete.** This milestone establishes local backend readiness and core
API documentation. Flutter implementation starts with F2; its screens are not
part of this delivery.

The subsequent [F1 code review and QA](FOUNDATION_F1_CODE_REVIEW_QA.md) corrected
schema nullability, failure documentation, launcher integrity/readiness/recovery,
and Windows clean-build instructions. Latest verification: **78 passing tests**,
12 launcher checks in each of PowerShell 7/Windows PowerShell 5.1, and schema/live
workflow checks. The original 76-test evidence below records the initial delivery.

## Delivered

- A Windows local Mailpit launcher at
  [start-local-mail.ps1](../backend/digital-banking/scripts/start-local-mail.ps1).
  It downloads pinned v1.31.5, checks the official release's SHA-256 archive digest,
  binds SMTP/UI to 127.0.0.1:1025/8025, reuses its existing process, and refuses
  conflicting ports. Binaries/logs stay under ignored .local.
- A local-first .env.example covering database, signing key, fixtures, and local
  mail capture. The existing ignored .env was updated only for the local profile
  and mail host/port/auth/TLS; existing credentials were retained.
- A foundation Swagger group containing 14 core paths. The full existing API
  document remains available separately.
- Public auth operations explicitly override inherited bearer security. Protected
  operations retain it. Registration/account opening document 201, success bodies
  document JSON, financial headers are required, and core error schemas/examples
  include rate-limit retry information.
- Executable request examples and descriptions for auth, accounts, internal
  transfers, history/details, staff deposits, and account status changes.
- [Local setup instructions](FOUNDATION_LOCAL_SETUP.md) and
  [the Swagger walkthrough](FOUNDATION_SWAGGER_WALKTHROUGH.md), including real
  request fields, response shapes, OTP delivery, token rotation, idempotency,
  role boundaries, fixtures, demo funds, and common failures.
- Foundation integration tests in
  [FoundationReadinessTests.java](../backend/digital-banking/src/test/java/com/bank/digital_banking/FoundationReadinessTests.java):
  generated contract checks for the full/grouped API, and execution of the
  published examples against isolated PostgreSQL and local SMTP. Review expanded
  the initial two tests to four, covering nullability and audit failure contracts.

## Verification evidence

| Requirement | Observed result |
| --- | --- |
| Configured database | digital_banking_db reachable on local PostgreSQL 18 |
| Migration state | V2–V9 successful; restart validated eight migrations and reported schema version 9, up to date |
| Required fixtures | alice.demo, bob.demo, empty.demo, employee.demo enabled with expected roles; empty/staff have no customer accounts |
| Existing fixture balances | 9000000001 USD 1250.00; 9000000002 USD 500.00; unchanged by the live verification |
| Single backend | Existing process deliberately replaced; one listener owner on 8080 afterward |
| Local configuration | Updated backend started with local profile |
| Inbox | Mailpit v1.31.5 served its UI/API; SMTP and UI listened only on 127.0.0.1 |
| Repeatable launcher | A second launch reused the same inbox instead of starting a duplicate |
| Swagger UI/config | UI returned 200; swagger-config selected /v3/api-docs/foundation |
| OTP workflow | Two signup messages and a staff LOGIN message were captured and used successfully |
| Accounts | Both new customers initially had no accounts, then each opened an account at zero with HTTP 201 |
| Staff funding | Employee deposited USD 100.00; customer deposit/status attempts returned 403 |
| Ownership | Second customer account detail/history access returned 404 |
| Account state | Employee froze the sender; transfer returned 409; employee restored ACTIVE |
| Transfer/retry | USD 25.00 transfer returned 200; identical key/payload returned the same reference; changed payload with that key returned 409 |
| Balances/history | Sender USD 75.00 with deposit/transfer history; receiver USD 25.00 with incoming history; both could read the transfer detail |
| Session lifecycle | Refresh returned a replacement pair; logout revoked access and refresh use; /me without authorization returned 401 |
| Regression build | .\mvnw.cmd clean verify: 76 tests, zero failures/errors/skips, BUILD SUCCESS |
| Working tree hygiene | .env and downloaded binaries ignored; no migrations modified |

The regression build used isolated PostgreSQL 14.22 and local SMTP. Separate live
checks used the configured development database and Mailpit on 8080/1025/8025.
No external recipient received email and no external payment service was called.

The new contract test initially exposed wildcard success media types in generated
documentation. Those were corrected to application/json, then the full clean
verification passed. Existing runtime authorization and financial posting behavior
were preserved.

## Local runtime handoff

The verified backend and Mailpit were left running for Swagger testing:

- [Swagger UI](http://localhost:8080/swagger-ui/index.html).
- [Foundation OpenAPI JSON](http://localhost:8080/v3/api-docs/foundation).
- [Local OTP inbox](http://127.0.0.1:8025).

The backend was launched from the packaged jar produced by clean verify. Its PID
is recorded in backend/digital-banking/.local/backend.pid, with startup/error logs
in .local/backend-stdout.log and .local/backend-stderr.log. Check the current port
owner before another startup; these processes may be stopped/replaced later.

Live verification created two new demo customers/accounts. Their financial and
audit records were retained, and verification-created sessions were logged out:

| Item | Verification record |
| --- | --- |
| Run identifier | cca21195b4 |
| Sender account | 6894676031 |
| Receiver account | 9983241754 |
| Transfer reference | TXN-c6f3dc11eee4444986c577e6fd7a718f |

No passwords, OTPs, or tokens are recorded in this report. Detailed local build
output and a nonsensitive runtime result are under ignored .local. No advanced
features or new database migrations were added. Next: **F2 — Flutter foundation,
authentication, and session integration**.
