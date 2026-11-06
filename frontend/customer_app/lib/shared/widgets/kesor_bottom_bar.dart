import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/app_preferences.dart';
import '../../app/design_system/design_system.dart';

/// Figma 90:644 / 73:1328: 320x64 tab capsule + 16 gap + 64 assistant.
class KesorBottomBar extends StatelessWidget {
  const KesorBottomBar({
    required this.selectedIndex,
    required this.onSelected,
    this.onAssistant,
    super.key,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? onAssistant;

  static double height(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
    return math.max(64, 38 + 16 * scale * (scale > 1.3 ? 2 : 1));
  }

  @override
  Widget build(BuildContext context) {
    final colors =
        Theme.of(context).extension<AppColors>() ??
        AppColors.forBrightness(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final khmer = AppPreferences.maybeOf(context)?.isKhmer ?? true;
    final labels = khmer
        ? ['ទំព័រដើម', 'ការវិភាគ', 'ការកំណត់']
        : ['Home', 'Analytics', 'Settings'];
    final names = ['home', 'analytics', 'settings'];
    final barHeight = height(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            key: const ValueKey('kesor-nav-capsule'),
            height: barHeight,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Row(
              children: [
                for (var index = 0; index < 3; index++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: selectedIndex == index,
                      label: ['Home', 'Analytics', 'Settings'][index],
                      child: Tooltip(
                        message: ['Home', 'Analytics', 'Settings'][index],
                        excludeFromSemantics: true,
                        child: Material(
                          color: selectedIndex == index
                              ? colors.primary100
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(28),
                          child: InkWell(
                            key: ValueKey('bottom-tab-$index'),
                            borderRadius: BorderRadius.circular(28),
                            onTap: () => onSelected(index),
                            child: ExcludeSemantics(
                              child: SizedBox(
                                height: barHeight - 8,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SvgPicture.asset(
                                      selectedIndex == 1 && index == 0
                                          ? 'assets/analytics/figma-home.svg'
                                          : selectedIndex == 0
                                          ? 'assets/figma/${['34550', '6bee9', '1cbfc'][index]}.svg'
                                          : selectedIndex == 1
                                          ? 'assets/figma/${['f640a', '05ff1', '5b6a1'][index]}.svg'
                                          : 'assets/home/nav-${names[index]}-${selectedIndex == index ? 'active' : 'inactive'}.svg',
                                      width: 20,
                                      height: 20,
                                      excludeFromSemantics: true,
                                      colorFilter:
                                          dark && selectedIndex != index
                                          ? ColorFilter.mode(
                                              colors.foreground,
                                              BlendMode.srcIn,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 2),
                                    Flexible(
                                      child: Text(
                                        labels[index],
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        style: TextStyle(
                                          fontFamily: AppTypography.khmerFamily,
                                          fontFamilyFallback:
                                              AppTypography.fallbackFamilies,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w400,
                                          letterSpacing: 0,
                                          height: 16 / 11,
                                          color: selectedIndex == index
                                              ? colors.primary700
                                              : colors.foreground,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Semantics(
          button: true,
          selected: selectedIndex == 3,
          label: khmer ? 'ជំនួយការ AI' : 'AI assistant',
          child: Tooltip(
            message: 'AI assistant',
            excludeFromSemantics: true,
            child: Material(
              borderRadius: BorderRadius.circular(32),
              child: InkWell(
                onTap: onAssistant ?? () {},
                borderRadius: BorderRadius.circular(32),
                child: ExcludeSemantics(
                  child: Ink(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.primary50,
                          colors.primary100,
                          colors.primary200,
                        ],
                        stops: const [0, .5, 1],
                      ),
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/home/ai-chat.svg',
                        width: 24,
                        height: 24,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
