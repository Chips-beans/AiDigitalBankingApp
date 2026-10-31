import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_preferences.dart';
import '../auth/session_controller.dart';
import 'merchant_approval.dart';

String merchantError(BuildContext context, String? code) => switch (code) {
  'MERCHANT_AUTH_USED' ||
  'MERCHANT_AUTH_DENIED' ||
  'MERCHANT_AUTH_CANCELLED' => tr(
    context,
    'This request is already resolved. Return to Merchant or start a new request there.',
    'សំណើនេះបានបញ្ចប់។ សូមត្រឡប់ទៅ Merchant ឬចាប់ផ្ដើមសំណើថ្មីនៅទីនោះ។',
  ),
  'STORAGE_UNAVAILABLE' => tr(
    context,
    'Secure storage is unavailable. Close the request and try again.',
    'មិនអាចរក្សាទុកដោយសុវត្ថិភាព។ សូមបិទសំណើ ហើយព្យាយាមម្ដងទៀត។',
  ),
  'PIN_INVALID' => tr(
    context,
    'Incorrect PIN. Try again.',
    'លេខ PIN មិនត្រឹមត្រូវ។ សូមព្យាយាមម្ដងទៀត។',
  ),
  'PIN_RECOVERY_REQUIRED' => tr(
    context,
    'Five incorrect attempts. Recover your Customer PIN.',
    'ខុសប្រាំដង។ សូមស្ដារលេខ PIN របស់អ្នក។',
  ),
  'OFFLINE' || 'TIMEOUT' => tr(
    context,
    'Could not confirm the result. Check your connection and reload the request.',
    'មិនអាចបញ្ជាក់លទ្ធផល។ សូមពិនិត្យអ៊ីនធឺណិត ហើយផ្ទុកសំណើឡើងវិញ។',
  ),
  'MERCHANT_AUTH_EXPIRED' => tr(
    context,
    'This request expired. Start again in Kesor Merchant.',
    'សំណើនេះផុតកំណត់។ សូមចាប់ផ្ដើមម្ដងទៀតក្នុង Kesor Merchant។',
  ),
  'MERCHANT_AUTH_RATE_LIMITED' => tr(
    context,
    'Too many requests. Wait one minute before retrying.',
    'មានសំណើច្រើនពេក។ សូមរង់ចាំមួយនាទី។',
  ),
  'PEER_MISSING' => tr(
    context,
    'Install Kesor Merchant on this device to continue.',
    'សូមដំឡើង Kesor Merchant លើឧបករណ៍នេះ។',
  ),
  'HANDOFF_UNAVAILABLE' => tr(
    context,
    'The Merchant app could not be verified or opened.',
    'មិនអាចផ្ទៀងផ្ទាត់ ឬបើកកម្មវិធី Merchant។',
  ),
  _ => tr(
    context,
    'This request could not be confirmed. Reload its status before trying again.',
    'មិនអាចបញ្ជាក់សំណើនេះ។ សូមផ្ទុកស្ថានភាពឡើងវិញមុនព្យាយាមម្ដងទៀត។',
  ),
};

class MerchantApprovalScreen extends StatefulWidget {
  const MerchantApprovalScreen({
    required this.approval,
    required this.session,
    super.key,
  });
  final MerchantApproval approval;
  final SessionController session;
  @override
  State<MerchantApprovalScreen> createState() => _MerchantApprovalScreenState();
}

class _MerchantApprovalScreenState extends State<MerchantApprovalScreen>
    with WidgetsBindingObserver {
  final pin = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_clearPrivate);
  }

  void _clearPrivate() {
    if (widget.session.privacyCovered ||
        widget.session.phase != SessionPhase.signedIn) {
      pin.clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) pin.clear();
  }

  @override
  void dispose() {
    widget.session.removeListener(_clearPrivate);
    WidgetsBinding.instance.removeObserver(this);
    pin.clear();
    pin.dispose();
    super.dispose();
  }

  String t(String en, String km) => tr(context, en, km);
  Future<void> approve() async {
    final digits = pin.text;
    pin.clear();
    FocusScope.of(context).unfocus();
    await widget.approval.decide(pin: digits);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.approval,
    builder: (context, _) {
      final model = widget.approval, details = model.details;
      final name = widget.session.identity?.displayName;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !model.busy) model.discard();
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(t('Approve Merchant sign-in', 'អនុម័តការចូល Merchant')),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Icon(Icons.phonelink_lock_outlined, size: 56),
                    const SizedBox(height: 24),
                    Text(
                      t('Connect Kesor Merchant', 'ភ្ជាប់ Kesor Merchant'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t(
                        'Approve only a sign-in you started on this device. This connects your owner account to the Merchant app.',
                        'អនុម័តតែការចូលដែលអ្នកបានចាប់ផ្ដើមលើឧបករណ៍នេះ។ វាភ្ជាប់គណនីម្ចាស់របស់អ្នកទៅកម្មវិធី Merchant។',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      t('Owner account', 'គណនីម្ចាស់'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      name?.isNotEmpty == true
                          ? name!
                          : widget.session.identity?.username ?? '',
                    ),
                    const SizedBox(height: 20),
                    if (details != null) ...[
                      Text(
                        details['clientName'],
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(details['deviceName']),
                      const SizedBox(height: 8),
                      Text(
                        '${t('Expires', 'ផុតកំណត់')}: ${DateTime.parse(details['expiresAt']).toLocal()}',
                      ),
                      const SizedBox(height: 24),
                      if (details['status'] != 'PENDING')
                        Text(
                          t(
                            'This request is already resolved. Return to Merchant or start a fresh request.',
                            'សំណើនេះបានបញ្ចប់។ សូមត្រឡប់ទៅ Merchant ឬចាប់ផ្ដើមសំណើថ្មី។',
                          ),
                        ),
                    ],
                    if (model.message != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(merchantError(context, model.message)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (model.busy) const LinearProgressIndicator(),
                    if (model.canDecide) ...[
                      TextField(
                        key: const ValueKey('merchant-approval-pin'),
                        controller: pin,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: InputDecoration(
                          helperMaxLines: 3,
                          labelText: t('Customer PIN', 'លេខ PIN អតិថិជន'),
                          helperText: t(
                            'Enter your four-digit PIN to approve this sign-in.',
                            'បញ្ចូលលេខ PIN បួនខ្ទង់ ដើម្បីអនុម័តការចូលនេះ។',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder(
                        valueListenable: pin,
                        builder: (context, value, _) => FilledButton(
                          key: const ValueKey('merchant-approve'),
                          onPressed: value.text.length == 4 ? approve : null,
                          child: Text(t('Approve sign-in', 'អនុម័តការចូល')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: const ValueKey('merchant-deny'),
                        onPressed: () {
                          pin.clear();
                          model.decide();
                        },
                        child: Text(t('Cancel sign-in', 'បោះបង់ការចូល')),
                      ),
                    ],
                    if (model.canReturn)
                      FilledButton(
                        onPressed: model.returnToMerchant,
                        child: Text(
                          t(
                            'Return to Kesor Merchant',
                            'ត្រឡប់ទៅ Kesor Merchant',
                          ),
                        ),
                      ),
                    if (!model.busy && !model.canReturn)
                      TextButton(
                        onPressed: model.loadDetails,
                        child: Text(
                          t('Reload request status', 'ផ្ទុកស្ថានភាពសំណើឡើងវិញ'),
                        ),
                      ),
                    if (!model.busy)
                      TextButton(
                        onPressed: model.discard,
                        child: Text(t('Close request', 'បិទសំណើ')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
