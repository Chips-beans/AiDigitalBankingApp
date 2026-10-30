import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/app_labels.dart';
import '../../../shared/money.dart';
import '../../../shared/widgets/app_states.dart';
import '../../accounts/accounts_controller.dart';
import '../../accounts/account_gateway.dart';
import '../../auth/session_controller.dart';
import '../qr_controller.dart';
import '../qr_gateway.dart';

class ReceiveQrPanel extends StatefulWidget {
  const ReceiveQrPanel({
    required this.session,
    required this.gateway,
    required this.accounts,
    this.onPaid,
    super.key,
  });
  final SessionController session;
  final QrGateway gateway;
  final AccountsController accounts;
  final Future<void> Function()? onPaid;
  @override
  State<ReceiveQrPanel> createState() => _ReceiveQrPanelState();
}

class _ReceiveQrPanelState extends State<ReceiveQrPanel>
    with WidgetsBindingObserver {
  late final QrController model;
  final amount = TextEditingController();
  BankAccount? selected;
  bool requestAmount = false;
  String? amountError;
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

  Future<void> _generate() async {
    if (selected == null ||
        !widget.accounts.accounts.any(
          (a) => a.number == selected!.number && a.status == 'ACTIVE',
        )) {
      return;
    }
    Money? money;
    if (requestAmount) {
      try {
        final input = amount.text.trim();
        if (!(selected!.currency == 'USD'
                ? RegExp(r'^[0-9]+(?:\.[0-9]{1,2})?$')
                : RegExp(r'^[0-9]+$'))
            .hasMatch(input)) {
          throw const FormatException();
        }
        money = Money.parse(input, selected!.currency);
        if (money.minorUnits <= BigInt.zero) throw const FormatException();
      } catch (_) {
        setState(
          () => amountError = 'Enter a positive amount within the currency precision and supported range.',
        );
        return;
      }
    }
    setState(() => amountError = null);
    await model.generate(selected!, money);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, widget.accounts]),
    builder: (context, _) {
      final eligible = widget.accounts.accounts
          .where((a) => a.status == 'ACTIVE')
          .toList();
      final selectedNumber = eligible.any((a) => a.number == selected?.number)
          ? selected!.number
          : null;
      final code = selectedNumber == null ? null : model.code;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tx(context, 'Receive money'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (widget.accounts.accounts
              .where((a) => a.status == 'ACTIVE')
              .isEmpty)
            NoticePanel(tx(context, 'Open an account before receiving money.'))
          else
            DropdownButtonFormField<String>(
              key: ValueKey('receive-$selectedNumber'),
              initialValue: selectedNumber,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tx(context, 'Choose an account'),
              ),
              items: widget.accounts.accounts
                  .where((a) => a.status == 'ACTIVE')
                  .map(
                    (a) => DropdownMenuItem(
                      value: a.number,
                      child: Text(
                        '${a.currency} · ${a.number}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: model.busy
                  ? null
                  : (number) {
                      setState(() {
                        selected = widget.accounts.accounts.firstWhere(
                          (a) => a.number == number,
                        );
                        requestAmount = false;
                        amount.clear();
                        amountError = null;
                      });
                      model.generate(selected!, null);
                    },
            ),
          if (widget.accounts.hasMore)
            TextButton(
              onPressed: widget.accounts.loadingMore
                  ? null
                  : widget.accounts.loadMore,
              child: Text(tx(context, 'Load more accounts')),
            ),
          const SizedBox(height: 20),
          if (selectedNumber == null && eligible.isNotEmpty)
            NoticePanel(
              tx(context, 'Choose an active account to receive money.'),
            ),
          if (model.busy) const LinearProgressIndicator(),
          if (model.error != null) ...[
            NoticePanel(tx(context, model.error!.message), error: true),
            TextButton(
              onPressed: model.busy ? null : _generate,
              child: Text(tx(context, 'Retry')),
            ),
          ],
          if (code != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      code.name,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      '${code.currency} · ${code.account}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Semantics(
                      label: tx(context, 'My QR'),
                      image: true,
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(16),
                        child: LayoutBuilder(
                          builder: (context, box) => QrImageView(
                            data: code.payload,
                            size: box.maxWidth.clamp(120, 260),
                            padding: const EdgeInsets.all(8),
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
                    const SizedBox(height: 16),
                    Text(
                      code.amount?.formatted ??
                          tx(context, 'Reusable account QR'),
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tx(
                        context,
                        code.dynamic ? 'This amount request can be paid once.' : 'Use this QR to receive Kesor internal transfers.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            if (code.dynamic)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    tx(
                      context,
                      model.isPaid ? 'Payment received' : 'Waiting for payment',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tx(context, 'Request an amount')),
            value: requestAmount,
            onChanged: selectedNumber == null || model.busy
                ? null
                : (value) {
                    setState(() {
                      requestAmount = value;
                      amountError = null;
                    });
                    if (!value) model.generate(selected!, null);
                  },
          ),
          if (requestAmount) ...[
            TextField(
              key: const ValueKey('qr-request-amount'),
              controller: amount,
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
            BusyButton(
              label: tx(context, 'Create amount request'),
              busy: model.busy,
              onPressed: selectedNumber == null ? null : _generate,
            ),
          ],
        ],
      );
    },
  );
}
