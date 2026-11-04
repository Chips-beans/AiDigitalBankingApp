import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../../core/merchant_strings.dart';
import '../../core/merchant_ui.dart';
import 'merchant_shop.dart';
import 'shop_widgets.dart';

@immutable
class PickedLogo {
  const PickedLogo(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

typedef LogoPicker = Future<PickedLogo?> Function();

/// System file picker limited to JPG/PNG. The server still decodes and bounds it.
Future<PickedLogo?> pickLogoFile() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Images',
        extensions: ['jpg', 'jpeg', 'png'],
        mimeTypes: ['image/jpeg', 'image/png'],
        uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
      ),
    ],
  );
  if (file == null) return null;
  return PickedLogo(await file.readAsBytes(), file.name);
}

/// Cambodia's capital and provinces; the English name is what the server stores.
const cambodiaProvinces = [
  ('Phnom Penh', 'ភ្នំពេញ'),
  ('Banteay Meanchey', 'បន្ទាយមានជ័យ'),
  ('Battambang', 'បាត់ដំបង'),
  ('Kampong Cham', 'កំពង់ចាម'),
  ('Kampong Chhnang', 'កំពង់ឆ្នាំង'),
  ('Kampong Speu', 'កំពង់ស្ពឺ'),
  ('Kampong Thom', 'កំពង់ធំ'),
  ('Kampot', 'កំពត'),
  ('Kandal', 'កណ្ដាល'),
  ('Kep', 'កែប'),
  ('Koh Kong', 'កោះកុង'),
  ('Kratie', 'ក្រចេះ'),
  ('Mondulkiri', 'មណ្ឌលគិរី'),
  ('Oddar Meanchey', 'ឧត្ដរមានជ័យ'),
  ('Pailin', 'ប៉ៃលិន'),
  ('Preah Sihanouk', 'ព្រះសីហនុ'),
  ('Preah Vihear', 'ព្រះវិហារ'),
  ('Prey Veng', 'ព្រៃវែង'),
  ('Pursat', 'ពោធិ៍សាត់'),
  ('Ratanakiri', 'រតនគិរី'),
  ('Siem Reap', 'សៀមរាប'),
  ('Stung Treng', 'ស្ទឹងត្រែង'),
  ('Svay Rieng', 'ស្វាយរៀង'),
  ('Takeo', 'តាកែវ'),
  ('Tbong Khmum', 'ត្បូងឃ្មុំ'),
];

/// Shared fields for registration and profile editing.
class ShopFormController {
  ShopFormController([ShopDetails? shop])
    : name = TextEditingController(text: shop?.storeName ?? ''),
      phone = TextEditingController(text: localPhone(shop?.phone)),
      address = TextEditingController(text: shop?.address ?? ''),
      description = TextEditingController(text: shop?.description ?? ''),
      category = shop?.categoryCode,
      city = shop?.city;

  final TextEditingController name, phone, address, description;
  String? category, city;

  /// Shows Cambodian numbers in their familiar local form.
  static String localPhone(String? e164) {
    if (e164 == null) return '';
    return e164.startsWith('+855') ? '0${e164.substring(4)}' : e164;
  }

  void load(ShopDraft draft) {
    name.text = draft.storeName;
    phone.text = draft.phone;
    address.text = draft.address;
    description.text = draft.description;
    category = draft.categoryCode;
    city = draft.city;
  }

  ShopDraft draft({String? logoId}) => ShopDraft(
    storeName: name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
    categoryCode: category ?? '',
    phone: phone.text.trim(),
    city: city ?? '',
    address: address.text.trim(),
    description: description.text.trim(),
    logoId: logoId,
  );

  void dispose() {
    name.dispose();
    phone.dispose();
    address.dispose();
    description.dispose();
  }
}

String? validatePhone(BuildContext context, String? raw) {
  final value = (raw ?? '').replaceAll(RegExp(r'[\s().-]'), '');
  final ok =
      RegExp(r'^0[1-9][0-9]{7,8}$').hasMatch(value) ||
      RegExp(r'^\+855[1-9][0-9]{7,8}$').hasMatch(value) ||
      (RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value) &&
          !value.startsWith('+855'));
  return ok
      ? null
      : t(
          context,
          'Enter a phone number like 012 345 678',
          'បញ្ចូលលេខទូរស័ព្ទដូចជា ០១២ ៣៤៥ ៦៧៨',
        );
}

class ShopFormFields extends StatefulWidget {
  const ShopFormFields({
    required this.form,
    required this.enabled,
    this.onChanged,
    super.key,
  });
  final ShopFormController form;
  final bool enabled;
  final VoidCallback? onChanged;
  @override
  State<ShopFormFields> createState() => _ShopFormFieldsState();
}

class _ShopFormFieldsState extends State<ShopFormFields> {
  void _changed() {
    setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    final khmer = MerchantStrings.isKhmer(context);
    final provinces = [
      ...cambodiaProvinces,
      // A legacy or previously saved city outside the list stays selectable.
      if (form.city != null && !cambodiaProvinces.any((p) => p.$1 == form.city))
        (form.city!, form.city!),
    ];
    String? required(String? v) =>
        (v ?? '').trim().isEmpty ? t(context, 'Required', 'ត្រូវបំពេញ') : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(t(context, 'Shop name', 'ឈ្មោះហាង')),
        TextFormField(
          key: const ValueKey('shop-name'),
          controller: form.name,
          enabled: widget.enabled,
          maxLength: 150,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _changed(),
          validator: required,
          decoration: InputDecoration(
            hintText: t(context, 'e.g. Sokha Coffee', 'ឧ. កាហ្វេសុខា'),
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        _Label(t(context, 'Business category', 'ប្រភេទអាជីវកម្ម')),
        DropdownButtonFormField<String>(
          key: ValueKey('shop-category-${form.category}'),
          initialValue: form.category,
          icon: const QIcon('f7f78'),
          isExpanded: true,
          onChanged: widget.enabled
              ? (v) {
                  form.category = v;
                  _changed();
                }
              : null,
          validator: (v) => v == null
              ? t(context, 'Choose a category', 'សូមជ្រើសប្រភេទ')
              : null,
          decoration: InputDecoration(
            hintText: t(context, 'Choose a category', 'ជ្រើសប្រភេទ'),
          ),
          items: [
            for (final c in shopCategories)
              DropdownMenuItem(
                value: c.code,
                child: Text(
                  khmer ? c.km : c.en,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _Label(t(context, 'Business phone', 'លេខទូរស័ព្ទអាជីវកម្ម')),
        TextFormField(
          key: const ValueKey('shop-phone'),
          controller: form.phone,
          enabled: widget.enabled,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
            LengthLimitingTextInputFormatter(20),
          ],
          onChanged: (_) => _changed(),
          validator: (v) => validatePhone(context, v),
          decoration: const InputDecoration(hintText: '012 345 678'),
        ),
        const SizedBox(height: 16),
        _Label(t(context, 'City or province', 'ទីក្រុង / ខេត្ត')),
        DropdownButtonFormField<String>(
          key: ValueKey('shop-city-${form.city}'),
          initialValue: form.city,
          icon: const QIcon('f7f78'),
          isExpanded: true,
          menuMaxHeight: 360,
          onChanged: widget.enabled
              ? (v) {
                  form.city = v;
                  _changed();
                }
              : null,
          validator: (v) => v == null
              ? t(
                  context,
                  'Choose a city or province',
                  'សូមជ្រើសទីក្រុង ឬខេត្ត',
                )
              : null,
          decoration: InputDecoration(
            hintText: t(context, 'Choose a location', 'ជ្រើសទីតាំង'),
          ),
          items: [
            for (final p in provinces)
              DropdownMenuItem(
                value: p.$1,
                child: Text(
                  khmer ? p.$2 : p.$1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _Label(t(context, 'Shop address', 'អាសយដ្ឋានហាង')),
        TextFormField(
          key: const ValueKey('shop-address'),
          controller: form.address,
          enabled: widget.enabled,
          maxLength: 255,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => _changed(),
          validator: required,
          decoration: InputDecoration(
            hintText: t(
              context,
              'Street, house number, commune',
              'ផ្លូវ លេខផ្ទះ សង្កាត់',
            ),
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        _Label(t(context, 'Description', 'អំពីហាង (ស្រេចចិត្ត)')),
        TextFormField(
          key: const ValueKey('shop-description'),
          controller: form.description,
          enabled: widget.enabled,
          maxLength: 500,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            counterText: '',
            hintText: t(context, 'Optional', 'អ្នកលក់អ្វី? ម៉ោងបើក?'),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: mText(
        context,
        13,
        18,
        color: AppColors.of(context).disabledBackground,
      ),
    ),
  );
}

/// Inline logo editor shared by registration and shop profile.
class LogoEditor extends StatelessWidget {
  const LogoEditor({
    required this.name,
    required this.logo,
    required this.busy,
    required this.onPick,
    this.onRemove,
    this.editing = false,
    super.key,
  });
  final String name;
  final Uint8List? logo;
  final bool busy, editing;
  final VoidCallback? onPick, onRemove;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Semantics(
        button: true,
        label: t(context, 'Choose shop logo', 'ជ្រើសរូបសញ្ញាហាង'),
        child: InkWell(
          key: const ValueKey('shop-logo-pick'),
          onTap: busy ? null : onPick,
          borderRadius: BorderRadius.circular(16),
          child: ShopAvatar(name: name, logo: logo, size: 56),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 24),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: busy ? null : onPick,
                  child: Text(
                    editing
                        ? t(context, 'Change logo', 'ប្ដូររូបសញ្ញា')
                        : t(context, 'Add a logo', 'បន្ថែមរូបសញ្ញា'),
                    style: mText(context, 15, 24, color: merchantNavy(context)),
                  ),
                ),
                if (editing && logo != null && onRemove != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 24),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: busy ? null : onRemove,
                    child: Text(
                      t(context, 'Remove', 'លុប'),
                      style: mText(
                        context,
                        15,
                        24,
                        color: AppColors.of(context).disabledBackground,
                      ),
                    ),
                  ),
              ],
            ),
            if (!editing) ...[
              const SizedBox(height: 2),
              Text(
                t(
                  context,
                  'Optional · JPG or PNG, up to 5 MB',
                  'ស្រេចចិត្ត · JPG ឬ PNG មិនលើស ៥ MB',
                ),
                style: mText(
                  context,
                  13,
                  18,
                  color: AppColors.of(context).disabledBackground,
                ),
              ),
            ],
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    ],
  );
}
