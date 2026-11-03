# Merchant M8 — payment alerts and owner transfers

4 November 2026, Asia/Phnom_Penh. Implements sections 4, 5 and 6 (G1, G2, G4, G5) of
[MERCHANT_REMAINING_WORK_PLAN.md](MERCHANT_REMAINING_WORK_PLAN.md) on top of
[M7](MERCHANT_M7_SALES.md). M9 (pilot APKs and device acceptance) is not part of this run.

## Status

Source and automated verification complete. Nothing is committed, no APK was built, the
development backend/database was neither restarted nor migrated, and no PIN was entered.
Work is uncommitted on branch `docs-built-with` (M7 was merged to `main` through PR #1, so the
plan's `merchant-m4-shop-registration` / `373f03a` start state no longer applies).

| Check | Result | Log |
| --- | --- | --- |
| Backend `./mvnw.cmd -o test` | **234/234** (220 + 14 `MerchantOwnerTransferTests`), zero failures/errors/skips | `backend/digital-banking/.local/m8-full-backend.log` |
| Merchant `flutter test test` | **106/106** (73 + 15 feed + 18 transfer) | `frontend/merchant_app/.local/m8-merchant-tests.log` |
| Customer `flutter test` | **273/273** (251 + 22 transfer) | `frontend/customer_app/.local/m8-customer-tests.log` |
| Merchant visual fixture | **232** PNGs, no overflow (220 + banner + 4 transfer screens, light/dark) | `frontend/merchant_app/.local/qa/m8/` |
| Customer transfer approval fixture | **24** PNGs (USD/KHR × 6 sizes/languages × light/dark), decline stays reachable | `frontend/customer_app/.local/qa/merchant-m8/` |
| `flutter analyze` (both apps), `git diff --check` | Clean | — |

## M8a — live payment feed and alerts (Merchant app only, no backend route)

- `PaymentFeedController` (`lib/features/feed/`) polls `GET /merchants/me/dashboard` every 10 s
  (30 s after 3 consecutive failures) **only** while the app is resumed, uncovered and the shop is
  READY. Pause/cover/sign-out stop it and drop any poll still in flight.
- The first successful load only records existing references, so history never alerts. Later new
  references show one in-app banner (`+25,000 ៛ from Sophea`, or `N new payments received`; tap opens
  Sales), refresh the shop, and play the system alert sound / medium haptic if enabled.
  Payments that arrive while the app was away alert when it resumes.
- A payment the Collect screen already confirmed is marked seen through
  `CollectController.onReceipt`, so it does not alert twice. Known limit: if a feed poll that already
  contains the payment lands before the Collect status poll (2 s), one duplicate banner is possible.
- More → **Payment alerts**: Sound and Vibration (device-local, stored in `MerchantPreferences`, default
  on) plus the honest note that alerts work only while the app is open and background notifications
  come later (M10).
- Review fix: a stop followed by a quick restart while a poll was in flight (the Android notification
  shade: inactive then resumed) used to leave the feed running with no timer. A stale poll now
  re-polls immediately when the feed is still running; `a quick stop and restart during a poll...`
  fails without the fix.

## M8b — owner transfers (business wallet → the same owner's personal wallet)

**Flow.** Merchant creates an intent → opens `kesorbank://merchant/transfer` → Customer shows the exact
intent and the owner approves with a fresh PIN → the **same database transaction** posts the transfer
and completes the intent → Customer opens `kesormerchant://transfer/callback` → Merchant polls the
authenticated status. The callback is only a nudge: it must carry this intent's ID and saved `state`,
and the final answer always comes from the server. Denial, cancel and expiry move no money.

**Backend (V21, additive).** `merchant_owner_transfers`: intent/destination/currency/amount, status
(`PENDING` `COMPLETED` `DENIED` `CANCELLED` `EXPIRED` `FAILED`), SHA-256 of key, request, intent and
handoff secret, callback `state`, expiry, `transaction_id UNIQUE`, and CHECKs tying `COMPLETED` to its
transaction and `FAILED` to its code. A partial unique index allows **one open intent per owner**;
lapsed rows are settled before a new one is created.

| Route | Session | Notes |
| --- | --- | --- |
| `POST /api/v1/merchants/me/owner-transfers` | Merchant | `Idempotency-Key`; body only `{sourceAccountNumber, amount}` (unknown fields → 400). The server picks the destination: the owner's earliest ACTIVE personal wallet in that currency (`409 OWNER_WALLET_REQUIRED` if none). Balance is checked up front (`409 INSUFFICIENT_FUNDS`) and again at approval. Returns `approvalUri` + `state` once; a same-key replay of a waiting intent returns the **same intent with a fresh handoff secret** (the old one stops working). |
| `GET .../owner-transfers/{id}` and `POST .../{id}/cancel` | Merchant | Lazy expiry; cancel after approval returns `COMPLETED`. |
| `GET /api/v1/merchant-transfers/{id}` | Customer | `X-Merchant-Handoff`; owner-only (others get 404). Shows shop name, masked wallets, exact amount, expiry. |
| `POST .../approve`, `POST .../deny` | Customer | Approve takes `{handoffToken, pin}`. |

`approve` order: owner lock → intent `FOR UPDATE` → handoff secret → valid unlocked Customer session
(`MerchantAuthService.customer`, now public) → replay if already `COMPLETED` → pending/not expired →
recomputed `intent_hash` (tamper check) → shop still ACTIVE → shared-budget PIN check
(`AppPinService.verifyForOwnerTransfer`; failed attempts commit through `noRollbackFor`, five wrong
digits lock Customer PIN gates) → `FinancialPostingService.postOwnerTransfer` → intent `COMPLETED`.
`postOwnerTransfer` is the **only** path allowed to debit a business wallet (the
`MERCHANT_WALLET_RESTRICTED` guard in `post` is unchanged). It locks both accounts in id order and
returns empty (no exception) when the balance is short, so the intent commits as `FAILED`
(`INSUFFICIENT_FUNDS`, HTTP 200, `status=FAILED`, callback `error=failed`) with no money moved.
Owner transfers are not in `merchant_collections`, so they never appear in sales or reports; they
show as `TRANSFER_OUT` in wallet activity and as an incoming transfer named after the shop (via the
existing `Account.merchantStoreName` formula) in the owner's history (`operation=OWNER_TRANSFER`).

**Links and config.** `MerchantAuthConfig` gained `transferApproval`/`transferCallback` (development
defaults `kesorbank://merchant/transfer` and `kesormerchant://transfer/callback`, same `checkLink`
rule; properties `app.merchant-auth.transfer-*-uri`, env `MERCHANT_TRANSFER_*_URI`). Blank outside
development disables **only** transfers (`503 MERCHANT_TRANSFER_UNAVAILABLE`); existing production
configs do not fail at startup. Release App Links still need your domain and release certificate.

**Native transport (debug-only, like M3).** Both `MerchantLinkBridge.kt` files keep sign-in links in
`take`/`open` untouched and add a separate slot: `takeTransfer`/`openTransfer` with their own exact
bases, the same peer package + debug-certificate check, and component-targeted launch. Debug manifests
gained the exact `kesorbank://merchant/transfer` (Customer) and `kesormerchant://transfer/callback`
(Merchant) filters. `kesor_auth_handoff` gained `transferApprovalBase`/`transferCallbackBase` and the
two native methods. **Kotlin was not compiled** (no Gradle build before M9).

**Customer app.** `MerchantTransferApproval` + `MerchantTransferApprovalScreen`
(`features/merchant/`) are a sibling of the sign-in coordinator, so sign-in code is unchanged. Its own
storage slot, resumes after process death/PIN lock, never replaces an active request and leaves a
transfer link untaken while a sign-in request is active (`blocked`). The screen shows the large exact
amount, shop, masked source/destination, expiry countdown, *Approve with PIN* and *Decline*; the PIN
clears on privacy cover/lifecycle and is never saved. Approval/denial responses are validated against
the exact registered callback for this intent. A lost approval response is resolved by reloading the
request (it reports `OWNER_TRANSFER_COMPLETED`); it is never re-approved. A `FAILED` outcome waits for
the owner to tap *Return to Kesor Merchant*; `COMPLETED`/`DENIED` return automatically.
Customer history already accepts the new posting: `operation` is optional text and the type stays
`TRANSFER` (a parse test covers `OWNER_TRANSFER`). `BankingApp` routing is tested for: pending transfer
shows its screen, a pending sign-in wins, a PIN-locked app goes straight to the PIN pad, and a
signed-out app shows the waiting banner.

**Merchant app.** Wallet detail → **Transfer to my wallet** (hidden/disabled for zero balance or a
restricted shop; reopens an open transfer) → `OwnerTransferPage` (amount form with the wallet balance as
ceiling, waiting state with countdown, *Continue in Kesor Bank*, *Cancel*, and
completed/denied/cancelled/expired/failed results). `OwnerTransferController` is per owner, saves
`{id, key, source, amount, state}` (never the handoff secret), resumes after restart, polls every 2 s,
reuses the key after an uncertain create, replays the create for a fresh link after a restart, and
refreshes the shop on completion.

## Decisions I made (with reason)

1. **No `idempotency_records` row for approval.** The intent row lock + `status='PENDING'` guard +
   `transaction_id UNIQUE` already make a second posting impossible (tested sequentially and
   concurrently); a second ledger of the same fact would add a place to drift.
2. **One open intent per owner** (partial unique index) so approval is never ambiguous.
3. **Failed funds is HTTP 200 `FAILED`, not an error**, so the failed state commits (an exception
   would roll the intent back to `PENDING`).
4. **Sibling Customer coordinator and separate native slot** instead of extending the sign-in
   coordinator, so sign-in behaviour and its tests are provably untouched.
5. **Approving an already `COMPLETED` intent returns its callback without a PIN**: it needs the
   handoff secret and an unlocked owner session, and moves nothing.
6. **Intent TTL** 300 s (`app.merchant.owner-transfer-ttl-seconds`, clamped 60–900 s).
7. **One existing test line changed:** `merchant_foundation_test.dart` now uses `scrollUntilVisible` to
   reach *Sign out* because the More tab gained the Payment alerts section; the assertion is unchanged.
8. **G1 riel sign:** `AmountText` draws `៛` in the Khmer face at 1.3× (the Khmer face alone still
   drew it small in the fixture) and `CurrencyBadge` uses 24 instead of 18. A subclass of `Text`, so
   `.data`/finders are unchanged. Customer has the same issue and was left alone, as the plan says.

## Known limits and not verified

- No Android native compilation, APK, device approval, return link, sound/vibration or persistence
  across a real process death; V19–V21 are not applied to the development database; no live transfer.
- A process death during an *uncertain create* loses the in-memory key; a retry is then refused with
  `OWNER_TRANSFER_IN_PROGRESS` until the first intent expires (≤ 5 minutes by default). No money can
  move without the owner's PIN approval.
- Customer riel rendering is unchanged (same small glyph as before).
- Gaps: **G2** the legacy `GET /merchants/me/accounts` is Customer-session legacy and was not
  changed (removal needs your decision); **G4** EMV tag 59 truncates long/Khmer shop names to 25
  bytes, which is acceptable because the scan shows the verified name; **G3** was done in M7.
