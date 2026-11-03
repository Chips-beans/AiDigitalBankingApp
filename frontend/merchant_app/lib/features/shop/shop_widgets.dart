import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import 'merchant_shop.dart';

/// Formats exact server decimal text: `1234.5` USD -> `$1,234.50`, KHR -> `1,234 ៛`.
String shopAmount(String decimal, String currency) {
  final negative = decimal.startsWith('-');
  final parts = (negative ? decimal.substring(1) : decimal).split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final sign = negative ? '-' : '';
  if (currency != 'USD') return '$sign$whole ៛';
  final cents = (parts.length > 1 ? parts[1] : '').padRight(2, '0');
  return '$sign\$$whole.${cents.substring(0, 2)}';
}

String walletLabel(BuildContext context, String currency) => currency == 'KHR'
    ? t(context, 'Khmer Riel wallet', 'កាបូបប្រាក់រៀល')
    : t(context, 'US Dollar wallet', 'កាបូបប្រាក់ដុល្លារ');

/// Shop logo, or the shop initial while no logo exists or it cannot load.
class ShopAvatar extends StatelessWidget {
  const ShopAvatar({
    required this.name,
    this.logo,
    this.size = 56,
    this.onDark = false,
    super.key,
  });
  final String name;
  final Uint8List? logo;
  final double size;
  final bool onDark;
  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? 'K'
        : name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark ? AppPalette.gold100 : AppColors.of(context).primary100,
        borderRadius: BorderRadius.circular(size * .3),
        border: Border.all(
          color: onDark ? Colors.white24 : AppPalette.gold400,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: logo != null
          ? Image.memory(
              logo!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              semanticLabel: t(context, 'Shop logo', 'រូបសញ្ញាហាង'),
              errorBuilder: (context, _, _) => _Initial(initial, size),
            )
          : _Initial(initial, size),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial(this.letter, this.size);
  final String letter;
  final double size;
  @override
  Widget build(BuildContext context) => Text(
    letter,
    style: mText(
      context,
      size * .42,
      size * .5,
      weight: FontWeight.w600,
      color: AppPalette.navy700,
    ),
  );
}

class CurrencyBadge extends StatelessWidget {
  const CurrencyBadge(this.currency, {super.key});
  final String currency;
  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: currency == 'KHR' ? AppPalette.gold100 : AppPalette.navy50,
    ),
    alignment: Alignment.center,
    child: Text(
      currency == 'KHR' ? '៛' : r'$',
      style: mText(
        context,
        18,
        22,
        weight: FontWeight.w700,
        color: currency == 'KHR' ? AppPalette.gold700 : AppPalette.navy500,
        // The riel sign is only in the Khmer face; fallback renders it tiny.
      ).copyWith(fontFamily: currency == 'KHR' ? 'Noto Sans Khmer' : null),
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {this.onDark = false, super.key});
  final String status;
  final bool onDark;
  @override
  Widget build(BuildContext context) {
    final (label, foreground, background) = switch (status) {
      'ACTIVE' => (
        t(context, 'Active', 'សកម្ម'),
        AppPalette.semanticSuccess,
        AppPalette.semanticSuccessMuted,
      ),
      'PENDING' => (
        t(context, 'In review', 'កំពុងពិនិត្យ'),
        AppPalette.semanticWarning,
        AppPalette.semanticWarningMuted,
      ),
      'FROZEN' || 'SUSPENDED' => (
        t(context, 'Suspended', 'បានផ្អាក'),
        AppPalette.semanticError,
        AppPalette.semanticErrorMuted,
      ),
      'CLOSED' || 'INACTIVE' => (
        t(context, 'Inactive', 'អសកម្ម'),
        AppPalette.neutralLightDisabledBackground,
        AppPalette.neutralLightDisabled,
      ),
      _ => (
        status,
        AppPalette.semanticWarning,
        AppPalette.semanticWarningMuted,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: mText(
          context,
          12,
          18,
          weight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {this.trailing, super.key});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: mText(
            context,
            16,
            24,
            weight: FontWeight.w600,
            color: merchantNavy(context),
          ),
        ),
      ),
      ?trailing,
    ],
  );
}

/// Bordered surface card used throughout the Customer App.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

class CircleAction extends StatelessWidget {
  const CircleAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      color: colors.foreground,
      style: IconButton.styleFrom(
        fixedSize: const Size(48, 48),
        backgroundColor: colors.surface,
        side: BorderSide(color: colors.border),
      ),
    );
  }
}

class ActionTile extends StatelessWidget {
  const ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
    super.key,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onTap != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = enabled
        ? (highlighted && !dark ? AppPalette.navy500 : merchantNavy(context))
        : colors.disabledBackground;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: highlighted
            ? (dark
                  ? AppPalette.gold700.withValues(alpha: .35)
                  : AppPalette.gold100)
            : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: highlighted ? AppPalette.gold400 : colors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: foreground),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: mText(
                      context,
                      13,
                      20,
                      weight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline notice: info (default), success or error.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner(
    this.message, {
    this.tone = NoticeTone.info,
    this.action,
    super.key,
  });
  final String message;
  final NoticeTone tone;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final (icon, foreground, background) = switch (tone) {
      NoticeTone.success => (
        Icons.check_circle_outline,
        AppPalette.semanticSuccess,
        AppPalette.semanticSuccessMuted,
      ),
      NoticeTone.error => (
        Icons.error_outline,
        AppPalette.semanticError,
        AppPalette.semanticErrorMuted,
      ),
      NoticeTone.warning => (
        Icons.schedule_outlined,
        AppPalette.semanticWarning,
        AppPalette.semanticWarningMuted,
      ),
      NoticeTone.info => (
        Icons.info_outline,
        AppPalette.semanticInfo,
        AppPalette.semanticInfoMuted,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: mText(
                      context,
                      13,
                      20,
                      weight: FontWeight.w500,
                      color: AppPalette.navy700,
                    ),
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerEnd, child: action),
            ],
          ],
        ),
      ),
    );
  }
}

enum NoticeTone { info, success, warning, error }

/// Navy hero card with a faded Kesor mark, matching the Customer balance card.
class NavyCard extends StatelessWidget {
  const NavyCard({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppPalette.navy400, AppPalette.navy500, AppPalette.navy700],
          stops: [0, .45, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -28,
            top: -18,
            child: ExcludeSemantics(
              child: Opacity(
                opacity: .12,
                child: Transform.rotate(
                  angle: -.26,
                  child: SvgPicture.asset(
                    'assets/kesor-logo.svg',
                    package: 'kesor_design_system',
                    width: 132,
                    height: 165,
                    colorFilter: const ColorFilter.mode(
                      AppPalette.gold200,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ],
      ),
    ),
  );
}

/// Localized message for a shop API failure.
String shopFailureMessage(
  BuildContext context,
  ShopFailure failure,
) => switch (failure.code) {
  'OFFLINE' || 'TIMEOUT' => t(
    context,
    'You’re offline. Connect to the internet and try again.',
    'អ្នកគ្មានអ៊ីនធឺណិត។ សូមភ្ជាប់អ៊ីនធឺណិត ហើយព្យាយាមម្ដងទៀត។',
  ),
  'MERCHANT_CATEGORY_INVALID' => t(
    context,
    'Choose a business category.',
    'សូមជ្រើសរើសប្រភេទអាជីវកម្ម។',
  ),
  'MERCHANT_PHONE_INVALID' => t(
    context,
    'Enter a valid business phone number.',
    'សូមបញ្ចូលលេខទូរស័ព្ទអាជីវកម្មដែលត្រឹមត្រូវ។',
  ),
  'MERCHANT_LOGO_INVALID' => t(
    context,
    'That logo could not be used. Choose a JPG or PNG and try again.',
    'មិនអាចប្រើរូបសញ្ញានេះបានទេ។ សូមជ្រើស JPG ឬ PNG ហើយព្យាយាមម្ដងទៀត។',
  ),
  'MERCHANT_LOGO_TOO_LARGE' => t(
    context,
    'Choose a logo smaller than 5 MB.',
    'សូមជ្រើសរូបសញ្ញាតូចជាង ៥ MB។',
  ),
  'MERCHANT_ALREADY_REGISTERED' => t(
    context,
    'Your shop is already registered.',
    'ហាងរបស់អ្នកបានចុះឈ្មោះរួចហើយ។',
  ),
  'MERCHANT_PROFILE_CONFLICT' => t(
    context,
    'Your shop changed on another device. We loaded the latest details.',
    'ហាងរបស់អ្នកត្រូវបានកែនៅឧបករណ៍ផ្សេង។ យើងបានផ្ទុកព័ត៌មានថ្មីបំផុត។',
  ),
  'MERCHANT_INACTIVE' => t(
    context,
    'This shop can’t be changed right now. Contact support.',
    'មិនអាចកែហាងនេះបានទេឥឡូវនេះ។ សូមទាក់ទងផ្នែកគាំទ្រ។',
  ),
  'MERCHANT_AUTH_RATE_LIMITED' => t(
    context,
    'Too many requests. Please wait one minute.',
    'មានសំណើច្រើនពេក។ សូមរង់ចាំមួយនាទី។',
  ),
  'VALIDATION_FAILED' || 'INVALID_REQUEST' => t(
    context,
    'Check the shop details and try again.',
    'សូមពិនិត្យព័ត៌មានហាង ហើយព្យាយាមម្ដងទៀត។',
  ),
  'STORAGE_UNAVAILABLE' => t(
    context,
    'This device couldn’t save your request securely. Nothing was sent.',
    'ឧបករណ៍នេះមិនអាចរក្សាសំណើរបស់អ្នកដោយសុវត្ថិភាពទេ។ គ្មានអ្វីត្រូវបានផ្ញើទេ។',
  ),
  _ => t(
    context,
    'Something went wrong. Please try again.',
    'មានបញ្ហាកើតឡើង។ សូមព្យាយាមម្ដងទៀត។',
  ),
};
