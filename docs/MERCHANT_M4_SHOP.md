# Merchant M4 — shop registration, profile and business wallets

3 November 2026, Asia/Phnom_Penh. Implements section 6 of
[MERCHANT_M0_CONTRACTS.md](MERCHANT_M0_CONTRACTS.md) and the M4 milestone of
[MERCHANT_APP_IMPLEMENTATION_PLAN.md](MERCHANT_APP_IMPLEMENTATION_PLAN.md).

## Status

- Source complete with automated verification. Full backend **203/203**, Merchant
  Flutter **42/42**, Merchant visual fixture **106 renders**, analysis clean.
- **Not yet done:** V19 is not applied to the development database (the backend was
  not running), no APK was built or installed (no device connected), and no
  device acceptance has been recorded. Restart the backend to apply V19, then build
  and install the Merchant APK for the user to register a real shop.

## Backend

Migration `V19__merchant_shop_registration.sql` (additive):

- Preflight halts with `V19 preflight` if any shop already has two MERCHANT wallets
  in one currency. Nothing is repaired automatically.
- `merchants`: `onboarding` (`LEGACY` default, `SELF_SERVICE`), `category_code`,
  `business_phone`, `address`, `description`, `profile_version`. Self-service rows
  must have category, phone and address.
- Partial unique `uq_merchants_self_service_owner(owner_user_id)` for self-service
  shops. Legacy multi-shop owners are untouched and surface as `RECOVERY_REQUIRED`.
- Partial unique `uq_accounts_merchant_currency(merchant_id, currency)` for
  MERCHANT accounts. Personal `(user_id, currency)` uniqueness is still not added.
- `merchant_logos` (owner-scoped STAGED/ATTACHED images, one attached per shop).
- `merchant_registration_requests` (owner + hashed key → request hash + shop).

Routes (Merchant session only; Customer sessions get `MERCHANT_SESSION_REQUIRED`):

| Route | Behaviour |
| --- | --- |
| `GET /api/v1/merchants/me` | `onboardingState`, owner `{id, displayName}` (first name only), shop, wallets KHR then USD |
| `POST /api/v1/merchants/me/registration` | `Idempotency-Key` (16–128 URL-safe chars) required. 201 created, 200 same-key replay, 409 `MERCHANT_REGISTRATION_CONFLICT` (same key, changed body), 409 `MERCHANT_ALREADY_REGISTERED` |
| `PATCH /api/v1/merchants/me/profile` | Partial edit with `version`; 409 `MERCHANT_PROFILE_CONFLICT` when stale; 403 `MERCHANT_INACTIVE` for SUSPENDED/INACTIVE; `stagedLogoId` or `removeLogo` |
| `POST /api/v1/merchants/me/logo-uploads` | Multipart part `logo`; JPG/PNG ≤5 MB and ≤16 MP; decoded, re-encoded ≤512 px, metadata stripped; returns staged `logoId` |
| `GET /api/v1/merchants/me/logo` | Attached logo bytes, `no-store`, `nosniff`; 404 when none |

The exact route set lives in `SessionPurposePolicy.SHOP_ROUTES`. The legacy
`GET /merchants/me/accounts` stays a Customer-session route until M5 reconciles it.

Registration body: `storeName` (1–150), `categoryCode` (allowlist below), `phone`,
`city` (1–100), `address` (1–255), optional `description` (≤500) and
`stagedLogoId`. **Any other field fails with 400**, including `ownerUserId`,
`merchantId`, `status`, `openingBalance`, `bakongAccountId`. Text is trimmed and
whitespace-collapsed; control characters are rejected.

Phone is normalized to E.164: `012 345 678` → `+85512345678`; `855…` and `00…`
prefixes are accepted; other countries need `+`. Cambodian numbers must have 8–9
national digits (`MERCHANT_PHONE_INVALID`).

Categories (code → MCC): FOOD_DRINK 5814, GROCERY 5411, RETAIL 5399, FASHION 5651,
BEAUTY 7230, ELECTRONICS 5732, HEALTH 5912, SERVICES 7299, EDUCATION 8299,
TRANSPORT 4121, OTHER 5999 (`MERCHANT_CATEGORY_INVALID`).

In one transaction under the owner row lock: journal check → existing-shop check →
staged-logo lock → shop insert (server `MCH-XXXXXXXX` code and `m.xxxxxxxx@kesor`
QR alias) → KHR then USD CHECKING MERCHANT wallets at zero → logo attach → journal
row → audit `SHOP_REGISTERED`. Merchant wallets **never** receive the customer
development opening credit (`AccountService.openMerchantWallets`). The owner is
not given `ROLE_MERCHANT`, so the Customer session gains no legacy merchant access.

Activation: `MerchantOnboardingPolicy` starts shops ACTIVE only for local/dev/test
profiles (`app.merchant.self-service-activation`, default by profile); elsewhere
PENDING. Setting it true outside development fails startup. ACTIVE → `READY`,
anything else → `RESTRICTED`.

Staged logos: at most five per owner (older ones deleted on upload); a scheduled
sweep removes staged logos older than one day. Logo upload and profile edits share
the persistent Merchant rate budgets (10 registrations, 10 uploads, 30 edits per
minute per owner). `ProfilePhotoService` now shares `ImageNormalizer`.

## Merchant app

- `features/shop/`: `merchant_shop.dart` (models, category list, gateway),
  `merchant_shop_api.dart` (HTTP), `shop_controller.dart`, `shop_form.dart`,
  `register_shop_page.dart`, `shop_home.dart`, `shop_profile_page.dart`,
  `shop_widgets.dart`. Strings/type helpers moved to `core/merchant_strings.dart`.
- `MerchantApiAuth.accessToken()` supplies the Merchant token to shop APIs,
  sharing the single-flight guard so rotations never race.
- Registration saves `{key, draft}` in the secure store (namespace `…|shop`, slot
  `registration-<ownerId>`) **before** sending. Offline/timeout/5xx/unparseable is
  uncertain: the form locks to the saved draft and offers *Check registration
  status* (same key, same body) or *Discard and edit*. Definitive rejections clear
  the intent. A loaded shop clears any stale intent. Intents never cross owners.
- After success the app revalidates the Merchant identity and opens Home.
- UI follows the Customer App: Poppins/Google Sans scale, 20 px gutters, 20 px
  bordered surface cards, navy gradient identity card, gold highlighted action
  tile, status chips, circle actions. Province picker (25 locations, EN/KM),
  category picker with icons, optional logo with initial fallback.
- Home shows shop identity, Merchant ID, status, both wallets with exact decimal
  balances and copyable account numbers. More has a shop profile row → editor.
- The privacy cover now overlays (Offstage) instead of replacing the screen, so a
  half-filled form and a picked logo survive the system file picker.
- `file_selector ^1.1.0` added (same as the Customer App) for the logo picker.

## Verification evidence

- `backend/digital-banking/.local/merchant-m4-full-backend.log`: 203 tests, 0
  failures/errors. New `MerchantShopTests` (11) and a V18→V19 upgrade/preflight
  test. `FoundationHandoffTests` now expects V19/18 applied. One M2 assertion moved
  from `/merchants/me` to `/merchants/me/accounts` because `/merchants/me` is now
  the contracted Merchant route.
- Covered: zero wallets with funding enabled, replay/conflict/second shop,
  concurrent different/same keys, second-wallet rollback including logo and
  journal, forbidden fields and invalid values, purpose isolation and revocation,
  logo normalization/ownership/foreign reuse, version conflicts, suspended edits,
  legacy multi-shop recovery, staged cap/sweep, activation policy.
- Merchant `flutter test` 42/42; `tool/merchant_visual_qa.dart` 106 renders under
  `frontend/merchant_app/.local/qa/m4` (EN/KM, light/dark, phone, 320 px, 2× text,
  landscape, tablet; registration, saved intent, home, review, restricted, profile).
