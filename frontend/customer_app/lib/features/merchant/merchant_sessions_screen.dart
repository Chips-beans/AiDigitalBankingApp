import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kesor_auth_handoff/kesor_auth_handoff.dart';

import '../../app/app_preferences.dart';
import '../auth/data/auth_gateway.dart';
import '../auth/session_controller.dart';
import 'merchant_approval.dart';
import 'merchant_approval_screen.dart';

class MerchantSessionsScreen extends StatefulWidget {
  const MerchantSessionsScreen({
    required this.session,
    required this.onBack,
    this.api,
    super.key,
  });
  final SessionController session;
  final VoidCallback onBack;
  final HandoffApi? api;
  @override
  State<MerchantSessionsScreen> createState() => _MerchantSessionsScreenState();
}

class _MerchantSessionsScreenState extends State<MerchantSessionsScreen> {
  List<Map<String, dynamic>>? sessions;
  bool busy = false;
  String? message;
  late final HandoffApi? api =
      widget.api ??
      (widget.session.gateway is HttpAuthGateway
          ? HandoffApi(
              (widget.session.gateway as HttpAuthGateway)
                  .client
                  .config
                  .apiBaseUrl,
            )
          : null);
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    if (widget.api == null) api?.client.close();
    super.dispose();
  }

  Future<void> load() async {
    if (busy || api == null) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final data = await widget.session.authorizedRead(
        (access) =>
            api!.request('GET', '/auth/merchant-sessions', access: access),
      );
      if (data is! List ||
          data.any(
            (s) =>
                s is! Map ||
                !attemptId(s['sessionId']) ||
                s['clientName'] is! String ||
                s['deviceName'] is! String,
          )) {
        throw const HandoffFailure('INVALID_RESPONSE');
      }
      if (mounted) {
        setState(
          () =>
              sessions = data.map((s) => Map<String, dynamic>.from(s)).toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = failureCode(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String t(String en, String km) => tr(context, en, km);
  Future<void> revoke(Map<String, dynamic> row) async {
    if (busy || api == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Sign out Merchant?', 'ចាកចេញពី Merchant?')),
        content: Text(
          t(
            'This ends this Merchant session. Your Customer app stays signed in.',
            'វាបញ្ចប់វគ្គ Merchant នេះ។ កម្មវិធីអតិថិជននៅតែចូលប្រើ។',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Cancel', 'បោះបង់')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Sign out', 'ចាកចេញ')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.session.authorizedMutation(
        (access) => api!.request(
          'POST',
          '/auth/merchant-sessions/${row['sessionId']}/revoke',
          access: access,
        ),
      );
      if (mounted) setState(() => sessions?.remove(row));
    } catch (e) {
      if (mounted) setState(() => message = failureCode(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) widget.onBack();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        title: Text(t('Merchant sessions', 'វគ្គប្រើប្រាស់ Merchant')),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  t(
                    'Review Merchant apps connected to your owner account.',
                    'ពិនិត្យកម្មវិធី Merchant ដែលភ្ជាប់ទៅគណនីម្ចាស់របស់អ្នក។',
                  ),
                ),
                const SizedBox(height: 20),
                if (busy) const LinearProgressIndicator(),
                if (message != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(merchantError(context, message)),
                  ),
                if (api == null)
                  Text(
                    t(
                      'Merchant session management is unavailable in this preview.',
                      'មិនអាចគ្រប់គ្រងវគ្គ Merchant ក្នុងការមើលជាមុននេះ។',
                    ),
                  ),
                if (sessions?.isEmpty == true)
                  Text(
                    t(
                      'No active Merchant sessions.',
                      'គ្មានវគ្គ Merchant សកម្ម។',
                    ),
                  ),
                for (final row in sessions ?? <Map<String, dynamic>>[])
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row['clientName'],
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(row['deviceName']),
                          Text(
                            '${t('Connected', 'បានភ្ជាប់')}: ${DateTime.tryParse(row['createdAt'] ?? '')?.toLocal() ?? ''}',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: busy ? null : () => revoke(row),
                            child: Text(
                              t('Sign out Merchant', 'ចាកចេញពី Merchant'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: busy ? null : load,
                  child: Text(t('Refresh', 'ផ្ទុកឡើងវិញ')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
