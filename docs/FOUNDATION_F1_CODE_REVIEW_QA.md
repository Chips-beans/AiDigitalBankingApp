# F1 code review and QA

Reviewed and verified 17 October 2026, Asia/Phnom_Penh (UTC+07:00).

**Result: F1 review passed after corrections.** The full clean build passed
**78 tests with zero failures, errors, or skips**. Launcher regression checks,
JSON Schema checks, and the local banking workflow passed separately. No known
unresolved defect remains in the reviewed F1 scope. This evidence covers the
cases below; it is not a guarantee that all possible software defects are absent.

## Review scope

Reviewed the F1 OpenAPI configuration, foundation API group and examples, mail
launcher/cache behavior, local environment template, setup/Swagger instructions,
and integration tests. Compared generated contracts with the actual security,
audit, authentication, account, and transaction implementations. Preserved the
existing working tree, credentials, migrations, and financial safeguards.

## Findings and corrections

| Finding | Reproduction / impact | Correction and regression evidence |
| --- | --- | --- |
| Nullable values contradicted the OpenAPI 3.1 schemas | A real unauthenticated /auth/me response failed JSON Schema validation because retryAfterSeconds=null was declared integer-only. The same issue invalidated 65 published error examples in the foundation document. Optional request values and nullable deposit/transaction fields had equivalent mismatches. | Generate the error model for the active specification version; document null unions for the actual nullable fields. New integration checks cover both documents and real optional-null inputs; independent schema validation passed afterward. |
| Read/identity operations omitted audit-storage failure | The outer request audit filter can return 503 AUDIT_UNAVAILABLE even for a failed read or missing access token; several documented operations had no 503 response. | All core operations include the 503 contract. An isolated database fault-injection test proves /auth/me returns the documented 503 and restores its temporary constraint afterward. |
| Verified ZIP did not establish cached executable integrity | A valid cached archive plus a deliberately invalid mailpit.exe still reached the launch operation. The original code skipped extraction whenever the executable existed. | Hash the executable against the mailpit.exe entry inside the verified archive on every invocation, including reuse. Repair an invalid idle cache before launch; reject invalid archive/extraction output. |
| Download path was fragile on Windows PowerShell 5.1 and after interruption | The downloader omitted UseBasicParsing, which current Windows PowerShell can require to avoid an interactive web-content prompt. It also wrote directly to the final cached archive, allowing an interrupted download to poison later attempts. | Use basic parsing and a bounded timeout; download to a unique temporary file, verify it, then move it into the cache. Cleanup interrupted/invalid temporary files. Mocked failure checks and a real Windows PowerShell 5.1 empty-cache download/extraction passed. |
| Readiness and startup races could report success incorrectly | Existing-process reuse checked its path/listeners without an API health check; fresh readiness checked only the UI liveness URL. Failed readiness could leave its new process alive, and simultaneous invocations had no coordination. | Require both loopback listeners owned by the expected PID and the pinned Mailpit API version. Serialize launchers with a named mutex. Clean up only a newly created child on failed readiness. Unit-style checks and a real simultaneous cold-start check passed. |
| Inherited Mailpit settings could violate local-only behavior | MP_* environment overrides can enable forwarding/relay or change the otherwise pinned local configuration. | Reject nonempty overrides without printing their values. The regression test restores its test environment; empty variables are harmless. No external mail was sent. |
| Setup guide overstated clean-build compatibility with a running packaged server | A real clean verify failed when Windows refused to delete the jar held open by the QA server. | Document stopping that specific packaged backend before clean verify, and using mvnw.cmd test when retaining the running jar. After the identified QA instance stopped, the clean build passed. |

The source changes are documentation/configuration and development tooling; the
authentication and financial service algorithms were not rewritten. Existing
ownership, role restrictions, locks, idempotency, rollback, and audit requirements
remain enforced by their regression tests.

Relevant primary references:
[Windows PowerShell web-request behavior](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest?view=powershell-5.1),
[OpenAPI 3.1 specification](https://spec.openapis.org/oas/v3.1.0), and
[Mailpit runtime configuration](https://mailpit.axllent.org/docs/configuration/runtime-options/).

## Automated backend verification

Command from backend/digital-banking:

```powershell
.\mvnw.cmd clean verify
```

| Test class | Passing tests |
| --- | ---: |
| DigitalBankingApplicationTests | 1 |
| FoundationReadinessTests | 4 |
| JwtTokenProviderTests | 1 |
| PhaseOneFinancialTests | 18 |
| PhaseOneMigrationTests | 2 |
| PhaseOneReviewMigrationTests | 4 |
| PhaseOneReviewTests | 13 |
| PhaseZeroIntegrationTests | 34 |
| PhaseZeroMigrationTests | 1 |
| **Total** | **78** |

The build finished successfully at 10:44 UTC+07:00. Tests use isolated PostgreSQL
14.22 and local SMTP. They do not reset the development database. Expected SQL
error logs appear in fault-injection/constraint tests; those are asserted failure
scenarios, not test failures.

Foundation tests verify public versus protected security metadata, actual creation
statuses and JSON schemas, required idempotency headers, the foundation-only API
group, nullable fields, audit unavailability, and execution of the published core
request examples. Request timeouts bound the new test client's network waits.

## Launcher regression and live installation checks

Run the reusable harness after the official archive is cached:

```powershell
.\scripts\test-local-mail.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-local-mail.ps1
```

**12 checks passed in each shell** (PowerShell 7 and Windows PowerShell 5.1):

1. Repair a corrupt cached executable before launch.
2. Reject a corrupt cached archive.
3. Use a verified temporary download with basic parsing and timeout.
4. Clean up an interrupted download without poisoning the cache.
5. Reject an invalid downloaded checksum.
6. Preserve a conflicting port owner and avoid duplicate startup.
7. Reject inherited Mailpit overrides without exposing their values.
8. Reuse a healthy, verified inbox.
9. Reject and preserve an unhealthy existing inbox.
10. Clean up only the new child after failed startup.
11. Reject UI-only readiness when SMTP is missing.
12. Check extraction output before execution.

Those harness checks mock process/network boundaries and use ignored isolated
.local/launcher-qa fixtures. Additional live checks established:

- A real Windows PowerShell 5.1 empty-cache download, pinned checksum validation,
  and extraction succeeded; launch was intercepted to preserve the actual inbox.
- Two real simultaneous launch attempts produced one successful startup and one
  intentional competing-launch rejection. SMTP/UI had one owner afterward.
- Re-running the launcher reused that healthy inbox.
- SMTP/UI listened only on 127.0.0.1:1025/8025.

## Generated contracts and live workflow

Independent Python jsonschema Draft 2020-12 validation checked:

| Check | Result |
| --- | --- |
| Schema definitions across full/grouped documents (including repeated models) | 65 valid |
| Published core request/error examples across both documents | 160 valid |
| Live workflow request bodies | 19 matched their schemas |
| Live workflow response bodies | 36 matched their schemas |

The live workflow used the reviewed packaged backend, PostgreSQL development
database, and local Mailpit. Two new customers received signup OTPs, opened
zero-balance accounts, and exercised staff funding, status changes, transfers,
history/details, token refresh, and logout.

| Scenario | Observed result |
| --- | --- |
| Missing access token | 401 with a schema-valid null retryAfterSeconds |
| Signup and account opening | 201; initial account balances zero |
| Employee fixture login | 200 with BANK_EMPLOYEE role and a captured LOGIN OTP |
| Customer staff deposit/status attempts | 403 |
| Another customer's private account/history | 404 |
| Staff demo funding | One USD 100.00 deposit |
| Frozen account transfer | 409; account restored to ACTIVE by staff |
| Internal transfer | One USD 25.00 transfer |
| Identical retry | Same reference; no duplicate debit |
| Changed payload with reused key | 409 |
| Final balances | Sender USD 75.00; receiver USD 25.00 |
| History/detail | Sender has deposit and transfer; receiver has incoming transfer; both can read the shared transfer |
| Refresh/logout | Replacement tokens returned; revoked session rejected for access and refresh |

Successful live run: **3ac8e15cc1**, recorded at 10:46 UTC+07:00.
Sender account: **7523333790**; receiver: **8538368330**.
Transfer reference: **TXN-7e38c76fe7e94bbbb540272417a8477b**.
Demo financial/audit records were retained; verification-created sessions were
logged out. Passwords, tokens, and OTPs are not included in this report.

Local build output and nonsensitive runtime/schema results are under ignored
.local; committed/reviewable regression sources are in the test class and
scripts/test-local-mail.ps1. No database migration or real credential was changed
during this review. The updated backend and inbox were left running for Swagger.

## Verification boundaries

This review covers F1 on the current Windows AMD64 environment and the stated
backend/launcher cases. Flutter, other operating systems, live email providers,
advanced fraud/AI/payment integrations, and production load were outside scope.
The next application milestone remains F2.
