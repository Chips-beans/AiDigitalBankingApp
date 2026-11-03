# Kesor Merchant

Android-first Flutter app, package `com.bank.merchant_app`. The Customer App remains
`com.bank.customer_app`; both install independently.

Current milestone: M1 app shell. The normal entrypoint uses a fail-closed auth
gateway until M2/M3 backend approval and Android links are implemented. It cannot
create a local merchant identity, register a shop or move money. Registration and
shop/tab renders use injected test fixtures only; these are not live acceptance.

The only sign-in action is **Continue with Kesor Bank**. Customer approval with
the existing PIN and same-owner onboarding are defined in
`../../docs/MERCHANT_APP.md`. Project progress and continuation steps are
in `../../docs/PROJECT_PROGRESS_AND_AGENT_GUIDE.md`.

Shared palette, type roles and Material theme come from
`../packages/kesor_design_system`; Customer's old imports re-export those same
classes. Bundled font files retain their original licenses and global family names.
Display settings use Merchant-specific secure-storage keys, separate from Customer.

Run from this directory, sequentially:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --concurrency=1 --no-pub
flutter test tool/merchant_visual_qa.dart --concurrency=1 --no-pub
flutter build apk --debug --no-pub --dart-define=APP_ENV=dev --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
```

Visual fixtures/logs are ignored under `.local/`. Production configuration requires
an explicit HTTPS API URL. No credentials, demo login, or fake money are included.
Only Android scaffolding is created; no native iOS acceptance is claimed.
