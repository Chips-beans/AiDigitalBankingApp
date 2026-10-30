import 'package:flutter/material.dart';

import '../../../app/app_labels.dart';
import '../../../shared/widgets/app_states.dart';
import '../account_gateway.dart';
import '../pair_opening.dart';

class PairOpeningPanel extends StatefulWidget {
  const PairOpeningPanel({
    required this.model,
    required this.legacyPending,
    required this.onOpened,
    super.key,
  });
  final PairOpeningController model;
  final bool legacyPending;
  final VoidCallback onOpened;
  @override
  State<PairOpeningPanel> createState() => _PairOpeningPanelState();
}

class _PairOpeningPanelState extends State<PairOpeningPanel> {
  String type = 'SAVINGS';
  @override
  void initState() {
    super.initState();
    if (!widget.model.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.model.initialize();
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) {
      final model = widget.model, policy = model.policy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tx(context, 'USD and KHR accounts'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (model.busy) const LinearProgressIndicator(),
          if (model.error != null)
            NoticePanel(tx(context, model.error!.message), error: true),
          if (!model.ready)
            TextButton(
              onPressed: model.busy ? null : model.initialize,
              child: Text(tx(context, 'Retry')),
            ),
          if (widget.legacyPending)
            NoticePanel(
              tx(context, 'Review the earlier account-opening request first.'),
              error: true,
            ),
          if (model.pending case final pending?) ...[
            Text(
              tx(
                context,
                '${pending.type[0]}${pending.type.substring(1).toLowerCase()}',
              ),
            ),
            NoticePanel(
              tx(
                context,
                'This request may have completed. Retry uses the original request and cannot create another pair.',
              ),
            ),
            BusyButton(
              label: tx(context, 'Retry this exact opening request'),
              busy: model.busy,
              onPressed: !model.ready || widget.legacyPending
                  ? null
                  : () async {
                      if (await model.retry() && mounted) widget.onOpened();
                    },
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: type,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tx(context, 'Account type'),
              ),
              items: BankAccount.types
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(
                        tx(
                          context,
                          '${value[0]}${value.substring(1).toLowerCase()}',
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: model.busy
                  ? null
                  : (value) => setState(() => type = value!),
            ),
            const SizedBox(height: 24),
            if (policy != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tx(context, 'Opening balances'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(policy.usd.formatted),
                      Text(policy.khr.formatted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (policy.testFundingEnabled)
                NoticePanel(
                  tx(
                    context,
                    'Test funds for non-production transfer testing.',
                  ),
                ),
            ],
            const SizedBox(height: 16),
            BusyButton(
              label: tx(context, 'Confirm open accounts'),
              busy: model.busy,
              onPressed: !model.ready || policy == null || widget.legacyPending
                  ? null
                  : () async {
                      if (await model.open(type) && mounted) widget.onOpened();
                    },
            ),
          ],
        ],
      );
    },
  );
}
