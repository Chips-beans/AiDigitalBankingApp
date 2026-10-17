# Phase 1 Code Review and QA Report

Review date: 17 October 2026.

## Result

Six groups of defects were found and corrected. The first eight regression tests
failed against the implementation before the corrections. Expanded QA also
reproduced an unbounded failure-audit wait and an incorrectly classified
idempotency-lock timeout; both were corrected.

The complete suite passes **74 tests**, with **zero failures, errors, or skips**.
There are no unresolved blocking findings in the Phase 1 paths reviewed here.
This result covers the financial posting and audit foundation; the later payment,
fraud-enforcement, administration, and application phases remain separate work.
Biometric authentication remains excluded.

## Review scope and method

Reviewed transfer/deposit orchestration, account locking and status updates,
idempotency claims and saved responses, money validation, database constraints,
pagination, audit identity/correlation, failure handling, and migrations. Existing
authentication and ownership tests were retained as regressions.

QA used real HTTP on automatically allocated ports, isolated PostgreSQL 14.22,
local SMTP capture, two-connection application pools, controlled concurrent
requests, and injected database failures. The build uses JDK 24.0.2 with Java 21
compilation targets and the project's Maven wrapper. Tests do not send external
email or change the configured development database.

P1 denotes a financial-integrity issue requiring priority correction. P2 denotes
a correctness, availability, or audit-reliability issue.

## Findings and corrections

| ID | Priority | Reproduced behavior | Correction |
| --- | --- | --- | --- |
| F1 | P1 | A caller transaction that had already loaded an account could post using cached balance/status even after obtaining a database lock | Explicitly refresh locked account entities before reading financial state; apply the same rule to staff status changes |
| F2 | P1 | PostgreSQL `NUMERIC` accepted `NaN` balances, amounts, and fees despite the positivity constraints | Add V9 finite-money constraints and a preflight that refuses existing non-finite records without changing them |
| F3 | P2 | A complete audit-write failure escaped the HTTP filter as a generic servlet error instead of the standard API response | Add a typed audit-storage exception and safe HTTP 503 `AUDIT_UNAVAILABLE` responses, including filter-level failures |
| F4 | P2 | Account/idempotency lock waits were unbounded; a separate rejection-audit transaction could also wait indefinitely | Add transaction-local lock limits to financial and audit transactions; consistently map retryable JDBC/ORM lock conflicts to HTTP 409 |
| F5 | P2 | Validation failures used plural audit modules such as `TRANSACTIONS`, whereas successful postings used `TRANSACTION` | Normalize modules and known operation actions so rejected and successful requests can be queried consistently |
| F6 | P2 | A failed registration audit left the request attributed to a generated user ID even though that user transaction rolled back | Promote request identity only after transaction commit; a rolled-back registration stays anonymous |

### F1 - Cached entity state after locking

The reproduction loaded a USD 100 account in a transaction, committed a separate
update to USD 200, and then invoked the shared financial command for USD 10.
Before the correction, the resulting balance was **USD 90**, rather than
**USD 190**. A corresponding test showed that a separately committed freeze could
be bypassed through the same cached entity.

The regular HTTP facade starts a fresh command transaction, so this reproduction
targets reuse of the shared service inside an existing caller transaction. That
is a supported and relevant boundary for later workflows. A locking query alone
does not guarantee that Hibernate replaces an existing entity's cached fields.

The posting service and staff account-status service now refresh account state
while holding the pessimistic lock. Ascending account-ID lock order is preserved.
Tests also verify that a status change cannot overwrite a newer committed balance.

Source: [FinancialPostingService](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/transaction/service/FinancialPostingService.java)
and [AccountServiceImpl](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/account/service/impl/AccountServiceImpl.java).

### F2 - Non-finite money at the database boundary

Direct SQL could store `NaN` in Phase 1's numeric money columns. This was a database
constraint gap; HTTP requests already use validated `BigDecimal` values. Imported
or internally written invalid data could still break later account reads and
financial processing.

V9 adds explicit upper-bound checks, which reject PostgreSQL's `NaN` ordering as
well as out-of-range money. It retains the existing nonnegative/positive,
currency, and KHR precision rules from V8. Existing migrations were not edited.

Tests cover valid V8 upgrades, preservation of balances/history/saved idempotency
responses, and separate refusal cases for legacy `NaN` balances, amounts, and
fees. Failed upgrades leave the original values intact and add no partial V9
constraints. Invalid legacy money requires explicit reconciliation, not an
automatic replacement with zero.

Source: [V9 migration](../backend/digital-banking/src/main/resources/db/migration/V9__reject_non_finite_money.sql).

### F3 - Audit storage failure responses

QA disabled audit insertion through an isolated test constraint and exercised
both anonymous requests and transfers. Before the fix, the filter returned a
generic HTTP 500 servlet response. A failure occurring after MVC handling was
outside the controller exception advice.

Required audit failures now return HTTP **503**, with `success=false` and
`error=AUDIT_UNAVAILABLE`. Responses retain correlation and CORS metadata and do
not disclose SQL, constraint names, or stack traces. A failed audit attempt is
tracked so the filter does not repeatedly retry an already failed rejection write.

The posting-audit failure tests confirm rollback of balances, transaction history,
and idempotency claims. Restoring audit storage and retrying the original key
creates one posting. When audit storage itself is unavailable, the failed request
cannot also be durably recorded there; the service reports that unavailability
instead of pretending the audit succeeded.

Source: [AuditTrail](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/audit/service/AuditTrail.java),
[RequestAuditFilter](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/audit/service/RequestAuditFilter.java),
and [GlobalExceptionHandler](../backend/digital-banking/src/main/java/com/bank/digital_banking/common/exception/GlobalExceptionHandler.java).

### F4 - Bounded contention and consistent retry behavior

Tests held account locks, unique idempotency claims, and an exclusive audit-table
lock from a separate connection. They demonstrated that the original requests
could outlive the test deadline. A later test also found that JDBC's idempotency
insert classified PostgreSQL lock timeout `55P03` as an uncategorized SQL error,
while the ORM account-lock path already produced a retryable conflict.

The shared transaction lock policy now uses PostgreSQL transaction-local
`lock_timeout`. It applies before account/idempotency locking and audit insertion,
including separate rejection-audit transactions. The helper lives in common
utilities so audit and transaction modules do not depend on each other's services.

`FINANCIAL_LOCK_TIMEOUT_MS` defaults to **5000** and accepts **50-60000** milliseconds.
It limits each database lock wait; it is not a total HTTP request deadline. The QA
profile uses 250 ms to reproduce contention quickly. Tests confirm that the setting
does not leak into reused pooled connections.

Account/idempotency conflicts return HTTP **409 / CONCURRENT_UPDATE**, and required
audit-storage contention returns HTTP **503 / AUDIT_UNAVAILABLE**. The raw JDBC
states `55P03`, `40P01`, and `40001` receive consistent conflict handling. Failed
claims and postings roll back. Clients retain the same idempotency key on retries.

Source: [TransactionLockPolicy](../backend/digital-banking/src/main/java/com/bank/digital_banking/common/util/TransactionLockPolicy.java).

### F5 - Consistent audit classification

A transfer rejected by DTO validation previously produced module `TRANSACTIONS`
and action `REQUEST_REJECTED`; a transfer rejected by its financial service used
module `TRANSACTION` and action `TRANSFER`. A canonical module query could therefore
miss relevant new failure events.

Known routes now map to fixed canonical module and action names. Arbitrary paths,
credentials, and request bodies are not copied into audit details. Existing audit
rows are preserved; historical records retain their original module names.

### F6 - Identity promotion after commit

QA forced a registration audit failure after the database allocated a new user ID.
The user, device, and session transaction rolled back, but the old implementation
had already attached that generated identity to the request. The rejection audit
therefore claimed a user ID that did not exist.

The successful event still writes its intended actor inside the business
transaction. Request-level identity promotion now occurs through an after-commit
callback. The failure regression confirms that no user is created and that the
rejection audit actor is `ANONYMOUS`.

## QA results

| Test group | Tests | Result |
| --- | ---: | --- |
| Existing context, JWT, authentication/ownership, and Phase 0 migration regressions | 37 | Passed |
| Original Phase 1 financial tests | 18 | Passed |
| Original Phase 1 migration tests | 2 | Passed |
| New review behavior/concurrency/failure regressions | 13 | Passed |
| New V8-to-V9 preservation and invalid-data migration checks | 4 | Passed |
| **Total** | **74** | **0 failures, 0 errors, 0 skips** |

The new review tests additionally verify simultaneous conflicting payloads using
one key, clean retry after an in-flight claim times out, pooled lock-setting reset,
canonical rejection audits, CORS headers during audit outages, and correct
registration identity after rollback.

Regression sources: [PhaseOneReviewTests](../backend/digital-banking/src/test/java/com/bank/digital_banking/PhaseOneReviewTests.java)
and [PhaseOneReviewMigrationTests](../backend/digital-banking/src/test/java/com/bank/digital_banking/PhaseOneReviewMigrationTests.java).

Tests intentionally generate database constraint errors, lock timeouts, and
migration refusal messages. These are expected fault-injection evidence; the
Maven final test summary determines success.

## Migration and local application handoff

The configured development database was inspected read-only. At review time it
was at V7, with no non-finite account balances, transaction amounts, or fees. The
existing server on port 8080 was left running and was not replaced by the tests.

Stop that server in its VS Code terminal with `Ctrl+C`, then run from
`backend/digital-banking`:

```powershell
.\mvnw.cmd spring-boot:run
```

The updated startup applies pending V8 and V9 migrations. Existing V8 installations
apply V9 only. If the finite-money preflight fails in another database, reconcile
the flagged financial records explicitly before retrying; do not edit migration
checksums or replace unknown balances automatically.

Transfers and staff deposits continue to require `Idempotency-Key`. Keep its value
and payload stable after timeouts or retryable failures. Validations, ownership,
roles, and the original successful-result replay rules remain in effect.

## Verification and limits

Run from `backend/digital-banking`:

```powershell
.\mvnw.cmd clean verify
```

This verifies compilation, the complete regression suite, and the packaged Spring
Boot artifact. Reports are generated in `target/surefire-reports`.

Final clean verification completed at **07:58 on 17 October 2026 (UTC+07:00)**:
**BUILD SUCCESS**, 74 passing tests. The packaged artifact includes V9 and the common
transaction lock policy; the obsolete transaction-module lock-policy class is absent.

The review demonstrates correctness for the tested Phase 1 scenarios. It does not
establish production throughput, availability during a complete database outage,
or real-provider settlement correctness. Payment verification/settlement and
fraud enforcement remain the later milestones in the
[backend completion plan](BACKEND_COMPLETION_PLAN.md).
