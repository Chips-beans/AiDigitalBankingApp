import 'package:flutter/material.dart';

import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/copyable_value.dart';
import '../../accounts/accounts_controller.dart';
import '../transfer_controller.dart';
import '../transfer_models.dart';

class TransferPanel extends StatefulWidget {
  const TransferPanel({
    required this.controller,
    required this.accounts,
    required this.enabled,
    super.key,
  });
  final TransferController controller;
  final AccountsController accounts;
  final bool enabled;
  @override
  State<TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends State<TransferPanel> {
  final destination = TextEditingController(),
      amount = TextEditingController(),
      remark = TextEditingController();
  final form = GlobalKey<FormState>();
  final errorFocus = FocusNode();
  @override
  void dispose() {
    destination.dispose();
    amount.dispose();
    remark.dispose();
    errorFocus.dispose();
    super.dispose();
  }

  Widget _summary(TransferDraft draft) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('FROM ACCOUNT'),
          TextFormField(
            key: ValueKey('review-source-${draft.source}'),
            initialValue: draft.source,
            readOnly: true,
            maxLines: null,
          ),
          const SizedBox(height: 16),
          const Text('TO ACCOUNT'),
          TextFormField(
            key: ValueKey('review-destination-${draft.destination}'),
            initialValue: draft.destination,
            readOnly: true,
            maxLines: null,
          ),
          const SizedBox(height: 16),
          Text(
            'Amount: ${draft.amount.formatted}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('Fee: ${draft.amount.currency == 'USD' ? 'USD 0.00' : 'KHR 0'}'),
          Text('Total debit: ${draft.amount.formatted}'),
          if (draft.remark != null) ...[
            const SizedBox(height: 16),
            Text('Remark: ${draft.remark}'),
          ],
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final model = widget.controller;
    final saved = model.saved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.enabled)
          const NoticePanel(
            'Sending transfers is available in the native app with the real API. This preview does not send payments.',
          ),
        if (model.busy)
          const LinearProgressIndicator(
            semanticsLabel: 'Checking transfer safety',
          ),
        if (model.storageError != null) ...[
          NoticePanel(model.storageError!.message, error: true),
          TextButton(
            onPressed: model.busy ? null : model.initialize,
            child: const Text('Retry transfer secure setup'),
          ),
        ],
        if (model.error != null)
          NoticePanel(model.error!.message, error: true, focusNode: errorFocus),
        if (model.refreshError != null)
          NoticePanel(model.refreshError!.message, error: true),
        if (saved != null) ...[
          Text(
            saved.outcome == 'success'
                ? 'Transfer confirmed'
                : saved.outcome == 'rejected'
                ? 'Transfer rejected'
                : 'Transfer outcome unknown',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          _summary(saved.draft),
          if (saved.unresolved) ...[
            const NoticePanel(
              'This transfer may already have completed. Retry sends exactly the same transfer with the original request key. If it was not processed, retry may complete the transfer. A timeout alone does not establish failure.',
            ),
            BusyButton(
              label: 'Retry this exact transfer',
              busy: model.busy,
              onPressed:
                  widget.enabled && model.ready && model.storageError == null
                  ? model.retry
                  : null,
            ),
          ] else ...[
            if (saved.reference != null) ...[
              const Text('TRANSACTION REFERENCE'),
              CopyableValue(saved.reference!),
              const SizedBox(height: 16),
              const Text('Status: SUCCESS'),
            ],
            if (saved.rejectionCode != null)
              NoticePanel(
                'No transfer was posted. ${saved.rejectionCode!.replaceAll('_', ' ')}',
                error: true,
              ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: model.busy || model.storageError != null
                  ? null
                  : () async {
                      await model.dismiss();
                      if (mounted && model.saved == null) {
                        destination.clear();
                        amount.clear();
                        remark.clear();
                      }
                    },
              child: const Text('Done — return to transfer entry'),
            ),
          ],
        ] else if (model.review != null) ...[
          Text(
            'Review transfer',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          _summary(model.review!),
          const NoticePanel(
            'Check the destination account number carefully. Recipient names are not available. Confirm only when these details are correct.',
          ),
          BusyButton(
            label: 'Confirm and send',
            busy: model.busy,
            onPressed:
                widget.enabled && model.ready && model.storageError == null
                ? model.confirm
                : null,
          ),
          TextButton(
            onPressed: model.busy ? null : model.edit,
            child: const Text('Edit transfer'),
          ),
        ] else
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const NoticePanel(
                  'Internal transfers only. Both accounts must use the same currency. The current transfer fee is zero.',
                ),
                if (widget.accounts.accounts.isEmpty)
                  const NoticePanel(
                    'Open an account from Home before making a transfer.',
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'transfer-source-${widget.accounts.selected?.number}',
                    ),
                    initialValue: widget.accounts.selected?.number,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Source account',
                    ),
                    items: widget.accounts.accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.number,
                            child: Text(
                              '${a.type} · ${a.currency} · ${a.number}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: model.busy
                        ? null
                        : (number) => widget.accounts.select(
                            widget.accounts.accounts.firstWhere(
                              (a) => a.number == number,
                            ),
                          ),
                  ),
                if (widget.accounts.hasMore)
                  TextButton(
                    onPressed: widget.accounts.loadingMore
                        ? null
                        : widget.accounts.loadMore,
                    child: const Text('Load more source accounts'),
                  ),
                if (widget.accounts.selected != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Last known balance: ${widget.accounts.selected!.balance.formatted}',
                  ),
                  Text('Status: ${widget.accounts.selected!.status}'),
                ],
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('transfer-destination'),
                  controller: destination,
                  decoration: const InputDecoration(
                    labelText: 'Destination account number',
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !model.busy,
                  textInputAction: TextInputAction.next,
                  validator: (value) =>
                      RegExp(r'^[0-9]{10,20}$').hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Enter 10–20 digits.',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('transfer-amount'),
                  controller: amount,
                  decoration: InputDecoration(
                    labelText:
                        'Amount (${widget.accounts.selected?.currency ?? 'select source'})',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  enabled: !model.busy,
                  textInputAction: TextInputAction.next,
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Enter an amount.'
                      : null,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('transfer-remark'),
                  controller: remark,
                  decoration: const InputDecoration(
                    labelText: 'Remark (optional)',
                  ),
                  maxLength: 255,
                  enabled: !model.busy,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 24),
                BusyButton(
                  label: 'Review transfer',
                  busy: model.busy,
                  onPressed:
                      !widget.enabled ||
                          !model.ready ||
                          model.storageError != null ||
                          widget.accounts.selected == null ||
                          widget.accounts.loadingDetail
                      ? null
                      : () {
                          if (!form.currentState!.validate()) return;
                          if (!model.prepare(
                            widget.accounts.selected!,
                            destination.text,
                            amount.text,
                            remark.text,
                          )) {
                            errorFocus.requestFocus();
                          }
                        },
                ),
              ],
            ),
          ),
      ],
    );
  }
}
