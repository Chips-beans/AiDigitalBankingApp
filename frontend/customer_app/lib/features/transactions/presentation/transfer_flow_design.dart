import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../../../shared/widgets/kesor_layout.dart';
import '../transfer_models.dart';

TextStyle transferText(
  BuildContext context,
  double size,
  double lineHeight, {
  FontWeight weight = FontWeight.w400,
  Color? color,
}) => AppTextStyles.of(context).body.copyWith(
  fontSize: size,
  height: lineHeight / size,
  fontWeight: weight,
  color: color ?? AppColors.of(context).foreground,
  fontFamily: AppPreferences.maybeOf(context)?.isKhmer == true
      ? AppTypography.khmerFamily
      : AppTypography.englishFamily,
  letterSpacing: 0,
);

Color transferNavy(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppPalette.navy100
    : AppPalette.navy500;

/// Figma exports retain their intrinsic root dimensions inside their design slot.
class FlowAsset extends StatelessWidget {
  const FlowAsset(this.name, {super.key});
  final String name;
  static const sizes = {
    'success-seal.png': Size(198, 178.174),
    'success-device-status.svg': Size(75.67, 13),
    'device-status.svg': Size(75.67, 13),
    'status-point.svg': Size(5, 5),
    'receiver.svg': Size(22, 22.005),
    'card.svg': Size(20.4475, 15.7542),
    'receipt-notch.svg': Size(18, 18),
    'another-transfer.svg': Size(10.875, 12.375),
    'review-info.svg': Size(20, 20),
    'review-back.svg': Size(44, 44),
    'emblem-transfer.svg': Size(20.25, 23.25),
  };
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.fromSize(
      size: sizes[name]!,
      child: name.endsWith('.png')
          ? Image.asset(
              'assets/transfer/$name',
              fit: BoxFit.fill,
              excludeFromSemantics: true,
            )
          : SvgPicture.asset(
              'assets/transfer/$name',
              colorFilter:
                  Theme.of(context).brightness == Brightness.dark &&
                      {
                        'receiver.svg',
                        'card.svg',
                        'review-info.svg',
                        'another-transfer.svg',
                        'receipt-notch.svg',
                        'success-device-status.svg',
                      }.contains(name)
                  ? ColorFilter.mode(
                      name == 'receipt-notch.svg'
                          ? AppColors.of(context).background
                          : AppPalette.navy100,
                      BlendMode.srcIn,
                    )
                  : null,
            ),
    ),
  );
}

class TransferCurrencyFlag extends StatelessWidget {
  const TransferCurrencyFlag(this.currency, {this.small = false, super.key});
  final String currency;
  final bool small;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      key: ValueKey('transfer-currency-flag-$currency'),
      width: small ? 22 : 26,
      height: small ? 15 : 18,
      child: SvgPicture.asset(
        currency == 'KHR'
            ? 'assets/transfer/flag-kh.svg'
            : 'assets/transfer/flag-us.svg',
        fit: BoxFit.fill,
        excludeFromSemantics: true,
      ),
    ),
  );
}

class TransferSafeBottom extends StatelessWidget {
  const TransferSafeBottom({
    required this.preview,
    this.success = false,
    super.key,
  });
  final bool preview, success;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: preview ? 20 : math.max(20, MediaQuery.paddingOf(context).bottom),
    child: preview
        ? Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 134,
              height: 5,
              decoration: BoxDecoration(
                color:
                    (success && Theme.of(context).brightness != Brightness.dark
                            ? AppPalette.navy500
                            : AppColors.of(context).foreground)
                        .withValues(alpha: success ? .22 : .2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          )
        : null,
  );
}

class TransferStatusBar extends StatelessWidget {
  const TransferStatusBar({this.success = false, super.key});
  final bool success;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: Padding(
      padding: const EdgeInsets.only(left: 37, right: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '9:41',
            style: transferText(
              context,
              20,
              28,
              weight: FontWeight.w700,
              color: success && Theme.of(context).brightness == Brightness.dark
                  ? AppPalette.navy100
                  : success
                  ? AppPalette.neutralLightForegroundAndBase
                  : Colors.white,
            ),
          ),
          FlowAsset(
            success ? 'success-device-status.svg' : 'device-status.svg',
          ),
        ],
      ),
    ),
  );
}

/// Shared screen frame; actions stay reachable above the native bottom inset.
class TransferFlowFrame extends StatelessWidget {
  const TransferFlowFrame({
    required this.content,
    required this.footer,
    required this.preview,
    this.success = false,
    super.key,
  });
  final Widget content, footer;
  final bool preview, success;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = success
        ? (dark ? colors.background : AppPalette.gold50)
        : AppPalette.navy500;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (success && !dark
                  ? SystemUiOverlayStyle.dark
                  : SystemUiOverlayStyle.light)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: success
                    ? background
                    : colors.background,
                systemNavigationBarIconBrightness: dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
      child: Scaffold(
        backgroundColor: background,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: KesorLayout.frameWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(preview ? 38 : 0),
              child: ColoredBox(
                color: background,
                child: success
                    ? LayoutBuilder(
                        builder: (context, viewport) => SingleChildScrollView(
                          key: const ValueKey('transfer-flow-scroll'),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: viewport.maxHeight,
                            ),
                            child: IntrinsicHeight(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [content, footer],
                              ),
                            ),
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, viewport) =>
                                  SingleChildScrollView(
                                    key: const ValueKey('transfer-flow-scroll'),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: viewport.maxHeight,
                                      ),
                                      child: IntrinsicHeight(child: content),
                                    ),
                                  ),
                            ),
                          ),
                          ColoredBox(
                            color: success ? background : colors.background,
                            child: footer,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TransferFlowHeader extends StatelessWidget {
  const TransferFlowHeader({
    required this.preview,
    required this.onBack,
    super.key,
  });
  final bool preview;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (preview)
        const TransferStatusBar()
      else
        SizedBox(height: MediaQuery.paddingOf(context).top),
      SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: tr(context, 'Back', 'ត្រឡប់ក្រោយ'),
                child: InkWell(
                  key: const ValueKey('transfer-review-back'),
                  onTap: onBack,
                  borderRadius: BorderRadius.circular(24),
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(child: FlowAsset('review-back.svg')),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  tr(context, 'Review transfer', 'ពិនិត្យការផ្ទេរ'),
                  textAlign: TextAlign.center,
                  style: transferText(
                    context,
                    20,
                    28,
                    weight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          children: [
            Container(
              key: const ValueKey('transfer-review-emblem'),
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppPalette.gold100,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 7.875,
                        top: 7.875,
                        child: FlowAsset('emblem-transfer.svg'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr(context, 'Review your transfer', 'ពិនិត្យការផ្ទេររបស់អ្នក'),
              textAlign: TextAlign.center,
              style: transferText(
                context,
                20,
                28,
                weight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                context,
                'Check the details before you send',
                'ពិនិត្យព័ត៌មានមុនពេលផ្ញើ',
              ),
              textAlign: TextAlign.center,
              style: transferText(context, 12, 18, color: Colors.white),
            ),
          ],
        ),
      ),
    ],
  );
}

class TransferPartyDetails extends StatelessWidget {
  const TransferPartyDetails({
    required this.draft,
    required this.walletName,
    this.receipt = false,
    super.key,
  });
  final TransferDraft draft;
  final String walletName;
  final bool receipt;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context), navy = transferNavy(context);
    final hasName = draft.destinationName?.isNotEmpty == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 22,
              height: 24.45,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FlowAsset('receiver.svg'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(context, 'Receive', 'អ្នកទទួល'),
                    style: transferText(
                      context,
                      12,
                      20,
                      color: colors.disabledBackground,
                    ),
                  ),
                  const SizedBox(height: 1),
                  SelectableText(
                    hasName ? draft.destinationName! : draft.destination,
                    key: const ValueKey('transfer-review-recipient'),
                    style: transferText(
                      context,
                      18,
                      28,
                      weight: FontWeight.w500,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    hasName
                        ? draft.destination
                        : tr(context, 'Kesor account', 'គណនី Kesor'),
                    style: transferText(context, 12, 20, color: navy),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: receipt ? 16 : 14),
        if (!receipt) ...[
          Divider(height: 1, thickness: 1, color: colors.border),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: Center(child: FlowAsset('card.svg')),
            ),
            SizedBox(width: receipt ? 14 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(context, 'From account', 'ពីគណនី'),
                    style: transferText(
                      context,
                      12,
                      receipt ? 20 : 18,
                      color: colors.disabledBackground,
                    ),
                  ),
                  SizedBox(height: receipt ? 1 : 2),
                  Text(
                    walletName,
                    style: transferText(
                      context,
                      15,
                      24,
                      color: receipt ? navy : colors.foreground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class TransferFlowButton extends StatelessWidget {
  const TransferFlowButton({
    required this.label,
    required this.onPressed,
    this.navy = false,
    this.busy = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool navy, busy;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      minimumSize: Size(double.infinity, navy ? 56 : 54),
      backgroundColor: navy ? AppPalette.navy500 : AppPalette.gold500,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: transferText(
        context,
        14,
        22,
        weight: navy ? FontWeight.w600 : FontWeight.w500,
      ),
    ),
    child: busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label, textAlign: TextAlign.center),
  );
}
