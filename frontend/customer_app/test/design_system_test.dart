import 'dart:convert';
import 'dart:io';

import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = jsonDecode(
    File('design/figma_tokens.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  Color color(String hex) =>
      Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));

  test('every color primitive matches the captured Figma source', () {
    final expected = (source['primitives'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, color(value as String)),
    );
    expect(AppPalette.primitives, expected);
  });

  for (final brightness in Brightness.values) {
    final mode = brightness == Brightness.light ? 'light' : 'dark';
    test('$mode aliases and Material theme use the exact Figma colors', () {
      final expected = (source['modes'][mode] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, color(value as String)),
      );
      final theme = AppTheme.build(brightness);
      final colors = theme.extension<AppColors>()!;
      expect(colors.tokens, expected);
      expect(theme.scaffoldBackgroundColor, expected['Neutral/Background']);
      expect(theme.colorScheme.surface, expected['Neutral/Surface']);
      expect(theme.colorScheme.onSurface, expected['Neutral/Foreground&Base']);
      expect(theme.colorScheme.primary, expected['Primary/500']);
      expect(theme.colorScheme.secondary, expected['Accent/500']);
      expect(theme.colorScheme.error, expected['Semantic/Error']);
      expect(theme.colorScheme.errorContainer, expected['Semantic/ErrorMuted']);
      expect(theme.disabledColor, expected['Neutral/DisabledBackground']);
    });
  }

  final weights = {
    'Light': FontWeight.w300,
    'Regular': FontWeight.w400,
    'Medium': FontWeight.w500,
    'SemiBold': FontWeight.w600,
    'Bold': FontWeight.w700,
  };
  for (final language in ['English', 'Khmer']) {
    test(
      '$language imports all nine Figma text styles without losing metrics',
      () {
        final styles = language == 'English'
            ? AppTypography.english
            : AppTypography.khmer;
        final expected = (source['typography'] as List<dynamic>)
            .where(
              (s) => (s['name'] as String).startsWith('Typography/$language/'),
            )
            .toList();
        expect(styles.roles.length, expected.length);
        for (var index = 0; index < expected.length; index++) {
          final token = expected[index];
          final style = styles.roles.values.elementAt(index);
          expect(style.fontFamily, token['fontName']['family']);
          expect(style.fontWeight, weights[token['fontName']['style']]);
          expect(style.fontSize, token['fontSize']);
          expect(
            style.height! * style.fontSize!,
            closeTo((token['lineHeight']['value'] as num).toDouble(), .0001),
          );
          expect(style.letterSpacing, token['letterSpacing']['value']);
          expect(style.fontFamilyFallback, contains('Noto Sans Khmer'));
        }
      },
    );
  }

  test(
    'Khmer locale selects Khmer metrics and theme extensions interpolate',
    () {
      final khmer = AppTheme.build(
        Brightness.light,
        locale: const Locale('km', 'KH'),
      );
      expect(khmer.textTheme.bodyMedium!.fontFamily, 'Google Sans');
      expect(khmer.textTheme.bodyMedium!.height! * 15, 28);
      expect(khmer.extension<AppTextStyles>(), AppTypography.khmer);
      final english = AppTheme.build(Brightness.light);
      expect(english.textTheme.bodyMedium!.fontFamily, 'Poppins');
      expect(english.textTheme.labelLarge!.fontWeight, FontWeight.w600);
      final halfway = ThemeData.lerp(
        english,
        AppTheme.build(Brightness.dark),
        .5,
      );
      expect(
        halfway.extension<AppColors>()!.background,
        Color.lerp(AppColors.light.background, AppColors.dark.background, .5),
      );
      expect(halfway.extension<AppTextStyles>()!.body.fontFamily, 'Poppins');
    },
  );
}
