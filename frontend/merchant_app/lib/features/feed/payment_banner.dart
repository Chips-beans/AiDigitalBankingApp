import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_preferences.dart';
import '../../core/merchant_strings.dart';
import '../../core/merchant_ui.dart';
import '../shop/shop_widgets.dart';
import 'payment_feed_controller.dart';

/// Floats the newest payment banner over the shop screens and closes it after a few
/// seconds. It never blocks the screen underneath.
class PaymentBannerHost extends StatelessWidget {
  const PaymentBannerHost({
    required this.controller,
    required this.onOpen,
    required this.child,
    this.visibleFor = const Duration(seconds: 8),
    super.key,
  });
  final PaymentFeedController controller;
  final VoidCallback onOpen;
  final Widget child;
  final Duration visibleFor;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      Positioned(
        top: MediaQuery.paddingOf(context).top + 8,
        left: 16,
        right: 16,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final banner = controller.banner;
            if (banner == null) return const SizedBox.shrink();
            return _Banner(
              key: ValueKey('payment-banner-${banner.sequence}'),
              banner: banner,
              visibleFor: visibleFor,
              onClose: () => controller.dismiss(banner.sequence),
              onOpen: () {
                controller.dismiss(banner.sequence);
                onOpen();
              },
            );
          },
        ),
      ),
    ],
  );
}

/// More > Payment alerts: device-local sound/vibration and an honest scope note.
class PaymentAlertSettings extends StatelessWidget {
  const PaymentAlertSettings({required this.preferences, super.key});
  final MerchantPreferences preferences;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in <(String, String, String, bool, ValueChanged<bool>)>[
          (
            'alert-sound',
            t(context, 'Sound', 'សំឡេង'),
            t(
              context,
              'A short sound for each payment',
              'សំឡេងខ្លីសម្រាប់ការទូទាត់នីមួយៗ',
            ),
            preferences.alertSound,
            preferences.setAlertSound,
          ),
          (
            'alert-vibration',
            t(context, 'Vibration', 'ការញ័រ'),
            t(context, 'Vibrate for each payment', 'ញ័រសម្រាប់ការទូទាត់នីមួយៗ'),
            preferences.alertVibration,
            preferences.setAlertVibration,
          ),
        ])
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.of(context).background,
              border: Border(
                bottom: BorderSide(color: AppColors.of(context).border),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.$2),
                      const SizedBox(height: 2),
                      Text(
                        item.$3,
                        style: mText(
                          context,
                          13,
                          18,
                          color: AppColors.of(context).disabledBackground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Semantics(
                  toggled: item.$4,
                  label: item.$2,
                  child: InkWell(
                    key: ValueKey(item.$1),
                    onTap: () => item.$5(!item.$4),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: item.$4
                            ? const QIcon('c24d4', darkAdaptive: false)
                            : Container(
                                width: 44,
                                height: 26,
                                padding: const EdgeInsets.all(3),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  color: AppColors.of(context)
                                      .disabledBackground,
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: SizedBox(width: 20, height: 20),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        NoticeBanner(
          t(
            context,
            'Alerts work while Kesor Merchant is open. Background notifications are coming later.',
            'ការជូនដំណឹងដំណើរការពេលកម្មវិធី Kesor Merchant បើកនៅឡើយ។ ការជូនដំណឹងផ្ទៃខាងក្រោយនឹងមកនៅពេលក្រោយ។',
          ),
        ),
      ],
    ),
  );
}

String paymentBannerText(BuildContext context, FeedBanner banner) {
  final payments = banner.payments;
  if (payments.length == 1) {
    final payment = payments.first;
    final amount = '+${shopAmount(payment.amount, payment.currency)}';
    return t(
      context,
      '$amount from ${payment.payerName}',
      '$amount ពី ${payment.payerName}',
    );
  }
  return t(
    context,
    '${payments.length} new payments received',
    'បានទទួលការទូទាត់ថ្មី ${payments.length}',
  );
}

class _Banner extends StatefulWidget {
  const _Banner({
    required this.banner,
    required this.visibleFor,
    required this.onClose,
    required this.onOpen,
    super.key,
  });
  final FeedBanner banner;
  final Duration visibleFor;
  final VoidCallback onClose, onOpen;
  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.visibleFor, widget.onClose);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.of(context).background,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppPalette.semanticSuccessMuted,
                    ),
                    child: const QIcon('849ed', darkAdaptive: false),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t(context, 'Payment received', 'បានទទួលការទូទាត់'),
                          style: mText(
                            context,
                            12,
                            18,
                            color: AppColors.of(context).disabledBackground,
                          ),
                        ),
                        AmountText(
                          paymentBannerText(context, widget.banner),
                          key: const ValueKey('payment-banner-text'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: mText(
                            context,
                            15,
                            22,
                            weight: FontWeight.w500,
                            color: AppColors.of(context).foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t(context, 'Dismiss', 'បិទ'),
                    onPressed: widget.onClose,
                    icon: const QIcon('7827e'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
