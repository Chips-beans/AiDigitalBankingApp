# Kesor colors and typography

Imported 29 October 2026 from the current Kesor Bank Figma foundations:

- [Color palette, 206:233](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=206-233)
- [English typography, 230:208](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=230-208)
- [Khmer typography, 230:302](https://www.figma.com/design/Mkhqgqnt1SQoq4pn9INLY5/Kesor-Bank?node-id=230-302)

`design/figma_tokens.json` captures the source values, style IDs, and resolved mode
aliases. Legacy typography, navigation component tokens, spacing, shapes, and
artwork are outside this import.

## Colors

`AppPalette` contains all 36 exact primitives: 14 light/dark neutrals, seven gold,
seven navy, and eight semantic colors. `AppColors`, a `ThemeExtension`, exposes
all 29 source tokens per mode. The seven neutrals switch between Light and Dark;
Figma uses the same brand and semantic values in both modes. No shades are generated.

`AppTheme.build` maps gold to Material primary, navy to secondary, and the Figma
surface, foreground, border, disabled, and error tokens to their corresponding
roles. Primary button text uses navy; text-only actions use gold700 in light mode
and gold400 in dark mode for legibility. Material's additional container roles
reuse imported primitives; those role assignments are Flutter integration choices.

```dart
import 'package:customer_app/app/design_system/design_system.dart';

final colors = AppColors.of(context);
final background = colors.background;
final success = colors.success;
const brandGold = AppPalette.gold500;
```

The source name `Neutral/DisabledBackground` is retained exactly, including its
unusual name. Its value also serves as the theme's muted/disabled foreground.

## Typography

`AppTypography.english` uses Poppins, and `AppTypography.khmer` uses Google Sans
with Noto Sans Khmer as a bundled fallback. All styles use zero letter spacing.
Line height is represented as Figma pixels divided by font size, allowing normal
Flutter text scaling. Values below are size / line height in logical pixels.

| Role | English | Weight | Khmer | Weight |
| --- | --- | --- | --- | --- |
| hero | 32 / 44 | 300 | 32 / 56 | 400 |
| titleXL | 24 / 36 | 600 | 24 / 44 | 700 |
| titleL | 20 / 30 | 600 | 20 / 36 | 700 |
| titleM | 18 / 28 | 500 | 18 / 32 | 500 |
| bodyL | 17 / 28 | 400 | 17 / 30 | 400 |
| body | 15 / 24 | 400 | 15 / 28 | 400 |
| button | 14 / 22 | 600 | 14 / 26 | 700 |
| caption | 12 / 20 | 400 | 12 / 22 | 400 |
| micro | 10 / 16 | 500 | 10 / 20 | 500 |

The nine roles remain available through `AppTextStyles.of(context)`. Flutter's
TextTheme aliases are mapped as follows:

| Material role | Figma role |
| --- | --- |
| displayLarge / displayMedium / displaySmall | hero |
| headlineLarge / titleLarge | titleXL |
| headlineMedium | titleL |
| headlineSmall / titleMedium | titleM |
| bodyLarge | bodyL |
| bodyMedium | body |
| bodySmall / labelMedium | caption |
| titleSmall / labelLarge | button |
| labelSmall | micro |

```dart
final body = Theme.of(context).textTheme.bodyMedium;
final title = AppTextStyles.of(context).titleXL;
final khmer = AppTypography.khmer.body;

// Select the Khmer ramp for a Khmer-language subtree or app theme:
final theme = AppTheme.build(Brightness.light, locale: const Locale('km'));
```

The app's default global theme uses English. Home follows the app's selected light/dark theme and English/Khmer language.
See [Home integration](HOME_SCREEN.md) for login controls and shared navigation. Its private brand
aliases and the welcome screen brand aliases now use the shared primitives.
Existing screen-specific text sizes, artwork colors, gradients, and layouts remain
screen overrides. The subsequent Home implementation adds theme/language controls
and shared navigation as documented in [Home integration](HOME_SCREEN.md).

## Bundled font files

`pubspec.yaml` registers Poppins 300/400/500/600 and Google Sans 400/500/700.
Poppins Light and SemiBold were added from the official
[Google Fonts repository](https://github.com/google/fonts/tree/main/ofl/poppins).
Google Sans Bold and its OFL were copied from the existing workstation download
`DM_Sans,Google_Sans (1)/Google_Sans`; that download's Regular matches the app's
existing Regular file. The static Google Sans faces retain their default grade,
corresponding to Figma's GRAD 0. Noto Sans Khmer fallback is registered at
400/500/700. Font licenses are in `assets/fonts/*-OFL.txt`; fonts load offline.

## Interactive preview without an emulator

```powershell
flutter run -d chrome --no-pub --web-hostname=127.0.0.1 --web-port=8082 --target lib/main_design_system_preview.dart
```

This offline Flutter entry point provides Colors, Typography, and Home tabs. Use
the sun/moon button to change the foundation theme and English/Khmer to inspect
both type ramps. Home follows the selected theme and uses sample data. The preview requires no backend, login, Android emulator, or new package.
Press `q` in the Flutter command session to stop it.

## Verification

```powershell
flutter analyze
flutter test test/ tool/design_system_visual_qa.dart
```

The contract tests compare all imported primitives, both token modes, and all
18 type styles against the captured Figma source, and verify theme integration
and interpolation. The offline fixture loads every bundled font weight and
renders light/dark specimens to ignored `.local/qa/design-system/` PNGs. Existing
widget tests cover banking/auth journeys and responsive/large-text layouts.

Verified after the import: analysis reported no issues; all 103 tests passed
(96 existing, six design-system contract tests, one visual fixture). Both rendered
specimens were inspected. `flutter build web --no-pub --dart-define=APP_ENV=dev`
succeeded, including its Wasm dry run. The built font manifest registers all
imported weights, and the three added font binaries match the bundled source
files. No app server was started.
