import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_preferences.dart';
import '../../core/merchant_strings.dart';
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
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => Material(
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.border),
        ),
        child: Column(
          children: [
            SwitchListTile(
              key: const ValueKey('alert-sound'),
              secondary: const Icon(Icons.volume_up_outlined),
              title: Text(t(context, 'Sound', 'សំឡេង')),
              value: preferences.alertSound,
              onChanged: preferences.setAlertSound,
            ),
            const Divider(height: 1),
            SwitchListTile(
              key: const ValueKey('alert-vibration'),
              secondary: const Icon(Icons.vibration),
              title: Text(t(context, 'Vibration', 'ការញ័រ')),
              value: preferences.alertVibration,
              onChanged: preferences.setAlertVibration,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                t(
                  context,
                  'Alerts work while Kesor Merchant is open. Background notifications are coming later.',
                  'ការជូនដំណឹងដំណើរការពេលកម្មវិធី Kesor Merchant បើកនៅឡើយ។ ការជូនដំណឹងផ្ទៃខាងក្រោយនឹងមកនៅពេលក្រោយ។',
                ),
                style: mText(context, 12, 18, color: colors.disabledBackground),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
          color: AppPalette.navy500,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppPalette.gold400.withValues(alpha: .5)),
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
                  const Icon(
                    Icons.payments_outlined,
                    color: AppPalette.gold400,
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
                            color: AppPalette.gold400,
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
                            weight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t(context, 'Dismiss', 'បិទ'),
                    onPressed: widget.onClose,
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
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
