# Backend Completion Implementation Plan

Prepared 17 October 2026 following the backend requirements review.

## Objective and scope

Complete the missing and incomplete backend requirements for AI Digital Banking
and Smart Wallet. Biometric authentication is excluded from the project scope.
Password, email OTP, registered devices, and server-managed sessions remain the
authentication approach.

This is an implementation plan, not a record of completed work. Existing
authentication, account ownership, refresh rotation, logout, merchant ownership,
and migrations V2-V7 form the baseline. The 37 existing tests passed during the
preceding debugging session; they do not establish financial-workflow readiness.

Phase 1 is now implemented; see [Phase 1 delivery and verification](PHASE_1_IMPLEMENTATION.md).
Later phases remain planned. The Phase 1 notes define the delivered contracts and
the remaining boundary with provider settlement and fraud enforcement.

Retain the Spring Boot modular monolith, PostgreSQL, Flyway, and current
controller/service/repository structure. Extend existing modules rather than
introducing microservices. Keep the existing `/api/v1` contract compatible where
possible, and document new endpoints in OpenAPI.

The plan covers backend services and integration contracts. Flutter screens,
camera-based QR scanning, and the merchant, employee, and administrator interfaces
remain separate application work. A backend milestone alone does not complete
those applications.

## Delivery sequence

| Phase | Deliverable | Dependencies | Completion gate |
| --- | --- | --- | --- |
| 1 | Financial correctness and automatic auditing | Existing baseline | Concurrent requests preserve balances; retries cannot duplicate postings; financial actions have attributable audit events |
| 2 | Password recovery, devices, and administration | Phase 1 audit foundation | Reset and revocation work; administrators manage users and roles without privilege escalation |
| 3 | Integrated fraud detection and employee review | Phases 1-2 | Transfer execution enforces risk decisions; employees investigate and resolve alerts |
| 4 | Provider-independent payments and QR lifecycle | Phases 1-3 | Verified, reconciled provider events cause one financial posting per payment |
| 5 | Merchant transactions, settlements, and sales analytics | Phase 4 | Merchants see only their sales and request settlements without duplicate payouts |
| 6 | Beneficiaries, schedules, statements, and receipts | Phases 1-3; receipts also use Phase 4 | Scheduled transfers execute once per occurrence; account documents reconcile with stored transactions |
| 7 | Transaction categorization, spending analytics, and AI | Phases 1, 4, and 6 transaction contracts | Spending answers use server-calculated data belonging to the signed-in customer |
| 8 | Notifications, bills, top-ups, locator, and exchange simulation | Phases 1-4 | Each simulated financial operation is labelled, validated, and posted once |
| 9 | Disputes, operational monitoring, and release verification | Phases 1-8 | All required role journeys and recovery scenarios pass against a fresh and upgraded database |

Phase 2 and non-financial parts of Phase 6 can follow Phase 1 independently.
Preserve the listed gates before enabling dependent financial operations.

## Phase 1 - Financial correctness and automatic auditing

### Implementation

- Create a shared financial posting path used by transfers, deposits, payment
  settlement, and later bill/top-up operations. Persist balance changes and their
  transaction record in the same database transaction.
- Lock affected account rows in a consistent account-ID order. Include staff
  account-status changes in the same concurrency policy so a stale update cannot
  overwrite a freeze or a balance. Recheck status and available balance after
  obtaining locks.
- Introduce `Idempotency-Key` for financial mutation APIs. Persist the authenticated
  caller, operation, key, request fingerprint, and result. Enforce uniqueness;
  a repeated matching request returns its original result, and a changed payload
  with the same key returns a conflict. Handle simultaneous duplicates atomically.
- Validate supported currency, amount precision, maximum value, and account
  currency at both API and service boundaries. Define the USD/KHR precision policy
  explicitly; reject unsupported precision rather than silently rounding it.
- Add database constraints for positive transaction amounts, nonnegative fees,
  and valid account balances, consistent with the supported account model.
  Inspect existing data before adding constraints.
- Bound page sizes and validate pagination inputs. Use stable ordering including
  an ID tie-breaker for transaction history.
- Replace placeholder audit actors with authenticated identities or explicit
  system-job identities. Capture action, resource, outcome, and correlation ID;
  record request metadata where available. Never capture passwords, OTPs, tokens,
  or whole financial request bodies.
- Emit audit events from actual authentication, account, financial, and
  administration operations. Commit successful financial audit records with the
  posting; persist rejected-attempt events separately from rolled-back mutations.
  Use synchronous writes for the initial implementation; add asynchronous delivery
  only when failure handling is defined.

### Data and API changes

- Add `idempotency_records` and appropriate unique constraints/indexes.
- Extend existing transactions with the linkage needed to trace the initiating
  operation; retain existing references and ownership rules.
- Apply new Flyway migrations after V7. Do not modify applied migrations.
- Keep `POST /transactions/transfer` and the staff-only deposit route; document
  their idempotency contract and consistent error responses.

### Acceptance criteria

- Parallel transfers cannot spend the same funds twice or lose incoming credits.
- Repeated and simultaneous duplicate submissions create one posting.
- An induced failure rolls back both balances and the transaction record.
- Frozen, foreign-owned, insufficient-funds, wrong-currency, invalid-precision,
  and oversized-amount requests fail without changing balances.
- Audit records identify the real actor; financial success cannot commit without
  its associated required audit record.

## Phase 2 - Password recovery, devices, and administration

### Implementation

- Add password-reset request and confirmation using purpose-specific, expiring,
  single-use challenges. Apply request and verification limits and a uniform
  public response for known and unknown email addresses.
- A successful reset updates the password hash, consumes the challenge, and
  revokes all existing sessions atomically. Reusing the challenge must fail.
- Add customer APIs to list and revoke their own devices and sessions. Revoking
  a device invalidates its access and refresh sessions. A fingerprint remains an
  installation identifier, not proof of possession or biometric authentication.
- Add administrator APIs for paginated user search, user detail, enable/disable,
  role assignment/removal, and approved runtime configuration.
- Public registration continues to create customers only. Staff, administrator,
  and merchant access is provisioned through an administrator workflow.
- Prevent removal or disabling of the last active administrator. Ensure current
  database permissions are enforced after role changes.
- Keep secrets outside runtime configuration APIs. Allow only explicitly defined,
  validated settings, with administrator audit history. Connect configurable fraud
  thresholds to the evaluator rather than storing unused settings.

### Proposed API additions

- `POST /auth/password-reset/request` and `/auth/password-reset/confirm`.
- `GET /devices`, `DELETE /devices/{id}`, `GET /auth/sessions`, and
  `DELETE /auth/sessions/{id}`.
- `/admin/users`, `/admin/users/{id}/roles`, and `/admin/configuration`.

### Acceptance criteria

Reset expiry, replay, limits, and session revocation are tested. Customers cannot
manage another user's devices or grant roles. Disabled users lose access. Every
administrative change is attributable and the last active administrator remains
protected.

## Phase 3 - Integrated fraud detection and employee review

### Implementation

- Invoke risk evaluation inside transfer orchestration before financial posting.
  Reuse it for payments and other financial operations as they are introduced.
  Derive user, account, session/device, and transaction context on the server.
- Evaluate active stored fraud rules. Count all relevant recent transaction
  attempts or executions under a documented definition, not just flagged records.
- Implement a transparent educational score using amount deviation from history,
  recent activity, unusual local time, country change, and new/untrusted device.
  Persist the score, rule version, reasons, and decision. Do not describe this
  rule-based score as a calibrated fraud probability or a trained ML model.
- Use an injectable location resolver. Local tests use explicit country fixtures;
  external geolocation can be configured later and must not be presented as
  working when only simulated data is available.
- Define allow, step-up, review, and block outcomes. Require a short-lived,
  single-use OTP authorization bound to the exact transaction for step-up.
  Transactions waiting for review do not move funds; approval revalidates funds,
  account state, and authorization before posting once.
- Handle unavailable risk dependencies with a documented review/step-up policy;
  do not silently convert dependency failure to LOW risk.
- Extend flagged records into a fraud-alert lifecycle: open, assigned,
  investigating, resolved, or dismissed. Add employee notes, assignment history,
  and audit events. Add read-only customer/transaction review APIs for employees.

### Data and API changes

- Introduce `fraud_alerts` or migrate `flagged_transactions` into an equivalent
  model with traceable legacy records. If the assessment requires the literal
  table name, use `fraud_alerts`.
- Add investigation/history and transaction authorization records as needed.
- Add `GET /fraud/alerts`, assignment, notes, and resolution endpoints, plus
  `/staff/customers` and `/staff/transactions` with limited response fields.

### Acceptance criteria

The example unusual transaction (foreign location, $2,500, 3 AM, new device)
produces an explainable elevated score relative to the customer's baseline.
Blocked and pending-review requests never post funds. Employee resolution is
audited and cannot duplicate a transfer. Customer users cannot invoke staff APIs.

## Phase 4 - Payment providers, QR lifecycle, and settlement

### Implementation

- Refactor toward `PaymentController -> PaymentService -> PaymentProviderAdapter`.
  Provide common operations for payment creation, QR validation, status inquiry,
  and callback verification. Normalize provider results inside each adapter;
  provider SDK classes do not become the general business contract.
- Add a provider registry selected from persisted/configured provider identity.
  Store provider secrets only in server-side environment/configuration storage.
- Implement Bakong behind the common interface. Add Provider B and Provider C
  using explicit simulator adapters for the course project unless real providers
  and credentials are supplied. Simulators demonstrate interchangeability;
  they do not count as completed live external integrations.
- Replace invented Bakong account IDs with configured, approved merchant/provider
  identities. Validate merchant status, currency, amount, expiry, and ownership.
- Add `qr_payments` and `payment_providers`. Separate the QR request lifecycle
  from the resulting financial payment and its posting reference.
- Add backend QR decoding/validation and payment-confirmation APIs. Camera capture
  and scanning presentation belong to the client applications.
- Define legal payment transitions including pending, successful, failed,
  expired, and cancelled. Do not allow a late failure event to reverse a successful
  posting automatically.
- Verify callbacks according to the provider's actual contract, or perform an
  authenticated server-to-server confirmation when required. Match provider
  reference, amount, currency, recipient, and finality before posting.
- Deduplicate callbacks and status-poll results using unique provider event and
  payment references. Give repeated legitimate callbacks a stable acknowledgement.
- Keep external calls outside long-held account database locks. Commit the verified
  financial result atomically using Phase 1 posting and deduplication safeguards.
- Enable webhook access only after verification is implemented; scope each route
  to its provider. Add reconciliation of pending payments after outages.
- Distinguish local-wallet transfers from externally received funds so the same
  payment is not credited through both paths. External credits need a verified
  funding event and a defined reconciliation record.

### Proposed API additions

`POST /payments/qr`, `/payments/qr/validate`, and `/payments/confirm`;
`GET /payments/{id}`; and `POST /payments/webhooks/{provider}`.
Keep compatible aliases for existing KHQR routes where practical.

### Acceptance criteria

All adapters pass the same contract suite. Forged, mismatched, expired, duplicated,
and out-of-order events cannot create an invalid or duplicate posting. A provider
timeout remains distinguishable from a rejected or unpaid transaction. Pending
payments recover through reconciliation without manual balance edits.

## Phase 5 - Merchant operations

- Associate approved merchants with receiving accounts and provider identities.
  Supply a documented, auditable route for provisioning the merchant role.
- Add merchant-scoped payment/transaction history, date filters, and pagination.
- Calculate sales totals, payment counts, refunds where supported, and settlement
  availability from verified records, with currency separated.
- Define which funds are available versus pending or already reserved for payout.
- Add settlement request, review, approval/rejection, and payout tracking. Reserve
  eligible funds when a request is accepted; prevent overlapping requests from
  consuming the same funds. Release reservations on rejection or confirmed failure.
- Record an external payout reference or an explicitly simulated payout result.
  A settlement status change alone must not fabricate a completed payout.
- Add `settlements` and related reservation/event records; expose
  `/merchants/{id}/transactions`, `/analytics`, and `/settlements`.

**Gate:** one merchant cannot access another's records; requested payouts cannot
exceed available funds; repeated approvals or callbacks cannot pay twice; sales
and settlement totals reconcile by currency.

## Phase 6 - Complete customer banking workflows

- Add `beneficiaries` with customer ownership, account/merchant validation,
  duplicate rules, and create/list/update/delete APIs.
- Replace the empty scheduled-transfer class with persisted `scheduled_transfers`
  and occurrence records. Support create, list, edit, cancel, next execution time,
  and a documented recurrence/time-zone policy.
- Implement a scheduler with atomic claiming and a unique occurrence key. Route
  execution through financial posting and fraud checks. Recheck ownership, funds,
  and account status at execution; record skipped, failed, pending-review, and
  successful outcomes. Define bounded retries and restart recovery.
- Generate account statements with opening balance, chronological entries,
  closing balance, period, and currency. Add CSV export and PDF output using the
  same server-side statement data. Establish auditable opening-balance checkpoints
  for existing/demo accounts whose original funds have no transaction history;
  do not fabricate historical customer transactions. Use bounded or streamed exports.
- Generate authenticated receipts from verified transaction/payment records,
  including reference, date, parties with appropriate masking, amount, currency,
  fees, and final status.
- Add `/beneficiaries`, `/scheduled-transfers`,
  `/accounts/{number}/statements`, and transaction/payment receipt routes.

**Gate:** each scheduled occurrence posts at most once even across application
restarts or multiple workers. Failure does not partially debit accounts. Statement
opening balance plus movements equals closing balance, and documents remain
accessible only to authorized owners or staff.

## Phase 7 - Categorization, analytics, and grounded AI

- Add `transaction_categories` and transaction-category assignments. Supply
  initial categories and deterministic merchant/description rules, with an
  uncategorized fallback and customer correction support.
- Calculate spending on the server from successful outgoing transactions for the
  requested account/period. Define treatment of transfers between the customer's
  own accounts, fees, refunds, and external merchant payments. Never combine
  different currencies into a single unsupported total.
- Add `GET /analytics/spending` with bounded date ranges, category breakdowns,
  totals, and optional prior-period comparisons.
- Make financial chat retrieve only the authenticated customer's authorized
  analytics. Answer arithmetic through deterministic calculations; use AI to
  explain the computed results and identify the period/currency used.
- Replace client-supplied category totals as authoritative insight input.
  Invalidate or version cached insights when relevant transactions or categories
  change. Never cache an offline/error message as a successful financial insight.
- Add explicit AI configuration, bounded input/output, dependency timeouts,
  request limits, and redacted diagnostics. Supply a truthful unavailable response
  when the provider is disabled; never silently invent financial results.

**Gate:** “How much did I spend on food this month?” agrees with seeded database
transactions, honors time boundaries and currency, and cannot expose another
customer's records. Provider errors do not pollute the insight cache.

## Phase 8 - Remaining customer services

- Add `notifications` with owner, event reference, status, creation/read times,
  and paginated list/read APIs. Create notifications from committed business
  events using a database outbox, with deduplication and bounded delivery retries.
- Add biller and mobile-operator catalogs, validated customer references, and
  idempotent bill-payment/top-up workflows. Use explicit simulators until external
  integrations are selected. Define whether a charge is pending, successful, or
  eligible for an audited reversal after provider failure.
- Add ATM/branch records with coordinates, address, hours, and supported services;
  provide filtered and bounded nearby-search APIs and administrator maintenance.
- Add an exchange simulator with configured rates, quote time, expiry, source and
  destination currency, fees, and explicit rounding. Default to quote-only; do not
  change actual balances. Any later simulated conversion execution must use the
  shared posting path and remain clearly labelled as simulation.
- Add the supporting bill/top-up order, location, rate, and outbox migrations.

**Gate:** notifications remain owner-scoped; a committed event is delivered without
duplicate notifications; failed/retried bill and top-up requests cannot duplicate
charges; location fixtures return predictable results; exchange quotes expire and
have reproducible calculations.

## Phase 9 - Disputes, monitoring, and release verification

- Add `disputes` and event/history records. Customers open disputes for their own
  eligible transactions; employees assign, investigate, request information, and
  resolve them. Apply explicit eligibility, time-window, and duplicate rules.
- Refunds/reversals use new linked financial postings; never edit the original
  successful transaction or manually rewrite balances. Add approval requirements
  appropriate to the project's staff roles.
- Add health/readiness and protected operational metrics for database, mail,
  payment reconciliation, scheduled jobs, fraud review, and delivery backlogs.
  Administrator monitoring must not expose secrets or raw customer data.
- Add validated local/test/deployment configuration, startup prerequisites,
  development service setup, and instructions for avoiding duplicate server starts.
- Add bounded cleanup/retention jobs for expired challenges, sessions, rate-limit
  counters, outbox records, and idempotency records. Preserve financial/audit data
  and keep deduplication records long enough for defined retry/replay windows.
- Verify database backup/restore, migration upgrades, provider outage recovery,
  application restart recovery, and representative concurrent/load scenarios.
- Document API contracts, role permissions, status transitions, simulation
  boundaries, demo journeys, and remaining external integration dependencies.

**Gate:** complete customer, merchant, employee, and administrator scenarios pass.
A fresh database and an upgraded V7 database both work. Backup restoration is
demonstrated. No unresolved high-priority financial-integrity or authorization
finding remains within the agreed demonstration scope.

## Shared implementation and verification rules

1. Start each phase by confirming API contracts, schema changes, role permissions,
   error/status behavior, and the phase's acceptance scenarios.
2. Review existing data before migrations; preserve applied migration files and
   allocate the next available version when implementation actually begins.
3. Keep financial arithmetic in `BigDecimal`, use explicit currency/precision
   rules, and store timezone-aware execution timestamps.
4. Use real isolated PostgreSQL for financial, locking, and migration tests.
   Use local SMTP and deterministic provider/risk/AI fixtures for failures and
   callbacks. External sandbox checks are separate, explicitly labelled evidence.
5. Extend the existing regression suite with meaningful tests for each phase;
   run it before accepting the milestone. Avoid starting a second backend on 8080
   during verification, and stop temporary servers when checks finish.
6. Do not mark a feature complete because its controller, table, simulator, or
   OpenAPI entry exists. Completion requires its permitted end-to-end workflow,
   failure paths, ownership checks, and financial reconciliation where applicable.

## Integration with the application plan

The existing [customer application plan](CUSTOMER_APP_DEVELOPMENT_PLAN.md) can
continue with authentication and read-only account integration. Transfer UI
integration depends on Phase 1 and the relevant Phase 3 risk contract; QR payment
integration depends on Phase 4; analytics and assistant integration depends on
Phase 7. Expose no biometric action in any application.

Merchant, employee, and administrator application plans should consume the
contracts delivered by Phases 2-5 and 9. Full application delivery requires
separate UI implementation and integration verification.

## Project tracking

Track each phase as an epic with schema, service, API, authorization, testing,
documentation, and application-handoff tasks. Status values are planned, in
progress, awaiting integration, verified, or blocked by an explicit dependency.

Use the acceptance gates to report progress rather than endpoint counts or an
unsupported completion percentage. Commit to calendar dates only after breaking
down the tasks and confirming team capacity and external-provider access.

Next implementation milestone: **Phase 2 - Password recovery, devices, and
administration**. Phase 1 delivery is recorded in the linked implementation notes.
