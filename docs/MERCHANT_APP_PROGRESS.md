# Kesor Merchant — progress and handoff

Updated: 3 November 2026 Asia/Phnom_Penh (M7 F1–F6 follow-up checkpoint).

## Current checkpoint

- User authorized implementation beginning at M0 and requested usage-aware reports.
- M0-M3 are COMPLETE for the adopted development scope. The user confirmed
  native approval/return and restore. M4 source and automated checks are complete;
  its live V19/APK/device acceptance is pending. M5+M6 source and automated checks
  are complete (V20; device acceptance pending). M7 source/automated checks are
  complete; M8-M9 not started; M10-M13 deferred.
- Branch: `merchant-m4-shop-registration`; use `git log -1` for the M7 commit ID.
  M7 and F1–F6 are included in this user-authorized commit, with Codex contributor
  and co-author credit. No push/merge. Uncommitted notes below are historical.
- Initial tree was clean except `.claude/`, preserved. Customer source is unchanged.
- Latest M7 usage: 36% remaining in five-hour window, 90% in weekly window.
  Check before milestones and during long work. If either available remaining
  percentage falls below 10%, immediately save a detailed checkpoint here and in
  `NEXT_SESSION_BRIEF.md`, copy the report to this chat's outputs, and notify user.
  Periodic checks are not continuous background monitoring; unavailable is not zero.

## Next work: follow MERCHANT_REMAINING_WORK_PLAN.md

M7 is complete in source/automated verification. The implementation plan for the
remaining M8 alerts/owner transfers, small gaps and M9 pilot APKs
is `MERCHANT_REMAINING_WORK_PLAN.md`. Implementing agents start there. APKs are
built only in M9 and only after the user approves.

## M7 F1–F6 follow-up complete — 3 November 2026

- Added the exact UTC-to-Phnom-Penh regression, human exact-rate formatting in
  receipt/share output, one EN/KM payment-count helper and a matching Sales title.
- Request history settles at most 50 total rows per call, prioritizes returned
  due rows and locks payment IDs ascending. Effective expiry filters keep due
  rows out of WAITING and preserve complete EXPIRED pagination. Bulk SQL test
  covers 160 requests and the cap. No isolation or posting changes.
- CONCURRENT_UPDATE has localized notices and refresh actions in Sales/Reports;
  known limit documented. Controller endpoints have Tag, Operation and concrete
  ApiResponse record types.
- Backend **220/220** (219 + 1), Merchant **73/73** (66 + 7), clean analysis;
  fixture **220 PNGs**, no overflow. Inspected receipt EN/light and KM/dark,
  Sales, Reports and Home. Exact logs: `MERCHANT_M7_SALES.md` follow-up section.
- Customer diff empty; its prior 251 tests were not rerun. No APK, dev runtime,
  DB/migration, private credential or commit action. All existing uncommitted M7
  work and `.claude/` preserved. M8/M9 unchanged. Usage 36%/90%, threshold not hit.

## Merchant M7 source complete — 3 November 2026

- Built: `MerchantSalesService`/`MerchantSalesController`; four GET routes under
  `/api/v1/merchants/me`: sales, sales/{reference}, reports/collections and
  payment-requests history. V20 snapshot/index reused; no new migration or ledger.
- Merchant: owner-scoped/generation-safe Sales controller and filters/paging,
  receipt navigation from Home/Sales/wallet/request, daily/monthly reports and
  request history. English/Khmer and existing Customer-style widgets. Native
  `kesor/merchant_share`, cache-only FileProvider, explicit QR/receipt PNG/text
  actions, gallery `Pictures/Kesor Merchant`, localized failure states.
- Final evidence: backend **219/219** (8 new M7, zero failures/errors/skips),
  Merchant **66/66** (13 new M7), Customer **251/251** unchanged; both analyses
  clean. Visual fixture **220 PNGs**, no overflow, seven inspected including
  Khmer/dark/2x text. `git diff --check` passes. Exact logs/decisions/render names
  and acceptance limits: `MERCHANT_M7_SALES.md`.
- Safety decisions: only confirmed QR collection snapshots, separate receiving
  currencies, Phnom Penh date bounds, validated keysets, repeatable-read list/
  report snapshots, masked share output. Loaded day groups say “shown”; summary
  totals cover the whole filter. Request expiry is settled before status filters;
  an old poll cannot replace a request reopened from history.
- Not done/verified: no development DB access, restart/migration, APK, Android
  native compilation or physical sharing/payment acceptance. V19/V20 remain
  unapplied to development by this task. M8/M9 and unrelated gaps were not started.
- Nothing committed. No credential/.env access or personal PIN entry. Initial
  `.claude/` preserved. Latest usage 54%/93% remaining; threshold not triggered.
- Next: review this uncommitted M7 change; M8 needs a subsequent assignment, and
  M9 still requires explicit runtime/APK approval per the remaining-work plan.

## Merchant M5 + M6 source complete - 3 November 2026

Dashboard, wallet details and QR collection (fixed-amount requests and the
reusable shop QR) are implemented with migration V20, plus the Customer scan/pay
side (verified shop name/logo, expiry/cancel/inactive checks, shop name on
receipts). Read `MERCHANT_M5_M6_COLLECTION.md`. Full backend **211/211**;
Merchant Flutter 53; Customer Flutter 251; 146 Merchant renders. **Pending:** V19+V20 not applied
to development, no APKs built/installed, no device payment. Business-wallet
debits are blocked until M8 owner transfers. Work is on branch
`merchant-m4-shop-registration` (M4 committed as `7b711d5`; M5/M6 uncommitted).

## Merchant M4 source complete - 3 November 2026

Shop registration, shop profile/logo and the two business wallets are implemented
(source + automated verification). Read `MERCHANT_M4_SHOP.md` for routes, V19,
app behaviour and evidence. Full backend **203/203**, Merchant Flutter **42/42**,
**106** Merchant renders, analysis clean. Customer App source is unchanged.
**Pending:** V19 is not applied to the development database (backend was stopped),
no APK was built/installed (no device connected) and no device acceptance exists.
Next: restart the backend (applies V19), build/install the Merchant APK, let the
user register a shop privately, then M5 dashboard. Work is uncommitted on `main`
(`a88b061`); earlier statements about `kesor-phase4-fixes`/`e1a9da2` are stale.
Usage tool unavailable in this session; unavailable is not zero.

## Merchant M3 complete - 31 October 2026

M3 development sign-in is complete. Both final APKs are installed on Samsung
`R9TXB0G1VKT`. The user privately approved Customer sign-in and confirmed:
**"Register Shop or my existing shop opens, including after reopening."**
This verifies the native approval/return path, expected routing and session
restore with the tablet's existing Don't keep activities setting.

Read `MERCHANT_M3_HANDOFF.md` for exact protocol/native behavior, artifacts,
hashes and acceptance limits. M0-M3 are complete for the adopted development
scope; M4-M9 are not started and M10-M13 remain deferred. M4 registration is next.

Customer full regression: **247 passed**; focused + visual: **14 passed**;
final visual fixture: **24** combinations and reachable lower controls.
Merchant final full run: **28 passed**, including **90** visual combinations,
failed-storage revocation and cancellation/logout versus new-sign-in overlap.
Analysis is clean in both apps. Prior M2 backend **191/191** log was confirmed;
M3 made no backend Java/migration source changes and claims no new full rerun.

Backend: **8080 / Java 2036**, launcher 10272. Controlled restart applied **V18
over V17** at 11:30 local; private environment preserved. Live OpenAPI has all 12
Merchant paths. Samsung reached the session endpoint over Wi-Fi (401/no-store).
Both APKs use `http://172.16.128.192:8080/api/v1`; installed hashes match
verified outputs. No private environment files are packaged.

New source: shared `frontend/packages/kesor_auth_handoff`, Merchant API gateway/
secure journal and retained Android engine; separate Customer approval bridge,
fresh-PIN page and Settings > Merchant sessions. Exact callback/state and peer
package/signer checks; explicit same-body 60-second exchange recovery; durable
cancellation, Merchant rotation/logout and owner revocation. Customer PINs/tokens
never cross the Merchant link. Registration/financial capabilities remain M4+.

Device Don't keep activities=1 and text scale=1.3 were preserved. The agent
entered no personal PIN/OTP. The user performed personal approval privately.
Source remains uncommitted on `kesor-phase4-fixes` / `e1a9da2`; prior Customer
work is preserved. Release HTTPS links still require a supplied domain/release
certificate. Other native edge cases have automated coverage; do not claim every
physical scenario was personally tested from this successful round trip.
Usage/quota tool unavailable in this session; unavailable is not zero.

Outputs: `C:\Users\User\Documents\Codex\2026-10-31\kesor-bank-is-a-digital-banking\outputs`.
Merchant: `KesorMerchant-M3-SignIn.apk` (SHA-256
`128df250e8b82c42429f34254cb9c3ad55265aed4323c60df3d4b533d617c8c8`).
Customer: `KesorBank-M3-Approval.apk` (SHA-256
`a3e2d16993680337f829944c4f8eccf8712555c152cfe58b87c1f780f8937c74`).

## Completed work and evidence

### M2 completed implementation checkpoint — 31 October 2026

- Read M0 contracts and current source; source migrations previously ended at V17.
- Added V18 (source/test databases only): CUSTOMER session backfill, purpose/client
  constraints, durable approval attempts and database-atomic request budgets.
- Added exact registered callbacks, S256 PKCE/state/private-secret binding,
  Customer PIN approval, status/denial/cancellation/exchange, 60-second encrypted
  response recovery, Merchant refresh/logout/identity and owner session revocation.
- Purpose and audience are checked against database metadata; Merchant requests
  use a restrictive route allowlist independent of the owner's Customer roles.
- Added distinct PIN verification sharing the persistent five-attempt budget;
  security PIN changes also invalidate approved, unexchanged Merchant attempts.
- Compilation and the initial 25 focused security/configuration/migration tests
  passed. Final full backend regression PASSED: **191 tests, 0 failures, 0 errors,
  0 skipped**, completed 31 October 2026 at 10:42 Asia/Phnom_Penh. It includes
  26 Merchant HTTP tests, three configuration/crypto tests, one V17-to-V18 upgrade
  test, actual server-restart recovery, and all 161 existing backend tests.
  The first full attempt exposed fixture cleanup ordering (40 setup errors);
  both resets now clear approval dependents before deleting test sessions.
  No foreign-key guard or assertion was weakened. Final logs:
  `backend/digital-banking/.local/merchant-m2-focused.log` and
  `backend/digital-banking/.local/merchant-m2-full-backend.log`.
- API/configuration/security integration details: `MERCHANT_M2_SECURITY.md`.
- Existing active backend on 8080 was observed as PID 16248. It has not been
  restarted and no development-database migration/data mutation was performed.
- No Flutter changes or APK rebuild for M2. Real Android approval remains M3.
- Production defaults disabled; enabling requires exact HTTPS links and a separate
  recovery-encryption key. Domain/certificate verification remains M3 work.
- Usage stayed above 10%; the low-usage threshold was not triggered. This report
  and the session brief nevertheless contain a detailed normal milestone handoff.

### M2 acceptance evidence and changed areas

- Invalid client/callback/PKCE/state/secret/code, missing authentication/handoff,
  transfer-proof substitution, duplicate approval, denial, cancellation and expiry
  fail without issuing an unauthorized session.
- PIN failures persist across requests and share the transfer verification budget;
  five wrong digits close Customer PIN gates. PIN change cancels pending approved
  codes and revokes existing Merchant sessions while preserving the current Customer.
- Same-key concurrent exchange returns the same token pair/session. Different
  exchange keys produce one success; encrypted response recovery survives a real
  server restart and expires after 60 seconds. Rotation/revocation blocks recovery.
- Approval-vs-cancel, exchange-vs-cancel, competing-owner approvals and
  refresh-vs-revoke races are covered. No successful cancellation/revocation leaves
  a usable derived session.
- Dual-role owners, forged signed audiences and legacy claim shapes cannot use a
  Merchant session for personal, payment, PIN/profile, administrative or legacy
  merchant APIs. Pre-V18 Customer tokens retain their existing Customer behavior.
- Shop status is owner-scoped; foreign shops are hidden, suspended shops restricted,
  and multiple legacy shops require recovery. No wallet data/financial access is
  exposed by the M2 identity endpoint.
- Refresh reuse revokes the affected Merchant session; wrong-purpose refresh does
  not consume the other app's credentials. Merchant logout does not log out Customer.
- Audit bodies omit secrets/PINs/full callback URLs; no-store headers, persistent
  rate budgets/Retry-After, bounded cleanup and the twelve-route OpenAPI group pass.
- V18 migration preserves active/revoked V17 Customer sessions and credential hashes.
  Older migration versions are unchanged. It scopes device uniqueness by client/
  purpose, preserving Customer uniqueness while allowing independent Merchant use.
- New Java: `module/auth/merchant/*`, `security/SessionPurposePolicy.java`,
  `config/MerchantAuthOpenApiConfig.java`; session/JWT/filter/PIN/security/audit
  integration changes; V18 migration. Tests: MerchantAuthTests,
  MerchantAuthConfigTests, MerchantSessionMigrationTests; restart/API expectations
  and isolated fixture cleanup adjusted in existing suites.
- `git diff --check` passes. Branch remains `kesor-phase4-fixes`, HEAD `e1a9da2`;
  no commit/push/merge. Existing Customer Home/Wallet/QR/scanner changes are preserved.

- Read project instructions, consolidated brief and Merchant implementation plan.
- Audited merchant registration/account creation, authentication/session filtering,
  Customer App PIN/native intent routing and QR resolution/financial posting.
- Backend baseline PASSED: 161 tests, 0 failures/errors/skips, isolated PostgreSQL
  and test SMTP. Log: `backend/digital-banking/.local/merchant-m0-backend-baseline.log`.
- Customer baseline PASSED: 230 tests; analysis found no issues. Logs:
  `frontend/customer_app/.local/merchant-m0-flutter-baseline.log` and
  `frontend/customer_app/.local/merchant-m0-analysis.log`.
- Live development backend remains on port 8080, PID 18612. Samsung
  `R9TXB0G1VKT` is connected with USB forwarding for 8080. No runtime restart,
  live financial write, database migration or device setting change performed.

## Findings requiring contracts

- Merchant registration starts PENDING and accepts owner/QR alias fields; the new
  flow must derive the owner and internal alias from server-controlled identity.
- Merchant wallet provisioning calls customer-style development funding.
- Roles alone do not isolate Merchant sessions from personal customer APIs.
- Current QR creation uses the owner's personal name; merchant QR configuration
  does not establish a registered internal merchant payment request.
- Merchant QR acceptance needs shop-status enforcement in addition to account status.
- Existing Android retained-engine and Telegram routing must remain intact.

## Verification and next steps

M0 exit evidence: green backend/Customer baselines; read-only live schema V17 and
legacy aggregate audit; development package/link/certificate inventory; feature
ownership, API/error contracts, session access matrix and additive migration design
in `MERCHANT_M0_CONTRACTS.md`. No data repair or live migration performed.

M1 complete: separate Android Flutter project `frontend/merchant_app` and shared
`frontend/packages/kesor_design_system` created. Shared tokens/theme were copied
exactly from Customer source; integration, regression, renders and APK checks pass.

### M1 implementation checkpoint

- Normal entrypoint, configuration validation and independent Android package/icon.
- Only Continue with Kesor Bank can initiate sign-in. The M1 gateway deliberately
  returns unavailable until M2/M3 are connected; no local/demo identity or money.
- Cancellation/late-result protection, onboarding/ready/restricted routing, expiry
  handling, distinct offline/unavailable/denied/missing-app states and privacy cover.
- Registration form structure with shop-initial preview; submission is unavailable
  until M4. Shop Home/Collect/Sales/More are reachable only through injected test
  identities, not the normal entrypoint. Missing balances show unavailable, not zero.
- EN/KM, system/light/dark, serialized Merchant-only secure display preferences,
  support-address copy and sign-out structure.
- Shared theme extracted without changing palette/type/theme behavior. Customer
  imports re-export the exact same shared classes; asset font family names remain.
- Merchant verification: 11 foundation tests plus one visual fixture PASSED; the
  fixture renders 78 combinations across screens/themes/languages/sizes/large text.
- Customer regression after extraction: 230 tests PASSED; analysis is clean in
  both apps. Merchant test log: `frontend/merchant_app/.local/merchant-m1-tests.log`.
  Customer log: `frontend/customer_app/.local/merchant-m1-customer-regression.log`.
- Normal-entrypoint API/dev APK builds PASSED for both apps. Logs:
  `frontend/merchant_app/.local/merchant-m1-build.log` and
  `frontend/customer_app/.local/merchant-m1-customer-build.log`.
- Font licenses/brand assets are packaged; APK inspection found no `.env` files.
- Merchant APK installed alongside Customer on Samsung R9TXB0G1VKT, preserving
  data. Native welcome screen was visually verified at the existing device text/
  weight settings. Device was dozing initially; waking it exposed the app. No PIN
  was entered, no bank authorization approved and no device settings were changed.
- Installed Merchant hash matches the output APK. Installed Customer hash remains
  the Scanner APK hash below; the Customer rebuild was not installed.
- Gradle daemon stopped; backend 8080/PID 18612 and USB forwarding remain available.

### Files and scope

- New app: `frontend/merchant_app/lib`, Android scaffolding, bundled fonts/licenses,
  `test/merchant_foundation_test.dart`, `tool/merchant_visual_qa.dart`.
- Shared package: `frontend/packages/kesor_design_system` (existing Kesor source).
- Customer integration: `lib/app/app_theme.dart`, design-system exports, pubspec/
  lock only in addition to preserved pre-existing scanner edits.
- M0 audit/contracts and this report, plan/brief links, project AGENTS reporting rule.
- No backend Java/configuration/migration or live financial records changed.

Known future dependency: verified release App Links require a user-controlled
domain and release certificate. The Telegram callback domain cannot be reused.
Use exact package-targeted development links for M3 until that is supplied; no
production association is claimed. M2 backend approval/session security is now
complete; next is M3 Customer approval and Android handoff. The current APK
intentionally cannot complete sign-in, register a shop, display real balances or
submit a payment. Those are future milestone work, not acceptance failures hidden
by fixture data.

## Deliverables

Output directory:
`C:\Users\User\Documents\Codex\2026-10-31\kesor-bank-is-a-digital-banking\outputs`.

- `KesorMerchant-M1-Foundation.apk`: 165,316,562 bytes.
  SHA-256: `e73f7749c3b32f65723b4a61d40d66892fc3adfac5d3a680b9f967c2c7a29f35`.
- `Kesor-Merchant-M1-Tablet.png`: actual installed welcome screen.
- `Kesor-Merchant-Welcome.png`, `Kesor-Merchant-Welcome-Khmer-Tablet.png`:
  Flutter-rendered welcome examples.
- `Kesor-Merchant-Home-Fixture.png`, `Kesor-Merchant-Registration-Fixture.png`:
  injected test identities only; not live shops/wallets.
- This report, M0 contracts and the updated implementation plan are copied there.
- Existing installed Customer Scanner APK hash:
  `134d3334707d52ae1f8755ba2da3cf9eea3f441fd7c6d1b78416aa800a85cca4`.

## Resume M3 — concrete steps

1. Read AGENTS, current brief, plan, this report, M0 contracts and
   `MERCHANT_M2_SECURITY.md`. Check usage
   before starting; all work remains uncommitted on `kesor-phase4-fixes`.
2. Confirm M2's final full-backend result above before continuing. Source now ends
   at V18; development has not been migrated by M2. Inspect the listener/current
   startup settings before a controlled M3 runtime restart. Keep the Wi-Fi origin
   `http://172.16.128.192:8080/api/v1` aligned in both development APKs. Preserve
   private `.env` flags and transfer-PIN enforcement; never print credentials.
3. Replace `UnavailableMerchantAuth` in `frontend/merchant_app/lib/features/auth/`
   with a real API/deep-link gateway. Persist a separate Merchant installation ID,
   immutable pending attempt (verifier/state/private secret/exchange key), and
   rotating Merchant token pair in the Merchant secure namespace. Display
   preferences are a separate concern; fixtures must not become live identities.
4. Start using the exact M2 request shapes. Open Customer package
   `com.bank.customer_app` at `kesorbank://merchant/approve`; verify the installed
   signing certificate before handing off. Return only to
   `com.bank.merchant_app` at `kesormerchant://auth/callback`. Verify the reverse
   package/certificate as well. Production verified HTTPS links remain a separate
   dependency on a user-controlled domain and release certificate.
5. Extend Customer retained-engine/native routing (`KesorApplication.kt`,
   `MainActivity.kt`) separately from Telegram and image picking. Do not silently
   replace an active approval. Resume existing sign-in/onboarding/PIN gates if
   needed, then show server-owned request details with Approve/Cancel. Approve
   sends fresh PIN digits to M2; never pass Customer tokens/PINs to Merchant.
6. Merchant validates exact callback, pending attempt, unique parameters and state;
   exchange with the same immutable credentials. Explicit response-loss recovery
   is allowed only during the 60-second server window, never a new-key automatic
   resend. Cancellation must reach the private-secret cancel route and suppress
   late results. Read `GET /merchant-auth/session` for M2 onboarding state; full
   `/merchants/me` profile/registration and business wallet integrity are M4.
7. Wire Merchant refresh/logout/restore and Customer inspect/revoke UI using the
   new twelve routes. Merchant Bearer tokens must not use `/auth/refresh`, personal
   `/auth/me`, or legacy merchant APIs. Route policy is intentionally restrictive;
   extend it only when adding owner-scoped future milestone capabilities.
8. Verify backend/app contracts, callback forgery/replay, expiry, missing Customer
   app, offline/cancel, uncertain exchange, app death and activity recreation.
   Run heavy checks sequentially. Rebuild both apps for physical round-trip
   acceptance; leave tablet accessibility/developer settings unchanged and let
   the user privately enter PIN/OTP. No shop creation or payment is needed for M3.

Useful commands (run from the named directory, one heavy operation at a time):

```powershell
# backend/digital-banking: isolated embedded PostgreSQL/test SMTP
$env:MAVEN_OPTS = '-Xmx512m'
.\mvnw.cmd '-DargLine=-Xmx768m' test

# frontend/customer_app
flutter pub get
flutter analyze --no-pub
flutter test --concurrency=1 --no-pub

# frontend/merchant_app
flutter pub get
flutter analyze --no-pub
flutter test test tool/merchant_visual_qa.dart --concurrency=1 --no-pub
flutter build apk --debug --no-pub --dart-define=APP_ENV=dev --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
```

## Remaining risks and acceptance limits

- M2 backend approval/session code and guards are complete; 191 backend tests pass.
  M3 native handoff, M4 registration/logo API, M5 live
  merchant financial reads and M6 payment collection are not implemented.
- Existing backend merchant registration/funding/QR gaps remain as audited above.
- Native welcome appearance was observed; personal customer approval/PIN, real
  shop onboarding and end-to-end collection are untested until those exist.
- Release signing/domain associations and external Bakong settlement are separate
  dependencies. M1 debug signing is not production configuration.
- No commits/pushes/PRs, production deployment, backend runtime replacement, live
  database migrations, live financial writes or personal-wallet repairs were
  performed. V18 was applied only to isolated automated-test databases.

## Later Customer Wi-Fi task — 31 October 2026

User steered work to Customer Wi-Fi connectivity. Merchant milestone status is
unchanged. A normal Customer API/dev debug APK now targets
`http://172.16.128.192:8080/api/v1`; five configuration checks/build/signature and
compiled-URL verification passed. Output: `KesorBank-WiFi-Test.apk`, SHA-256
`badef91fb842cfb2d7a1dfde8b215e353f37dd3706a5ef1c6858ca79ca4cb087`.
It was delivered but not installed during that task. A TECNO phone at
`172.16.128.213` reached the backend through wlan0 and received expected 401,
without USB forwarding. Existing Public Java firewall rules already permitted
access, so firewall/network profile stayed unchanged and no elevation was needed.
Details: `frontend/customer_app/docs/WIFI_DEVELOPMENT.md`. Gradle stopped after
packaging; backend 18612/8080 left running. This is not M2/M3 Merchant sign-in work.
