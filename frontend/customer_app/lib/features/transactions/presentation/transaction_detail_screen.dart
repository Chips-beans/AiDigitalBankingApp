import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../../../core/platform/image_share.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/figma_presentation.dart';
import '../../accounts/accounts_controller.dart';
import '../../accounts/presentation/wallet_detail_screen.dart';
import '../../auth/session_controller.dart';
import '../history_controller.dart';

/// Figma 426:993. The receipt overlays the current owned wallet, rather than
/// navigating to a generic form. Closing it restores the originating page.
class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({
    required this.accounts,
    required this.history,
    required this.reference,
    required this.ownerName,
    required this.onBack,
    this.exportImage,
    super.key,
  });
  final AccountsController accounts;
  final HistoryController history;
  final String reference, ownerName;
  final VoidCallback onBack;
  final Future<void> Function(Uint8List png, bool share)? exportImage;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        ExcludeSemantics(
          child: IgnorePointer(
            child: WalletDetailScreen(
              accounts: accounts,
              history: history,
              ownerName: ownerName,
              onBack: onBack,
              onTransaction: (_) {},
              receiptBackdrop: true,
            ),
          ),
        ),
        Positioned.fill(
          child: Material(
            color: AppPalette.navy700.withValues(alpha: .64),
            child: InkWell(
              onTap: onBack,
              excludeFromSemantics: true,
              child: const SizedBox.expand(),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: LayoutBuilder(
              builder: (context, constraints) => ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  maxHeight: math.max(0, constraints.maxHeight - 8),
                ),
                child: TransactionReceiptSheet(
                  key: ValueKey(reference),
                  accounts: accounts,
                  model: history,
                  reference: reference,
                  onClose: onBack,
                  exportImage: exportImage,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class TransactionReceiptSheet extends StatefulWidget {
  const TransactionReceiptSheet({
    required this.accounts,
    required this.model,
    required this.reference,
    required this.onClose,
    this.exportImage,
    super.key,
  });
  final AccountsController accounts;
  final HistoryController model;
  final String reference;
  final VoidCallback onClose;
  final Future<void> Function(Uint8List png, bool share)? exportImage;
  @override
  State<TransactionReceiptSheet> createState() =>
      _TransactionReceiptSheetState();
}

class _TransactionReceiptSheetState extends State<TransactionReceiptSheet> {
  bool expanded = false, exporting = false;
  final receiptKey = GlobalKey();

  bool get current =>
      mounted &&
      widget.model.session.phase == SessionPhase.signedIn &&
      widget.model.detail?.reference == widget.reference;

  Future<void> _export(bool share) async {
    if (!current || exporting) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (widget.exportImage == null && !imageShareSupported) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Saving and sharing are available in the Android app.',
              'ការរក្សាទុក និងចែករំលែកមាននៅក្នុងកម្មវិធី Android។',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => exporting = true);
    ui.Image? image;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!current) return;
      final boundary =
          receiptKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!current || bytes == null) return;
      final png = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      if (widget.exportImage != null) {
        await widget.exportImage!(png, share);
      } else {
        final name =
            'Kesor-receipt-${widget.reference.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.png';
        if (share) {
          await shareImage(png, name, text: 'Kesor Bank transaction receipt');
        } else {
          await saveImageToGallery(png, name);
        }
      }
      if (mounted && current && !share) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Saved to Pictures/Kesor Bank',
                'បានរក្សាទុកក្នុង Pictures/Kesor Bank',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted && current) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'The receipt could not be saved or shared. Please try again.',
                'មិនអាចរក្សាទុក ឬចែករំលែកបង្កាន់ដៃបានទេ។ សូមព្យាយាមម្ដងទៀត។',
              ),
            ),
          ),
        );
      }
    } finally {
      image?.dispose();
      if (mounted) setState(() => exporting = false);
    }
  }

  Widget _rule(String asset) => SizedBox(
    height: 1,
    width: double.infinity,
    child: SvgPicture.asset(
      'assets/wallet-details/$asset.svg',
      fit: BoxFit.fill,
      excludeFromSemantics: true,
    ),
  );

  Widget _detail(String label, String value) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 44),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: customerText(
                context,
                12,
                20,
                color: AppColors.of(context).disabledBackground,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: SelectableText(
              value,
              textAlign: TextAlign.end,
              style: customerText(
                context,
                12,
                20,
                color: customerNavy(context),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final item = widget.model.detail?.reference == widget.reference
        ? widget.model.detail
        : null;
    final number = widget.model.accountNumber;
    final canExport = item != null && !widget.model.detailLoading && !exporting;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      onDismiss: widget.onClose,
      namesRoute: true,
      label: tr(context, 'Transaction details', 'ព័ត៌មានប្រតិបត្តិការ'),
      child: Material(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          key: const ValueKey('receipt-scroll'),
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            math.max(32, MediaQuery.paddingOf(context).bottom + 8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The handle has a full touch target and supports dismissing the sheet.
              GestureDetector(
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 200) widget.onClose();
                },
                child: Semantics(
                  button: true,
                  label: tr(
                    context,
                    'Close transaction details',
                    'បិទព័ត៌មានប្រតិបត្តិការ',
                  ),
                  child: InkWell(
                    onTap: widget.onClose,
                    child: SizedBox(
                      height: 32,
                      child: Align(
                        alignment: const Alignment(0, -.25),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.model.detailLoading) const LinearProgressIndicator(),
              if (widget.model.detailError != null) ...[
                NoticePanel(widget.model.detailError!.message, error: true),
                TextButton(
                  onPressed: () => widget.model.openDetail(widget.reference),
                  child: Text(
                    tr(
                      context,
                      'Retry transaction details',
                      'សាកល្បងព័ត៌មានប្រតិបត្តិការម្ដងទៀត',
                    ),
                  ),
                ),
              ],
              if (item != null && number != null) ...[
                RepaintBoundary(
                  key: receiptKey,
                  child: ColoredBox(
                    color: colors.background,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 64),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colors.primary50,
                                ),
                                child: WalletAsset(
                                  postingMerchant(item)
                                      ? 'f0ee6'
                                      : postingAsset(item),
                                  size: 26,
                                  color: colors.primary700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      postingAmount(
                                        item,
                                        number,
                                        currencyCode: true,
                                      ),
                                      key: const ValueKey('receipt-amount'),
                                      style: customerText(
                                        context,
                                        24,
                                        36,
                                        weight: FontWeight.w600,
                                        color: customerNavy(context),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      postingName(
                                        context,
                                        item,
                                        number,
                                        widget.accounts.accounts,
                                      ),
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
                            ],
                          ),
                        ),
                        if (item.status != 'SUCCESS')
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: NoticePanel(
                              '${tr(context, 'Status', 'ស្ថានភាព')}: ${postingStatus(context, item.status)}',
                              error: item.status == 'FAILED',
                            ),
                          ),
                        const SizedBox(height: 24),
                        _rule('fb2f7'),
                        const SizedBox(height: 11),
                        _detail(
                          tr(context, 'Transaction ID', 'លេខប្រតិបត្តិការ'),
                          item.reference,
                        ),
                        _detail(
                          tr(
                            context,
                            'Transaction date',
                            'កាលបរិច្ឆេទប្រតិបត្តិការ',
                          ),
                          postingDate(context, item.createdAt, time: true),
                        ),
                        _detail(
                          tr(context, 'Original amount', 'ចំនួនទឹកប្រាក់ដើម'),
                          '${item.debit.decimal} ${item.debit.currency}',
                        ),
                        // No approval code is supplied by the banking API.
                        _detail(
                          tr(context, 'Approval code', 'លេខកូដអនុម័ត'),
                          tr(context, 'Unavailable', 'មិនមាន'),
                        ),
                        if (expanded) ...[
                          _detail(
                            tr(context, 'Status', 'ស្ថានភាព'),
                            postingStatus(context, item.status),
                          ),
                          _detail(
                            tr(context, 'Fee', 'ថ្លៃសេវា'),
                            item.fee.formatted,
                          ),
                          _detail(tr(context, 'Type', 'ប្រភេទ'), item.type),
                          if (item.source != null)
                            _detail(
                              tr(context, 'Source account', 'គណនីប្រភព'),
                              item.source!,
                            ),
                          if (item.destination != null)
                            _detail(
                              tr(context, 'Destination account', 'គណនីទទួល'),
                              item.destination!,
                            ),
                          if (item.converted)
                            _detail(
                              tr(
                                context,
                                'Wallet amount',
                                'ចំនួនទឹកប្រាក់ក្នុងកាបូប',
                              ),
                              item.amount.formatted,
                            ),
                          if (item.exchangeRate != null)
                            _detail(
                              tr(context, 'Exchange rate', 'អត្រាប្តូរប្រាក់'),
                              item.exchangeRate!,
                            ),
                          if (item.remark?.isNotEmpty == true)
                            _detail(
                              tr(context, 'Remark', 'កំណត់សម្គាល់'),
                              item.remark!,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('receipt-view-more'),
                    onPressed: () => setState(() => expanded = !expanded),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.primary700,
                      minimumSize: const Size(48, 44),
                      padding: EdgeInsets.zero,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr(
                            context,
                            expanded ? 'View less' : 'View more',
                            expanded ? 'បង្ហាញតិច' : 'បង្ហាញបន្ថែម',
                          ),
                          style: customerText(
                            context,
                            14,
                            22,
                            weight: FontWeight.w600,
                            color: colors.primary700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        RotatedBox(
                          quarterTurns: expanded ? 3 : 1,
                          child: SizedBox(
                            width: 4.39,
                            height: 7.44,
                            child: SvgPicture.asset(
                              'assets/wallet-details/86a2f.svg',
                              colorFilter: ColorFilter.mode(
                                colors.primary700,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (expanded)
                  TextButton(
                    onPressed: () => widget.model.openDetail(widget.reference),
                    child: Text(
                      tr(
                        context,
                        'Refresh transaction details',
                        'ផ្ទុកព័ត៌មានប្រតិបត្តិការឡើងវិញ',
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 4),
              _rule('ccd9c'),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _action(
                      tr(context, 'Share', 'ចែករំលែក'),
                      '8bbd8',
                      canExport ? () => _export(true) : null,
                      true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _action(
                      tr(context, 'Download', 'ទាញយក'),
                      '79db0',
                      canExport ? () => _export(false) : null,
                      false,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(
    String label,
    String asset,
    VoidCallback? onTap,
    bool primary,
  ) {
    final colors = AppColors.of(context);
    final foreground = primary ? Colors.white : colors.primary700;
    return FilledButton(
      key: ValueKey(primary ? 'receipt-share' : 'receipt-download'),
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: primary ? AppPalette.navy500 : colors.primary50,
        foregroundColor: foreground,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          WalletAsset(asset, size: 20, color: foreground),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: customerText(
                context,
                14,
                22,
                weight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
