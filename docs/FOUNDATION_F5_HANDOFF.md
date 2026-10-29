# F5: final regression, migration checks, and handoff

Completed 20 October 2026 (UTC+07:00) for the local basic banking foundation.
F1–F5 are verified within the scope below. Biometric authentication is excluded;
advanced features and external payment networks remain outside this milestone.

## Delivered

- Added `FoundationHandoffTests`: a fresh PostgreSQL installation, real HTTP/SMTP
  customer journey, and two server-context restarts against the same database.
- Updated [local setup](FOUNDATION_LOCAL_SETUP.md), backend/customer READMEs, and
  [Swagger walkthrough](FOUNDATION_SWAGGER_WALKTHROUGH.md) for the completed
  foundation and current Gmail workflow. Removed stale live-Mailpit instructions
  from the primary setup path; historical evidence remains linked.
- Added the [complete demo checklist](FOUNDATION_DEMO_CHECKLIST.md), including
  the two-customer sequence, failure/recovery matrix, safe repeat instructions,
  current QA balance checkpoints, and acceptance evidence by milestone.

F5 changes test/documentation files only. No application behavior, migration,
credentials, QA identity, or financial record was changed for this handoff.
Existing uncommitted F1–F4 work remains preserved; no commit was created.

## Final verification

| Check | Result on 20 October 2026 |
| --- | --- |
| Backend `./mvnw.cmd clean verify` | **84 passed**, zero failures/errors/skips; packaged JAR rebuilt |
| Flutter `flutter analyze` | **No issues found** |
| Flutter `flutter test --reporter expanded` | **86 passed** |
| Fresh PostgreSQL / Flyway | Eight migrations V2–V9 applied, validated, no pending versions |
| Supported upgrade fixtures | V6 → V9, V7 → V9, V8 → V9 passed |
| Server-context restart journey | Money, histories, original idempotent result, sessions, rotation, and logout persisted |
| Rebuilt JAR on existing PostgreSQL 18 | Started successfully; validated eight migrations; V9 up to date, no migration applied |
| Packaged Swagger/OpenAPI | HTTP 200; OpenAPI 3.1.0; 14 foundation paths |
| Development-data checkpoint | Same approved balances/statuses; 24 users, 13 accounts, 10 transactions before/after |
| Existing ordinary Android APK | SHA-256 matches F4's normal-entrypoint/QA-secret inspection |

The runtime was JDK 24.0.2; compiler target remains Java 21 (class major version
65 verified). Flutter was 3.47.5 with Dart 3.13.4. Isolated Maven databases used
embedded PostgreSQL 14.22. The packaged live-local smoke used the installed
PostgreSQL 18 database. No live Gmail code, registration, funding, or new transfer
was requested during F5.

The initial new handoff test overcompared a database-loaded detail with the
original receipt: PostgreSQL normalizes decimal scale and persists microsecond
timestamps. Its assertion now checks identical identifiers/content, exact decimal
values, and timestamps within one microsecond. Idempotent replay still requires
the original complete receipt. The subsequent full clean build passed all 84
tests. The failed assertion attempt is retained separately from the final log.

## Fresh installation and restart coverage

The new test starts a separate temporary PostgreSQL instance and local SMTP
server; it never uses the development database or sends external mail. It starts
the real application on random ports with explicit isolated configuration.

1. Boot an empty database; Flyway installs V2–V9 and Hibernate validates it.
   Register two customers with real locally captured SIGNUP codes, verify empty
   accounts, and explicitly open zero-balance USD savings accounts.
2. Log in as seeded test staff with a LOGIN code. Confirm customer funding is
   forbidden, deposit USD 100.00 as staff, and log staff out. Transfer USD 25.00
   once and retain its original request/key as if the response were lost.
   Verify balances 75.00/25.00 and reject foreign source account/history reads.
3. Close the application context and its HTTP/database resources, then boot a new
   context against the same database. Validate Flyway again, rotate the sender's
   saved refresh token, and verify the same customer/session. Replay the original
   key/payload and require the original receipt with unchanged balances. Verify
   one matching transfer in each participant's history and owner-readable detail.
4. Log out both customers, close the second context, and boot a third. Both access
   and refresh tokens must remain rejected. A new JDBC connection confirms exactly
   one durable row for the transfer reference.

These are actual application-context restarts within a test JVM. Native Android
process termination/restoration is established separately by F3/F4 evidence;
the embedded PostgreSQL process itself stays running during this new test.

## Migration acceptance

| Starting state | Assertions |
| --- | --- |
| Empty database | V2 is the first migration; all eight reach V9, validate, and remain unchanged on app restart |
| V6 auth fixture | Existing users, devices, sessions and OTP records survive; normalized identity/current-session constraints enforced |
| V7 financial fixture | Balance, legacy transaction and audit remain; financial constraints added |
| Invalid V7 financial fixture | Preflight refuses negative legacy money; does not silently repair the balance or leave the new idempotency table |
| V8 fixture | Balance, transaction reference and saved idempotency result survive V9 |
| Invalid V8 NaN fixtures | V9 refuses NaN in balance/amount/fee, preserves invalid input for investigation, and rolls back its new constraints |
| Existing development V9 | Packaged startup validates checksum/history, applies nothing, preserves the measured data checkpoint |

Existing `PhaseZeroMigrationTests`, `PhaseOneMigrationTests`, and
`PhaseOneReviewMigrationTests` supply upgrade coverage. No migration was added or
edited. This does not establish migration from arbitrary manually edited schemas
or every historical intermediate version. Back up a real database before a future
upgrade; inspect invalid legacy data instead of bypassing Flyway validation.

## Customer acceptance and platform boundary

The completed two-customer journey is supported by complementary evidence:

- [F3 Gmail/Android acceptance](FOUNDATION_F3_IMPLEMENTATION.md): registration,
  zero-balance account opening, staff funding visibility, currency/status handling,
  ownership, native session rotation/restart, uncertain opening, and sign-out.
- [F4 Gmail/Android acceptance](FOUNDATION_F4_IMPLEMENTATION.md): review/confirmation,
  exact transfers, both history/detail directions, duplicate protection, rejection
  cases, committed-response loss, original-key recovery after native process
  restart, and persistent logout.
- F5 reruns final backend/Flutter regression and adds fresh-install/server-restart
  acceptance. The [demo checklist](FOUNDATION_DEMO_CHECKLIST.md) maps every required
  success/failure scenario to its evidence. Earlier native runs were not repeated
  or represented as new F5 inbox/device tests.

Acceptance remains local Spring Boot/PostgreSQL and the Android 14/API34 x64
emulator. The ordinary app uses native secure storage; browser sessions are
in-memory and browser/demo previews do not offer real transfer submission.
Physical-device, iOS/desktop, TalkBack, ARM/release build, deployment, store signing,
and external-money/payment-provider acceptance are not claimed. Release signing
still uses the Flutter template debug key. F1–F5 completion does not imply those
deployment requirements or deferred advanced features are complete.

## Artifacts and workstation handoff

Rebuilt backend: `backend/digital-banking/target/digital-banking-0.0.1-SNAPSHOT.jar`.
SHA-256: `1aa4d604d948007469b5c0ab8167110a8f16d9081bfb4fb1c8bcb0e78f08cf22`.

The ordinary F4 x64 debug APK remains at
`frontend/customer_app/build/app/outputs/flutter-apk/app-debug.apk`, 75,117,769
bytes, SHA-256:
`07bd8503bbe04df4473d24818557beaa6f86dd9c00c54cdc8990236b34afe0b0`.
F5 confirmed that hash matches F4's normal-entrypoint inspection, which excluded
the integration entrypoint/listener, QA password and bridge key. No native code
changed or integration APK was installed during F5.

Local evidence is retained under `D:\CodexQa\AiDigitalBankingF5`:

- `maven-clean-verify-final.log` — final 84-test clean verification and packaging.
- `maven-clean-verify.log` — passing 83-test baseline before the new test.
- `maven-handoff-assertion-attempt.log` — initial new-test assertion failure.
- `flutter-analyze.log`, `flutter-test.log` — final clean analysis/86-test suite.
- `packaged-startup.log`, `packaged-smoke.json` — rebuilt JAR, existing V9 startup,
  Swagger/OpenAPI response and JAR hash.
- `development-before.txt`, `development-after.txt` — identical read-only snapshots
  of migration versions, approved balances/statuses and user/account/transaction counts.
- `normal-apk.json` — ordinary APK path, byte count and hash.

The task-started packaged backend was stopped after the smoke check; port 8080 is
free. Test instances and command sessions exited. PostgreSQL and existing emulator
data were preserved. No OTP bridge or visible terminal window was started for F5.
The next normal run is documented in the setup guide. The foundation stopping
point is reached; begin deferred work only as a separately requested milestone.
