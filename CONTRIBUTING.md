# Contributing to Kesor Bank

Read [AGENTS.md](AGENTS.md), the
[progress guide](docs/PROJECT_PROGRESS_AND_AGENT_GUIDE.md), and the product
document for the component you change. Current behavior belongs in
[CUSTOMER_APP.md](docs/CUSTOMER_APP.md) or
[MERCHANT_APP.md](docs/MERCHANT_APP.md); deployment procedures belong in
[DEPLOYMENT.md](docs/DEPLOYMENT.md).

## Setup

- Backend: Java 21 or a compatible newer JDK; use the checked-in Maven wrapper.
  PostgreSQL and mail settings are needed to run the app. Copy
  `backend/digital-banking/.env.example` only if `.env` does not already exist.
- Flutter: use an SDK satisfying Dart `^3.13.4` in both app manifests; the recorded
  workstation baseline is Flutter 3.47.x. Run `flutter --version` rather than
  relying on the SDK folder name. Android development also requires the Android SDK.
- Showcase: Node.js and npm; Node 24/npm 11 are the locally verified toolchain.
  Use `npm --prefix showcase ci` to install from the lockfile.

Keep the full checkout: both apps depend on the sibling packages under
`frontend/packages/`. Reuse healthy local services and preserve existing edits.
There is no repository-wide dependency install or build command.

## Check a change

Run the relevant checks **sequentially** on this workstation (about 8 GB RAM).
These commands are run from the indicated component directory:

| Component | Checks |
| --- | --- |
| `backend/digital-banking` | `./mvnw.cmd test` on Windows; `./mvnw test` on Unix |
| `frontend/customer_app` | `flutter pub get`, then `flutter analyze` and `flutter test test --concurrency=1` |
| `frontend/merchant_app` | `flutter pub get`, then `flutter analyze` and `flutter test test --concurrency=1` |
| Shared Flutter packages | Analyze and test both consuming apps |
| `showcase` | `npm run build:website`; preview with `npm run preview:website` |
| Documentation / metadata | Verify local links and commands, then `git diff --check` |

Maven `-o` uses cached dependencies only. Omit it on a fresh checkout. Backend
tests use embedded PostgreSQL and local SMTP, with separate loopback Gmail/AI
provider fixtures. Both the shared fixture and the separate restart-test launcher
pin `app.mail.provider=smtp` even when Gmail is selected by inherited configuration;
`MailProviderIsolationTests` checks that override and local delivery. Do not load
credentials into a test shell.

For Flutter presentation changes, use the relevant `tool/*visual_qa.dart`
fixture and inspect representative English/Khmer, light/dark, large-text and
phone/tablet output. Automated renders do not establish native device acceptance.
Historical Gmail-dependent live harnesses are described in the Customer README;
they are not part of routine local tests.

## Change and review conventions

Use a focused branch (`codex/` for Codex-created branches), a focused diff and the
pull request template. Keep unrelated local changes out of staging. Applied
Flyway migrations are immutable; add the next version and update the foundation
contract test when changing the schema.

Money uses exact decimal strings, USD scale 2 and KHR scale 0. Keep the currencies
separate and use Asia/Phnom_Penh business days. Preserve owner/session checks,
PIN gates and original-key recovery for uncertain money requests. UI copy is
English and Khmer. Format only changed files.

At milestone boundaries update progress guide §2 and §8 plus the relevant product
document. Preserve dated history; correct current summaries when newer evidence
supersedes it. Record commands, counts and anything still unverified.

Keep credentials in the ignored backend `.env`. Keep APKs, `.local/`, exported
screenshots, generated downloads and browser captures out of Git. Before staging,
review `git status --short`, `git diff --stat` and the actual diff; after staging,
review `git diff --cached --stat` and `git diff --cached --check`.

The project requires explicit user instructions before commit/push/merge and
before APK builds/installs, dev-backend restarts, dev-database migrations or live
deployment/configuration changes. Local source edits and ordinary isolated tests
can proceed within the assigned task. Use the deployment runbook for live work.
