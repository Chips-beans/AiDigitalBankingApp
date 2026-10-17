# Phase 1 - Financial correctness and automatic auditing

Implemented 17 October 2026. Scope follows Phase 1 of the
[backend completion plan](BACKEND_COMPLETION_PLAN.md); biometrics remain excluded.

Review corrections are recorded in the [Phase 1 code review and QA report](PHASE_1_CODE_REVIEW_QA.md).
They add V9, locked-entity refreshes, bounded lock waits, reliable audit-failure
responses, and corrected audit classification/identity handling.

## Delivered behavior

- Transfers and staff deposits share a financial posting service. It locks account
  rows in ascending database-ID order before reading mutable financial state.
  Staff account-status changes use the same row-lock policy.
  Locked entities are explicitly refreshed so an existing persistence context
  cannot supply stale balances or account status.
- The posting validates ownership, active account status, currency, sufficient
  funds, and destination balance limits after locks are acquired. Both balance
  updates, the transaction, its audit event, and its successful idempotency result
  commit together. Any failure rolls all of them back.
- Financial mutations require a persistent, caller/operation-scoped
  `Idempotency-Key`. Concurrent matching requests produce one posting. Replays
  return the saved original result, including a stable UTC timestamp. Changed
  payloads using an already successful key receive HTTP 409.
- USD supports two decimal places; KHR supports whole riel. Unsupported precision
  is rejected, not rounded. Supported currencies are USD and KHR, case-insensitive
  at input and uppercase in storage. A transaction amount must be positive and
  fit `NUMERIC(15,2)`; the upper bound is USD 9,999,999,999,999.99 or KHR
  9,999,999,999,999. Deposits must match the destination account currency.
- Transaction history sorts by `created_at DESC, id DESC`. All existing list
  endpoints accept bounded pagination and retain their existing response shapes.
- Authentication, account creation/status changes, merchant registration/edits/
  approval, fraud-rule creation, QR creation/status updates, transfers, and deposits
  emit real audit events. Failed HTTP requests are audited after business rollback.
- Audit events use actual user IDs or explicit `ANONYMOUS`/`SYSTEM` identities,
  generated correlation IDs, outcomes, resource identifiers where available,
  remote address, and bounded user-agent metadata. Automated events do not store
  passwords, OTPs, tokens, request bodies, or financial remarks.

Payment settlement and fraud enforcement remain in their later phases. Current QR
status updates are audited but do not constitute verified balance settlement.

## Financial mutation contract

Existing routes remain under `/api/v1`:

| Route | Role | Required addition |
| --- | --- | --- |
| `POST /transactions/transfer` | CUSTOMER | `Idempotency-Key` header |
| `POST /transactions/deposit` | BANK_EMPLOYEE or ADMIN | `Idempotency-Key` header; actor comes from authentication |

Keys contain 1-128 ASCII letters/digits or `.`, `_`, `:`, `-`. A UUID is suitable.
The client generates the key once for an intended financial operation and retains
it until its result is known. It reuses that key and the same payload after a
timeout; it uses a new key for a different operation.

Example headers:

```http
Authorization: Bearer <access-token>
Content-Type: application/json
Idempotency-Key: 2479e3db-4166-4705-8985-dd47dfad65f5
```

Example transfer body:

```json
{
  "sourceAccountNumber": "9000000001",
  "destinationAccountNumber": "9000000002",
  "amount": 10.25,
  "currency": "USD",
  "remark": "Lunch"
}
```

Canonical request fingerprints normalize currency case and numerically equivalent
amounts, so `10` and `10.00` represent the same amount. Account, amount, currency,
and remark changes otherwise participate in conflict detection. Authentication
and role checks still apply to replays. Failed operations do not retain a committed
idempotency claim; a later retry must pass current financial checks.

Successful keys currently have no automatic expiry. Do not delete their records
or reuse their keys as a cleanup shortcut. Retention and replay windows will be
defined before Phase 9 cleanup jobs are enabled.

| HTTP status | Code or condition |
| --- | --- |
| 400 | `IDEMPOTENCY_KEY_REQUIRED`, `INVALID_AMOUNT`, `UNSUPPORTED_CURRENCY`, `CURRENCY_MISMATCH`, `VALIDATION_FAILED`, `INVALID_REQUEST`, `INSUFFICIENT_FUNDS`, `INVALID_PAGINATION` |
| 403 | Wrong role |
| 404 | Missing or foreign-owned source account |
| 409 | `IDEMPOTENCY_CONFLICT`, `ACCOUNT_INACTIVE`, or `CONCURRENT_UPDATE` |
| 503 | `AUDIT_UNAVAILABLE`; a required posting-audit failure rolls back its financial command |
| 500 | Other internal errors; retain the original key when retrying a financial operation |

Business responses continue to use `ApiResponse`. The response envelope's timestamp
may differ on a replay; `data` is the persisted original financial result.

## Pagination and audit compatibility

Existing account, merchant-owner/status, fraud, AI-insight, and audit lists accept
`page` (default 0) and `size` (default 20). Transaction history retains its default
size of 10. Maximum size is 100; invalid sizes, negative pages, and offset overflow
return HTTP 400. List response formats are preserved, so clients must request the
next page rather than assume an unbounded response contains all records.

API responses include server-generated `X-Correlation-ID`, exposed through CORS.
Audit responses now include `correlationId`. Financial records also store their
initiating user, operation, and correlation ID. New success events have explicit
resource references; historical rows are left unchanged and may lack this metadata.
Known rejection routes use the same canonical modules/actions as their business
events. Registration promotes request identity only after commit, so a rolled-back
user does not become the failure audit's actor.

The old unused annotation-based audit aspect was retired in favor of explicit
business events. Audit writes are synchronous. The administrator-only
`POST /audit/log` route remains compatible at the request level but records only
`AUDIT / MANUAL_EVENT_SUBMITTED` using the actual caller and server metadata. It
does not accept client-supplied actors, outcomes, arbitrary details, or financial
event claims as authoritative audit facts.

## Transaction design

`TransactionServiceImpl` is a nontransactional orchestration boundary: financial
entry points reject an existing caller transaction. They invoke the transactional
`FinancialCommandService`, which claims the request key at READ COMMITTED isolation
using a unique PostgreSQL key and `INSERT ... ON CONFLICT DO NOTHING`. Competing
claims wait for the in-flight transaction; a rollback releases the claim.

The command calls `FinancialPostingService` inside that same transaction. Account
IDs are read as scalar values first; managed account entities are loaded only when
their locks are acquired, preventing stale balance/status reads. The posting service
requires an existing transaction and repeats its money/role invariants.

The audit writer participates in the posting transaction through the same data
source. Rejection audit writes run separately only after the command transaction
has unwound. This avoids losing the failure event to rollback and avoids holding
an outer financial connection while acquiring a failure-audit connection. API
responses are buffered until rejection auditing completes.
Required audit-storage errors use a safe HTTP 503 response, including failures
outside MVC exception handling. If audit storage is down, failure logging there
cannot be guaranteed and the API reports unavailability.

The common transaction lock policy applies a transaction-local limit to account,
idempotency, and audit lock waits. `FINANCIAL_LOCK_TIMEOUT_MS` defaults to 5000 and
accepts 50-60000 milliseconds. This is a per-lock limit, not an overall request
deadline. JDBC and ORM contention both receive HTTP 409 `CONCURRENT_UPDATE`;
clients retry financial operations with their original key.

Future payment, bill, and top-up services must extend this posting path with their
own verified funding/authorization rules. They must not write account balances
directly. This phase supplies the shared primitive; it does not enable those future
financial operations.

## Migration and local startup

V8 adds:

- Account/transaction money constraints and transaction history indexes.
- `idempotency_records`, its unique caller/operation/key constraint, a transaction
  link, request fingerprint, and saved response.
- Transaction initiator/operation/correlation fields and audit correlation metadata.

The migration checks existing balances, currencies, amounts, fees, and KHR precision
before changing the schema. It aborts on invalid legacy money and does not silently
rewrite records. V2-V7 are unchanged. Existing financial records are preserved;
their previously unknown initiator/correlation metadata remains null.

V9 adds finite-money guards because PostgreSQL `NUMERIC` can otherwise accept
`NaN`. Its preflight refuses non-finite balances, amounts, or fees without changing
them. V8 remains unchanged, and valid V8 balances, transaction history, and saved
idempotency responses are preserved during the upgrade.

The configured local database passed a read-only V8 preflight (zero invalid account
or transaction rows). It was still at V7 during implementation. A pre-existing
VS Code server was listening on 8080 and was left untouched. Stop that instance
with `Ctrl+C`, then run from `backend/digital-banking`:

```powershell
.\mvnw.cmd spring-boot:run
```

Flyway applies pending V8 and V9 migrations during the updated startup. Do not run
a second copy on 8080.

## Verification

The 37 prior backend tests, 20 original Phase 1 tests, and 17 review regressions
pass: 74 total, with no failures, errors, or skips. Tests use isolated PostgreSQL, real HTTP on an allocated port,
and local SMTP; they do not mutate the configured development database or send
external email.

Coverage includes simultaneous overspending, opposite-direction locking, concurrent
credits, duplicate/replayed/conflicting keys, staff deposits, currency/precision/
range errors, KHR replay stability, destination overflow, account-freeze races,
stable pagination across all list APIs, attributable/correlated audit events,
authentication and administrative auditing, rejected-request privacy, manual audit
spoof prevention, service/database money checks, and induced audit-write failure
rolling back balances/history/claims.

Migration tests cover a fresh schema, V7-to-V8 preservation, and refusal of invalid
legacy data without silently changing it. These are correctness/concurrency tests,
not a production load or real-provider settlement assessment.

Verification command:

```powershell
.\mvnw.cmd clean verify
```
