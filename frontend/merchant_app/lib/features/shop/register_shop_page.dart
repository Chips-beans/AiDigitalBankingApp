import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import 'shop_controller.dart';
import 'shop_form.dart';
import 'shop_widgets.dart';

/// One-time shop registration: one shop, one KHR wallet and one USD wallet.
class RegisterShopPage extends StatefulWidget {
  const RegisterShopPage({
    required this.controller,
    required this.onRegistered,
    required this.onSignOut,
    this.pickLogo = pickLogoFile,
    super.key,
  });
  final ShopController? controller;
  final Future<void> Function() onRegistered;
  final VoidCallback onSignOut;
  final LogoPicker pickLogo;
  @override
  State<RegisterShopPage> createState() => _RegisterShopPageState();
}

class _RegisterShopPageState extends State<RegisterShopPage> {
  final formKey = GlobalKey<FormState>();
  final form = ShopFormController();
  Uint8List? logoPreview;
  String? logoId;
  String? _loadedPending;

  ShopController? get shop => widget.controller;

  @override
  void initState() {
    super.initState();
    shop?.addListener(_syncPending);
    _syncPending(rebuild: false);
  }

  /// Shows the saved, immutable intent exactly as it will be resent.
  void _syncPending({bool rebuild = true}) {
    final pending = shop?.pending;
    if (pending == null) {
      _loadedPending = null;
    } else if (_loadedPending != pending.key) {
      _loadedPending = pending.key;
      form.load(pending.draft);
      logoId = pending.draft.logoId;
      if (rebuild && mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    shop?.removeListener(_syncPending);
    form.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final controller = shop;
    if (controller == null) return;
    final picked = await widget.pickLogo();
    if (picked == null || !mounted) return;
    final id = await controller.stageLogo(picked.bytes, picked.name);
    if (id != null && mounted) {
      setState(() {
        logoPreview = picked.bytes;
        logoId = id;
      });
    }
  }

  Future<void> _submit() async {
    final controller = shop;
    if (controller == null) return;
    FocusScope.of(context).unfocus();
    if (controller.pending == null && !formKey.currentState!.validate()) {
      return;
    }
    final ok = await controller.register(form.draft(logoId: logoId));
    if (!mounted) return;
    if (ok) {
      await widget.onRegistered();
    } else if (controller.failure?.code == 'MERCHANT_LOGO_INVALID') {
      setState(() {
        logoPreview = null;
        logoId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = shop;
    return ListenableBuilder(
      listenable: controller ?? const AlwaysStoppedAnimation(0),
      builder: (context, _) {
        final pending = controller?.pending;
        final busy =
            controller == null ||
            controller.submitting ||
            controller.uploadingLogo ||
            controller.loading;
        final locked = pending != null;
        final colors = AppColors.of(context);
        return Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Form(
                  key: formKey,
                  child: ListView(
                    key: const PageStorageKey('register-shop'),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t(
                                context,
                                'Register your shop',
                                'ចុះឈ្មោះហាងរបស់អ្នក',
                              ),
                              style: mText(
                                context,
                                20,
                                28,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                          CircleAction(
                            tooltip: t(context, 'Sign out', 'ចាកចេញ'),
                            icon: Icons.logout_rounded,
                            onPressed: controller?.submitting == true
                                ? null
                                : widget.onSignOut,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t(
                          context,
                          'Set up your business once. You can edit these details later.',
                          'រៀបចំអាជីវកម្មរបស់អ្នកម្ដង។ អ្នកអាចកែព័ត៌មាននេះពេលក្រោយ។',
                        ),
                        style: mText(
                          context,
                          14,
                          22,
                          color: colors.disabledBackground,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: LogoEditor(
                          name: form.name.text,
                          logo: logoPreview,
                          busy: controller?.uploadingLogo == true,
                          onPick: locked || controller == null
                              ? null
                              : _pickLogo,
                          onRemove: locked
                              ? null
                              : () => setState(() {
                                  logoPreview = null;
                                  logoId = null;
                                }),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (controller == null) ...[
                        NoticeBanner(
                          t(
                            context,
                            'Shop registration is currently unavailable. Please try again later.',
                            'ការចុះឈ្មោះហាងមិនទាន់អាចប្រើបាន។ សូមព្យាយាមម្ដងទៀតនៅពេលក្រោយ។',
                          ),
                          tone: NoticeTone.warning,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (locked) ...[
                        NoticeBanner(
                          controller!.notice == ShopNotice.uncertain
                              ? t(
                                  context,
                                  'We couldn’t confirm your registration. Check its status — your shop will not be created twice.',
                                  'យើងមិនអាចបញ្ជាក់ការចុះឈ្មោះបានទេ។ សូមពិនិត្យស្ថានភាព — ហាងរបស់អ្នកនឹងមិនត្រូវបង្កើតពីរដងទេ។',
                                )
                              : t(
                                  context,
                                  'You have an unfinished registration. Check its status to finish safely.',
                                  'អ្នកមានការចុះឈ្មោះមិនទាន់បញ្ចប់។ សូមពិនិត្យស្ថានភាពដើម្បីបញ្ចប់ដោយសុវត្ថិភាព។',
                                ),
                          tone: NoticeTone.warning,
                          action: TextButton(
                            key: const ValueKey('discard-pending-registration'),
                            onPressed: busy ? null : controller.discardPending,
                            child: Text(
                              t(context, 'Discard and edit', 'បោះបង់ ហើយកែ'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else if (controller?.failure != null) ...[
                        NoticeBanner(
                          shopFailureMessage(context, controller!.failure!),
                          tone: NoticeTone.error,
                        ),
                        const SizedBox(height: 16),
                      ],
                      SurfaceCard(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: ShopFormFields(
                          form: form,
                          enabled: !locked && !busy,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _WalletPreview(),
                      const SizedBox(height: 24),
                      if (controller?.submitting == true) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                      ],
                      FilledButton.icon(
                        key: const ValueKey('register-shop-submit'),
                        onPressed: busy ? null : _submit,
                        icon: Icon(
                          locked ? Icons.sync_rounded : Icons.check_rounded,
                        ),
                        label: Text(
                          locked
                              ? t(
                                  context,
                                  'Check registration status',
                                  'ពិនិត្យស្ថានភាពចុះឈ្មោះ',
                                )
                              : t(context, 'Register shop', 'ចុះឈ្មោះហាង'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t(
                          context,
                          'Your shop uses your Kesor Bank owner account. Your personal name, photo and wallets stay separate.',
                          'ហាងរបស់អ្នកប្រើគណនីម្ចាស់ធនាគារកេសរ។ ឈ្មោះ រូបថត និងកាបូបផ្ទាល់ខ្លួនរបស់អ្នកនៅដាច់ដោយឡែក។',
                        ),
                        textAlign: TextAlign.center,
                        style: mText(
                          context,
                          12,
                          18,
                          color: colors.disabledBackground,
                        ),
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
}

class _WalletPreview extends StatelessWidget {
  const _WalletPreview();
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(t(context, 'Two business wallets', 'កាបូបអាជីវកម្មពីរ')),
        const SizedBox(height: 4),
        Text(
          t(
            context,
            'Created with your shop. Both start at zero and receive your QR payments.',
            'បង្កើតជាមួយហាងរបស់អ្នក។ ទាំងពីរចាប់ផ្ដើមពីសូន្យ ហើយទទួលការទូទាត់ QR។',
          ),
          style: mText(
            context,
            13,
            20,
            color: AppColors.of(context).disabledBackground,
          ),
        ),
        const SizedBox(height: 12),
        for (final currency in const ['KHR', 'USD'])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                CurrencyBadge(currency),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    walletLabel(context, currency),
                    style: mText(context, 14, 22, weight: FontWeight.w500),
                  ),
                ),
                AmountText(
                  shopAmount('0', currency),
                  style: mText(context, 14, 22, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
