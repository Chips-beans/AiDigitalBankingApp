import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/app_labels.dart';
import '../../../app/design_system/design_system.dart';
import '../../../core/network/api_client.dart';
import '../../../core/platform/image_share.dart';
import '../../../shared/money.dart';
import '../../../shared/widgets/app_states.dart';
import '../../accounts/accounts_controller.dart';
import '../../accounts/account_gateway.dart';
import '../../auth/session_controller.dart';
import '../qr_controller.dart';
import '../qr_gateway.dart';

// Mockup palette (dark "My QR" sheet).
const _sheet = Color(0xFF3B3B3D);
const _surface = Color(0xFF1F1F21);
const _tile = Color(0xFF2A2A2D);
const _muted = Color(0xFFA1A1A6);
const _qrRed = AppPalette.semanticError;

/// "My QR" (user mockup, 31 Oct 2026): a shareable Kesor QR card, optional fixed
/// amount, wallet selection, and Save / Share of the rendered card.
class ReceiveQrPanel extends StatefulWidget {
  const ReceiveQrPanel({
    required this.session,
    required this.gateway,
    required this.accounts,
    this.onPaid,
    this.onClose,
    super.key,
  });
  final SessionController session;
  final QrGateway gateway;
  final AccountsController accounts;
  final Future<void> Function()? onPaid;

  /// Shows the close button; the shell uses it to leave this full-screen page.
  final VoidCallback? onClose;
  @override
  State<ReceiveQrPanel> createState() => _ReceiveQrPanelState();
}

class _ReceiveQrPanelState extends State<ReceiveQrPanel>
    with WidgetsBindingObserver {
  late final QrController model;
  final amount = TextEditingController();
  final cardKey = GlobalKey();
  BankAccount? selected;
  Money? requested;
  String? amountError;
  bool exporting = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model = QrController(widget.session, widget.gateway, onPaid: widget.onPaid);
    selected = widget.accounts.selected?.status == 'ACTIVE'
        ? widget.accounts.selected
        : widget.accounts.accounts
              .where((a) => a.status == 'ACTIVE')
              .firstOrNull;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && selected != null) model.generate(selected!, null);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      model.setVisible(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.dispose();
    amount.dispose();
    super.dispose();
  }

  void _select(BankAccount account) {
    if (model.busy || account.number == selected?.number) return;
    setState(() {
      selected = account;
      requested = null;
      amount.clear();
      amountError = null;
    });
    model.generate(account, null);
  }

  /// Validates the amount for the selected wallet; returns null (and sets the error) if invalid.
  Money? _parseAmount() {
    try {
      final input = amount.text.trim();
      if (!(selected!.currency == 'USD'
              ? RegExp(r'^[0-9]+(?:\.[0-9]{1,2})?$')
              : RegExp(r'^[0-9]+$'))
          .hasMatch(input)) {
        throw const FormatException();
      }
      final money = Money.parse(input, selected!.currency);
      if (money.minorUnits <= BigInt.zero) throw const FormatException();
      return money;
    } catch (_) {
      amountError =
          'Enter a positive amount within the currency precision and supported range.';
      return null;
    }
  }

  Future<void> _enterAmount() async {
    if (selected == null || model.busy) return;
    amountError = null;
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            24 + MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tx(context, 'Request an amount'),
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('qr-request-amount'),
                controller: amount,
                autofocus: true,
                decoration: InputDecoration(
                  labelText:
                      '${tx(context, 'Amount')} (${selected?.currency ?? ''})',
                  errorText: amountError == null
                      ? null
                      : tx(context, amountError!),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('qr-request-create'),
                onPressed: () {
                  if (_parseAmount() == null) {
                    update(() {});
                  } else {
                    Navigator.pop(sheet, true);
                  }
                },
                child: Text(tx(context, 'Create amount request')),
              ),
              if (requested != null)
                TextButton(
                  onPressed: () => Navigator.pop(sheet, false),
                  child: Text(tx(context, 'Remove amount')),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || apply == null || selected == null) return;
    final money = apply ? _parseAmount() : null;
    if (apply && money == null) return;
    setState(() {
      requested = money;
      if (money == null) amount.clear();
    });
    await model.generate(selected!, money);
  }

  Future<ui.Image?> _render() async {
    final boundary =
        cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    return boundary?.toImage(pixelRatio: 3);
  }

  Future<void> _export({required bool share}) async {
    final code = model.code;
    if (code == null || exporting) return;
    setState(() => exporting = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Resolved before any await so no BuildContext is used across async gaps.
    final saved = tx(context, 'Saved to Pictures/Kesor Bank');
    final failed = tx(context, 'The QR image could not be saved or shared.');
    String translate(String message) => tx(context, message);
    try {
      final image = await _render();
      final data = await image?.toByteData(format: ui.ImageByteFormat.png);
      image?.dispose();
      if (data == null) {
        throw const ApiFailure('UNAVAILABLE', 'The QR image could not be prepared.');
      }
      final png = data.buffer.asUint8List();
      final name = 'kesor-qr-${code.currency.toLowerCase()}';
      if (share) {
        await shareImage(png, name, text: 'Scan to pay me with Kesor Bank');
      } else {
        await saveImageToGallery(png, name);
        messenger?.showSnackBar(SnackBar(content: Text(saved)));
      }
    } on ApiFailure catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(translate(e.message))));
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  static String grouped(String number) {
    final head = number.substring(0, number.length.clamp(0, 3));
    final rest = number.substring(head.length);
    final parts = [head];
    for (var i = 0; i < rest.length; i += 4) {
      parts.add(rest.substring(i, (i + 4).clamp(0, rest.length)));
    }
    return parts.join(' ');
  }

  TextStyle _text(double size, {Color color = Colors.white, FontWeight? weight}) =>
      AppTextStyles.of(context).body.copyWith(
        fontSize: size,
        height: 1.4,
        color: color,
        fontWeight: weight,
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, widget.accounts]),
    builder: (context, _) {
      final eligible = widget.accounts.accounts
          .where((a) => a.status == 'ACTIVE')
          .toList();
      final current = eligible
          .where((a) => a.number == selected?.number)
          .firstOrNull;
      final code = current == null ? null : model.code;
      return DefaultTextStyle(
        style: _text(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 20),
            if (eligible.isEmpty)
              NoticePanel(tx(context, 'Open an account before receiving money.'))
            else if (current == null)
              NoticePanel(
                tx(context, 'Choose an active account to receive money.'),
              ),
            if (model.busy) const LinearProgressIndicator(),
            if (model.error != null) ...[
              NoticePanel(tx(context, model.error!.message), error: true),
              TextButton(
                onPressed: model.busy || current == null
                    ? null
                    : () => model.generate(current, requested),
                child: Text(tx(context, 'Retry')),
              ),
            ],
            if (code != null) _card(code),
            if (current != null) ...[
              const SizedBox(height: 12),
              _amountRow(),
            ],
            for (final account in eligible) ...[
              const SizedBox(height: 10),
              _walletRow(account, account.number == current?.number),
            ],
            if (widget.accounts.hasMore)
              TextButton(
                onPressed: widget.accounts.loadingMore
                    ? null
                    : widget.accounts.loadMore,
                child: Text(tx(context, 'Load more accounts')),
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _roundAction(
                  key: const ValueKey('qr-save'),
                  icon: Icons.download_rounded,
                  label: tx(context, 'Save'),
                  onTap: code == null || exporting
                      ? null
                      : () => _export(share: false),
                ),
                const SizedBox(width: 28),
                _roundAction(
                  key: const ValueKey('qr-share'),
                  icon: Icons.share_outlined,
                  label: tx(context, 'Share'),
                  onTap: code == null || exporting
                      ? null
                      : () => _export(share: true),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _header() => Column(
    children: [
      SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              tx(context, 'My QR'),
              style: _text(22, weight: FontWeight.w700),
            ),
            if (widget.onClose != null)
              Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  button: true,
                  label: tx(context, 'Close'),
                  child: Material(
                    color: const Color(0xFF2B2B2D),
                    shape: const CircleBorder(),
                    child: InkWell(
                      key: const ValueKey('qr-close'),
                      customBorder: const CircleBorder(),
                      onTap: widget.onClose,
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Text(
        tx(context, 'Share your QR code to receive money'),
        textAlign: TextAlign.center,
        style: _text(14, color: _muted),
      ),
    ],
  );

  Widget _card(AccountQr code) => RepaintBoundary(
    key: cardKey,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: _surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: _qrRed,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Text(
                tx(context, 'Kesor Bank QR Code'),
                style: _text(18, weight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Text(code.name, style: _text(15, color: _muted)),
            ),
            const Divider(height: 1, color: Color(0x22FFFFFF)),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Semantics(
                  label: tx(context, 'My QR'),
                  image: true,
                  // Dark modules on white keep the code readable by every scanner.
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: LayoutBuilder(
                      builder: (context, box) => QrImageView(
                        data: code.payload,
                        size: box.maxWidth.clamp(140, 250),
                        padding: const EdgeInsets.all(6),
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Column(
                children: [
                  Text(
                    code.amount?.formatted ??
                        '${code.currency} · ${grouped(code.account)}',
                    textAlign: TextAlign.center,
                    style: _text(
                      code.amount == null ? 13 : 20,
                      color: code.amount == null ? _muted : Colors.white,
                      weight: code.amount == null ? null : FontWeight.w600,
                    ),
                  ),
                  if (code.dynamic)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        tx(
                          context,
                          model.isPaid
                              ? 'Payment received'
                              : 'Waiting for payment',
                        ),
                        style: _text(
                          13,
                          color: model.isPaid
                              ? const Color(0xFF34C759)
                              : AppPalette.gold500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _amountRow() => Material(
    color: _tile,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      key: const ValueKey('qr-enter-amount'),
      borderRadius: BorderRadius.circular(16),
      onTap: model.busy ? null : _enterAmount,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            const Icon(Icons.add_circle_outline, color: AppPalette.gold500),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tx(context, 'Enter amount'),
                style: _text(15, color: AppPalette.gold500, weight: FontWeight.w600),
              ),
            ),
            Text(
              requested?.formatted ?? tx(context, 'Optional'),
              style: _text(13, color: _muted),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppPalette.gold500),
          ],
        ),
      ),
    ),
  );

  Widget _walletRow(BankAccount account, bool active) {
    final khr = account.currency == 'KHR';
    return Material(
      color: _tile,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: active ? AppPalette.gold500 : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        key: ValueKey('qr-wallet-${account.number}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => _select(account),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: khr ? AppPalette.gold500 : AppPalette.navy500,
                ),
                child: Text(
                  khr ? '៛' : r'$',
                  style: _text(16, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx(context, khr ? 'KHR Wallet' : 'USD Wallet'),
                      style: _text(15, weight: FontWeight.w600),
                    ),
                    Text(grouped(account.number), style: _text(12, color: _muted)),
                  ],
                ),
              ),
              if (active)
                const Icon(Icons.check_circle, color: AppPalette.gold500),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundAction({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        button: true,
        label: label,
        child: Material(
          color: const Color(0xFF2B2B2D),
          shape: const CircleBorder(),
          child: InkWell(
            key: key,
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                icon,
                color: onTap == null ? Colors.white38 : Colors.white,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: _text(12, color: _muted)),
    ],
  );
}

/// Full-screen dark sheet hosting [ReceiveQrPanel], matching the mockup.
class ReceiveQrScreen extends StatelessWidget {
  const ReceiveQrScreen({required this.panel, super.key});
  final ReceiveQrPanel panel;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _sheet,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: panel,
          ),
        ),
      ),
    ),
  );
}
