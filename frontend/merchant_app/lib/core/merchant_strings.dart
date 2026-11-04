import 'package:flutter/material.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

class MerchantStrings extends InheritedWidget {
  const MerchantStrings({required this.khmer, required super.child, super.key});
  final bool khmer;
  @override
  bool updateShouldNotify(MerchantStrings oldWidget) =>
      oldWidget.khmer != khmer;
  static bool isKhmer(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MerchantStrings>()?.khmer ==
      true;
  static String text(BuildContext context, String en, String km) =>
      isKhmer(context) ? km : en;
}

String t(BuildContext context, String en, String km) =>
    MerchantStrings.text(context, en, km);

/// Customer App type scale: explicit size/line height in Poppins or Google Sans.
TextStyle mText(
  BuildContext context,
  double size,
  double lineHeight, {
  FontWeight weight = FontWeight.w400,
  Color? color,
}) => AppTextStyles.of(context).body.copyWith(
  fontSize: size,
  height: lineHeight / size,
  fontWeight: weight,
  color: color ?? AppColors.of(context).foreground,
  fontFamily: MerchantStrings.isKhmer(context)
      ? AppTypography.khmerFamily
      : AppTypography.englishFamily,
  letterSpacing: 0,
);

Color merchantNavy(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppPalette.navy100
    : AppPalette.navy500;

/// Short business-calendar labels, without dependence on the host timezone.
String merchantDateLabel(
  BuildContext context,
  DateTime date, {
  bool today = false,
}) {
  const en = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  const km = [
    'មករា',
    'កុម្ភៈ',
    'មីនា',
    'មេសា',
    'ឧសភា',
    'មិថុនា',
    'កក្កដា',
    'សីហា',
    'កញ្ញា',
    'តុលា',
    'វិច្ឆិកា',
    'ធ្នូ',
  ];
  final months = MerchantStrings.isKhmer(context) ? km : en;
  final now = DateTime.now().toUtc().add(const Duration(hours: 7));
  final prefix =
      today &&
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day
      ? '${t(context, 'Today', 'ថ្ងៃនេះ')}, '
      : '';
  return '$prefix${date.day} ${months[date.month - 1]}';
}
