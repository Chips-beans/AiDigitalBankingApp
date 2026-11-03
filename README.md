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

## Documentation

Start with [AGENTS.md](AGENTS.md), then
[docs/NEXT_SESSION_BRIEF.md](docs/NEXT_SESSION_BRIEF.md) for the current state.
Merchant milestones are tracked in
[docs/MERCHANT_APP_PROGRESS.md](docs/MERCHANT_APP_PROGRESS.md), and the remaining
work in [docs/MERCHANT_REMAINING_WORK_PLAN.md](docs/MERCHANT_REMAINING_WORK_PLAN.md).

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
