import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'dart:ui' as ui;

import '../../app/app_preferences.dart';
import '../../app/design_system/design_system.dart';

/// Local exports from the Customer Figma section 387:6034.
class CustomerDesignIcon extends StatelessWidget {
  const CustomerDesignIcon(this.asset, {this.size = 24, this.color, super.key});
  final String asset;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: SvgPicture.asset(
      'assets/figma/$asset.svg',
      excludeFromSemantics: true,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    ),
  );
}

Color customerNavy(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppPalette.navy100
    : AppPalette.navy500;

TextStyle customerText(
  BuildContext context,
  double size,
  double lineHeight, {
  Color? color,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: AppPreferences.maybeOf(context)?.isKhmer == true
      ? AppTypography.khmerFamily
      : 'Poppins',
  fontFamilyFallback: AppTypography.fallbackFamilies,
  fontSize: size,
  height: lineHeight / size,
  fontWeight: weight,
  color: color ?? AppColors.of(context).foreground,
  letterSpacing: 0,
);

class CustomerPageHeader extends StatelessWidget {
  const CustomerPageHeader({
    required this.title,
    required this.onBack,
    this.trailing,
    super.key,
  });
  final String title;
  final VoidCallback onBack;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    child: Row(
      children: [
        IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBack,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.of(context).surface,
            minimumSize: const Size(48, 48),
          ),
          icon: CustomerDesignIcon(
            '03138',
            size: 22,
            color: customerNavy(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: customerText(
              context,
              24,
              36,
              color: customerNavy(context),
              weight: FontWeight.w600,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class CustomerAssistantBackground extends StatelessWidget {
  const CustomerAssistantBackground({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ColoredBox(
      color: colors.background,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final position in [true, false])
              Positioned(
                right: position ? -112 : null,
                left: position ? null : -144,
                top: position ? 35 : 434,
                child: IgnorePointer(
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                    child: Container(
                      width: 225,
                      height: 225,
                      color: colors.primary200.withValues(alpha: .65),
                    ),
                  ),
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}
