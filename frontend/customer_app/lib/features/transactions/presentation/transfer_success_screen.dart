import 'package:flutter/material.dart';

import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../transfer_models.dart';
import 'transfer_flow_design.dart';

/// Figma 308:740. Rendered exclusively for a durably confirmed successful transfer.
class KesorTransferSuccessScreen extends StatelessWidget {
  const KesorTransferSuccessScreen({
    required this.saved,
    required this.walletName,
    required this.messages,
    required this.onHome,
    required this.onAnother,
    this.completedAt,
    this.showDeviceChrome = false,
    super.key,
  });
  final SavedTransfer saved;
  final String walletName;
  final DateTime? completedAt;
  final Widget messages;
  final VoidCallback? onHome, onAnother;
  final bool showDeviceChrome;

  @override
  Widget build(BuildContext context) {
    final draft = saved.draft;
    final colors = AppColors.of(context), navy = transferNavy(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final date = completedAt?.toLocal();
    final localizations = MaterialLocalizations.of(context);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dateText = date == null
        ? tr(context, 'Unavailable', 'មិនមាន')
        : '${AppPreferences.maybeOf(context)?.isKhmer == true ? localizations.formatMediumDate(date) : '${date.day} ${months[date.month - 1]} ${date.year}'}, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)}';
    Widget rule() => Divider(
      height: 1,
      thickness: 1,
      color: dark ? colors.border : const Color(0xFFEAE4D3),
    );
    Widget detail(
      String label,
      String value, {
      bool muted = false,
      bool copyable = false,
    }) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: transferText(
              context,
              12,
              20,
              color: colors.disabledBackground,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: copyable
              ? SelectableText(
                  value,
                  textAlign: TextAlign.end,
                  style: transferText(context, 12, 20, color: navy),
                )
              : Text(
                  value,
                  textAlign: TextAlign.end,
                  style: transferText(
                    context,
                    12,
                    20,
                    color: muted ? colors.disabledBackground : navy,
                  ),
                ),
        ),
      ],
    );
    return TransferFlowFrame(
      preview: showDeviceChrome,
      success: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showDeviceChrome)
            const TransferStatusBar(success: true)
          else
            SizedBox(height: MediaQuery.paddingOf(context).top),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 14, 32, 24),
            child: Column(
              children: [
                const SizedBox(
                  key: ValueKey('transfer-success-seal'),
                  width: 198,
                  height: 168,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        child: FlowAsset('success-seal.png'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  tr(context, 'Transfer successful', 'ផ្ទេរប្រាក់បានជោគជ័យ'),
                  key: const ValueKey('transfer-success-title'),
                  textAlign: TextAlign.center,
                  style: transferText(
                    context,
                    20,
                    30,
                    weight: FontWeight.w600,
                    color: navy,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    draft.amount.decimal,
                    key: const ValueKey('transfer-success-amount'),
                    style: transferText(
                      context,
                      84,
                      100,
                      weight: FontWeight.w300,
                      color: navy,
                    ).copyWith(letterSpacing: -4),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TransferCurrencyFlag(draft.amount.currency, small: true),
                    Text(
                      tr(
                        context,
                        '${draft.amount.currency} sent successfully',
                        '${draft.amount.currency} បានផ្ញើដោយជោគជ័យ',
                      ),
                      style: transferText(context, 15, 24, color: navy),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Container(
              key: const ValueKey('transfer-success-receipt'),
              decoration: BoxDecoration(
                color: dark ? colors.surface : colors.background,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.gold700.withValues(alpha: .14),
                    offset: const Offset(0, 8),
                    blurRadius: 28,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  tr(
                                    context,
                                    'Transfer details',
                                    'ព័ត៌មានលម្អិតការផ្ទេរ',
                                  ),
                                  style: transferText(
                                    context,
                                    12,
                                    20,
                                    color: navy,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const FlowAsset('status-point.svg'),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        tr(context, 'Completed', 'បានបញ្ចប់'),
                                        style: transferText(
                                          context,
                                          12,
                                          20,
                                          color: dark
                                              ? AppPalette.gold200
                                              : AppPalette.gold700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Image.asset(
                            'assets/transfer/receipt-perforation.png',
                            height: 1,
                            fit: BoxFit.fill,
                            excludeFromSemantics: true,
                          ),
                          const SizedBox(height: 16),
                          TransferPartyDetails(
                            draft: draft,
                            walletName: walletName,
                            receipt: true,
                          ),
                          const SizedBox(height: 16),
                          rule(),
                          const SizedBox(height: 16),
                          detail(
                            tr(
                              context,
                              'Date & time',
                              'កាលបរិច្ឆេទ និងពេលវេលា',
                            ),
                            dateText,
                          ),
                          const SizedBox(height: 16),
                          detail(
                            tr(context, 'Reference', 'លេខយោង'),
                            saved.reference!,
                            copyable: true,
                          ),
                          const SizedBox(height: 16),
                          rule(),
                          const SizedBox(height: 16),
                          detail(
                            tr(context, 'Remark', 'កំណត់សម្គាល់'),
                            draft.remark ??
                                tr(context, 'Not added', 'មិនបានបន្ថែម'),
                            muted: true,
                          ),
                        ],
                      ),
                    ),
                    const Positioned(
                      left: -6,
                      top: 48,
                      child: FlowAsset('receipt-notch.svg'),
                    ),
                    const Positioned(
                      right: -5,
                      top: 48,
                      child: FlowAsset('receipt-notch.svg'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: messages,
          ),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 8),
        child: Column(
          children: [
            TransferFlowButton(
              key: const ValueKey('transfer-back-home'),
              label: tr(context, 'Back to home', 'ត្រឡប់ទៅទំព័រដើម'),
              onPressed: onHome,
              navy: true,
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('transfer-another'),
              onPressed: onAnother,
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 13,
                ),
                foregroundColor: navy,
                textStyle: transferText(
                  context,
                  14,
                  22,
                  weight: FontWeight.w600,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: Center(child: FlowAsset('another-transfer.svg')),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      tr(
                        context,
                        'Make another transfer',
                        'ធ្វើការផ្ទេរម្ដងទៀត',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TransferSafeBottom(preview: showDeviceChrome, success: true),
          ],
        ),
      ),
    );
  }
}
