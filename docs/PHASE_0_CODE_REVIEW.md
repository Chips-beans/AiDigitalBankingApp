# Phase 0 Backend Code Review

Reviewed and corrected **16 October 2026**. Baseline: commit `672c4af`.

## Result

The Phase 0 architecture is suitable for the next Flutter authentication phase.
Eleven defects were corrected; **37 backend tests and Maven packaging pass**.
This is a source and regression review of authentication, authorization, API
errors, and persistence readiness, not certification that every banking workflow
is complete or free of defects. Remaining financial-workflow findings are below.

## Findings corrected

P1 means a high-priority security issue; P2 means a correctness or reliability issue.

| Priority | Previous behavior | Correction |
| --- | --- | --- |
| P1 | Wrong passwords bypassed OTP verification counters, allowing unlimited password guesses | Database-backed login limit: 10 attempts per fixed 15-minute window; username and email share the user's counter; unknown identities are also limited |
| P1 | Merchants could read/edit other merchants and approve themselves | Service methods receive the authenticated actor, enforce ownership, and reserve approval/status listing for administrators |
| P1 | Customers could change their own account to ACTIVE, bypassing a bank freeze | Account status changes require BANK_EMPLOYEE or ADMIN in both routing and service checks |
| P2 | Registration/login held a connection while OTP validation requested another; a busy pool returned HTTP 500 | Credential checks run before a separate, short transaction writes the user/device/session |
| P2 | Multibyte passwords could pass character validation, exceed BCrypt's 72-byte limit, and consume the signup OTP before failing | UTF-8 byte validation returns a password field error before service execution; 72-byte passwords still work |
| P2 | A signed token missing its session claim caused a null-pointer exception | Required claims are checked explicitly and return authentication failure |
| P2 | Server clock differences could make an older OTP appear newest | Select the highest inserted ID under the per-identity lock; use a matching index |
| P2 | Unsupported methods/content types and missing parameters became HTTP 500 | Preserve the framework's 4xx status and headers inside the standard API error envelope |
| P1 | A concurrent merchant profile edit could overwrite an administrator's suspension | Lock merchant rows before both profile edits and status changes |
| P2 | Mixed-case emails stored before Phase 0 could no longer receive login OTPs | Use case-insensitive identity lookup and uniqueness, and normalize the OTP lookup key |
| P2 | Unicode normalization could overflow an unknown identity's rate-limit key and return HTTP 409 | Hash normalized unknown identities into bounded SHA-256 keys; repeated attempts still receive HTTP 429 |

The first six defects, the merchant status race, and the Unicode key overflow were
reproduced with failing tests before their fixes. The others also have regression coverage.

## Architecture

The existing modules retain controllers for HTTP contracts, services for business
rules, repositories for persistence, and DTOs for responses. Dependencies flow
from controllers to services to repositories; persistence entities are not returned
as customer API responses.

`AuthServiceImpl` coordinates verification without holding an outer database
transaction. `LoginAttemptService` commits counters before password checks;
`OtpServiceImpl` commits attempts and single-use consumption independently.
`AuthPersistenceService` then writes identity/device/session data atomically,
locking the user and rechecking enabled state and the verified password hash.
This avoids nested connection acquisition while preserving failed-attempt counters.
Spring documents the connection-exhaustion risk of nested independent transactions
in its [transaction propagation guidance](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-propagation.html).

`SessionService` continues to own refresh rotation, replay revocation, fixed expiry,
and logout. Authorization uses current database roles and session/device state.
No additional service framework or microservice split is needed for Phase 0.

## Data structures and algorithms

Complexities describe expected indexed work, not measured production throughput.
Here, N is stored rows, K is returned records, and L is token length.

| Structure / algorithm | Assessment |
| --- | --- |
| Role `Set` and field-error `LinkedHashMap` | Roles are deduplicated in response sets; validation errors preserve insertion order and one message per field |
| UUID session primary key | Indexed lookup is approximately O(log N); access checks also load current user/device state |
| SHA-256 refresh hash | O(L) hashing; compare fixed-size hashes with `MessageDigest.isEqual`; raw refresh tokens are not stored |
| BCrypt and SecureRandom | Password/OTP hashing is deliberately costly; six-digit OTPs use a cryptographic generator plus expiry, single use, and attempt limits |
| OTP lookup | `(email, purpose, id DESC)` finds the latest challenge without sorting its entire history; approximately O(log N) |
| Login/OTP counters | Atomic insert plus row lock serializes updates per key across app instances; O(log N) lookup, with contention wait under load |
| Account lookup | New `accounts(user_id)` index supports approximately O(log N + K) retrieval instead of a whole-table scan |
| Session replacement | Partial unique index permits only one unrevoked session per user/device and narrows revocation searches |
| Email identity | Unique `LOWER(email)` index matches the repository's case-insensitive predicate and prevents duplicate identities differing only by case |

Index ordering follows the actual equality filters and newest-record query;
see PostgreSQL's [multicolumn index documentation](https://www.postgresql.org/docs/14/indexes-multicolumn.html).
The login limiter uses a fixed window, not a sliding window, and counts successful
and failed attempts. It does not reset on success.

## Migration and client changes

- New **V7** adds `login_attempt_limits`, account/email indexes, the session uniqueness
  constraint, and the replacement OTP index. Applied migrations V2–V6 are unchanged.
  Existing duplicate emails differing only by case must be resolved before V7;
  the migration refuses them rather than merging user identities.
- `LOGIN_MAX_ATTEMPTS` defaults to 10; `LOGIN_WINDOW_MINUTES` defaults to 15.
  Login throttling returns `429`, `LOGIN_RATE_LIMITED`, and `Retry-After`.
- Registration/login passwords must fit **72 UTF-8 bytes**. Flutter should display
  the server's password field error and rate-limit retry time.
- `PATCH /api/v1/accounts/{number}/status` is a staff operation. Merchants may edit
  their own details, but only administrators change merchant status.
- A successfully verified OTP stays consumed if a later device/session write fails;
  request a new code. This preserves one-time use.

## Verification

Run `./mvnw.cmd -q package` from `backend/digital-banking`.

Passed: **34 integration tests, 1 context test, 1 JWT regression test,
and 1 migration test; zero failures, errors, or skips**. Tests use real isolated
PostgreSQL and local SMTP, with a two-connection pool. Coverage includes concurrent
refresh/OTP/login limits, one-free-connection authentication, alias throttling and
window reset, merchant/staff permissions, Unicode password boundaries, clock-skew
OTP selection, legacy email login, Unicode identity limits, concurrent merchant suspension, and existing
identity/ownership/session checks. V6-to-V7 upgrade preserves sample users,
sessions, and OTPs and enforces session and normalized-email uniqueness.

## Remaining work outside Phase 0

These findings prevent treating the whole backend as ready for real-money use:

- **P1 — Balance concurrency and retries:** `TransactionServiceImpl.processTransfer`
  and `processDeposit` read and rewrite balances without row locking, entity
  versioning, or idempotency records. Concurrent changes can lose updates, and
  retried requests can apply twice. Complete this in the transfer phase.
- **P1 — Money validation:** `processDeposit` does not compare request currency to
  the account currency. Transfer/deposit DTOs do not restrict decimal scale to
  the database's two decimal places. Validate currency, precision, and rounding
  before enabling those flows.
- **P1 — Payments:** provider verification, amount/currency reconciliation,
  idempotent ledger settlement, and the required PaymentProviderAdapter abstraction
  remain incomplete. The unsigned webhook remains blocked.
- **P2 — Operational scale:** add expiry/retention jobs for sessions, OTPs and rate
  counters, bounded pagination, deployment-level traffic limits, asynchronous email
  delivery, and auth audit events. The existing audit aspect still uses a placeholder
  actor. Small-pool concurrency tests are not a load test.

The historical `Phase_0_Implementation.docx` describes the initial implementation;
this review and the updated [implementation notes](PHASE_0_IMPLEMENTATION.md) record
the changes above.
