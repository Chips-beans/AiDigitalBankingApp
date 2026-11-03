import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_preferences.dart';
import '../auth/session_controller.dart';
import 'merchant_transfer_approval.dart';

/// Exact server decimal text as the owner will see it on both wallets.
String transferAmount(String decimal, String currency) {
  final parts = decimal.split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  if (currency != 'USD') return '$whole ៛';
  final cents = (parts.length > 1 ? parts[1] : '').padRight(2, '0');
  return '\$$whole.${cents.substring(0, 2)}';
}

String transferError(BuildContext context, String? code) => switch (code) {
  'OWNER_TRANSFER_EXPIRED' => tr(
    context,
    'This transfer request expired. Start again in Kesor Merchant.',
    'សំណើផ្ទេរប្រាក់នេះផុតកំណត់។ សូមចាប់ផ្ដើមម្ដងទៀតក្នុង Kesor Merchant។',
  ),
  'OWNER_TRANSFER_CANCELLED' || 'OWNER_TRANSFER_DENIED' => tr(
    context,
    'This transfer request was closed. Nothing was moved.',
    'សំណើផ្ទេរប្រាក់នេះត្រូវបានបិទ។ គ្មានប្រាក់ត្រូវបានផ្ទេរទេ។',
  ),
  'OWNER_TRANSFER_COMPLETED' => tr(
    context,
    'This transfer was already completed. Open Kesor Merchant to see the receipt.',
    'ការផ្ទេរប្រាក់នេះបានបញ្ចប់រួចហើយ។ សូមបើក Kesor Merchant ដើម្បីមើលបង្កាន់ដៃ។',
  ),
  'OWNER_TRANSFER_FAILED' => tr(
    context,
    'The business wallet balance was not enough. Nothing was moved.',
    'សមតុល្យកាបូបអាជីវកម្មមិនគ្រប់គ្រាន់។ គ្មានប្រាក់ត្រូវបានផ្ទេរទេ។',
  ),
  'MERCHANT_INACTIVE' => tr(
    context,
    'This shop cannot transfer money right now. Nothing was moved.',
    'ហាងនេះមិនអាចផ្ទេរប្រាក់បានពេលនេះទេ។ គ្មានប្រាក់ត្រូវបានផ្ទេរទេ។',
  ),
  'OWNER_TRANSFER_INVALID' => tr(
    context,
    'This transfer request is not valid. Close it and start again in Kesor Merchant.',
    'សំណើផ្ទេរប្រាក់នេះមិនត្រឹមត្រូវ។ សូមបិទ ហើយចាប់ផ្ដើមម្ដងទៀតក្នុង Kesor Merchant។',
  ),
  'OFFLINE' || 'TIMEOUT' => tr(
    context,
    'Could not confirm the result. Reload the request to check whether it went through.',
    'មិនអាចបញ្ជាក់លទ្ធផល។ សូមផ្ទុកសំណើឡើងវិញ ដើម្បីពិនិត្យថាវាបានជោគជ័យឬអត់។',
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
  'STORAGE_UNAVAILABLE' => tr(
    context,
    'Secure storage is unavailable. Close the request and try again.',
    'មិនអាចរក្សាទុកដោយសុវត្ថិភាព។ សូមបិទសំណើ ហើយព្យាយាមម្ដងទៀត។',
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

class MerchantTransferApprovalScreen extends StatefulWidget {
  const MerchantTransferApprovalScreen({
    required this.approval,
    required this.session,
    super.key,
  });
  final MerchantTransferApproval approval;
  final SessionController session;
  @override
  State<MerchantTransferApprovalScreen> createState() =>
      _MerchantTransferApprovalScreenState();
}

class _MerchantTransferApprovalScreenState
    extends State<MerchantTransferApprovalScreen>
    with WidgetsBindingObserver {
  final pin = TextEditingController();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_clearPrivate);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
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
    _tick?.cancel();
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

  String _countdown(Duration left) {
    final minutes = left.inMinutes, seconds = left.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.approval,
    builder: (context, _) {
      final model = widget.approval, details = model.details;
      final theme = Theme.of(context);
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !model.busy) model.discard();
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(t('Approve transfer', 'អនុម័តការផ្ទេរប្រាក់')),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Icon(Icons.swap_horiz_rounded, size: 56),
                    const SizedBox(height: 24),
                    Text(
                      t('Transfer to your wallet', 'ផ្ទេរទៅកាបូបរបស់អ្នក'),
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t(
                        'Approve only a transfer you started in Kesor Merchant on this device.',
                        'អនុម័តតែការផ្ទេរដែលអ្នកបានចាប់ផ្ដើមក្នុង Kesor Merchant លើឧបករណ៍នេះ។',
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (details != null) ...[
                      Text(
                        transferAmount(details['amount'], details['currency']),
                        key: const ValueKey('transfer-amount'),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(t('Shop', 'ហាង'), style: theme.textTheme.labelLarge),
                      Text(details['shopName']),
                      const SizedBox(height: 12),
                      Text(
                        t('From business wallet', 'ពីកាបូបអាជីវកម្ម'),
                        style: theme.textTheme.labelLarge,
                      ),
                      Text(
                        details['sourceAccount'],
                        key: const ValueKey('transfer-source'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t('To your wallet', 'ទៅកាបូបរបស់អ្នក'),
                        style: theme.textTheme.labelLarge,
                      ),
                      Text(
                        details['destinationAccount'],
                        key: const ValueKey('transfer-destination'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${t('Expires in', 'ផុតកំណត់ក្នុង')} '
                        '${_countdown(model.remaining)}',
                        key: const ValueKey('transfer-countdown'),
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (model.message != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(transferError(context, model.message)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (model.outcome == 'FAILED') ...[
                      Text(
                        transferError(context, 'OWNER_TRANSFER_FAILED'),
                        key: const ValueKey('transfer-failed'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (model.busy) const LinearProgressIndicator(),
                    if (model.canDecide) ...[
                      TextField(
                        key: const ValueKey('transfer-pin'),
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
                            'Enter your four-digit PIN to move this exact amount.',
                            'បញ្ចូលលេខ PIN បួនខ្ទង់ ដើម្បីផ្ទេរចំនួនទឹកប្រាក់នេះ។',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder(
                        valueListenable: pin,
                        builder: (context, value, _) => FilledButton(
                          key: const ValueKey('transfer-approve'),
                          onPressed: value.text.length == 4 ? approve : null,
                          child: Text(t('Approve with PIN', 'អនុម័តដោយ PIN')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: const ValueKey('transfer-deny'),
                        onPressed: () {
                          pin.clear();
                          model.decide();
                        },
                        child: Text(t('Decline', 'បដិសេធ')),
                      ),
                    ],
                    if (model.canReturn)
                      FilledButton(
                        key: const ValueKey('transfer-return'),
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
                        key: const ValueKey('transfer-reload'),
                        onPressed: model.loadDetails,
                        child: Text(
                          t('Reload request status', 'ផ្ទុកស្ថានភាពសំណើឡើងវិញ'),
                        ),
                      ),
                    if (!model.busy)
                      TextButton(
                        key: const ValueKey('transfer-close'),
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
