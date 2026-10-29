# Kesor Bank Home

Source: [HomeScreen Final Design, Figma node 9:43](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=9-43).
Reference frame: 440 × 999 logical pixels.

The signed-in Home follows the app's selected light/dark theme and English/Khmer
language. Login controls carry those choices through authentication. Home reads
all owned account balances and recent transactions through `HomeController` and
`AccountHomeGateway`, using the existing authenticated Spring Boot endpoints.

The shared Figma bar opens Home and the requested label-only Analytics/Settings
placeholders. The assistant opens a label-only placeholder too. Existing banking
tools remain accessible: Home logo/balance → accounts; Home All transactions →
history; accounts/tool app-bar Profile → the existing profile and logout view.
Financial commands and recovery logic remain in place.

## Offline visual preview

From `frontend/customer_app`:

```powershell
flutter run -d chrome --target lib/main_home_preview.dart
```

This explicit preview needs no sign-in and reproduces the Figma sample balances,
recipients, transaction rows, iOS status bar, rounded frame, and home indicator.
The normal app uses native system bars. Preview actions open local sheets; adding
a recipient is a temporary UI interaction and does not provision a bank contact.

## Assets and rendering

- Original exported SVGs and PNGs are bundled in `assets/home/`; no temporary Figma
  download URL is used at runtime. Every visible artwork asset is retained.
- Google Sans Regular/Medium/Bold and Poppins Light/Regular/Medium/SemiBold are
  bundled, matching the imported English/Khmer foundations. Poppins and the
  Noto Sans Khmer variable font are bundled with their OFL license files.
- Spacing, text sizes/line heights, rounded corners, opacity, color stops,
  gold artwork transform, and the floating navigation follow the source nodes.
- SVG filter tags are not supported by Flutter SVG. The original motif SVG is
  retained and its progressive blur is reproduced with Flutter image filters.
- Figma GLASS has no identical native Flutter primitive. Clipped backdrop blur
  and directional lighting reproduce its appearance; Figma's proprietary optical
  refraction and dispersion can differ slightly from the Flutter render.
- Layout grows and scrolls for small screens and larger system text settings.
  Balance visibility, recipient sheets, horizontal actions, and navigation work.

## Verification

```powershell
flutter analyze
flutter test
flutter test tool/home_visual_qa.dart
flutter test test/ tool/home_modes_visual_qa.dart
```

The visual fixture loads the real bundled fonts and writes 440 × 999, 375 × 812,
large-text, and landscape screenshots under ignored `.local/qa/home/`.

## Current Figma references

- [Home, 9:43](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=9-43).
- [Bottom bar, 90:644](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=90-644), including all three selected states.
- [Light login, 116:776](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=116-776) and [dark login, 216:392](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=216-392), with original day/night artwork and controls.

Dark Home retains the Home geometry using the dark neutral palette, readable
foregrounds/icons, and subdued gold balance gradient. The second top-level frame
named HomeScreen is an Analytics design, not a dark Home reference.

## Preferences and shared navigation

`AppPreferences` drives ThemeMode, locale, typography, and Material localizations.
The login capsule toggles theme and English/Khmer; it is also available in the
email/code/onboarding layouts. Display choices persist in browser localStorage
or native secure storage under the separate `kesor.ui.preferences.v1` key. No
auth token enters browser localStorage. Corrupt/unavailable preference storage
uses system theme and English; writes are serialized against rapid toggles.
Home's balance mask stays selected across tab changes within the signed-in shell.

`KesorBottomBar` uses the six original SVGs from node 90:644. At reference scale
its capsule is 320×64, with 4 px inset, equal 104×56 areas, 32/28 px radii, 20 px
icons, 2 px icon/label gap, and 11/16 px Google Sans labels. The separate 64 px
assistant sits 16 px to the right and uses the source Gold50/100/200 gradient.
It scales horizontally and can grow taller for large system text.

## Authenticated Home data

API mode remains the normal `lib/main.dart` default:

1. `GET /api/v1/accounts/me?page=N&size=20` until every owned page is loaded.
2. `GET /api/v1/transactions/account/{accountNumber}?page=0&size=5` for every owned account, with at most four history reads in flight.

Balances sum `BigInt` minor units per currency, including amounts beyond
JavaScript's exact integer range. Histories are validated for ownership/currency,
sorted newest first, and deduplicated by reference so transfers between two owned
accounts appear once. Home displays the latest five; pending, failed, and reversed
statuses remain visible. Opening a row selects its owned account before fetching
transaction detail.

There is no backend contacts directory. Recipient account numbers are derived
from successful external transfers in those recent results; API mode invents no
names or avatars. The existing Add recipient interaction remains a temporary local
UI convenience, not a saved bank contact or a new backend endpoint.

Loading uses unknown-balance placeholders. Failure never activates sample data.
A failed refresh retains the last snapshot with a stale-data notice; pull down to
retry. Request generations and the original user/session identity suppress late
responses after refresh, sign-out, or disposal. Existing read-token renewal,
browser/native transfer restrictions, and financial recovery remain unchanged.
Figma content is only used in explicit `APP_MODE=demo` or the offline design fixture.

## New verification coverage

The Home API tests exercise client paths/auth headers, full pagination, exact
totals, internal-transfer deduplication, empty data, failures, stale responses,
sign-out, balance-mask retention, and the API-backed widget. They use local
response fixtures, not real customer profiles or outgoing email.

`tool/home_modes_visual_qa.dart` loads real font weights and original assets,
renders both languages/themes, login day/night artwork, all navigation states,
small phones, 2× text, and landscape. It verifies the reference navigation bounds.
Images are in ignored `.local/qa/home-modes/`.

Completed verification: 111 tests passed (110 VM/widget tests plus the visual
fixture), clean Flutter analysis, API-mode web build and Wasm dry run. Compiled
browser demo checks verified preference reload, Khmer continuation into dark Home,
both placeholder tabs, and no browser errors. The temporary runtime was stopped
afterward, as requested.

## Component consistency pass — 29 October 2026

The user's feedback was inconsistent sizes across themes, overflow, spacing and
fonts. The live Figma desktop document was inspected after the connector required
reauthentication; the existing exported SVGs and earlier full node contexts were
retained as the implementation references. No Figma source was modified.

- `KesorLayout` shares the 440px frame width, 20px gutters, 52px action height and
  16px radius. Desktop root content no longer stretches to 600px; auth forms no
  longer use a separate 480px frame.
- Material density is standard on web and mobile. Welcome buttons use the same
  Google Sans 15/28 regular style in both modes, 24px original SVGs and a 16px gap.
  The dark source's 48px buttons are intentionally normalized to the light
  source's 52px height to satisfy the user's theme-consistency request.
- At 440×956 the English welcome actions start at y=726.2 and y=794.2. The source
  logo offset, 44px capsule appearance and compact 18px footer lines are retained.
  Separate transparent 48px hit targets preserve keyboard and touch access.
  Enlarged/localized text grows and scrolls instead of clipping.
- At 440×999 Home's card bounds are (20,132,400,312), (20,510,400,94) and
  (20,664,400,228). Both themes use the same bounds. The activity viewport stops
  19px above navigation so rows do not paint beneath it on shorter devices.
- Recipient labels use bounded measured slots and ellipsis rather than painting
  into adjacent names. Full names remain in accessible labels and detail sheets.
- Bottom navigation uses an explicit regular weight in both themes. Its source
  geometry remains 320×64 with three 104×56 selected slots at reference size.

`test/figma_layout_test.dart` guards the measured card/action geometry, theme
stability, desktop centering, long names, and separation from the floating bar.
`tool/home_modes_visual_qa.dart` renders reference, narrow and 2x-text fixtures
for both languages/themes. Existing auth accessibility and banking widget tests
also pass. Browser inspection was unavailable in this pass because Browser Use
is disabled in the app settings; no browser preview was reopened. The source's
proprietary GLASS optics remain an approximation, and dark Home uses token-based
adaptation because the file has no separate dark Home frame.

Final validation for this pass: analyzer clean; 114 tests passed; full demo web
build and Wasm dry run succeeded. The final geometry/render subset also passed
after adding 320px, 2x-text scrolled-footer captures. Preview ports 8081–8083 were
confirmed closed.
