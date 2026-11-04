import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import 'merchant_strings.dart';

/// Merchant Redesign v2 · Quiet, Figma section 370:4356. Merchant-only
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
    hero: role(32, 43, FontWeight.w300),
    titleXL: role(20, 27, FontWeight.w500),
    titleL: role(17, 22, FontWeight.w500),
    titleM: role(15, 24, FontWeight.w500),
    body: role(15, 24, FontWeight.w400),
    bodyL: role(15, 24, FontWeight.w400),
    button: role(14, 22, FontWeight.w500),
    caption: role(13, 18, FontWeight.w400),
    micro: role(11, 14, FontWeight.w500),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return base.copyWith(
    extensions: [colors, type],
    textTheme: type.textTheme.apply(
      bodyColor: colors.foreground,
      displayColor: colors.foreground,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 8,
      toolbarHeight: 56,
      titleTextStyle: type.titleL,
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: type.body.copyWith(color: colors.disabledBackground),
      labelStyle: type.caption.copyWith(color: colors.disabledBackground),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.accent500),
      ),
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        backgroundColor: colors.primary500,
        foregroundColor: AppPalette.neutralLightForegroundAndBase,
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
      selectedColor: colors.accent50,
      side: BorderSide.none,
      showCheckmark: false,
      labelStyle: type.caption.copyWith(fontSize: 13, color: colors.foreground),
      secondaryLabelStyle: type.caption.copyWith(
        fontSize: 13,
        color: AppPalette.navy500,
      ),
      secondarySelectedColor: colors.accent50,
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
      'assets/figma/$asset.svg',
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
    onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
    icon: const QIcon('20fad'),
  );
}

/// Scrolls the whole flow when the keyboard, landscape or large text needs room;
/// otherwise the final action stays at the bottom of the available stage.
class QStage extends StatelessWidget {
  const QStage({
    required this.child,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
    appBar: AppBar(
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
      color: AppColors.of(context).surface,
      borderRadius: BorderRadius.circular(16),
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
              13,
              18,
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
            style: mText(context, 15, 24),
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
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (tone) {
          'success' => AppPalette.semanticSuccessMuted,
          'error' => AppPalette.semanticErrorMuted,
          'warning' => AppPalette.semanticWarningMuted,
          _ => AppColors.of(context).surface,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Text(
                labels[i],
                textAlign: TextAlign.center,
                style: mText(
                  context,
                  13,
                  18,
                  weight: values[i] == value
                      ? FontWeight.w500
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
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.of(context).surface,
          borderRadius: BorderRadius.circular(12),
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
  Widget build(BuildContext context) => Column(
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
                child: SizedBox(
                  height:
                      MediaQuery.textScalerOf(context)
                          .scale(35)
                          .clamp(40.0, double.infinity) +
                      16,
                  child: TextButton(
                    onPressed: key == '.' && !decimal ? null : () => enter(key),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.of(context).foreground,
                      textStyle: mText(
                        context,
                        26,
                        35,
                        weight: FontWeight.w300,
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
          ],
        ),
    ],
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
            final style = mText(context, 48, 64, weight: FontWeight.w300);
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
      border: divider
          ? Border(bottom: BorderSide(color: AppColors.of(context).border))
          : null,
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
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
