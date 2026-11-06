import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_labels.dart';
import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../../../shared/widgets/figma_presentation.dart';
import '../account_gateway.dart';
import 'wallet_accounts_screen.dart' show walletAmount, walletName;

class FigmaWalletCard extends StatelessWidget {
  const FigmaWalletCard({
    required this.account,
    required this.balanceVisible,
    this.onTap,
    super.key,
  });
  final BankAccount account;
  final bool balanceVisible;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final a = account;
    final merchant = a.isMerchant;
    final khr = a.currency == 'KHR';
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('wallet-tile-${a.number}'),
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: khr || merchant
                              ? colors.primary100
                              : (Theme.of(context).brightness == Brightness.dark
                                    ? colors.accent
                                    : AppPalette.navy50),
                        ),
                        child: merchant
                            ? CustomerDesignIcon(
                                '2d9fd',
                                size: 22,
                                color: customerNavy(context),
                              )
                            : Text(
                                khr ? '៛' : r'$',
                                style:
                                    customerText(
                                      context,
                                      22,
                                      28,
                                      color: khr
                                          ? colors.primary700
                                          : customerNavy(context),
                                      weight: FontWeight.w500,
                                    ).copyWith(
                                      fontFamily: khr
                                          ? 'Google Sans'
                                          : 'Poppins',
                                    ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              merchant
                                  ? tr(
                                      context,
                                      'Merchant ${a.currency} Wallet',
                                      'កាបូបអាជីវករ ${a.currency}',
                                    )
                                  : walletName(context, a.currency),
                              style: customerText(
                                context,
                                15,
                                24,
                                color: customerNavy(context),
                              ),
                            ),
                            Text(
                              merchant
                                  ? tr(
                                      context,
                                      'Business funds · ${a.currency}',
                                      'ប្រាក់អាជីវកម្ម · ${a.currency}',
                                    )
                                  : a.currency,
                              style: customerText(
                                context,
                                12,
                                20,
                                color: colors.disabledBackground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      CustomerDesignIcon('b50e3', color: customerNavy(context)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      balanceVisible
                          ? walletAmount(
                              a.balance.minorUnits,
                              a.currency,
                            ).replaceAll(' ៛', '៛')
                          : '••••',
                      key: ValueKey('wallet-balance-${a.number}'),
                      style:
                          customerText(
                            context,
                            32,
                            40,
                            color: customerNavy(context),
                            weight: FontWeight.w500,
                          ).copyWith(
                            fontFamilyFallback: const [
                              'Google Sans',
                              'Noto Sans Khmer',
                            ],
                          ),
                    ),
                  ),
                  Text(
                    a.status == 'ACTIVE'
                        ? tr(
                            context,
                            'Available balance',
                            'សមតុល្យដែលអាចប្រើបាន',
                          )
                        : a.status == 'FROZEN'
                        ? tr(context, 'Frozen', 'បានបង្កក')
                        : tr(context, 'Closed', 'បានបិទ'),
                    style: customerText(
                      context,
                      12,
                      20,
                      color: colors.disabledBackground,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 36),
                    child: Row(
                      children: [
                        Text(
                          tx(context, 'Account'),
                          style: customerText(
                            context,
                            12,
                            20,
                            color: colors.disabledBackground,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _groupAccount(a.number),
                              style: customerText(context, 15, 24),
                            ),
                          ),
                        ),
                        const SizedBox(width: 36),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 14,
              bottom: 14,
              width: 48,
              height: 48,
              child: IconButton(
                tooltip: tr(context, 'Copy account number', 'ចម្លងលេខគណនី'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: a.number));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          tr(
                            context,
                            'Account number copied',
                            'បានចម្លងលេខគណនី',
                          ),
                        ),
                      ),
                    );
                  }
                },
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: CustomerDesignIcon(
                  'e9581',
                  size: 20,
                  color: customerNavy(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _groupAccount(String value) {
  final first = value.substring(0, value.length.clamp(0, 3));
  return [
    first,
    ...RegExp(r'.{1,4}')
        .allMatches(value.substring(first.length))
        .map((m) => m[0]!),
  ].join(' ');
}
