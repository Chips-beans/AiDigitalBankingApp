# Merchant M2 — backend approval and session security

31 October 2026, Asia/Phnom_Penh. Implementation details for M3 app integration.
Milestone verification and runtime activation are recorded in
[MERCHANT_APP_PROGRESS.md](MERCHANT_APP_PROGRESS.md).

## API contract

All paths below start with `/api/v1`. Responses use the existing `ApiResponse`
envelope (`data`) and `ApiErrorResponse` (`error`). Sign-in/session responses and
errors use `Cache-Control: no-store`. OpenAPI group: `/v3/api-docs/merchant-auth`.

| Method and path | Credential and behavior |
| --- | --- |
| POST `/merchant-auth/attempts` | Public registered-client start; returns attemptId, expiresAt, approvalUri, customerPackage |
| GET `/merchant-auth/attempts/{id}` | Unlocked Customer access token plus `X-Merchant-Handoff`; minimal server-owned client name, device name, status/expiry/package |
| POST `/merchant-auth/attempts/{id}/approve` | Unlocked Customer access token; body handoffToken + fresh four-digit pin; returns exact registered callbackUri and merchantPackage |
| POST `/merchant-auth/attempts/{id}/deny` | Unlocked Customer access token; body handoffToken; callback has error=access_denied and original state, no code |
| POST `/merchant-auth/attempts/{id}/status` | Body attemptSecret; only attemptId/status/expiresAt, never code/owner/tokens |
| POST `/merchant-auth/attempts/{id}/cancel` | Body attemptSecret; cancels pending/approved/consumed attempt and revokes any derived session atomically |
| POST `/merchant-auth/exchange` | Approval code, S256 verifier, private attempt secret, stable exchange key, state, registered client/callback; creates one Merchant session |
| POST `/merchant-auth/refresh` | Body refreshToken; Merchant tokens only; rotation and reuse detection |
| GET `/merchant-auth/session` | Merchant access token; sessionId, ownerId, clientId, onboardingState and minimal owned shop status |
| POST `/merchant-auth/logout` | Merchant access token; revokes that Merchant session and clears response-recovery receipt |
| GET `/auth/merchant-sessions` | Unlocked Customer access token; up to 100 newest active owned Merchant sessions, display metadata only |
| POST `/auth/merchant-sessions/{id}/revoke` | Unlocked Customer access token; own Merchant session only; clears recovery receipt |

Start request fields:

```json
{
  "clientId": "kesor-merchant-android",
  "redirectUri": "kesormerchant://auth/callback",
  "state": "BASE64URL_RANDOM_32_BYTES",
  "codeChallenge": "BASE64URL_SHA256_OF_VERIFIER",
  "codeChallengeMethod": "S256",
  "attemptSecretHash": "LOWERCASE_HEX_SHA256_OF_PRIVATE_SECRET",
  "installationId": "PERSISTED_RANDOM_INSTALLATION_ID",
  "deviceName": "Android phone"
}
```

Placeholders above describe the fields; they are not valid credentials. Generate
32 random bytes per verifier/state/attempt secret/exchange key, then base64url
without padding. Verifier permits RFC 7636's 43–128 unreserved characters; state,
private secret and exchange key permit 43–128 base64url characters. Installation
ID permits 22–128 base64url characters and is hashed before persistence. Device
name is 1–100 characters without control characters; display it as untrusted text.
Client name and package come from server registration.

Exchange body adds `attemptId`, `code`, `codeVerifier`, `attemptSecret`,
`exchangeKey`, `state`, `clientId`, `redirectUri`. Reuse the exact same immutable
body only for explicit response-loss recovery. A changed exchange key cannot
create another session. Start, status and exchange must not attach an unrelated
Customer Bearer token; possession credentials authorize those routes directly.

Development approval link is `kesorbank://merchant/approve` with attemptId and
handoffToken. Successful callback is `kesormerchant://auth/callback` with only
code and state. Never put PINs, access/refresh tokens, verifier, attempt secret or
exchange key in links. Treat the handoff/code URLs as private; omit full URLs
from Android, proxy and analytics logs. M3 must validate the exact URI, duplicate
parameters, pending attempt/state and installed target package/certificate.

## State, expiry and response loss

Attempts last 120 seconds: PENDING → APPROVED → CONSUMED, with DENIED, CANCELLED
and EXPIRED terminal. Codes are random 256-bit values, stored only as SHA-256,
and cannot outlive the attempt. Details/approval require the independent 256-bit
handoff token; the UUID alone grants no approval access.

Attempt mutations acquire an attempt-specific PostgreSQL transaction advisory
lock before owner/attempt/session row locks. Owner identity is locked and reloaded;
approval, exchange, cancellation, PIN security changes and revocation recheck
session eligibility inside their transactions. Cancel racing approval/exchange
either prevents creation or revokes the resulting session before succeeding.

The first exchange stores a 60-second AES-256-GCM encrypted token response, bound
to its attempt ID as authenticated data. Same-key recovery returns the same token
pair/session, including after server restart with the same encryption key. Only
the encrypted receipt contains recoverable refresh material; session refresh
credentials remain SHA-256 hashes. Refresh rotation, logout, owner revocation or
PIN security changes invalidate recovery. Expired/wrong-key/tampered receipts do
not create a replacement session. Merchant expiry timestamps are canonical UTC
so an initial response and deserialized recovery have identical JSON values.

A scheduled, bounded sweep runs every minute: erase expired recovery ciphertext,
mark overdue pending/approved attempts expired, delete attempts and rate buckets
older than one day. Each phase touches at most 200 rows per sweep and skips rows
locked by active requests. Receipt expiry is enforced during exchange even before
cleanup. The app should erase its attempt secrets once a session is safely saved.

## Session and PIN boundaries

V18 backfills existing sessions with purpose CUSTOMER/client kesor-customer and
scopes the current-device unique index by purpose/client. Customer replacement
revokes only Customer sessions; Merchant replacement revokes only that registered
Merchant client's session for the same Merchant device. Merchant fingerprints are
namespaced and derived from the hashed installation ID. Neither app's normal
sign-out signs out the other. Existing user-wide revocation and PIN reset/change
continue to revoke Merchant sessions as well.

New JWTs have explicit audience/purpose/client claims. Merchant audience is
kesor-merchant, purpose MERCHANT and client_id kesor-merchant-android; access life
is capped at five minutes. The configured refresh lifetime remains an absolute
database expiry; rotation does not extend it. Customer audience is kesor-customer.
Pre-V18 tokens with no audience/purpose/client claims are accepted only against
backfilled CUSTOMER rows and existing PIN generation rules. Merchant rows always
require exact Merchant claims; signed role claims cannot override the database.

Merchant authentication supplies only MERCHANT_SESSION authority. A separate route
policy denies personal wallets, history, payments, AI, profile/PIN, administration
and legacy merchant APIs even if the owner has both roles. At M2 only Merchant
session identity/logout are allowed through that policy; public refresh/exchange
have their own purpose/credential validation. M4–M8 must deliberately extend both
the route policy and owner-scoped service guards when adding capabilities.

The minimal session identity reports SHOP_REQUIRED, READY, RESTRICTED or
RECOVERY_REQUIRED for zero, one active, one inactive, or multiple legacy shops.
It exposes no wallets or financial capability. M4 adds registration/wallet-pair
integrity and full shop profile rules; M2 READY is only a shop-status signal.

Fresh PIN approval uses the shared persisted five-attempt counter and user lock,
without issuing or consuming a transfer proof. Rejections commit their counter;
the fifth mismatch locks Customer PIN gates. PIN changes/reset cancel approved,
unexchanged Merchant codes in addition to revoking existing sessions. A revoked,
disabled, incomplete or locked approving Customer cannot complete an exchange.
Merchant authentication rechecks enabled/profile/customer-role/device eligibility.

## Limits, audit and environment

Database-atomic fixed one-minute budgets apply: 120 operations/IP, 20 starts/IP,
10 starts/installation, 30 approval/detail actions/customer, 40 polls/attempt and
20 exchanges/attempt. Failed requests consume budgets. A 429 returns
MERCHANT_AUTH_RATE_LIMITED and Retry-After: 60. Use the actual remote address;
untrusted forwarded headers do not choose the budget. Tune these defaults for
production traffic before rollout.

Success and rejection audits store explicit action/actor/attempt or session ID,
never request bodies, private credentials, PINs or callback URLs. Required audit
failure fails the business mutation closed. Rate budgets intentionally commit in
their own transaction before business processing.

Local/dev/test enables the registered development links by default. Production,
mixed prod/dev profiles, and unknown profiles default to disabled. To enable in
production, configure exact HTTPS approval/callback paths and an independent
base64-encoded 32-byte encryption key. Do not reuse the JWT key. Properties:

| Spring property | Optional private environment equivalent |
| --- | --- |
| app.merchant-auth.enabled | MERCHANT_AUTH_ENABLED |
| app.merchant-auth.callback-uri | MERCHANT_AUTH_CALLBACK_URI |
| app.merchant-auth.approval-uri | MERCHANT_AUTH_APPROVAL_URI |
| app.merchant-auth.recovery-key | MERCHANT_AUTH_RECOVERY_KEY |

Development alone may derive a domain-separated recovery key from the JWT key;
production requires a separately generated secret. Keep it stable across replicas
and restarts. Key changes invalidate only pending recovery receipts, not signed
session access/refresh validation. No secrets are embedded in Flutter or docs.
HTTPS URI syntax checks do not establish domain ownership or verified App Links;
release association/certificate verification is M3 work.

## Verification and continuation

Focused tests: MerchantAuthTests, MerchantAuthConfigTests,
MerchantSessionMigrationTests. FoundationHandoffTests additionally exercises
response recovery after an actual server restart and existing customer regressions.
All use isolated PostgreSQL/synthetic credentials; never point tests at development.
Actual check results and limits are in the progress report.

M3 must wire both Flutter apps, retained Android engines/intent handling, exact
package/certificate checks, secure pending exchange storage, Customer approval UI
and Merchant session management. M2 does not replace the unavailable M1 gateway,
register a shop, create business wallets or certify external KHQR payments.

Protocol references: [S256 PKCE, RFC 7636](https://www.rfc-editor.org/rfc/rfc7636)
and [OAuth security practice, RFC 9700](https://www.rfc-editor.org/rfc/rfc9700).
