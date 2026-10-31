# Kesor Bank — implementation plan (next work)

Merchant App work is planned separately in
[MERCHANT_APP_IMPLEMENTATION_PLAN.md](MERCHANT_APP_IMPLEMENTATION_PLAN.md).
It defines Customer-App-only sign-in, shop identity, two business wallets and
milestones M0-M9 for the first release, with later features M10-M13.
The Merchant milestones have not been implemented.

Written 31 October 2026. Builds on `NEXT_SESSION_BRIEF.md`; that brief stays the
source of truth for current state. Nothing in this plan has been executed yet.

Ground rules for every phase: preserve all uncommitted/untracked work, never reset
or clean, keep `.env` private, run heavy tests/builds one at a time (~8 GB RAM),
never point tests at the live development database, install APKs with
`adb install -r`, and do not change the tablet's accessibility/developer settings.

Order: **Phase 1 → Phase 2 → Phase 3**, with the backlog after. Phase 2 can run
between Phase 1 steps because it only reads the running backend.

---

## Phase 1 — Make the full backend suite green (11 baseline cases)

**Status: done 31 October 2026.** Full suite 155/155. Causes A, C and D held. Cause B
was A plus C: the seeded `alice.demo` USD wallet (9000000001) was returned as the
"new" pair. The funding service already guarded once-per-account funding, so no new
marker was needed. The backend on 8080 has not been restarted with this code yet.
Remaining from this phase: step 1.4.3 (live check of a new signup) after a restart.

### What the evidence already shows

From `.local/settings-full-backend-tests.log` and the source:

- V16 (commit `60f8137`) made account creation automatic. `createDefaultUserWallets`
  in `AccountServiceImpl` is now called from:
  - `AuthPersistenceService.register` (line ~32)
  - `ContinuationPersistence.complete` (lines ~92 and ~98, including the
    already-complete branch)
- V14's design (`docs/QR_CUSTOMER_FLOW.md`) expected the customer to start with
  **no accounts** and open a USD/KHR pair explicitly through `AccountPairService.open`.

Grouping the 11 failures by probable cause:

| Cause | Tests | Observed |
|---|---|---|
| **A. Wallets already exist before paired opening** | `PhaseZeroIntegrationTests.signupUses…EmptyAccounts` | expected 0 accounts, got 2 |
| | `QrPaymentIntegrationTests.pairedOpeningIsZeroFundedByDefault` | expected 2, got 46 (the count includes other rows; needs a look) |
| | `PhaseOneFinancialTests.realAuthentication…EmitAudits` | expected 201, got 400 (`POST /accounts` hits `ACCOUNT_LIMIT_EXCEEDED`) |
| | `AccountPairQrTests.qrRejects…` (null account lookup), `customerJourney…` (`CURRENCY_MISMATCH`) | the pair response only lists *newly created* accounts, so the test picks the wrong currency or none at all |
| | `AccountPairQrTests.secondAccountFailureRollsBack…` | the rollback scenario can't happen because both accounts already exist |
| **B. Funding happens in the wrong place** | `AccountPairQrTests.fundedPairsReplay…`, `concurrentFixed…`, `concurrentSameKey…` | expected 200/210/220, got 1260–1280: the test likely resolves a seeded shared account, or funding has already been applied at signup |
| **C. Shared seed balance changed by other tests** | `PhaseZeroIntegrationTests.localFixturesAndOpenApi…` | expected 1250.00, got 1280.00 (+30 from an earlier test) |
| **D. Stale expectation** | `FoundationHandoffTests.nativeMigration…` | expected schema `"15"`, got `"16"` |

`FoundationReadinessTests` (path count 35 → 37) is already fixed in the working tree.

Behaviour bugs worth fixing whatever is decided below:

1. `AccountPairService.open` returns early when `existingWallets.size() >= 2`. When
   exactly one wallet exists, the response holds **only the new account**, so its
   shape depends on prior state. It should always return the customer's full
   USD + KHR wallet pair.
2. Test funding (`funding.creditNewAccount`) now runs inside signup and profile
   completion. Those flows have no opening idempotency key, so the "funded once per
   opening request" guarantee from V14 no longer covers them.
3. `ContinuationPersistence.complete` creates wallets even for an already-complete
   profile. That's a hidden side effect of a repeat call.

### Step 1.0 — Decision (made 31 October 2026: **Option 1, automatic wallets**)

Which account-opening model is intended now?

- **Option 1 (recommended): keep V16 automatic wallets.** Every customer gets USD
  and KHR wallets when signup/profile completes. Paired opening becomes an
  idempotent "ensure and return my pair" call. Tests and `QR_CUSTOMER_FLOW.md`
  change to match.
- **Option 2: go back to explicit opening.** Remove the automatic calls and keep
  V16's category/merchant columns and limits. The app's onboarding must call paired
  opening, which needs a Flutter check.

The steps below assume Option 1. Option 2 changes 1.2 and 1.3 only.

### Step 1.1 — Reproduce narrowly (no code changes)

From `backend/digital-banking`, one class at a time:

```powershell
.\mvnw.cmd -q "-Dtest=AccountPairQrTests" test
.\mvnw.cmd -q "-Dtest=QrPaymentIntegrationTests" test
.\mvnw.cmd -q "-Dtest=PhaseZeroIntegrationTests" test
.\mvnw.cmd -q "-Dtest=PhaseOneFinancialTests" test
.\mvnw.cmd -q "-Dtest=FoundationHandoffTests" test
```

For each failure, record which user/account the test resolves and when its
balance was credited. This confirms or rules out causes A–C before any edits. If a
cause doesn't hold, update the table above.

### Step 1.2 — Fix implementation (Option 1)

Files: `AccountPairService.java`, `AccountServiceImpl.java`,
`ContinuationPersistence.java`, `AuthPersistenceService.java`,
`TestOpeningFundingService.java`.

1. **One wallet-provisioning path.** `createDefaultUserWallets` and
   `AccountPairService.open` (WALLET branch) both call a single method that locks
   the user, creates any missing USD/KHR wallet and returns **both** wallets in
   USD-then-KHR order.
2. **Fund exactly once per account.** Test funding only applies when an account is
   actually created and the server flag is on, guarded by a durable marker per
   account so replays, concurrent requests and later paired-opening calls can't
   fund twice. The default stays zero funding.
3. **Idempotent paired opening.** Keep the `account_opening_requests` claim. A
   replay returns the stored response, and a different payload with the same key
   still gets `IDEMPOTENCY_CONFLICT`.
4. **Rollback.** If creating or funding the second wallet fails, the whole
   transaction (first wallet, its credit, the request claim) rolls back. Keep
   `secondAccountFailureRollsBack…` meaningful by injecting the failure at the
   shared provisioning method.
5. **No side effects on repeat calls.** `ContinuationPersistence.complete` on an
   already-complete profile only ensures wallets through the idempotent path, and
   writes no extra audit or funding.
6. **Audit actions.** Decide on one action name (`ACCOUNT_CREATED` vs
   `WALLET_ACCOUNT_CREATED`) and assert it in `PhaseOneFinancialTests`.
7. **QR account/currency selection.** Once the pair response is complete, check
   that the QR flow chooses the source account by currency. The `CURRENCY_MISMATCH`
   case must still be rejected when the currencies really differ.

### Step 1.3 — Fix tests honestly

- **Shared fixtures (cause C):** tests that move money create their own
  user/accounts, or snapshot balances and assert deltas. The seeded 1250.00
  fixture is read-only for the fixture test.
- **Signup expectation:** expects the two zero-balance wallets (Option 1), not
  "empty accounts". Rename the method to match.
- **`POST /accounts` audit test:** open a merchant account, or assert the
  `ACCOUNT_LIMIT_EXCEEDED` rejection audit. Keep checking that audits are emitted.
- **Migration test:** expect the latest schema version, and check that V10 profile
  data survives through V16.
- **No expected balance is replaced with an observed value.** Each changed number
  must follow from the rule "USD 200 / KHR 100,000 once, when enabled; otherwise 0".

### Step 1.4 — Verify

1. Rerun each class above, then the 27 focused auth/contract tests.
2. Run the full `.\mvnw.cmd test` once. Save the log to
   `.local/plan-phase1-full-backend.log`.
3. Check the running development backend without touching user data. A **new**
   test signup has exactly one USD and one KHR wallet. Existing users keep their
   accounts and balances.
4. Update `QR_CUSTOMER_FLOW.md`, `NEXT_SESSION_BRIEF.md` and the handoff.

**Done when:** the full suite is green, or each remaining failure is documented
with its cause; the funding rule is verified; and the docs are updated.

Restarting the backend: check the owner of port 8080 first and reuse
`.local/start-settings-backend.ps1` (it limits memory). Afterwards, restore
`adb reverse` so the device can keep testing.

---

## Phase 2 — Verify live Gemini (English + Khmer)

**Update ~02:00:** unblocked with the new key and `gemini-3.5-flash-lite`; the live
Khmer turns pass (see `docs/AI_ASSISTANT.md`). Still open: AI prose (the explanation
fell back once), an English-locale turn, a monthly summary and the refusal check.
Earlier status — **blocked on the provider.** Steps 1–2 done: configuration is
loaded and the key and model are valid, but `generateContent` never responds (see
`docs/AI_ASSISTANT.md`). Steps 3–5 are waiting for a working key or project.

Config: `app.ai.gemini.*` in `application.properties`, with values from `.env`
(the default model is `gemini-3.8-flash`). Read `docs/AI_ASSISTANT.md` first.

1. **Check the configuration without revealing it.** Confirm the backend sees
   enabled=true and has a non-empty key. Log or print presence only, never the
   value.
2. **Check the provider is reachable.** Make one minimal call through the backend's
   own client (or a temporary check) to confirm the model name exists and the key
   is accepted. A 404 or 403 here means the model name or the key's permissions
   need fixing.
3. **Live answers** from a test customer, through the assistant API:
   - English: "What is my USD balance?" and "Summarize this month."
   - Khmer: one balance question and one help question.

   For each answer, record whether it came from the provider or a fallback (from
   response metadata or logs), the latency, and whether the numbers match backend
   records.
4. **Safety checks.** A "send $10 to …" request must be refused or redirected (the
   assistant stays read-only). Then temporarily break the provider (wrong model
   via env override, never by editing `.env` content) and confirm the localized
   fallback and request recovery still work.
5. **Write up.** Record the results (no secrets) in `docs/AI_ASSISTANT.md` and the
   brief.

**Done when:** one successful provider answer in English and one in Khmer are
recorded, the fallback works, and the assistant shows no payment capability.

---

## Phase 3 — Device acceptance on SM-X216B (`R9TXB0G1VKT`)

**Status 31 October 2026:** preparation done (no reinstall needed). Item 7 (transfer
icons and flags) was **accepted** by the user, along with the Analytics screen
appearance. Items 1–6 and 8 are still to do.

Preparation (Claude):

1. Check the device with `adb devices`, the backend on 8080, and set up
   `adb reverse tcp:8080 tcp:8080`.
2. If Phase 1 changed anything the app depends on, run `flutter test
   --concurrency=1` and `flutter analyze`, build the dev/API debug APK, and
   install it with `adb install -r`. Record the size and SHA-256.

Checklist for you (PINs and authentication stay private):

| # | Check | Pass when |
|---|---|---|
| 1 | Turn on notification permission (Settings → Alerts) | Android permission granted; test alert appears |
| 2 | Activity alert | A real in-app event shows a local alert with no account values |
| 3 | PIN change | Old PIN works until change, then only the new one; other sessions are signed out |
| 4 | PIN recovery | Recovery flow completes; lock counter behaves as documented |
| 5 | Gallery photo | Preview shows straight away; photo stays after restart |
| 6 | Camera QR scan | Scanning another account's QR fills the review screen (cancel before submitting unless you choose a test transfer) |
| 7 | Transfer icons/flags | You accept the corrected entry/review/success visuals |
| 8 | New-account behaviour | A fresh test signup shows USD + KHR wallets as decided in Step 1.0 |

Claude records results and any defects in the brief. Each defect becomes its own
fix task.

---

## Phase 4 — User-reported app bugs and changes (31 October 2026)

User decisions: **cross-currency both ways at a fixed 1 USD = 4,000 KHR, rounding
KHR→USD credits down to whole cents**; **no PIN at launch, Home opens with balances
and transactions masked, the first feature tap asks for the PIN, re-ask after 3
minutes inactive, and always at transfer confirm**; **show receivers' full profile
name and photo**.

Survey findings that drive the order:

- The API has no way to resolve an account number to a person. Transfers, saved
  recipients and Home all show numbers because of that, not because of UI bugs alone.
- Saved recipients (`recipient_favorites.dart`) store only `{number, currency}`
  locally, so there is no name or photo to show.
- Home recent items (`home_gateway.dart`) use the posting **remark** first. That is
  why the opening credit shows "Test opening credit — non-production funds".
- **No profile photo exists on the server at all** (`customer_profile_photos` is
  empty and there are no photo audit events), so uploads are failing before they're
  stored. Home's header avatar also never uses the photo.
- The PIN is server-enforced (`/auth/pin/unlock` issues the access token). "Masked
  Home before PIN" therefore needs no data before unlock, which keeps that guarantee.

### 4.1 Backend (first; everything else depends on it)

**Status: done 31 October 2026, full backend suite 161/161** (`.local/p41-full-backend.log`).
Implemented contracts:

- **V17:** nullable `transactions.credit_amount/credit_currency/exchange_rate` (all NULL
  for same-currency rows), plus `transfer_pin_proofs`.
- **Conversion:** `ExchangeRates` (`app.fx.khr-per-usd`, default 4000). Request
  `currency` is always the **source** currency. USD→KHR is exact; KHR→USD rounds
  down to the cent, and a credit of 0 gives `AMOUNT_TOO_SMALL`. For a dynamic QR
  paid from the other currency, the debit is the exact equivalent; amounts that
  aren't exact give `CONVERSION_NOT_EXACT`. Staff deposits must match the currency.
  `GET /transactions/quote?sourceAccountNumber&destinationAccountNumber&amount`
  returns `{debitAmount, debitCurrency, creditAmount, creditCurrency, rate, converted}`.
- **PIN proof:** `POST /auth/pin/transfer-proof {pin}` returns `{proof, expiresInSeconds:120}`
  and shares the 5-attempt counter. `POST /transactions/transfer` and
  `/payments/qr/transfer` require an `X-Pin-Proof` header for a **new** key. The
  proof is one-use and bound to the session and user. A replay of a completed key
  needs no proof, and a failed transfer doesn't use up its proof. This is controlled
  by `app.transfer.pin-proof-required` (`TRANSFER_PIN_REQUIRED`), default **true**.
- **Transaction DTO additions:** `creditAmount`, `creditCurrency` (always filled),
  `exchangeRate`, `sourceName` (**"Kesor Bank"** when there is no source account),
  `destinationName`, `bankSource`, `operation`.
- **Lookup:** `GET /accounts/lookup?number=` returns `{accountNumber, currency,
  displayName, hasPhoto}` and `GET /accounts/lookup/photo?number=` returns
  `{contentType, imageBase64}`. Only active accounts resolve; 120 lookups per 15
  minutes per customer (`LOOKUP_RATE_LIMITED`); each lookup is audited
  `RECIPIENT_LOOKUP` with a masked number.
- Analytics income, the assistant's search and its amounts use the credited side for
  incoming converted transfers.
- **Test changes:** the new `TransferPinAndExchangeTests`; legacy suites set
  `pin-proof-required=false` via the base class; and some expectations were updated
  for V17, the 41 API paths, and KHR-pays-USD-QR now converting.

The dev backend runs 4.1 (dev DB at V17) with process-only `TRANSFER_PIN_REQUIRED=false`,
because the installed APK sends no PIN proof. Restart it without that variable after the
4.2 APK is installed.

1. **Recipient lookup:** `GET /accounts/lookup?number=` → `{accountNumber, currency,
   displayName, photoUrl|null, active}` for any ACTIVE wallet. Authenticated,
   rate-limited per customer and audited (anti-enumeration). Photo served by an
   authenticated `GET /customers/{accountNumber}/photo`-style route, or inline base64.
2. **Counterparty identity in history:** add `counterpartyName` and
   `counterpartyPhoto` (or a photo-available flag) to transaction DTOs. System
   postings (`TEST_OPENING_CREDIT`) report counterparty **"Kesor Bank"** with
   `systemCounterparty=true`.
3. **Cross-currency transfers** (manual and QR): when the source and destination
   currencies differ, convert at `4000` (configurable), USD→KHR ×4000 exact, KHR→USD
   ÷4000 rounded **down** to the cent. Reject when the credit would be 0. Store the
   rate, source amount and credited amount on the posting. Receipts and idempotent
   replays return both amounts. Add a quote endpoint or a quote in the review
   response so the app shows the exact credit before the PIN.
4. **Transfer PIN proof:** `POST /auth/pin/verify` returns a one-use, 2-minute
   proof bound to the session. Transfer and QR transfer endpoints require it. It
   uses the existing 5-attempt counter.
5. Tests for each: ownership, rounding edges (1, 39, 40, 4,001 KHR), idempotent
   replay of converted transfers, lookup of inactive or unknown accounts, proof reuse
   and expiry.

### 4.2 Flutter transfer flow (after 4.1)

**Status: done 31 October 2026, ~03:08.** `flutter analyze` is clean, and the full suite
had 224 passing plus 1 intentionally updated test (`saved recipients of any currency…`).
The new `test/transfer_pin_exchange_test.dart` passes 6/6. The APK
`KesorBank-Phase42-Test.apk` (SHA-256 `f8a93afd…c5e`) is installed with `adb install -r`.
The dev backend was restarted with the PIN proof **enforced** (Java PID 18612, launcher
24540). Key pieces:

- `transfer_support.dart`: `TransferSupportGateway` (lookup, photo, quote, transfer proof),
  a session-cached `RecipientDirectory`, and `exactDebitFor`, which mirrors the server's
  exact-conversion rule.
- `RecentPosting` now has `amount` from the viewing account's side, plus `debit`,
  `sourceName`, `destinationName`, `bankSource` and `operation`. Home de-duplicates by debit.
- `TransferController(support:)` fetches a quote after `prepare`. `confirm({pin})` and
  `retry({pin})` get a proof before claiming or resending. Wrong or missing PINs claim and
  send nothing. Proofs and PINs are never persisted. `AMOUNT_TOO_SMALL` and
  `CONVERSION_NOT_EXACT` are definite rejections.
- Transfer screen: prefill comes from Home recipients and QR scans (receiver locked for QR;
  amount locked for fixed QR, using the exact debit for the selected wallet). The live
  receiver card shows name and photo, the saved-recipient sheet shows names and photos for
  all currencies, there's a conversion hint, and a full-screen PIN keypad
  (`transfer_pin_prompt.dart`) appears at confirm and retry.
- `ScanQrPanel(onScanned:)` hands an unpaid verified scan to the transfer screen.
- **Device bug found and fixed at 03:11.** A manual transfer carrying the verified
  receiver name succeeded on the server (03:10:42), but the app showed "transfer safety
  record could not be read or saved". Version-1 records didn't persist `destinationName`,
  so `resolve` saw the stored record differ from the in-memory one. Fixed by persisting
  `destinationName` for every kind. `MemoryTransferStore` now round-trips through JSON like
  the device store, and there's a regression test. Flutter suite 226/226. The reinstalled
  `KesorBank-Phase42-Test.apk` has SHA-256 `1a0dcd39…b831`.
- Device acceptance by the user is pending.

1. **One transfer screen:** a successful QR scan opens the normal transfer screen
   with the receiver's wallet number, name and photo filled in (fixed-amount QR keeps
   its amount locked). The separate QR payment UI is removed from that path.
2. **Saved recipients:** a tap fills the wallet number. Rows show name and photo from
   the lookup. Stored favorites stay `{number, currency}`; the name is fetched live,
   not cached.
3. **Exchange:** allow USD↔KHR source/destination pairs and show "You send / They
   receive / Rate 1 USD = 4,000 KHR" on review.
4. **PIN at confirm:** the review screen asks for the PIN, gets the proof, then
   submits. The existing unresolved-payment journal is kept.

### 4.3 Flutter Home and profile

**Status: done 31 October 2026, ~03:35.** `flutter analyze` is clean and Flutter tests
pass 227/227. `KesorBank-Phase43-Test.apk` (SHA-256 `286b8a06…b07b`) is installed with
`adb install -r`. Device acceptance is pending.

- **Photo root cause:** the server never received an upload (there are no
  `PHOTO_UPDATED` or photo rejection audits). With "Don't keep activities", the
  `file_selector` result is delivered to a recreated Activity, while the plugin was
  listening on the destroyed one, so the picker never returned. The fix is the new
  `ImagePickerBridge.kt`, created by `KesorApplication` with channel
  `com.bank.customer_app/image_picker`. It holds the pending Dart result, and whichever
  `MainActivity` gets `onActivityResult` forwards it. It allows JPG or PNG up to 5 MB,
  copies the file to `cacheDir/picked-images`, and returns the path. Dart
  `core/platform/image_picker.dart#pickImageFile` uses it on Android and `openFile`
  elsewhere. The profile photo card and the QR image import both use it.
- **Home recent activity:** the name is the counterparty's profile name, "Kesor Bank"
  (with the logo) for bank postings, or "Between your accounts". Remarks and numbers
  are no longer titles. Avatars use `RecipientAvatar` (photo or initial). There's a new
  test in `home_api_test.dart`.
- The main card's 3rd button (which opens Transfer) is now labelled **Transfer / ផ្ទេរប្រាក់**.
- The Home header keeps the Figma layout (logo, inbox, My QR), with no profile slot. The
  photo appears in Settings and PIN screens once saved.
- **Second photo bug (device, ~03:36):** the picker now returned, but the card discarded
  the photo. Opening the gallery makes the app `inactive`, which raises the privacy
  cover (`banking_app.dart`), and the card cancelled a pick whenever the cover was up.
  "Profile saved" came from the name save (`PROFILE_UPDATED`), not the photo. Fixed:
  the cover no longer cancels a trusted selection, and the result is accepted while the
  cover is up (the >60 s lock still applies). The QR image import now waits up to 5 s for
  resume. There's a regression widget test. Flutter suite 228/228; the reinstalled APK
  has SHA-256 `816f0bab…337a`.

1. **Recent transactions:** photo (or initial) + name + amount + time. The opening
   credit shows the Kesor Bank logo and "Kesor Bank". No remark or wallet number in
   the title.
2. Rename the main card's third button **Payments → Transfer** (English and Khmer).
3. **Profile photo:** find and fix why uploads never persist (onboarding and
   Settings), then show the photo in the Home header, Settings and the QR card.

### 4.4 Receive QR screen redesign

**Status: done 31 October 2026, ~04:00.** Flutter tests pass 229/229 and analysis is
clean. `KesorBank-Phase44-Test.apk` (SHA-256 `4dacf0b9…2f63`) is installed with
`adb install -r`. Device acceptance is pending.

- `ReceiveQrPanel` was rewritten to the mockup and hosted full-screen by `ReceiveQrScreen`
  (dark sheet, "My QR" with a close button, subtitle). The card has a red "Kesor Bank QR
  Code" header, the holder's name, the QR, and either the amount with paid/waiting status
  or the grouped account number. The "Enter amount / Optional" row opens a sheet to create
  or remove a fixed amount. Wallet rows show the KHR (gold ៛) and USD (navy $) icons with
  grouped numbers; the selected one has a gold border. There are round Save and Share
  buttons.
- **Deliberate difference from the mockup:** the QR modules stay dark on a white tile
  (the mockup is white on dark). Inverted QR codes aren't reliably readable by scanners.
- **Save/Share:** there are no new pub packages. The new `ShareBridge.kt` (channel
  `com.bank.customer_app/share`) saves the rendered card PNG to MediaStore
  `Pictures/Kesor Bank` (Android 10+, no storage permission) or shares it with
  `ACTION_SEND` through a `FileProvider` (`${applicationId}.share`, only
  `cache/shared-images/`). The Dart wrapper is `core/platform/image_share.dart`.
- There's a new widget test (wallet rows, grouping, amount validation and request, close).

Match the provided mock: dark card with a red "Kesor Bank QR Code" header,
customer name, large QR, "Enter amount (Optional)", KHR/USD wallet selector rows
showing the account numbers, and **Save** (to gallery) and **Share** buttons. Save
and Share need new plugins (e.g. `share_plus`, a gallery saver) plus Android
permissions. These are new dependencies.

### 4.5 PIN gate rework

**Status: done 31 October 2026, ~04:20.** Flutter tests pass 229/229 and analysis is
clean. `KesorBank-Phase45-Test.apk` (SHA-256 `82a8ee22…093a`) is installed with
`adb install -r`. Device acceptance is pending.

- The server still requires the PIN before issuing any access token (unchanged).
  Launch or lock with an existing PIN shows `LockedHomePage`: the Home frame with
  `$••••`/`••••` and no accounts, recipients or transactions. Any feature, the bottom
  bar or the balance toggle opens the PIN pad. Back from the pad returns to the masked
  Home (no sign-out). Creating, confirming or recovering a PIN still goes straight to the
  pad.
- `SessionController.idleLimit = 3 min`. Any pointer-down anywhere counts as activity, a
  15 s timer runs `checkIdle()`, and an idle session locks. Backgrounding no longer locks
  immediately: `markBackground` keeps the first departure time and `markForeground` locks
  only if the app was away 3 minutes or more. The privacy cover still hides content
  while inactive, and a partly typed PIN is cleared when the app is backgrounded. The
  trusted image-selection exception is unchanged.
- Transfers still need the PIN at confirm (4.2). Telegram and retained-engine code are
  untouched.
- Tests rewritten for the decided behaviour: `app_pin_test` (2 minutes away keeps the
  session, 3 minutes idle locks, masked Home, then the pad on tap, partial PIN cleared)
  and `assistant_widget_test` (3 minutes away locks before a late answer shows, no
  resend). The rewrite caught a real bug: `hidden` fires again on return, which reset the
  departure time.

Launch → Home with masked balances and transactions, then the PIN on first
interaction. Unlock state is held in memory, and 3 minutes without interaction locks
again. Background/privacy cover rules are kept. Transfers always ask again (4.2.4).
The Telegram-return and retained-engine fixes are kept untouched.

### Order and verification

4.1 → 4.2 → 4.3 → 4.4 → 4.5, each with focused tests. Then the full backend suite,
`flutter analyze`, `flutter test --concurrency=1`, one APK build, `adb install -r`
and device acceptance by the user. Heavy builds run sequentially (8 GB RAM), so these
steps are not split into parallel sessions.

## Backlog (separate tasks, not scheduled)

1. **Recipient names for manual transfers** (now Phase 4.1.1, full name per the user). Add an authenticated, rate-limited
   `GET /accounts/lookup?number=` that returns a masked display name (for example
   "S. V***"), plus an anti-enumeration audit. Show it on the transfer review
   screen.
2. **Background push.** Add Firebase Cloud Messaging (FCM): device token
   registration, a backend sender and an opt-in toggle. Payloads keep no account
   values.
3. **Native iOS.** Build and accept on a real device. Needs a Mac/Xcode and
   Telegram iOS callback setup.
4. **KHQR/Bakong certification and real policies.** Both need outside parties;
   blocked until you provide access or documents.

## Open decisions for you

- Step 1.0: automatic wallets (Option 1, recommended) or explicit opening
  (Option 2).
- Whether the audit action for automatically created wallets should be
  `WALLET_ACCOUNT_CREATED` or `ACCOUNT_CREATED`.
