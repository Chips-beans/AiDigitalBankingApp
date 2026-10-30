import 'package:flutter/material.dart';

import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../transfer_models.dart';
import '../transfer_support.dart';
import 'transfer_flow_design.dart';

/// Figma 308:269; confirms only the controller's immutable reviewed draft.
class KesorTransferReviewScreen extends StatelessWidget {
  const KesorTransferReviewScreen({
    required this.draft,
    required this.walletName,
    required this.saveFavorite,
    required this.onEdit,
    required this.onConfirm,
    required this.messages,
    required this.busy,
    this.quote,
    this.showDeviceChrome = false,
    super.key,
  });
  final TransferDraft draft;

  /// Server quote; when converted, shows what the receiver will get.
  final TransferQuote? quote;
  final String walletName;
  final bool saveFavorite, busy, showDeviceChrome;
  final VoidCallback? onEdit, onConfirm;
  final Widget messages;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context), navy = transferNavy(context);
    Widget preference(String label, String value) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: transferText(context, 14, 22, color: navy)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: transferText(
              context,
              14,
              22,
              color: colors.disabledBackground,
            ),
          ),
        ),
      ],
    );
    return TransferFlowFrame(
      preview: showDeviceChrome,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TransferFlowHeader(preview: showDeviceChrome, onBack: onEdit),
          Expanded(
            child: Container(
              key: const ValueKey('transfer-review-panel'),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  messages,
                  Text(
                    tr(context, 'Transfer amount', 'ចំនួនទឹកប្រាក់ផ្ទេរ'),
                    textAlign: TextAlign.center,
                    style: transferText(context, 14, 22, color: navy),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    children: [
                      Text(
                        draft.amount.decimal,
                        key: const ValueKey('transfer-review-amount'),
                        style: transferText(
                          context,
                          32,
                          40,
                          weight: FontWeight.w500,
                          color: navy,
                        ),
                      ),
                      TransferCurrencyFlag(draft.amount.currency),
                      Text(
                        draft.amount.currency,
                        style: transferText(context, 14, 22),
                      ),
                    ],
                  ),
                  if (quote?.converted == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      tr(
                        context,
                        'Receiver gets ${quote!.credit.formatted} · Rate 1 USD = 4,000 KHR',
                        'អ្នកទទួលបាន ${quote!.credit.formatted} · អត្រា 1 USD = 4,000 KHR',
                      ),
                      key: const ValueKey('transfer-review-conversion'),
                      textAlign: TextAlign.center,
                      style: transferText(context, 13, 20, color: navy),
                    ),
                  ],
                  const SizedBox(height: 4),
                  SizedBox(
                    key: const ValueKey('transfer-details-heading'),
                    height: MediaQuery.textScalerOf(context).scale(24) > 48
                        ? null
                        : 48,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr(
                              context,
                              'Transfer details',
                              'ព័ត៌មានលម្អិតការផ្ទេរ',
                            ),
                            style: transferText(
                              context,
                              16,
                              24,
                              weight: FontWeight.w500,
                              color: navy,
                            ),
                          ),
                        ),
                        Flexible(
                          fit: FlexFit.tight,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Semantics(
                              button: true,
                              label: tr(
                                context,
                                'Edit transfer',
                                'កែសម្រួលការផ្ទេរ',
                              ),
                              child: TextButton(
                                key: const ValueKey('transfer-edit'),
                                onPressed: onEdit,
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  foregroundColor: navy,
                                  textStyle: transferText(
                                    context,
                                    14,
                                    22,
                                    weight: FontWeight.w500,
                                  ),
                                ),
                                child: Text(
                                  tr(
                                    context,
                                    'Edit details',
                                    'កែសម្រួលព័ត៌មាន',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    key: const ValueKey('transfer-review-accounts'),
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TransferPartyDetails(
                      draft: draft,
                      walletName: walletName,
                    ),
                  ),
                  const SizedBox(height: 16),
                  preference(
                    tr(context, 'Remark', 'កំណត់សម្គាល់'),
                    draft.remark ?? tr(context, 'Not added', 'មិនបានបន្ថែម'),
                  ),
                  const SizedBox(height: 12),
                  preference(
                    tr(
                      context,
                      'Save to Favorites',
                      'រក្សាទុកជាអ្នកទទួលពេញចិត្ត',
                    ),
                    saveFavorite
                        ? tr(context, 'On', 'បើក')
                        : tr(context, 'Off', 'បិទ'),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    key: const ValueKey('transfer-review-reminder'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? colors.accent
                          : AppPalette.navy50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const FlowAsset('review-info.svg'),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tr(
                              context,
                              "Please check the receiver's number and amount before confirming.",
                              'សូមពិនិត្យលេខគណនីអ្នកទទួល និងចំនួនទឹកប្រាក់មុនពេលបញ្ជាក់។',
                            ),
                            style: transferText(context, 12, 18, color: navy),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        child: Column(
          children: [
            TransferFlowButton(
              key: const ValueKey('transfer-confirm'),
              label: tr(
                context,
                'Confirm & send ${draft.amount.decimal} ${draft.amount.currency}',
                'បញ្ជាក់ និងផ្ញើ ${draft.amount.decimal} ${draft.amount.currency}',
              ),
              busy: busy,
              onPressed: onConfirm,
            ),
            const SizedBox(height: 8),
            TransferSafeBottom(preview: showDeviceChrome),
          ],
        ),
      ),
    );
  }
}
