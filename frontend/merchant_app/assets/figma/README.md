# Kesor Merchant · Quiet v2 assets

Exported from the user's [Figma design, section 370:4356](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=370-4356).
The SVG files retain Figma's exported geometry, dimensions and viewBoxes. `QIcon`
in `lib/core/merchant_ui.dart` places them in their original logical slots; only
foreground icons adapt to the existing dark theme.

The three rosette exports are `3633f` (Welcome), `cf7f4` (QR brand), and `923a9`
(receipt). The remaining exports cover navigation, fields, status, settings,
selected radio and switch controls. Shop logos remain server-supplied images.

`17e15.svg` is the design's sample QR artwork. It is **never used for payments**:
`KesorQrCard` renders the authenticated server's current QR payload with
`qr_flutter`. Amounts, balances, names, account suffixes, references, dates,
request status and approval countdowns also remain live data.
