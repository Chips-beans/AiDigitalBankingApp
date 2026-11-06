import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import 'merchant_strings.dart';

/// Merchant Redesign · Change list, Figma section 363:3084. Merchant-only
/// overrides keep the Customer app's established theme intact.
ThemeData merchantTheme(Brightness brightness, Locale locale) {
  final base = AppTheme.build(brightness, locale: locale);
  final colors = AppColors.forBrightness(brightness);
  final source = AppTypography.forLocale(locale);
  final km = locale.languageCode == 'km';
  TextStyle role(double size, double height, FontWeight weight) =>
      source.body.copyWith(
        fontSize: size,
        height: (km ? height + 6 : height) / size,
        fontWeight: weight,
        color: colors.foreground,
      );
  final type = source.copyWith(
    hero: role(32, 44, FontWeight.w600),
    titleXL: role(24, 36, FontWeight.w500),
    titleL: role(20, 30, FontWeight.w500),
    titleM: role(18, 28, FontWeight.w500),
    body: role(15, 24, FontWeight.w400),
    bodyL: role(15, 24, FontWeight.w400),
    button: role(14, 22, FontWeight.w600),
    caption: role(12, 20, FontWeight.w400),
    micro: role(10, 16, FontWeight.w500),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));
  return base.copyWith(
    extensions: [colors, type],
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xfff8f8ff)
        : colors.background,
    textTheme: type.textTheme.apply(
      bodyColor: colors.foreground,
      displayColor: colors.foreground,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppPalette.navy500,
      foregroundColor: AppPalette.navy50,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      iconTheme: const IconThemeData(color: AppPalette.navy50),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 8,
      toolbarHeight: 68,
      titleTextStyle: type.titleM.copyWith(color: AppPalette.navy50),
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.background,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: type.body.copyWith(color: colors.disabledBackground),
      labelStyle: type.caption.copyWith(color: colors.disabledBackground),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.accent500),
      ),
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        backgroundColor: colors.primary500,
        foregroundColor: Colors.white,
        textStyle: type.button,
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        backgroundColor: colors.surface,
        foregroundColor: colors.foreground,
        side: BorderSide.none,
        textStyle: type.button,
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: brightness == Brightness.dark
            ? colors.accent100
            : colors.accent500,
        textStyle: type.caption.copyWith(fontWeight: FontWeight.w500),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: colors.background,
      selectedColor: AppPalette.navy500,
      side: BorderSide.none,
      showCheckmark: false,
      labelStyle: type.caption.copyWith(fontSize: 13, color: colors.foreground),
      secondaryLabelStyle: type.caption.copyWith(
        fontSize: 13,
        color: AppPalette.navy50,
      ),
      secondarySelectedColor: AppPalette.navy500,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: DividerThemeData(
      color: colors.border,
      space: 1,
      thickness: 1,
    ),
  );
}

/// Downloaded Figma vectors retain their exported dimensions and viewBoxes.
class QIcon extends StatelessWidget {
  const QIcon(this.asset, {this.darkAdaptive = true, super.key});
  final String asset;
  final bool darkAdaptive;
  @override
  Widget build(BuildContext context) {
    Widget svg = SvgPicture.asset(
      figmaAsset(asset),
      colorFilter:
          darkAdaptive && Theme.of(context).brightness == Brightness.dark
          ? ColorFilter.mode(AppColors.of(context).foreground, BlendMode.srcIn)
          : null,
    );
    // Figma places the exported rosettes slightly outside their logical slots.
    final slot = switch (asset) {
      '3633f' => (44.0, 45.2, 44.8512),
      'cf7f4' => (20.0, 21.2, 21.0415),
      '923a9' => (28.0, 29.2, 28.9781),
      _ => (0.0, 0.0, 0.0),
    };
    if (slot.$1 > 0) {
      svg = SizedBox(
        width: slot.$1,
        height: slot.$1,
        child: OverflowBox(maxWidth: slot.$2, maxHeight: slot.$3, child: svg),
      );
    }
    return ExcludeSemantics(child: svg);
  }
}

class QBack extends StatelessWidget {
  const QBack({this.onPressed, super.key});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: t(context, 'Back', 'ថយក្រោយ'),
    style: IconButton.styleFrom(
      backgroundColor: AppPalette.navy400,
      shape: const CircleBorder(),
    ),
    onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
    icon: const ColorFiltered(
      colorFilter: ColorFilter.mode(AppPalette.navy50, BlendMode.srcIn),
      child: QIcon('20fad', darkAdaptive: false),
    ),
  );
}

/// Scrolls the whole flow when the keyboard, landscape or large text needs room;
/// otherwise the final action stays at the bottom of the available stage.
class QStage extends StatelessWidget {
  const QStage({
    required this.child,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 20),
    super.key,
  });
  final Widget child;
  final Widget? footer;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: box.hasBoundedHeight ? box.maxHeight : 0,
          ),
          child: Padding(
            padding: padding,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                child,
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: footer!,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class QPage extends StatelessWidget {
  const QPage({
    required this.title,
    required this.child,
    this.footer,
    this.actions,
    super.key,
  });
  final String title;
  final Widget child;
  final Widget? footer;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: merchantAppBar(
      context,
      leadingWidth: 52,
      leading: const QBack(),
      title: Text(title),
      actions: actions,
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: QStage(footer: footer, child: child),
        ),
      ),
    ),
  );
}

class QGroup extends StatelessWidget {
  const QGroup({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 10),
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.of(context).background,
      border: Border.all(color: AppColors.of(context).border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class QDetail extends StatelessWidget {
  const QDetail(this.label, this.value, {this.valueKey, super.key});
  final String label, value;
  final Key? valueKey;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: mText(
              context,
              12,
              20,
              color: AppColors.of(context).disabledBackground,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            value,
            key: valueKey,
            textAlign: TextAlign.end,
            style: mText(context, 12, 20),
          ),
        ),
      ],
    ),
  );
}

class QStatusIcon extends StatelessWidget {
  const QStatusIcon(this.asset, {this.tone = 'info', super.key});
  final String asset, tone;
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 84,
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (tone) {
          'success' => AppPalette.semanticSuccessMuted,
          'error' => AppPalette.semanticErrorMuted,
          'warning' => AppPalette.semanticWarningMuted,
          _ => AppPalette.gold100,
        },
      ),
      child: QIcon(asset, darkAdaptive: tone == 'info'),
    ),
  );
}

class QSegments<T> extends StatelessWidget {
  const QSegments({
    required this.values,
    required this.labels,
    required this.value,
    required this.onChanged,
    this.compact = false,
    super.key,
  });
  final List<T> values;
  final List<String> labels;
  final T value;
  final ValueChanged<T> onChanged;
  final bool compact;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
      Widget item(int i) => Semantics(
        selected: values[i] == value,
        button: true,
        child: Material(
          color: values[i] == value
              ? AppColors.of(context).background
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => onChanged(values[i]),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                labels[i],
                textAlign: TextAlign.center,
                style: mText(
                  context,
                  14,
                  22,
                  weight: values[i] == value
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: values[i] == value
                      ? AppColors.of(context).foreground
                      : AppColors.of(context).disabledBackground,
                ),
              ),
            ),
          ),
        ),
      );
      final wrap =
          box.hasBoundedWidth && box.maxWidth < values.length * 72 * scale;
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.light
              ? const Color(0xffececf0)
              : AppColors.of(context).surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: wrap
            ? Wrap(
                spacing: 2,
                runSpacing: 4,
                children: [for (var i = 0; i < values.length; i++) item(i)],
              )
            : Row(
                mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  for (var i = 0; i < values.length; i++)
                    if (compact) item(i) else Expanded(child: item(i)),
                ],
              ),
      );
    },
  );
}

class QNumberPad extends StatelessWidget {
  const QNumberPad({
    required this.controller,
    this.decimal = true,
    this.onChanged,
    super.key,
  });
  final TextEditingController controller;
  final bool decimal;
  final VoidCallback? onChanged;
  void enter(String key) {
    var text = controller.text;
    if (key == 'back') {
      if (text.isNotEmpty) text = text.substring(0, text.length - 1);
    } else if (key == '.') {
      if (!decimal || text.contains('.')) return;
      text = text.isEmpty ? '0.' : '$text.';
    } else {
      if (text.length >= 16 ||
          (text.contains('.') && text.split('.').last.length >= 2)) {
        return;
      }
      text = text == '0' ? key : '$text$key';
    }
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.of(context).background,
    child: Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['.', '0', 'back'],
        ])
          Row(
            children: [
              for (final key in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: SizedBox(
                      height:
                          MediaQuery.textScalerOf(context)
                              .scale(35)
                              .clamp(40.0, double.infinity) +
                          16,
                      child: TextButton(
                        onPressed: key == '.' && !decimal
                            ? null
                            : () => enter(key),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.of(context).foreground,
                          backgroundColor: Theme.of(context)
                              .scaffoldBackgroundColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: mText(
                            context,
                            20,
                            30,
                            weight: FontWeight.w600,
                          ),
                        ),
                        child: key == 'back'
                            ? Semantics(
                                label: t(context, 'Delete digit', 'លុបលេខ'),
                                child: const QIcon('f6dae'),
                              )
                            : Text(key),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}

/// Raw decimal text remains unchanged for validation and requests. Grouping is
/// presentation only; the keypad is the editor, so there is no grouped caret.
class QMoneyController extends TextEditingController {
  String get grouped =>
      text.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => TextSpan(text: grouped, style: style);
}

class QAmountField extends StatelessWidget {
  const QAmountField({
    required this.controller,
    required this.currency,
    required this.fieldKey,
    this.error,
    this.onChanged,
    super.key,
  });
  final QMoneyController controller;
  final String currency;
  final Key fieldKey;
  final String? error;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, value, _) => LayoutBuilder(
          builder: (context, box) {
            final style = mText(context, 40, 56, weight: FontWeight.w600);
            final hint = currency == 'USD' ? '0.00' : '0';
            final painter = TextPainter(
              text: TextSpan(
                text: controller.text.isEmpty ? hint : controller.grouped,
                style: style,
              ),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final signStyle = currency == 'USD'
                ? style
                : mText(
                    context,
                    26,
                    35,
                  ).copyWith(fontFamily: 'Noto Sans Khmer');
            final signPainter = TextPainter(
              text: TextSpan(
                text: currency == 'USD' ? r'$' : '៛',
                style: signStyle,
              ),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (currency == 'USD') Text(r'$', style: style),
                Flexible(
                  child: SizedBox(
                    width: (painter.width + 12).clamp(
                      1,
                      (box.maxWidth - signPainter.width).clamp(1, box.maxWidth),
                    ),
                    child: TextField(
                      key: fieldKey,
                      controller: controller,
                      keyboardType: TextInputType.none,
                      enableInteractiveSelection: false,
                      showCursor: false,
                      textAlign: TextAlign.center,
                      style: style,
                      onChanged: onChanged,
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: style,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        semanticCounterText: t(
                          context,
                          'Amount',
                          'ចំនួនទឹកប្រាក់',
                        ),
                      ),
                    ),
                  ),
                ),
                if (currency == 'KHR')
                  Text(
                    '៛',
                    style: mText(
                      context,
                      26,
                      35,
                    ).copyWith(fontFamily: 'Noto Sans Khmer'),
                  ),
              ],
            );
          },
        ),
      ),
      if (error != null)
        Text(
          error!,
          style: mText(context, 13, 18, color: AppColors.of(context).error),
        ),
    ],
  );
}

class QMenuRow extends StatelessWidget {
  const QMenuRow({
    required this.label,
    required this.asset,
    required this.onTap,
    this.value,
    this.destructive = false,
    this.divider = true,
    super.key,
  });
  final String label, asset;
  final String? value;
  final VoidCallback onTap;
  final bool destructive, divider;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.of(context).background,
      border: Border.all(color: AppColors.of(context).border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 16),
        child: Row(
          children: [
            if (destructive && Theme.of(context).brightness == Brightness.dark)
              ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  AppPalette.semanticErrorMuted,
                  BlendMode.srcIn,
                ),
                child: QIcon(asset, darkAdaptive: false),
              )
            else
              QIcon(asset, darkAdaptive: !destructive),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: mText(
                  context,
                  15,
                  24,
                  color: destructive
                      ? (Theme.of(context).brightness == Brightness.dark
                            ? AppPalette.semanticErrorMuted
                            : AppColors.of(context).error)
                      : null,
                ),
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value!,
                  textAlign: TextAlign.end,
                  style: mText(
                    context,
                    13,
                    18,
                    color: AppColors.of(context).disabledBackground,
                  ),
                ),
              ),
            ],
            if (!destructive) ...[
              const SizedBox(width: 8),
              const QIcon('5a018'),
            ],
          ],
        ),
      ),
    ),
  );
}

String figmaAsset(String asset) => switch (asset) {
  'form-phone' => 'assets/figma-change/3b1cc.svg',
  'form-pin' => 'assets/figma-change/e09b9.svg',
  'form-camera' => 'assets/figma-change/a87b9.svg',
  'alert-sound' => 'assets/figma-change/068a0.svg',
  'alert-vibration' => 'assets/figma-change/a0058.svg',
  'a83fb' => 'assets/figma-change/a83fb.svg',
  '156fc' => 'assets/figma-change/60b00.svg',
  'd8c8d' => 'assets/figma-change/d8c8d.svg',
  '20fad' => 'assets/figma-change/0ebe3.svg',
  'c0d59' => 'assets/figma-change/01600.svg',
  '00600' => 'assets/figma-change/075a7.svg',
  'f7f78' => 'assets/figma-change/38515.svg',
  'a9d14' => 'assets/figma-change/075a7.svg',
  '19f2d' => 'assets/figma-change/98773.svg',
  'f6e9c' => 'assets/figma-change/f3cd5.svg',
  'ff372' => 'assets/figma-change/ff372.svg',
  '56124' => 'assets/figma-change/88a91.svg',
  'cbe0a' => 'assets/figma-change/075a7.svg',
  '6e46a' => 'assets/figma-change/875aa.svg',
  '4a0ca' => 'assets/figma-change/58636.svg',
  '8d19a' => 'assets/figma-change/629f4.svg',
  '5bdf3' => 'assets/figma-change/154a9.svg',
  'cc139' => 'assets/figma-change/ddcdc.svg',
  '5e757' => 'assets/figma-change/60b00.svg',
  '8b848' => 'assets/figma-change/2d864.svg',
  'dc524' => 'assets/figma-change/36347.svg',
  '58f29' => 'assets/figma-change/59c8e.svg',
  '875aa' => 'assets/figma-change/875aa.svg',
  '849ed' => 'assets/figma-change/849ed.svg',
  '7827e' => 'assets/figma-change/7827e.svg',
  '015d6' => 'assets/figma-change/58636.svg',
  'f6dae' => 'assets/figma-change/f6dae.svg',
  'e33d1' => 'assets/figma-change/0076b.svg',
  '1e3d7' => 'assets/figma-change/849ed.svg',
  '5b56c' => 'assets/figma-change/98773.svg',
  'e306f' => 'assets/figma-change/f3cd5.svg',
  '1409f' => 'assets/figma-change/e0ad4.svg',
  '17e15' => 'assets/figma-change/17e15.svg',
  '08603' => 'assets/figma-change/0076b.svg',
  '7b0e4' => 'assets/figma-change/e6ee9.svg',
  '32729' => 'assets/figma-change/2a112.svg',
  '602f1' => 'assets/figma-change/b4d4c.svg',
  'be895' => 'assets/figma-change/ff372.svg',
  'b8ce6' => 'assets/figma-change/875aa.svg',
  '5a018' => 'assets/figma-change/38515.svg',
  '72888' => 'assets/figma-change/23e66.svg',
  '00519' => 'assets/figma-change/2cb10.svg',
  '72592' => 'assets/figma-change/0e7e8.svg',
  'e82c5' => 'assets/figma-change/f97b4.svg',
  '64959' => 'assets/figma-change/94e29.svg',
  'c24d4' => 'assets/figma-change/17155.svg',
  'c9889' => 'assets/figma-change/8d00f.svg',
  _ => 'assets/figma/$asset.svg',
};

/// Figma's 44px toolbar sits above a 24px lower inset. Text can grow the
/// toolbar on narrow screens instead of being clipped by the reference height.
AppBar merchantAppBar(
  BuildContext context, {
  Key? key,
  Widget? leading,
  double? leadingWidth,
  Widget? title,
  List<Widget>? actions,
  ShapeBorder? shape,
}) {
  final painter =
      TextPainter(
        text: TextSpan(
          text: title is Text ? title.data ?? '' : '',
          style: AppTextStyles.of(context).titleM,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(
        maxWidth: (MediaQuery.sizeOf(context).width - 144).clamp(
          80,
          double.infinity,
        ),
      );
  final height = (painter.height + 16).clamp(44.0, double.infinity);
  return AppBar(
    key: key,
    toolbarHeight: height + 24,
    leadingWidth: (leadingWidth ?? 72).clamp(72, double.infinity),
    shape: shape,
    leading: leading == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 24),
            child: leading,
          ),
    title: title == null
        ? null
        : Padding(padding: const EdgeInsets.only(bottom: 24), child: title),
    actions: actions
        ?.map(
          (action) => Padding(
            padding: const EdgeInsets.only(bottom: 24, right: 8),
            child: action,
          ),
        )
        .toList(),
  );
}
