# Kesor Transfer screen

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
