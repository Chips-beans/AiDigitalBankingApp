# Kesor Merchant

Android-first Flutter app, package `com.bank.merchant_app`. The Customer App remains
`com.bank.customer_app`; both install independently.

M0–M8 source and automated checks are complete: sign-in approval, shop registration,
KHR/USD business wallets, QR collection, sales, receipts, reports, foreground
payment alerts and PIN-approved transfers to the owner's personal wallet. M9
installation and integrated device acceptance remain open. Latest recorded APK:
`20261106-161530`; it includes the sign-in diagnostics/recovery fixes.

The only sign-in action is **Continue with Kesor Bank**. Customer approval with
the existing PIN and same-owner onboarding are defined in
[the Merchant product document](../../docs/MERCHANT_APP.md). Project progress and
continuation steps are in the [progress guide](../../docs/PROJECT_PROGRESS_AND_AGENT_GUIDE.md).
There is no separate Merchant password or local/demo identity. First-time owners
register a shop; returning owners open their existing shop. QR payments are
internal Kesor payments.

Shared palette, type roles and Material theme come from
`../packages/kesor_design_system`; Customer's old imports re-export those same
classes. Bundled font files retain their original licenses and global family names.
Display settings use Merchant-specific secure-storage keys, separate from Customer.

Use a Flutter SDK satisfying Dart `^3.13.4`. Run from this directory, sequentially:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test test --concurrency=1 --no-pub
flutter test tool/merchant_visual_qa.dart --concurrency=1 --no-pub
```

Visual fixtures/logs are ignored under `.local/`. Production configuration requires
an explicit HTTPS API URL. No credentials, demo login, or fake money are included.
Only Android scaffolding is created; no native iOS acceptance is claimed.

For an explicitly authorized device run, supply `APP_ENV=dev` and the desired
`API_BASE_URL`. Android emulator networking uses `10.0.2.2`; physical devices
need USB reverse forwarding or the backend computer's LAN address. See the
progress guide §4. APK builds and installs require separate authorization; the
[deployment runbook](../../docs/DEPLOYMENT.md) records Railway flags and checks.

## Structure

- `lib/app/`, `lib/core/`: composition, configuration, theme, localization and native sharing.
- `lib/features/`: authentication, shop, collection, feed, sales, owner transfers and settings.
- `test/`: isolated API/controller/widget tests.
- `tool/`: screen catalog, visual fixtures and Figma comparison tools.
- `android/`: native approval links and save/share integration.

The [contribution guide](../../CONTRIBUTING.md) covers review and verification.
