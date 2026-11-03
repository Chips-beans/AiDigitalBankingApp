import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import 'merchant_shop.dart';
import 'shop_controller.dart';
import 'shop_form.dart';
import 'shop_widgets.dart';

/// Edits shop identity only. The owner's personal name and photo are never changed.
class ShopProfilePage extends StatefulWidget {
  const ShopProfilePage({
    required this.controller,
    this.pickLogo = pickLogoFile,
    super.key,
  });
  final ShopController controller;
  final LogoPicker pickLogo;
  @override
  State<ShopProfilePage> createState() => _ShopProfilePageState();
}

class _ShopProfilePageState extends State<ShopProfilePage> {
  final formKey = GlobalKey<FormState>();
  late ShopFormController form;
  late ShopDetails base;
  Uint8List? newLogo;
  String? newLogoId;
  bool removeLogo = false;

  ShopController get shop => widget.controller;

  @override
  void initState() {
    super.initState();
    base = shop.shop!;
    form = ShopFormController(base);
    shop.clearNotice();
    shop.addListener(_reloadAfterConflict);
  }

  /// A version conflict reloads the latest details; restart edits from them.
  void _reloadAfterConflict() {
    final latest = shop.shop;
    if (latest == null || latest.version == base.version) return;
    if (shop.notice != ShopNotice.conflict) {
      base = latest;
      return;
    }
    setState(() {
      form.dispose();
      base = latest;
      form = ShopFormController(latest);
      newLogo = null;
      newLogoId = null;
      removeLogo = false;
    });
  }

  @override
  void dispose() {
    shop.removeListener(_reloadAfterConflict);
    form.dispose();
    super.dispose();
  }

  Map<String, Object?> _changes() {
    final draft = form.draft();
    final phone = ShopFormController.localPhone(base.phone);
    return {
      if (draft.storeName != base.storeName) 'storeName': draft.storeName,
      if (draft.categoryCode != (base.categoryCode ?? '') &&
          draft.categoryCode.isNotEmpty)
        'categoryCode': draft.categoryCode,
      if (draft.phone != phone) 'phone': draft.phone,
      if (draft.city != (base.city ?? '') && draft.city.isNotEmpty)
        'city': draft.city,
      if (draft.address != (base.address ?? '')) 'address': draft.address,
      if (draft.description != (base.description ?? ''))
        'description': draft.description,
      if (newLogoId != null) 'stagedLogoId': newLogoId,
      if (removeLogo && newLogoId == null) 'removeLogo': true,
    };
  }

  Future<void> _pickLogo() async {
    final picked = await widget.pickLogo();
    if (picked == null || !mounted) return;
    final id = await shop.stageLogo(picked.bytes, picked.name);
    if (id != null && mounted) {
      setState(() {
        newLogo = picked.bytes;
        newLogoId = id;
        removeLogo = false;
      });
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!formKey.currentState!.validate()) return;
    final changes = _changes();
    if (changes.isEmpty) return;
    final ok = await shop.update(changes);
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t(context, 'Shop updated', 'បានធ្វើបច្ចុប្បន្នភាពហាង')),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: shop,
    builder: (context, _) {
      final colors = AppColors.of(context);
      final busy = shop.submitting || shop.uploadingLogo;
      final editable = base.status == 'ACTIVE' || base.status == 'PENDING';
      final logo = removeLogo ? null : newLogo ?? shop.logoBytes;
      final changed = _changes().isNotEmpty;
      return PopScope(
        canPop: !shop.submitting,
        child: Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Form(
                  key: formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      Row(
                        children: [
                          CircleAction(
                            tooltip: t(context, 'Back', 'ថយក្រោយ'),
                            icon: Icons.arrow_back_rounded,
                            onPressed: shop.submitting
                                ? null
                                : () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              t(context, 'Shop profile', 'ប្រវត្តិរូបហាង'),
                              style: mText(
                                context,
                                20,
                                28,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: LogoEditor(
                          name: form.name.text,
                          logo: logo,
                          busy: shop.uploadingLogo,
                          onPick: editable ? _pickLogo : null,
                          onRemove: editable
                              ? () => setState(() {
                                  newLogo = null;
                                  newLogoId = null;
                                  removeLogo = true;
                                })
                              : null,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!editable) ...[
                        NoticeBanner(
                          t(
                            context,
                            'This shop can’t be changed right now. Contact support.',
                            'មិនអាចកែហាងនេះបានទេឥឡូវនេះ។ សូមទាក់ទងផ្នែកគាំទ្រ។',
                          ),
                          tone: NoticeTone.error,
                        ),
                        const SizedBox(height: 16),
                      ] else if (shop.notice == ShopNotice.conflict ||
                          shop.failure != null) ...[
                        NoticeBanner(
                          shopFailureMessage(
                            context,
                            shop.failure ??
                                const ShopFailure('MERCHANT_PROFILE_CONFLICT'),
                          ),
                          tone: shop.notice == ShopNotice.conflict
                              ? NoticeTone.warning
                              : NoticeTone.error,
                        ),
                        const SizedBox(height: 16),
                      ],
                      SurfaceCard(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: ShopFormFields(
                          key: ValueKey(base.version),
                          form: form,
                          enabled: editable && !busy,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SurfaceCard(
                        child: Row(
                          children: [
                            Icon(
                              Icons.badge_outlined,
                              color: merchantNavy(context),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t(context, 'Merchant ID', 'លេខសម្គាល់ហាង'),
                                    style: mText(
                                      context,
                                      12,
                                      18,
                                      color: colors.disabledBackground,
                                    ),
                                  ),
                                  Text(
                                    base.merchantId,
                                    style: mText(
                                      context,
                                      14,
                                      22,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            StatusChip(base.status),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (shop.submitting) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        key: const ValueKey('save-shop-profile'),
                        onPressed: editable && changed && !busy ? _save : null,
                        child: Text(
                          t(context, 'Save changes', 'រក្សាទុកការផ្លាស់ប្ដូរ'),
                        ),
                      ),
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
