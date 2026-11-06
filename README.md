# Kesor Bank

A digital banking project with two Android-first Flutter apps and one Spring Boot
backend:

- **Kesor Bank** (`frontend/customer_app`): the customer app. Sign-in, PIN
  protection, USD and KHR wallets, transfers, QR payments, history, analytics and
  a read-only AI assistant.
- **Kesor Merchant** (`frontend/merchant_app`): the shop owner app. Sign-in by
  approval in Kesor Bank, shop registration, business wallets, QR collection,
  sales, receipts and reports.
- **Backend** (`backend/digital-banking`): Spring Boot, Spring Security, JPA,
  Flyway and PostgreSQL.

Shared Flutter packages live in `frontend/packages`.

This is a university case study using test money and internal Kesor QR payments.
Android is the acceptance target; KHQR/Bakong and production banking are outside
the current implementation.

## Repository map

| Path | Purpose | Start here |
| --- | --- | --- |
| `backend/digital-banking/` | Shared API, database migrations and integration tests | [Backend README](backend/digital-banking/README.md) |
| `frontend/customer_app/` | Customer Android app, tests and visual fixtures | [Customer README](frontend/customer_app/README.md) |
| `frontend/merchant_app/` | Merchant Android app, tests and visual fixtures | [Merchant README](frontend/merchant_app/README.md) |
| `frontend/packages/kesor_design_system/` | Shared Flutter theme, typography and branding | [Design system README](frontend/packages/kesor_design_system/README.md) |
| `frontend/packages/kesor_auth_handoff/` | Shared app-to-app approval transport | [Package source](frontend/packages/kesor_auth_handoff/lib/kesor_auth_handoff.dart) |
| `showcase/` | React/Vite product showcase and static hosting files | [Showcase README](showcase/README.md) |
| `docs/` | Current status, product contracts and deployment runbooks | Documentation below |

As recorded on **7 November 2026**, the handoff is available on the default branch,
`main`, after merging `railway-gmail-otp`. Merchant M0–M8 source
and automated checks are complete; M9 device acceptance remains open. The latest
recorded APK pair is `20261106-161530`. The handoff includes complete showcase
source/assets and the three tested backend review fixes. See the progress guide
for dated evidence and limits; deployment and M9 device acceptance remain separate.

## Documentation

Start with [AGENTS.md](AGENTS.md), then the project documents in `docs/`:

- [docs/PROJECT_PROGRESS_AND_AGENT_GUIDE.md](docs/PROJECT_PROGRESS_AND_AGENT_GUIDE.md):
  current progress, agent rules, setup, commands and open work.
- [docs/CUSTOMER_APP.md](docs/CUSTOMER_APP.md): the Customer App and banking backend.
- [docs/MERCHANT_APP.md](docs/MERCHANT_APP.md): the Merchant App contracts and build record.
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md): hosting on Railway and runbooks for changing the
  live backend, database, configuration or APKs.

## Development and review

Read [CONTRIBUTING.md](CONTRIBUTING.md) for prerequisites, component commands,
verification and pull request guidance. There is no root build: each component
has its own dependency manifest. Keep the monorepo layout so Flutter path
dependencies resolve.

For a showcase preview without local APKs:

```powershell
npm --prefix showcase ci
npm --prefix showcase run dev:website
```

Credentials, APKs, screenshot exports, browser review output and local evidence
stay ignored. Keep original source/assets in their component folders; record
milestones in the existing progress guide rather than creating more reports.

## Built with

Built by the Kesor Bank project team with the help of AI coding assistants:

- **[Claude Code](https://claude.com/claude-code)** (Anthropic): Merchant app
  planning and implementation, including shop registration, dashboard, wallets,
  QR collection and the remaining-work plan.
- **[Codex](https://openai.com/codex)** (OpenAI): implementation and
  verification across the project, including Merchant sales, receipts, reports
  and sharing.

AI-assisted commits carry a `Co-authored-by` line naming the assistant. GitHub's
Contributors list shows only commit authors with GitHub accounts, so the
assistants appear here and in commit messages instead.
