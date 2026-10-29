import 'package:flutter/material.dart';

/// Current Figma Typography page (English 230:208, Khmer 230:302).
/// Figma pixel line heights become Flutter's lineHeight / fontSize ratio.
/// Letter spacing is zero for every source style.
abstract final class AppTypography {
  static const englishFamily = 'Poppins';
  static const khmerFamily = 'Google Sans';
  static const fallbackFamilies = ['Noto Sans Khmer'];

  static const english = AppTextStyles(
    hero: TextStyle(
      fontFamily: englishFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 32,
      height: 44 / 32,
      fontWeight: FontWeight.w300,
      letterSpacing: 0,
    ),
    titleXL: TextStyle(
      fontFamily: englishFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 24,
      height: 36 / 24,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    titleL: TextStyle(
      fontFamily: englishFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 20,
      height: 30 / 20,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    titleM: TextStyle(
      fontFamily: englishFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 18,
      height: 28 / 18,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
    bodyL: TextStyle(
      fontFamily: englishFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 17,
      height: 28 / 17,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    body: TextStyle(
      fontFamily: englishFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 15,
      height: 24 / 15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    button: TextStyle(
      fontFamily: englishFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 14,
      height: 22 / 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    caption: TextStyle(
      fontFamily: englishFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 12,
      height: 20 / 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    micro: TextStyle(
      fontFamily: englishFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 10,
      height: 16 / 10,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
  );

  static const khmer = AppTextStyles(
    hero: TextStyle(
      fontFamily: khmerFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 32,
      height: 56 / 32,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    titleXL: TextStyle(
      fontFamily: khmerFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 24,
      height: 44 / 24,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    titleL: TextStyle(
      fontFamily: khmerFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 20,
      height: 36 / 20,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    titleM: TextStyle(
      fontFamily: khmerFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 18,
      height: 32 / 18,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
    bodyL: TextStyle(
      fontFamily: khmerFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 17,
      height: 30 / 17,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    body: TextStyle(
      fontFamily: khmerFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 15,
      height: 28 / 15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    button: TextStyle(
      fontFamily: khmerFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 14,
      height: 26 / 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    caption: TextStyle(
      fontFamily: khmerFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 12,
      height: 22 / 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    micro: TextStyle(
      fontFamily: khmerFamily,
      fontFamilyFallback: fallbackFamilies,
      fontSize: 10,
      height: 20 / 10,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
  );

  static AppTextStyles forLocale(Locale locale) =>
      locale.languageCode == 'km' ? khmer : english;
}

/// The nine Figma roles remain available alongside Flutter's Material aliases.
@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  const AppTextStyles({
    required this.hero,
    required this.titleXL,
    required this.titleL,
    required this.titleM,
    required this.bodyL,
    required this.body,
    required this.button,
    required this.caption,
    required this.micro,
  });

  final TextStyle hero;
  final TextStyle titleXL;
  final TextStyle titleL;
  final TextStyle titleM;
  final TextStyle bodyL;
  final TextStyle body;
  final TextStyle button;
  final TextStyle caption;
  final TextStyle micro;

  static AppTextStyles of(BuildContext context) =>
      Theme.of(context).extension<AppTextStyles>()!;

  TextTheme get textTheme => TextTheme(
    displayLarge: hero,
    displayMedium: hero,
    displaySmall: hero,
    headlineLarge: titleXL,
    headlineMedium: titleL,
    headlineSmall: titleM,
    titleLarge: titleXL,
    titleMedium: titleM,
    titleSmall: button,
    bodyLarge: bodyL,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: button,
    labelMedium: caption,
    labelSmall: micro,
  );

  Map<String, TextStyle> get roles => {
    'hero': hero,
    'titleXL': titleXL,
    'titleL': titleL,
    'titleM': titleM,
    'bodyL': bodyL,
    'body': body,
    'button': button,
    'caption': caption,
    'micro': micro,
  };

  @override
  AppTextStyles copyWith({
    TextStyle? hero,
    TextStyle? titleXL,
    TextStyle? titleL,
    TextStyle? titleM,
    TextStyle? bodyL,
    TextStyle? body,
    TextStyle? button,
    TextStyle? caption,
    TextStyle? micro,
  }) => AppTextStyles(
    hero: hero ?? this.hero,
    titleXL: titleXL ?? this.titleXL,
    titleL: titleL ?? this.titleL,
    titleM: titleM ?? this.titleM,
    bodyL: bodyL ?? this.bodyL,
    body: body ?? this.body,
    button: button ?? this.button,
    caption: caption ?? this.caption,
    micro: micro ?? this.micro,
  );

  @override
  AppTextStyles lerp(covariant AppTextStyles? other, double t) {
    if (other == null) return this;
    return AppTextStyles(
      hero: TextStyle.lerp(hero, other.hero, t)!,
      titleXL: TextStyle.lerp(titleXL, other.titleXL, t)!,
      titleL: TextStyle.lerp(titleL, other.titleL, t)!,
      titleM: TextStyle.lerp(titleM, other.titleM, t)!,
      bodyL: TextStyle.lerp(bodyL, other.bodyL, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      button: TextStyle.lerp(button, other.button, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
      micro: TextStyle.lerp(micro, other.micro, t)!,
    );
  }
}
