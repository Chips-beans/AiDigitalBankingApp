# Kesor Bank Home

Source: [HomeScreen Final Design, Figma node 9:43](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=9-43).
Reference frame: 440 × 999 logical pixels.

The signed-in Home uses `KesorHomeScreen` and presentation values from the existing
account controller. Tap the logo or balances to open the existing account screen.
The floating navigation opens existing activity and profile screens. No network
client, endpoint, authentication logic, or service configuration was changed.

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
- Google Sans Regular/Medium are copied from the workstation's installed fonts,
  matching the design's Latin and Khmer fonts. Poppins Regular/Medium and the
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
```

The visual fixture loads the real bundled fonts and writes 440 × 999, 375 × 812,
large-text, and landscape screenshots under ignored `.local/qa/home/`.
