import 'package:flutter/material.dart';

/// Exact primitives from Kesor Bank / Color Palette (Figma 206:233).
/// See design/figma_tokens.json for source names, IDs, and mode aliases.
abstract final class AppPalette {
  static const neutralLightBackground = Color(0xFFFFFFFF);
  static const neutralDarkBackground = Color(0xFF222222);
  static const neutralLightSurface = Color(0xFFF8F8FF);
  static const neutralDarkSurface = Color(0xFF18181B);
  static const neutralLightDisabled = Color(0xFFECECF0);
  static const neutralDarkDisabled = Color(0xFF333333);
  static const neutralLightAccent = Color(0xFFE9EBEF);
  static const neutralDarkAccent = Color(0xFF2A2A2E);
  static const neutralLightBorder = Color(0xFFE5E5E5);
  static const neutralDarkBorder = Color(0xFF3A3A3F);
  static const neutralLightDisabledBackground = Color(0xFF717182);
  static const neutralDarkDisabledBackground = Color(0xFF8E8E96);
  static const neutralLightForegroundAndBase = Color(0xFF0A0A0B);
  static const neutralDarkForegroundAndBase = Color(0xFFF4F4F5);
  static const gold50 = Color(0xFFFCF8EA);
  static const gold100 = Color(0xFFF7EDCD);
  static const gold200 = Color(0xFFEFDA9B);
  static const gold400 = Color(0xFFDDBB59);
  static const gold500 = Color(0xFFCDA32F);
  static const gold600 = Color(0xFFA48226);
  static const gold700 = Color(0xFF7B621C);
  static const semanticSuccess = Color(0xFF16A34A);
  static const semanticSuccessMuted = Color(0xFFDCFCE7);
  static const semanticWarning = Color(0xFFD97706);
  static const semanticWarningMuted = Color(0xFFFEF3C7);
  static const semanticInfo = Color(0xFF0284C7);
  static const semanticInfoMuted = Color(0xFFE0F2FE);
  static const semanticError = Color(0xFFD4183D);
  static const semanticErrorMuted = Color(0xFFFEE2E2);
  static const navy50 = Color(0xFFF1F5F9);
  static const navy100 = Color(0xFFDDE7F1);
  static const navy200 = Color(0xFFB7CBE0);
  static const navy400 = Color(0xFF42678E);
  static const navy500 = Color(0xFF133358);
  static const navy600 = Color(0xFF0F2946);
  static const navy700 = Color(0xFF0B1F35);

  static const primitives = <String, Color>{
    'Neutral/Light/Background': neutralLightBackground,
    'Neutral/Dark/Background': neutralDarkBackground,
    'Neutral/Light/Surface': neutralLightSurface,
    'Neutral/Dark/Surface': neutralDarkSurface,
    'Neutral/Light/Disabled': neutralLightDisabled,
    'Neutral/Dark/Disabled': neutralDarkDisabled,
    'Neutral/Light/Accent': neutralLightAccent,
    'Neutral/Dark/Accent': neutralDarkAccent,
    'Neutral/Light/Border': neutralLightBorder,
    'Neutral/Dark/Border': neutralDarkBorder,
    'Neutral/Light/DisabledBackground': neutralLightDisabledBackground,
    'Neutral/Dark/DisabledBackground': neutralDarkDisabledBackground,
    'Neutral/Light/Foreground&Base': neutralLightForegroundAndBase,
    'Neutral/Dark/Foreground&Base': neutralDarkForegroundAndBase,
    'Gold/50': gold50,
    'Gold/100': gold100,
    'Gold/200': gold200,
    'Gold/400': gold400,
    'Gold/500': gold500,
    'Gold/600': gold600,
    'Gold/700': gold700,
    'Semantic/Success': semanticSuccess,
    'Semantic/SuccessMuted': semanticSuccessMuted,
    'Semantic/Warning': semanticWarning,
    'Semantic/WarningMuted': semanticWarningMuted,
    'Semantic/Info': semanticInfo,
    'Semantic/InfoMuted': semanticInfoMuted,
    'Semantic/Error': semanticError,
    'Semantic/ErrorMuted': semanticErrorMuted,
    'Navy/50': navy50,
    'Navy/100': navy100,
    'Navy/200': navy200,
    'Navy/400': navy400,
    'Navy/500': navy500,
    'Navy/600': navy600,
    'Navy/700': navy700,
  };
}

/// Figma's seven mode-dependent neutrals. Brand and status tokens are shared
/// by Light and Dark in the source; their names are retained here as getters.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.disabled,
    required this.accent,
    required this.border,
    required this.disabledBackground,
    required this.foreground,
  });

  final Color background;
  final Color surface;
  final Color disabled;
  final Color accent;
  final Color border;
  final Color disabledBackground;
  final Color foreground;

  static const light = AppColors(
    background: AppPalette.neutralLightBackground,
    surface: AppPalette.neutralLightSurface,
    disabled: AppPalette.neutralLightDisabled,
    accent: AppPalette.neutralLightAccent,
    border: AppPalette.neutralLightBorder,
    disabledBackground: AppPalette.neutralLightDisabledBackground,
    foreground: AppPalette.neutralLightForegroundAndBase,
  );

  static const dark = AppColors(
    background: AppPalette.neutralDarkBackground,
    surface: AppPalette.neutralDarkSurface,
    disabled: AppPalette.neutralDarkDisabled,
    accent: AppPalette.neutralDarkAccent,
    border: AppPalette.neutralDarkBorder,
    disabledBackground: AppPalette.neutralDarkDisabledBackground,
    foreground: AppPalette.neutralDarkForegroundAndBase,
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  static AppColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  Color get primary50 => AppPalette.gold50;
  Color get accent50 => AppPalette.navy50;
  Color get primary100 => AppPalette.gold100;
  Color get accent100 => AppPalette.navy100;
  Color get primary200 => AppPalette.gold200;
  Color get accent200 => AppPalette.navy200;
  Color get primary400 => AppPalette.gold400;
  Color get accent400 => AppPalette.navy400;
  Color get primary500 => AppPalette.gold500;
  Color get accent500 => AppPalette.navy500;
  Color get primary600 => AppPalette.gold600;
  Color get accent600 => AppPalette.navy600;
  Color get primary700 => AppPalette.gold700;
  Color get accent700 => AppPalette.navy700;
  Color get success => AppPalette.semanticSuccess;
  Color get successMuted => AppPalette.semanticSuccessMuted;
  Color get warning => AppPalette.semanticWarning;
  Color get warningMuted => AppPalette.semanticWarningMuted;
  Color get info => AppPalette.semanticInfo;
  Color get infoMuted => AppPalette.semanticInfoMuted;
  Color get error => AppPalette.semanticError;
  Color get errorMuted => AppPalette.semanticErrorMuted;

  /// Source token names, including Neutral/DisabledBackground as authored.
  Map<String, Color> get tokens => {
    'Neutral/Background': background,
    'Neutral/Surface': surface,
    'Neutral/Disabled': disabled,
    'Neutral/Accent': accent,
    'Neutral/Border': border,
    'Neutral/DisabledBackground': disabledBackground,
    'Neutral/Foreground&Base': foreground,
    'Primary/50': primary50,
    'Primary/100': primary100,
    'Primary/200': primary200,
    'Primary/400': primary400,
    'Primary/500': primary500,
    'Primary/600': primary600,
    'Primary/700': primary700,
    'Semantic/Success': success,
    'Semantic/SuccessMuted': successMuted,
    'Semantic/Warning': warning,
    'Semantic/WarningMuted': warningMuted,
    'Semantic/Info': info,
    'Semantic/InfoMuted': infoMuted,
    'Semantic/Error': error,
    'Semantic/ErrorMuted': errorMuted,
    'Accent/50': accent50,
    'Accent/100': accent100,
    'Accent/200': accent200,
    'Accent/400': accent400,
    'Accent/500': accent500,
    'Accent/600': accent600,
    'Accent/700': accent700,
  };

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? disabled,
    Color? accent,
    Color? border,
    Color? disabledBackground,
    Color? foreground,
  }) => AppColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    disabled: disabled ?? this.disabled,
    accent: accent ?? this.accent,
    border: border ?? this.border,
    disabledBackground: disabledBackground ?? this.disabledBackground,
    foreground: foreground ?? this.foreground,
  );

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      border: Color.lerp(border, other.border, t)!,
      disabledBackground: Color.lerp(
        disabledBackground,
        other.disabledBackground,
        t,
      )!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
    );
  }
}
