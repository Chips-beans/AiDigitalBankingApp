# Monthly analytics

Implemented 30 October 2026 for the signed-in Flutter customer app.
Project: `C:\Users\User\Documents\GitHub\AiDigitalBankingApp`.
Design: Kesor Bank, node `166:177`, 440 × 956. The live Figma connector was
reauthenticated during implementation; current design context, screenshot and
original SVG exports were used. Existing Home/navigation/fonts/tokens are reused.

## Financial meaning and API

`GET /api/v1/analytics/monthly-overview?year=2026&month=10&currency=USD`
requires a customer access token. The owner comes from that token; the API accepts
no owner or account selection. It combines the customer's accounts in the selected
currency, including historical activity on frozen/closed accounts. A transaction
whose source and destination both belong to the customer is excluded entirely.

Only `SUCCESS` transaction amounts contribute. Income means money received from
outside the customer's accounts (including deposits); expense means money sent
outside them (including withdrawals). Fees are not added: current posting commands
charge zero fees. This is a cash-flow view, not transaction categorization or tax
accounting. No currency conversion or cross-currency total is performed.

The existing `ApiResponse` envelope contains `data`:

```json
{
  "month": "2026-10",
  "currency": "USD",
  "timeZone": "Asia/Phnom_Penh",
  "totalIncome": "0.00",
  "totalExpense": "0.00",
  "daily": [
    { "date": "2026-10-01", "totalIncome": "0.00", "totalExpense": "0.00" }
  ]
}
```

The example abbreviates `daily`; the real response always includes every date in
order. Empty accounts/months return zero totals and all dates. USD amounts are
decimal strings with two places; KHR amounts are whole-unit strings. Aggregates
can exceed an individual transaction's maximum amount. Monthly totals are summed
from the results of one daily aggregate query, ensuring internal consistency.

Month filters and SQL date grouping explicitly use `Asia/Phnom_Penh`; filtering
uses inclusive local-month start and exclusive next-month start. Invalid month,
year outside 1–9999, missing parameters and unsupported currency return structured
400 responses. Authentication and role restrictions remain server-enforced.

The original `/daily`, `/monthly-summary`, and `/semester-comparison` endpoints
retain their response shapes and account ownership checks. Their daily direction
logic and timezone boundaries are corrected. Account-level analytics still count
transfers to/from other accounts owned by the same customer, because the scope of
those legacy endpoints is one account. The new overview excludes those movements.

No migration, financial posting, balance update, or development-database startup
is required by this change. Schema remains V11; the development database's
previous V10 state was not changed by implementation tests.

## Flutter behavior

`BankingApp` accepts an injectable `AnalyticsGateway`. API mode selects
`HttpAnalyticsGateway`; explicit demo mode selects `DemoAnalyticsGateway`.
There is no API-error fallback to demo data. The existing exact JSON decoder and
authorized-read token renewal are reused. Analytics models validate currency,
timezone, requested month, complete ordered dates, exact monetary strings and
agreement between daily values and totals. Monetary values stay in `BigInt` minor
units, without the single-transaction bound used by the existing `Money` model.

The controller loads on first Analytics entry, defaults to the current Phnom Penh
month/USD/Expense, and preserves its choices across tab navigation. Currency/month
changes and pull-to-refresh read the overview again. Successful internal transfers
and account openings invalidate the cache; a previously opened Analytics tab is
refreshed. The cache holds at most 24 month/currency snapshots in memory only.
Failures may retain a marked stale snapshot for the same selection; other
selections show unknown totals rather than unrelated data. Session identity,
request generations and disposal prevent stale private responses being published.

## Screen and chart

- Source geometry: 440px content frame, 20px gutters, 101px minimum-height summary
  cards, gold/navy surfaces and existing shared navigation. The USD/KHR selector
  is the agreed addition to the source month row. Monthly is a fixed period label.
- The decorative SVG retains its original bytes and transform. Its progressive
  blur uses the existing shared Home renderer because Flutter SVG ignores Figma's
  SVG filter tags; exact blur appearance can differ slightly.
- `CustomPainter` draws dynamic rounded bars (`6.57px` maximum width), gridlines,
  zero baseline and sparse labels with the bundled fonts. No chart package was
  added. Both series share a scale calculated in exact integer arithmetic.
- Source sample card amounts and bar heights are not treated as financial data.
  The explicit demo uses a coherent fixture whose cards equal its daily sums.
  Zero-baseline scaling intentionally replaces the source's illustrative labels.
- Only normalized drawing ratios become `double`. Tap or hover shows the exact
  date/amount. Focus the chart and use left/right arrows; Escape clears selection.
  Screen readers can step through days. Tap the Overview Trends title (with its
  localized tooltip) to open an accessible daily-values sheet containing both series.
- Light/dark and English/Khmer follow existing preferences. Small screens and
  large text scroll above the navigation. Cards stack and chart labels thin out
  when needed. Native system bars remain native; fake device chrome is QA-only.

## Verification

Commands run from their respective backend/customer-app directories:

```powershell
.\mvnw.cmd test
flutter analyze --no-pub
flutter test test/ tool/analytics_visual_qa.dart --no-pub --reporter expanded
flutter build web --no-pub --dart-define=APP_ENV=dev
flutter build apk --debug --no-pub --dart-define=APP_ENV=dev --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
```

Backend: **114 passed**, including four new integration scenarios using isolated
PostgreSQL and local SMTP fixtures. The scenarios cover direction, own-account
exclusion, currency/customer separation, frozen/closed history, unsuccessful
statuses, exact large totals, calendar lengths, local midnight/month edges,
authentication, invalid requests and legacy response shape/ownership.

Flutter: **134 checks passed** (133 tests plus the visual fixture), and final
analysis reported no issues. The full regression and visual fixture are recorded in ignored logs
under `frontend/customer_app/.local/analytics-*`. The final result is added to the
current project handoff. The visual fixture renders reference and narrow/2× text
variants in both themes/languages under `.local/qa/analytics/`. Unit/widget tests
cover parsing, totals, scale bounds, token renewal, cache/late responses, disposal,
session changes, selectors, daily values, loading/empty/error states and navigation.

The development web build includes a successful Wasm dry run. The normal-entrypoint
debug APK targets local API access through USB `adb reverse` and is not a production
release. No device installation or live customer acceptance is claimed. No emulator,
preview, tunnel, development backend, external email, or real transaction was started.

The initial targeted database test exposed the legacy projection's `java.sql.Date`
mismatch with Spring's `LocalDate`; it was corrected and the full backend suite
passed afterward. Early Flutter checks caught narrow large-text overflow and were
fixed before the final verification. No commit was created.
