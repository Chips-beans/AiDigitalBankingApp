import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import '../../core/merchant_ui.dart';
import 'shop_controller.dart';
import 'merchant_shop.dart';
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

  Future<void> _review() async {
    if (shop?.pending != null) {
      await _submit();
      return;
    }
    FocusScope.of(context).unfocus();
    if (!formKey.currentState!.validate()) return;
    final draft = form.draft(logoId: logoId);
    final category = categoryFor(draft.categoryCode);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(context, 'Review shop', 'ពិនិត្យហាង'),
                  style: mText(context, 20, 27, weight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                QDetail(t(context, 'Shop name', 'ឈ្មោះហាង'), draft.storeName),
                QDetail(
                  t(context, 'Category', 'ប្រភេទ'),
                  category == null
                      ? draft.categoryCode
                      : MerchantStrings.isKhmer(context)
                      ? category.km
                      : category.en,
                ),
                QDetail(t(context, 'Phone', 'ទូរស័ព្ទ'), draft.phone),
                QDetail(t(context, 'City', 'ទីក្រុង'), draft.city),
                QDetail(t(context, 'Address', 'អាសយដ្ឋាន'), draft.address),
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey('register-shop-confirm'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t(context, 'Register shop', 'ចុះឈ្មោះហាង')),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t(context, 'Back to edit', 'ត្រឡប់ទៅកែ')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed == true && mounted) await _submit();
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
        final draft = pending?.draft;
        return Scaffold(
          appBar: merchantAppBar(
            context,
            leading: QBack(onPressed: () => widget.onSignOut()),
            title: Text(
              t(context, 'Register your shop', 'ចុះឈ្មោះហាងរបស់អ្នក'),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Form(
                  key: formKey,
                  child: QStage(
                    footer: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (controller?.submitting == true)
                          const LinearProgressIndicator(),
                        FilledButton(
                          key: const ValueKey('register-shop-submit'),
                          onPressed: busy ? null : _review,
                          child: Text(
                            locked
                                ? t(context, 'Check status', 'ពិនិត្យស្ថានភាព')
                                : t(context, 'Review shop', 'ពិនិត្យហាង'),
                          ),
                        ),
                        if (locked) ...[
                          const SizedBox(height: 8),
                          OutlinedButton(
                            key: const ValueKey('discard-pending-registration'),
                            onPressed: busy ? null : controller.discardPending,
                            child: Text(
                              t(context, 'Discard and edit', 'បោះបង់ ហើយកែ'),
                            ),
                          ),
                        ],
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                        if (locked && draft != null) ...[
                          NoticeBanner(
                            t(
                              context,
                              'We couldn’t confirm your registration. Your details are saved — check the status before trying again.',
                              'យើងមិនអាចបញ្ជាក់ការចុះឈ្មោះបានទេ។ ព័ត៌មានរបស់អ្នកត្រូវបានរក្សាទុក — ពិនិត្យស្ថានភាព មុនព្យាយាមម្ដងទៀត។',
                            ),
                            tone: NoticeTone.warning,
                          ),
                          const SizedBox(height: 20),
                          QGroup(
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        t(
                                          context,
                                          'Saved details',
                                          'ព័ត៌មានបានរក្សាទុក',
                                        ),
                                        style: mText(
                                          context,
                                          14,
                                          22,
                                          weight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      t(context, 'Saved', 'បានរក្សាទុក'),
                                      style: mText(
                                        context,
                                        12,
                                        20,
                                        color: merchantNavy(context),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                QDetail(
                                  t(context, 'Shop name', 'ឈ្មោះហាង'),
                                  draft.storeName,
                                ),
                                QDetail(
                                  t(context, 'Category', 'ប្រភេទ'),
                                  (MerchantStrings.isKhmer(context)
                                          ? categoryFor(draft.categoryCode)?.km
                                          : categoryFor(draft.categoryCode)
                                                ?.en) ??
                                      draft.categoryCode,
                                ),
                                QDetail(
                                  t(context, 'Phone', 'ទូរស័ព្ទ'),
                                  draft.phone,
                                ),
                                QDetail(
                                  t(context, 'City', 'ទីក្រុង'),
                                  draft.city,
                                ),
                                QDetail(
                                  t(context, 'Address', 'អាសយដ្ឋាន'),
                                  draft.address,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            t(
                              context,
                              'We never resend your registration automatically.',
                              'យើងមិនផ្ញើការចុះឈ្មោះម្ដងទៀតដោយស្វ័យប្រវត្តិទេ។',
                            ),
                            style: mText(
                              context,
                              12,
                              20,
                              color: AppColors.of(context).disabledBackground,
                            ),
                          ),
                        ] else ...[
                          LogoEditor(
                            name: form.name.text,
                            logo: logoPreview,
                            busy: controller?.uploadingLogo == true,
                            onPick: controller == null ? null : _pickLogo,
                            onRemove: () => setState(() {
                              logoPreview = null;
                              logoId = null;
                            }),
                          ),
                          const SizedBox(height: 16),
                          if (controller?.failure != null) ...[
                            NoticeBanner(
                              shopFailureMessage(context, controller!.failure!),
                              tone: NoticeTone.error,
                            ),
                            const SizedBox(height: 16),
                          ],
                          ShopFormFields(
                            form: form,
                            enabled: !busy,
                            onChanged: () => setState(() {}),
                          ),
                        ],
                      ],
                    ),
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
