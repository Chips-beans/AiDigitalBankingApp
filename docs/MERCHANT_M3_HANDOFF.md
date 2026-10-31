# Kesor Merchant M3 — implementation and device handoff

Updated 31 October 2026, 11:59 Asia/Phnom_Penh.

**M3 COMPLETE for the adopted development scope.** Apps implemented, tested, packaged and installed; user-confirmed native round trip and session restore. M0-M3 complete; M4-M9 not started; M10-M13 deferred. Branch `kesor-phase4-fixes`, HEAD `e1a9da2`. No commit, push or merge.

## Implemented

- Normal Merchant entrypoint uses M2 HTTP APIs, an independent installation ID and an API/environment-scoped secure journal. Immutable PKCE verifier/state/private attempt secret/exchange key are saved before handoff; rotating Merchant credentials are saved atomically while pending secrets are erased. Display preferences remain separate.
- Exact callback URI, unique allowed parameters, pending attempt and constant-time state checks precede exchange. Tokens/PINs/private attempt credentials never enter links. Uncertain exchange requires explicit identical-body recovery within a conservative 60-second window.
- Cancellation persists a tombstone, reaches the private-secret cancel route and suppresses late results across app death. Server cancellation/revocation is still attempted if local storage writes fail. New sign-in waits for cancellation/logout and preceding authorization to settle.
- Restore, foreground validation, refresh and logout use Merchant routes only. Refresh is marked before send; an uncertain rotation cannot restore identity. Explicit continuation first revokes that uncertain session. Merchant sign-out leaves Customer signed in.
- Server onboarding state routes to registration, existing shop, restricted shop or support recovery. M4 registration and later financial capabilities remain unavailable; M3 creates no shop, wallet or payment.
- Customer preserves one bounded request through existing sign-in/onboarding/PIN gates and process recreation. It shows server-owned client/device details and the current owner identity. Explicit approval sends fresh PIN digits only to the authenticated approve route. PIN input clears on privacy/lifecycle changes and never persists.
- Settings > Merchant sessions lets Customer inspect/revoke owned Merchant sessions. Approval-response loss reloads status; MERCHANT_AUTH_USED cannot trigger reapproval. A durably saved callback can return after process recreation. If interruption loses the callback before durable save, start a fresh Merchant attempt.
- Both apps use retained engines, initial/new-intent routing and singleTask activities. Customer Merchant routing is separate from Telegram and image picking. Active approval is not overwritten by another request.
- Shared private package: `frontend/packages/kesor_auth_handoff`. Merchant gateway: `features/auth/merchant_api_auth.dart`; Customer approval/session screens: `features/merchant/`. M3 changes no backend Java/migration source.

## Android / release boundary

Development approval: `kesorbank://merchant/approve` → `com.bank.customer_app`.
Return: `kesormerchant://auth/callback` → `com.bank.merchant_app`.

Fixed-component outbound intents check the peer's current installed signing certificate in both directions. Development SHA-256:
`ae861749ac17ba744e16064146dc0320e27bdde8b5f61b55939c90baf1cbc2b4`.

Custom-scheme filters are debug-only; native development transport rejects non-debuggable builds. Production verified HTTPS links still require a supplied domain/release certificate. No release association is claimed; Telegram's domain is not reused.

## Verification

- M2 backend log re-read: **191 passed**, zero failures/errors/skips. This is prior M2 evidence, not a newly rerun full backend suite.
- Customer full regression: **247 passed**. Final focused + visual run: **14 passed**. Final separate visual run: **1 passed**, rendering **24** language/theme/size/large-text/landscape variants and scrolling to ensure Cancel is reachable. Analysis clean.
- Merchant final full run: **28 passed**: 14 protocol checks, 11 foundation checks, two new cancellation/logout overlap checks, and the visual fixture rendering **90** combinations. Analysis clean.
- Tests cover forged/duplicate/wrong-state callbacks, missing/untrusted peer, denial/expiry, explicit stable response recovery after process recreation, start/exchange/identity cancellation races, offline tombstones, failed storage, refresh/revocation, onboarding states, fresh PIN request shape, signed-out/PIN resume, saved callback return, private-input clearing and owned session revocation.
- Phone/light, large-text Khmer/dark, tablet session and Merchant recovery renders were visually inspected. Image-export fake-async and ambiguous-scrollable harness issues were corrected; final runs pass. No app assertion/server guard was weakened.
- Both normal-entrypoint API/dev APK builds passed. Compiled origins/gateways/routes/native classes, final overlap guard and pinned signers verified; ZIPs contain no `.env` files. Installed APK hashes match the verified outputs.
- Build commands request ARM64; debug artifacts also contain armv7/x86_64 native runtime libraries.

Logs are ignored under each app's `.local/merchant-m3-*.log`; APK inspection JSON is `.local/merchant-m3-apk-verification.json`. Customer full log: `merchant-m3-full.log`; final focused/visual: `merchant-m3-final-focused-visuals.log` and `merchant-m3-visuals.log`. Merchant full log includes the final 28 checks.

## Runtime and device

Controlled restart replaced Java 16248. Current backend: **8080 / Java 2036**, launcher **10272**, JVM max 512 MB. Flyway applied **V18 over V17** at 11:30:40; startup completed 11:31:12. Private backend environment flags/credentials preserved. Live OpenAPI has all **12** Merchant paths. Ignored logs: `backend/digital-banking/.local/merchant-m3-runtime{,.err}.log`.

Both APKs use **http://172.16.128.192:8080/api/v1**. Samsung `R9TXB0G1VKT` reached the new session endpoint over wlan0 (`172.16.128.148`), receiving expected unauthenticated 401/no-store. No firewall/network profile change. Both apps installed with `adb install -r`, preserving data. Customer was launched for private preparation. Don't keep activities=1 and font scale=1.3 remain unchanged.

The agent entered no personal PIN/OTP, submitted no personal approval and made no financial transaction.

First packaging received a Gradle stop command. Final builds passed with `GRADLE_OPTS=-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1`; no reusable daemon was requested. Automatic review rejected obsolete-cache removal; no cache was deleted. Incremental builds succeeded. A combined final-report shell command was also rejected; reports were saved with the file-editing tool instead.

## Deliverables

Directory: `C:\Users\User\Documents\Codex\2026-10-31\kesor-bank-is-a-digital-banking\outputs`.

| APK | Bytes | SHA-256 |
| --- | ---: | --- |
| KesorMerchant-M3-SignIn.apk | 165,316,417 | `128df250e8b82c42429f34254cb9c3ad55265aed4323c60df3d4b533d617c8c8` |
| KesorBank-M3-Approval.apk | 179,165,855 | `a3e2d16993680337f829944c4f8eccf8712555c152cfe58b87c1f780f8937c74` |

Synthetic examples: `Kesor-M3-Customer-Approval-Fixture.png`, `Kesor-M3-Customer-Sessions-Khmer-Fixture.png`. These are fixtures, not personal approval evidence. This report, progress, plan and current brief are copied alongside the APKs.

## Personal acceptance and next steps

The user performed the requested Samsung flow privately: Merchant → Continue with Kesor Bank → Customer approval → Merchant return, followed by closing/reopening Merchant. Their explicit result was: **"Register Shop or my existing shop opens, including after reopening."** This confirms native approval/return, expected routing and restore on the existing tablet settings. The agent did not enter or receive their PIN/OTP. No registration/payment was required.

M3's development acceptance is complete. Automated coverage is not proof that every physical new/returning/signed-out/cancellation/expiry/app-death scenario was personally tested. Release links remain a separate dependency. M4 shop registration/logo/profile and atomic zero-balance business wallet creation are next; no M4 implementation was started here.

## Usage and preservation

No Codex usage/quota tool is exposed. Checked before M3, during implementation and at handoff: remaining usage is **unavailable, not zero**. The last numeric snapshot is historical M2 usage (78% five-hour / 29% weekly), not current M3 usage. No below-10% reading was observed or invented.

All existing uncommitted Customer Home/Wallet/QR/scanner/favorites work is preserved. No reset/clean, credential export, production deployment, wallet repair, shop creation, payment, commit, push or merge.
