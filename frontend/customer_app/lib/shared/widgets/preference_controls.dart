import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/app_preferences.dart';
import '../../app/design_system/design_system.dart';

/// The source capsule is 44px high; transparent 48px hit areas surround it.
class PreferenceControls extends StatelessWidget {
  const PreferenceControls({super.key});
  @override
  Widget build(BuildContext context) {
    final prefs = AppPreferences.of(context);
    final colors = AppColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labelStyle = const TextStyle(
      fontFamily: AppTypography.englishFamily,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 21 / 14,
      letterSpacing: 0,
    ).copyWith(color: colors.foreground);
    final measure = TextPainter(
      text: TextSpan(text: prefs.isKhmer ? 'KM' : 'EN', style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = math.max(110.0, 92 + measure.width);
    final visualHeight = math.max(44.0, measure.height + 8);
    measure.dispose();
    return SizedBox(
      width: width,
      height: visualHeight + 4,
      child: Stack(
        children: [
          Positioned(
            top: 4,
            left: 0,
            right: 0,
            bottom: 0,
            child: ExcludeSemantics(
              child: Material(
                key: const ValueKey('preference-capsule'),
                color: colors.surface,
                borderRadius: BorderRadius.circular(27),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.background,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: SvgPicture.asset(
                            'assets/auth/theme-moon-${dark ? 'dark' : 'light'}.svg',
                            width: 20,
                            height: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!prefs.isKhmer)
                              SvgPicture.asset(
                                'assets/auth/flag-en.svg',
                                width: 28,
                                height: 28,
                              )
                            else
                              const SizedBox(
                                width: 28,
                                height: 28,
                                child: Icon(Icons.translate_rounded, size: 24),
                              ),
                            const SizedBox(width: 4),
                            Text(
                              prefs.isKhmer ? 'KM' : 'EN',
                              style: labelStyle,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('theme-toggle'),
                    tooltip: dark
                        ? 'Switch to light mode'
                        : 'Switch to dark mode',
                    onPressed: () =>
                        prefs.toggleTheme(Theme.of(context).brightness),
                    style: IconButton.styleFrom(
                      fixedSize: Size(48, visualHeight + 4),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: Semantics(
                      label: prefs.isKhmer
                          ? 'Switch to English'
                          : 'Switch to Khmer',
                      child: TextButton(
                        key: const ValueKey('language-toggle'),
                        onPressed: prefs.toggleLanguage,
                        style: TextButton.styleFrom(
                          minimumSize: Size(48, visualHeight + 4),
                          padding: EdgeInsets.zero,
                        ),
                        child: Semantics(
                          label: prefs.isKhmer
                              ? 'Switch to English'
                              : 'Switch to Khmer',
                          child: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
