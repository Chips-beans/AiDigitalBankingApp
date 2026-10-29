import 'package:flutter/material.dart';

import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/copyable_value.dart';
import '../../accounts/presentation/accounts_shell.dart' show displayDate;
import '../history_controller.dart';

class HistoryPanel extends StatelessWidget {
  const HistoryPanel(this.model, {required this.onDetail, super.key});
  final HistoryController model;
  final void Function(String reference) onDetail;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (model.accountNumber == null)
        const NoticePanel('Select an account from Home to see activity.')
      else ...[
        const Text('ACCOUNT'),
        CopyableValue(model.accountNumber!),
        const SizedBox(height: 16),
        const Text('Transaction history'),
        if (model.updatedAt != null)
          Text('Last updated ${displayDate(model.updatedAt!)}'),
        if (model.loading)
          const LinearProgressIndicator(semanticsLabel: 'Refreshing history'),
        if (model.error != null) ...[
          NoticePanel(model.error!.message, error: true),
          if (model.items.isNotEmpty)
            const Text('Refresh failed. Showing last known history.'),
        ],
        TextButton(
          onPressed: model.loading ? null : model.refresh,
          child: const Text('Refresh recent activity'),
        ),
        if (!model.loading && model.items.isEmpty && model.error == null)
          const NoticePanel('No activity yet for this account.'),
        for (final item in model.items)
          Card(
            child: InkWell(
              onTap: () => onDetail(item.reference),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${item.direction(model.accountNumber!)} · ${item.status}',
                    ),
                    Text(
                      item.amount.formatted,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(displayDate(item.createdAt)),
                    Text(item.reference),
                    const SizedBox(height: 8),
                    const Text('View transaction details'),
                  ],
                ),
              ),
            ),
          ),
        if (model.hasMore || model.moreLoading)
          TextButton(
            onPressed: model.loading || model.moreLoading
                ? null
                : model.loadMore,
            child: Text(
              model.moreLoading
                  ? 'Loading transactions…'
                  : 'Load more transactions',
            ),
          ),
      ],
    ],
  );
}

class TransactionDetailPanel extends StatelessWidget {
  const TransactionDetailPanel(
    this.model, {
    required this.reference,
    super.key,
  });
  final HistoryController model;
  final String reference;
  @override
  Widget build(BuildContext context) {
    final item = model.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (model.detailLoading)
          const LinearProgressIndicator(
            semanticsLabel: 'Loading transaction details',
          ),
        if (model.detailError != null)
          NoticePanel(model.detailError!.message, error: true),
        if (item != null) ...[
          Text(
            '${item.direction(model.accountNumber!)} · ${item.status}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            item.amount.formatted,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text('Fee: ${item.fee.formatted}'),
          Text('Currency: ${item.amount.currency}'),
          const SizedBox(height: 24),
          const Text('REFERENCE'),
          CopyableValue(item.reference),
          const SizedBox(height: 16),
          Text('Type: ${item.type}'),
          Text('Date: ${displayDate(item.createdAt)}'),
          if (item.source != null) ...[
            const SizedBox(height: 16),
            const Text('SOURCE ACCOUNT'),
            CopyableValue(item.source!),
          ],
          if (item.destination != null) ...[
            const SizedBox(height: 16),
            const Text('DESTINATION ACCOUNT'),
            CopyableValue(item.destination!),
          ],
          if (item.remark != null) ...[
            const SizedBox(height: 16),
            Text('Remark: ${item.remark}'),
          ],
          if (model.detailUpdatedAt != null)
            Text('Last updated ${displayDate(model.detailUpdatedAt!)}'),
        ],
        TextButton(
          onPressed: model.detailLoading
              ? null
              : () => model.openDetail(reference),
          child: const Text('Refresh transaction details'),
        ),
      ],
    );
  }
}
