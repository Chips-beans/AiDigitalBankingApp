# Kesor Transfer flow

## Latest — full Figma flow and bottom navigation

Updated 30 October 2026 from [Transfer Flow section 307:340](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=307-340).
The native entry `273:356` and review `308:269` target 440 × 956; success `308:740`
targets 440 × 978. The layouts use `kesor_transfer_screen.dart`,
`transfer_review_screen.dart`, `transfer_success_screen.dart` and shared
`transfer_flow_design.dart`. The original entry-only implementation is documented
below as history; its generic review is superseded for manual transfers.

Reference positions and typography are checked for the emblems/panels, inputs,
392 × 54 payment actions, 175px review account card, 64px reminder, 84px light
success amount, 376 × 366 receipt and 376 × 56 home action. The receipt uses
Figma's original perforation, notches, icons and gold shadow. The static seal is
exported directly from its Figma node as a transparent 2× PNG because Flutter's
SVG renderer does not support the source blur filter. Its 198 × 178.174 rendered
bounds remain in the 198 × 168 design slot. No screen screenshot is used as UI.
Existing entry/navigation SVGs were verified byte-for-byte against current exports.
All runtime assets are local; no temporary Figma URLs are embedded.

The customer's subsequent icon/flag correction is included: account/receiver
artwork uses the exact Figma paths and intrinsic bounds with no added gold square
in dark mode; a monochrome theme tint preserves contrast without changing shape.
KHR now uses the Cambodia flag and USD uses a borderless US flag, shared across
entry/review/success. These intentional flag changes replace the source's padded
US raster badge and earlier riel-glyph adaptation. Sources/licenses are recorded
in `assets/transfer/FLAG_SOURCES.md`. Original Figma glyph assets are unchanged.

Entry and review payment actions stay at the bottom above the keyboard; details
scroll independently. On wide displays the form and footer share the same 440px
maximum width. Success content/actions scroll together if needed. English/Khmer,
both themes, 2× text, narrow, landscape and tablet variants are supported.
Reference measurements apply at normal text settings. The connected Samsung uses
130% text plus a 300 font-weight adjustment; these accessibility settings are
respected and were not modified to imitate the reference.

Manual recipient names are not supplied by the existing API, so the real account
number occupies the primary recipient slot. A verified QR name can display when
available. No sample recipient, date or reference is inserted into a real receipt.
Dates use the confirmed server receipt; absent dates are explicitly unavailable.
Only a durably confirmed success selects the gold-seal screen. Home/another-transfer
actions dismiss the resolved journal through the existing controller before
navigating/clearing fields. Unknown/rejected states retain `TransferPanel` recovery.
No backend, transfer API, precision, PIN or idempotency behavior was changed.

The shared `KesorBottomBar` follows `90:644` and row `73:1328`: 320 × 64 capsule,
4px inset, 56px selected tab, 20px linked active/inactive icons, Google Sans 11/16
labels, 16px gap and separate 64px gradient assistant action. The assistant uses
the original 24px Figma chat artwork and exposes its selected state. Existing
Home/Analytics/Settings/AI routing is preserved; sizes adapt for narrow/large text.

Verification: **213 Flutter tests passed**, analyzer clean. The entry fixture and
new `tool/transfer_flow_visual_qa.dart` also passed, rendering 14 entry variants
and 42 review/success/navigation variants including KHR. Reference geometry checks passed;
representative renders were visually compared with Figma. Keyboard clearance,
explicit confirmation, lost-response retry and success dismissal are covered.
Latest packaged build and physical-device observations are in the project handoff.

## Original entry implementation — historical

Implemented from [Kesor Bank, frame 273:356](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=273-356)
on 30 October 2026. Home → Transfer opens the native Flutter screen in
`lib/features/transactions/presentation/kesor_transfer_screen.dart`.

## Design and adaptation

The 440 × 956 reference uses a navy header, gold transfer emblem, 32 px rounded
form panel, 24 px side insets, Poppins typography and gold Continue button.
Downloaded Figma SVG exports retain their intrinsic bounds in
`assets/transfer/`; the album icon reuses the identical existing
`assets/home/recipients.svg`. The USD flag is the original exported image.
The fixture asserts reference positions for the emblem, panel, picker, three
input frames and 392 × 54 button. No screenshot is used as application UI.

Runtime balances and accounts come from `AccountsController`. The sample
USD 168.00 balance belongs only to visual test data. The receiver field accepts
wallet account numbers (10–20 digits), rather than the Figma phone-number hint:
the existing backend transfers by account number. USD/KHR selection changes the
displayed balance, currency and precision rules. KHR uses a riel symbol instead
of the US flag. No phone lookup or cross-currency transfer was introduced.

English/Khmer, existing light/dark tokens, 48 px action targets, keyboard insets,
narrow displays, large text and landscape are supported. Content scrolls and
the button grows for larger text. Native system bars remain native; the
9:41/status icons/home indicator appear only in the screenshot fixture.

## Transfer safety and favorites

Continue validates and opens the existing `TransferPanel` review; only explicit
Confirm and send submits. The shared controller, immutable safety journal,
idempotency keys, unknown-result recovery, receipts and refresh callbacks remain
in use. Preview/demo submission stays disabled. QR payments still share that
same controller; this change styles the manual-transfer entry screen.

Save to Favorites records a number and currency only after confirmed success.
An unknown result does not save a recipient. The original explicit retry can
complete and save it. Recovered successful receipts also offer Save recipient.
Bookmarks use FlutterSecureStorage scoped by API/mode/user on native
API sessions; previews/tests use memory. They contain no recipient-name lookup
and provide no payment authorization. The list filters by selected currency;
choosing a bookmark fills the field without preparing or sending a payment.
Corrupt favorites are preserved, an error is shown, and manual entry remains
available. Concurrent saves are serialized and entries deduplicated (maximum 50).

Account/favorites sheets hide their contents and dismiss on privacy cover,
PIN lock, logout or owner/session change. Personal form values clear when the
session is invalidated. Existing background PIN behavior is unchanged.

## Verification

- `flutter analyze --no-pub`
- `flutter test --no-pub` (177 tests)
- `flutter test --no-pub tool/transfer_visual_qa.dart`
- API-mode web build with Wasm dry run and Android debug APK

After the final account-number example adjustment, the form/recovery and visual
subset passed another 12 checks. APK packaging verification passed and the
user-facing build is `KesorBank-Transfer-Test.apk` in the chat's outputs folder.

The visual fixture writes ignored `.local/qa/transfer/` images in English/Khmer,
both themes, 440 × 956 reference size, 375 px narrow, 320 px with 2× Khmer text,
812 × 375 landscape with 2× English text and 1024 × 768 tablet size.
Source/receipt fixtures are controlled test data, not live customer acceptance.
Physical-device keyboard/system-bar rendering, native favorites persistence and
live customer/PIN/transfer acceptance remain device checks. No backend or
database changes were needed for this screen.
