import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/app_labels.dart';
import '../../../app/design_system/design_system.dart';
import '../../../shared/widgets/figma_presentation.dart';
import '../../accounts/account_gateway.dart';

/// Figma 404:901. Entry only; the transfer host owns review, PIN and recovery.
class QrTransferScreen extends StatelessWidget {
  const QrTransferScreen({
    required this.name,
    required this.destination,
    required this.amount,
    required this.remark,
    required this.account,
    required this.onBack,
    required this.onCurrency,
    required this.onWallet,
    required this.onAmountChanged,
    required this.onRemark,
    required this.onContinue,
    this.photo,
    this.fixed = false,
    this.verifiedShop = false,
    this.message,
    this.showDeviceChrome = false,
    super.key,
  });
  final String name, destination, amount, remark;
  final BankAccount? account;
  final Uint8List? photo;
  final bool fixed, verifiedShop, showDeviceChrome;
  final String? message;
  final VoidCallback onBack, onWallet, onRemark;
  final VoidCallback? onContinue;
  final ValueChanged<String> onCurrency, onAmountChanged;

  static Widget icon(String name, double size) => SvgPicture.asset(
    'assets/transfer/qr-$name.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
  );

  void _key(String key) {
    if (fixed) return;
    var value = amount;
    if (key == 'backspace') {
      if (value.isNotEmpty) value = value.substring(0, value.length - 1);
    } else if (key == '.') {
      if (account?.currency != 'USD' || value.contains('.')) return;
      value = '${value.isEmpty ? '0' : value}.';
    } else {
      if (value.contains('.') && value.split('.').last.length >= 2) return;
      if (value.replaceAll('.', '').length >= 18) return;
      value = value == '0' ? key : '$value$key';
    }
    onAmountChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cream = dark ? AppColors.of(context).background : AppPalette.gold50;
    final ink = dark ? AppPalette.navy100 : AppPalette.navy500;
    final currency = account?.currency ?? 'USD';
    final display = amount.isEmpty
        ? (currency == 'USD' ? '0.00' : '0')
        : amount;
    final balance = account?.balance.formatted ?? '—';
    Widget fitText(
      String text,
      double size, {
      Color? color,
      FontWeight? weight,
    }) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: customerText(
          context,
          size,
          size * 1.5,
          color: color ?? ink,
          weight: weight ?? FontWeight.w400,
        ),
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: cream,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppPalette.navy500,
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440, maxHeight: 957),
              child: LayoutBuilder(
                builder: (context, box) {
                  final bottom = showDeviceChrome
                      ? 32.0
                      : math.max(8.0, MediaQuery.paddingOf(context).bottom);
                  final chrome = showDeviceChrome ? 44.0 : 0.0;
                  final h = box.maxHeight - chrome - bottom;
                  final compact = ((h - 330) / 551).clamp(0.0, 1.0);
                  final short = h < 500;
                  final keyHeight = short
                      ? (h * .055).clamp(16.0, 26.0)
                      : 48 + 8 * compact;
                  final keyGap = short ? 2.0 : 8 * compact;
                  final recipientHeight = short ? 30.0 : 12 + 130 * compact;
                  final navHeight = 48 + 8 * compact;
                  final detailsHeight = math.max(
                    0.0,
                    h -
                        navHeight -
                        recipientHeight -
                        keyHeight * 4 -
                        keyGap * 3 -
                        (62 + 24 * compact),
                  );
                  return MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Column(
                      children: [
                        if (showDeviceChrome)
                          SizedBox(
                            height: 44,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    '9:41',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      for (final height in [
                                        4.0,
                                        6.0,
                                        8.0,
                                        10.0,
                                      ])
                                        Container(
                                          width: 3,
                                          height: height,
                                          margin: const EdgeInsets.only(
                                            right: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              1,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 4),
                                      Container(
                                        width: 24,
                                        height: 12,
                                        padding: const EdgeInsets.all(1.2),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          width: 17,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        SizedBox(
                          height: navHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                IconButton(
                                  key: const ValueKey('qr-transfer-back'),
                                  onPressed: onBack,
                                  tooltip: MaterialLocalizations.of(context)
                                      .backButtonTooltip,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(
                                      alpha: .12,
                                    ),
                                    minimumSize: const Size(48, 48),
                                  ),
                                  icon: icon('back', 22),
                                ),
                                Expanded(
                                  child: Center(
                                    child: fitText(
                                      'Kesor QR',
                                      20,
                                      color: AppPalette.gold500,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 48),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          height: recipientHeight,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      clipBehavior: Clip.antiAlias,
                                      decoration: const BoxDecoration(
                                        color: AppPalette.gold100,
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: photo == null
                                          ? Text(
                                              _initials(name),
                                              style: customerText(
                                                context,
                                                14,
                                                18,
                                                color: AppPalette.navy500,
                                                weight: FontWeight.w500,
                                              ),
                                            )
                                          : Image.memory(
                                              photo!,
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  Text(_initials(name)),
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 290,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: customerText(
                                              context,
                                              20,
                                              30,
                                              color: Colors.white,
                                              weight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            'Kesor Bank · $destination',
                                            style: customerText(
                                              context,
                                              12,
                                              20,
                                              color: Colors.white,
                                            ),
                                          ),
                                          if (verifiedShop)
                                            Text(
                                              key: const ValueKey(
                                                'transfer-verified-shop',
                                              ),
                                              tx(
                                                context,
                                                'Verified Kesor shop',
                                              ),
                                              style: customerText(
                                                context,
                                                12,
                                                20,
                                                color: AppPalette.gold100,
                                              ),
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
                        Expanded(
                          child: Container(
                            key: const ValueKey('qr-transfer-panel'),
                            decoration: BoxDecoration(
                              color: cream,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(32),
                              ),
                            ),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: detailsHeight,
                                  child: detailsHeight < 220
                                      ? _compactDetails(
                                          context,
                                          box.maxWidth - 48,
                                          display,
                                          currency,
                                          balance,
                                          ink,
                                        )
                                      : Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                          ),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.topCenter,
                                            child: SizedBox(
                                              width: box.maxWidth - 48,
                                              height: 349,
                                              child: Column(
                                                children: [
                                                  const SizedBox(height: 24),
                                                  SizedBox(
                                                    height: 44,
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: fitText(
                                                            tx(
                                                              context,
                                                              'Transfer amount',
                                                            ),
                                                            14,
                                                          ),
                                                        ),
                                                        Container(
                                                          decoration: BoxDecoration(
                                                            border: Border.all(
                                                              color: AppPalette
                                                                  .gold200,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  999,
                                                                ),
                                                          ),
                                                          padding:
                                                              const EdgeInsets.all(
                                                                3,
                                                              ),
                                                          child: Row(
                                                            children: [
                                                              for (final cur
                                                                  in [
                                                                    'KHR',
                                                                    'USD',
                                                                  ])
                                                                SizedBox(
                                                                  width: math.min(
                                                                    76,
                                                                    (box.maxWidth -
                                                                            48) *
                                                                        .19,
                                                                  ),
                                                                  height: 36,
                                                                  child: TextButton(
                                                                    key: ValueKey(
                                                                      'qr-currency-$cur',
                                                                    ),
                                                                    onPressed: () =>
                                                                        onCurrency(
                                                                          cur,
                                                                        ),
                                                                    style: TextButton.styleFrom(
                                                                      padding:
                                                                          EdgeInsets
                                                                              .zero,
                                                                      backgroundColor:
                                                                          currency ==
                                                                              cur
                                                                          ? AppPalette.navy500
                                                                          : Colors.transparent,
                                                                      foregroundColor:
                                                                          currency ==
                                                                              cur
                                                                          ? Colors.white
                                                                          : ink,
                                                                    ),
                                                                    child: Text(
                                                                      cur,
                                                                      style: const TextStyle(
                                                                        fontFamily: 'Poppins',
                                                                        fontSize:
                                                                            14,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  SizedBox(
                                                    height: 72,
                                                    child: Center(
                                                      child: FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              currency == 'USD'
                                                                  ? r'$'
                                                                  : '៛',
                                                              style: customerText(
                                                                context,
                                                                28,
                                                                42,
                                                                color: AppPalette
                                                                    .navy400,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            Text(
                                                              display,
                                                              key:
                                                                  const ValueKey(
                                                                    'qr-transfer-amount',
                                                                  ),
                                                              style: customerText(
                                                                context,
                                                                56,
                                                                72,
                                                                color: dark
                                                                    ? Colors
                                                                          .white
                                                                    : AppPalette
                                                                          .navy700,
                                                              ).copyWith(letterSpacing: -2),
                                                            ),
                                                            if (!fixed)
                                                              Container(
                                                                margin:
                                                                    const EdgeInsets.only(
                                                                      left: 4,
                                                                    ),
                                                                width: 2,
                                                                height: 42,
                                                                color: AppPalette
                                                                    .gold500,
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  SizedBox(
                                                    height: 20,
                                                    child: Center(
                                                      child: fitText(
                                                        message ??
                                                            tx(
                                                              context,
                                                              fixed
                                                                  ? 'Fixed QR request'
                                                                  : 'Enter an amount to continue',
                                                            ),
                                                        12,
                                                        color: message == null
                                                            ? AppPalette.navy400
                                                            : Theme.of(context)
                                                                  .colorScheme
                                                                  .error,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 20),
                                                  SizedBox(
                                                    height: 22,
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: fitText(
                                                            tx(
                                                              context,
                                                              'Pay from',
                                                            ),
                                                            14,
                                                          ),
                                                        ),
                                                        Flexible(
                                                          child: fitText(
                                                            '${tx(context, 'Available')}: $balance',
                                                            12,
                                                            color: dark
                                                                ? AppPalette
                                                                      .gold200
                                                                : AppPalette
                                                                      .gold700,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  SizedBox(
                                                    height: 62,
                                                    child: Material(
                                                      color: dark
                                                          ? AppColors.of(
                                                              context,
                                                            ).surface
                                                          : Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              16,
                                                            ),
                                                        side: BorderSide(
                                                          color: AppColors.of(
                                                            context,
                                                          ).border,
                                                        ),
                                                      ),
                                                      child: InkWell(
                                                        key: const ValueKey(
                                                          'qr-wallet-picker',
                                                        ),
                                                        onTap: onWallet,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              16,
                                                            ),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                              ),
                                                          child: Row(
                                                            children: [
                                                              Container(
                                                                width: 40,
                                                                height: 40,
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                      AppPalette
                                                                          .navy50,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        10,
                                                                      ),
                                                                ),
                                                                alignment:
                                                                    Alignment
                                                                        .center,
                                                                child: icon(
                                                                  'wallet',
                                                                  22,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 14,
                                                              ),
                                                              Expanded(
                                                                child: fitText(
                                                                  tx(
                                                                    context,
                                                                    currency == 'USD'
                                                                        ? 'US Dollar Wallet'
                                                                        : 'Khmer Riel Wallet',
                                                                  ),
                                                                  15,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              fitText(
                                                                account == null
                                                                    ? '—'
                                                                    : '•• ${account!.number.substring(math.max(0, account!.number.length - 4))}',
                                                                12,
                                                                color: AppColors.of(
                                                                  context,
                                                                ).disabledBackground,
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              icon(
                                                                'chevron',
                                                                20,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  SizedBox(
                                                    height: 53,
                                                    child: InkWell(
                                                      key: const ValueKey(
                                                        'qr-remark',
                                                      ),
                                                      onTap: onRemark,
                                                      child: Container(
                                                        decoration: BoxDecoration(
                                                          border: Border(
                                                            bottom: BorderSide(
                                                              color:
                                                                  AppColors.of(
                                                                    context,
                                                                  ).border,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Expanded(
                                                              child: fitText(
                                                                remark.isEmpty
                                                                    ? tx(
                                                                        context,
                                                                        'Add a remark',
                                                                      )
                                                                    : remark,
                                                                14,
                                                              ),
                                                            ),
                                                            if (remark.isEmpty)
                                                              fitText(
                                                                tx(
                                                                  context,
                                                                  'Optional',
                                                                ),
                                                                12,
                                                                color: AppColors.of(
                                                                  context,
                                                                ).disabledBackground,
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12 * compact,
                                  ),
                                  child: Column(
                                    children: [
                                      for (var row = 0; row < 4; row++) ...[
                                        if (row > 0) SizedBox(height: keyGap),
                                        Row(
                                          children: [
                                            for (
                                              var col = 0;
                                              col < 3;
                                              col++
                                            ) ...[
                                              if (col > 0)
                                                const SizedBox(width: 8),
                                              Expanded(
                                                child: SizedBox(
                                                  height: keyHeight,
                                                  child: _keyButton(
                                                    context,
                                                    row == 3
                                                        ? [
                                                            '.',
                                                            '0',
                                                            'backspace',
                                                          ][col]
                                                        : '${row * 3 + col + 1}',
                                                    dark,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    8,
                                    24,
                                    0,
                                  ),
                                  child: SizedBox(
                                    width: double.infinity,
                                    height: 54,
                                    child: FilledButton(
                                      key: const ValueKey(
                                        'qr-transfer-continue',
                                      ),
                                      onPressed: onContinue,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppPalette.gold500,
                                        foregroundColor: AppPalette.navy500,
                                        disabledBackgroundColor: const Color(
                                          0xffececf0,
                                        ),
                                        disabledForegroundColor: const Color(
                                          0xff717182,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: fitText(
                                        tx(context, 'Transfer'),
                                        14,
                                        color: onContinue == null
                                            ? const Color(0xff717182)
                                            : AppPalette.navy500,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: bottom,
                                  child: showDeviceChrome
                                      ? Center(
                                          child: Container(
                                            width: 134,
                                            height: 5,
                                            decoration: BoxDecoration(
                                              color: AppPalette.navy500
                                                  .withValues(alpha: .2),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactDetails(
    BuildContext context,
    double width,
    String display,
    String currency,
    String balance,
    Color ink,
  ) {
    Widget text(String value, double size, {Color? color}) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        style: customerText(context, size, size * 1.25, color: color ?? ink),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: width,
          height: 144,
          child: Column(
            children: [
              SizedBox(
                height: 24,
                child: Row(
                  children: [
                    Expanded(child: text(tx(context, 'Transfer amount'), 12)),
                    for (final cur in ['KHR', 'USD'])
                      SizedBox(
                        width: 60,
                        height: 24,
                        child: TextButton(
                          key: ValueKey('qr-currency-$cur'),
                          onPressed: () => onCurrency(cur),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            backgroundColor: cur == currency
                                ? AppPalette.navy500
                                : Colors.transparent,
                          ),
                          child: text(
                            cur,
                            12,
                            color: cur == currency ? Colors.white : ink,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 32,
                child: Center(
                  child: text('${currency == 'USD' ? r'$' : '៛'} $display', 28),
                ),
              ),
              SizedBox(
                height: 14,
                child: Center(
                  child: text(
                    message ??
                        tx(
                          context,
                          fixed
                              ? 'Fixed QR request'
                              : 'Enter an amount to continue',
                        ),
                    11,
                  ),
                ),
              ),
              SizedBox(
                height: 16,
                child: Row(
                  children: [
                    Expanded(child: text(tx(context, 'Pay from'), 11)),
                    text('${tx(context, 'Available')}: $balance', 11),
                  ],
                ),
              ),
              SizedBox(
                height: 32,
                child: Material(
                  color: AppColors.of(context).background,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    key: const ValueKey('qr-wallet-picker'),
                    onTap: onWallet,
                    child: Row(
                      children: [
                        icon('wallet', 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: text(
                            tx(
                              context,
                              currency == 'USD'
                                  ? 'US Dollar Wallet'
                                  : 'Khmer Riel Wallet',
                            ),
                            12,
                          ),
                        ),
                        text(
                          account == null
                              ? '—'
                              : '•• ${account!.number.substring(math.max(0, account!.number.length - 4))}',
                          11,
                        ),
                        icon('chevron', 16),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 26,
                child: InkWell(
                  key: const ValueKey('qr-remark'),
                  onTap: onRemark,
                  child: Row(
                    children: [
                      Expanded(
                        child: text(
                          remark.isEmpty ? tx(context, 'Add a remark') : remark,
                          12,
                        ),
                      ),
                      if (remark.isEmpty) text(tx(context, 'Optional'), 11),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyButton(BuildContext context, String key, bool dark) => Semantics(
    label: key == 'backspace' ? tx(context, 'Delete') : key,
    button: true,
    child: Material(
      color: dark ? AppColors.of(context).surface : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('qr-key-$key'),
        borderRadius: BorderRadius.circular(14),
        onTap: fixed || key == '.' && account?.currency != 'USD'
            ? null
            : () => _key(key),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: key == 'backspace'
                ? icon('backspace', 24)
                : Text(
                    key,
                    style: customerText(
                      context,
                      20,
                      28,
                      color: dark ? AppPalette.navy100 : AppPalette.navy500,
                      weight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
      ),
    ),
  );

  static String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part.characters.first)
      .join()
      .toUpperCase();
}
