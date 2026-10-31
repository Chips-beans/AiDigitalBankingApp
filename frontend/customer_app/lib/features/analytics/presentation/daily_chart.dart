import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/design_system/design_system.dart';
import '../analytics_gateway.dart';

/// The scale uses exact integer arithmetic, independently of the selected series.
class AnalyticsScale {
  AnalyticsScale(AnalyticsSnapshot snapshot) {
    var peak = BigInt.zero;
    for (final day in snapshot.daily) {
      if (day.income > peak) peak = day.income;
      if (day.expense > peak) peak = day.expense;
    }
    if (peak == BigInt.zero) {
      peak = BigInt.from(snapshot.currency == 'USD' ? 15000 : 3);
    }
    final target = (peak + BigInt.two) ~/ BigInt.from(3);
    final magnitude = BigInt.from(10).pow(target.toString().length - 1);
    step = [
      1,
      2,
      5,
      10,
    ].map((n) => magnitude * BigInt.from(n)).firstWhere((n) => n >= target);
    maximum = step * BigInt.from(3);
  }
  late final BigInt step, maximum;
  double ratio(BigInt amount) =>
      ((amount * BigInt.from(1000000)) ~/ maximum).toDouble() / 1000000;
}

/// Income is gold and Expense is navy blue, for the bars and the series dot.
Color analyticsSeriesColor(BuildContext context, {required bool income}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return income
      ? (dark ? AppPalette.gold400 : AppPalette.gold500)
      : (dark ? AppPalette.navy200 : AppPalette.navy500);
}

class DailyAnalyticsChart extends StatefulWidget {
  const DailyAnalyticsChart({
    required this.snapshot,
    required this.showIncome,
    required this.seriesLabel,
    super.key,
  });
  final AnalyticsSnapshot snapshot;
  final bool showIncome;
  final String seriesLabel;
  @override
  State<DailyAnalyticsChart> createState() => _DailyAnalyticsChartState();
}

class _DailyAnalyticsChartState extends State<DailyAnalyticsChart> {
  int? selected;
  bool focused = false;
  @override
  void didUpdateWidget(DailyAnalyticsChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot ||
        oldWidget.showIncome != widget.showIncome) {
      selected = null;
    }
  }

  void select(int value) => setState(
    () => selected = value.clamp(0, widget.snapshot.daily.length - 1),
  );
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scale = AnalyticsScale(widget.snapshot);
    final day = selected == null ? null : widget.snapshot.daily[selected!];
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final tooltip = day == null
        ? null
        : '${monthKey(day.date)}-${day.date.day.toString().padLeft(2, '0')} · ${widget.seriesLabel} ${analyticsMoney(widget.showIncome ? day.income : day.expense, widget.snapshot.currency)}';
    return Focus(
      onFocusChange: (value) => setState(() => focused = value),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          select((selected ?? -1) + 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          select((selected ?? 1) - 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          setState(() => selected = null);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        label:
            tooltip ??
            '${widget.seriesLabel} · ${monthKey(widget.snapshot.month)} · ${widget.snapshot.currency}',
        onIncrease: () => select((selected ?? -1) + 1),
        onDecrease: () => select((selected ?? 1) - 1),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final left = math.min(42 * textScale, bounds.maxWidth * .45);
            void at(Offset offset) => select(
              ((offset.dx - left) /
                      (bounds.maxWidth - left) *
                      widget.snapshot.daily.length)
                  .floor(),
            );
            return MouseRegion(
              onHover: (event) => at(event.localPosition),
              onExit: (_) => setState(() => selected = null),
              child: GestureDetector(
                onTapUp: (event) => at(event.localPosition),
                behavior: HitTestBehavior.opaque,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: focused
                        ? Border.all(color: AppPalette.gold500, width: 2)
                        : null,
                  ),
                  child: SizedBox(
                    key: const ValueKey('analytics-chart'),
                    height: 153 + 18 * textScale,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _DailyPainter(
                                snapshot: widget.snapshot,
                                showIncome: widget.showIncome,
                                scale: scale,
                                selected: selected,
                                color: analyticsSeriesColor(
                                  context,
                                  income: widget.showIncome,
                                ),
                                // The selected bar must stand out from gold bars.
                                highlight: !widget.showIncome
                                    ? AppPalette.gold500
                                    : Theme.of(context).brightness ==
                                          Brightness.dark
                                    ? AppPalette.gold100
                                    : AppPalette.gold700,
                                grid: colors.border,
                                text: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11 * textScale,
                                  color: colors.disabledBackground,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (tooltip != null)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: colors.surface,
                                  border: Border.all(color: colors.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  tooltip,
                                  key: const ValueKey('analytics-tooltip'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.foreground,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DailyPainter extends CustomPainter {
  _DailyPainter({
    required this.snapshot,
    required this.showIncome,
    required this.scale,
    required this.selected,
    required this.color,
    required this.highlight,
    required this.grid,
    required this.text,
  });
  final AnalyticsSnapshot snapshot;
  final bool showIncome;
  final AnalyticsScale scale;
  final int? selected;
  final Color color, highlight, grid;
  final TextStyle text;
  @override
  void paint(Canvas canvas, Size size) {
    const top = 8.0;
    final left = math.min(42 * text.fontSize! / 11, size.width * .45);
    final baseline = size.height - (text.fontSize! * 1.5 + 7);
    final plotWidth = size.width - left, plotHeight = baseline - top;
    double label(
      String value,
      double x,
      double y, {
      bool center = false,
      bool draw = true,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: text),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: center ? size.width : left - 6);
      if (draw) {
        painter.paint(
          canvas,
          Offset(
            center
                ? (x - painter.width / 2).clamp(0, size.width - painter.width)
                : x,
            y,
          ),
        );
      }
      return painter.width;
    }

    for (var i = 0; i <= 3; i++) {
      final y = baseline - plotHeight * i / 3;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width, y),
        Paint()
          ..color = grid
          ..strokeWidth = .8,
      );
      label(_axis(scale.step * BigInt.from(i)), 0, y - text.fontSize! * .6);
    }
    final slot = plotWidth / snapshot.daily.length;
    var lastLabelRight = -double.infinity;
    final lastLabelWidth = label(
      '${snapshot.daily.length}',
      0,
      0,
      center: true,
      draw: false,
    );
    final lastLabelLeft = size.width - lastLabelWidth;
    for (var i = 0; i < snapshot.daily.length; i++) {
      final day = snapshot.daily[i];
      final value = showIncome ? day.income : day.expense;
      final height = scale.ratio(value) * plotHeight;
      final width = math.min(6.57, slot * .66);
      final x = left + slot * (i + .5);
      if (height > 0) {
        // Rounded top, flat base on the axis.
        final corner = Radius.circular(math.min(width / 2, height));
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x - width / 2, baseline - height, width, height),
            topLeft: corner,
            topRight: corner,
          ),
          Paint()..color = selected == i ? highlight : color,
        );
      }
      final number = i + 1;
      if (number == 1 ||
          number == snapshot.daily.length ||
          (number % 5 == 0 && number < snapshot.daily.length - 2)) {
        final value = number.toString().padLeft(2, '0');
        final width = label(value, x, 0, center: true, draw: false);
        final start = (x - width / 2).clamp(0, size.width - width);
        if (number == snapshot.daily.length ||
            (start >= lastLabelRight + 8 &&
                start + width < lastLabelLeft - 8)) {
          label(value, x, baseline + 6, center: true);
          lastLabelRight = start + width;
        }
      }
    }
  }

  String _axis(BigInt units) {
    final factor = snapshot.currency == 'USD' ? BigInt.from(100) : BigInt.one;
    final whole = units ~/ factor;
    var divisor = BigInt.one;
    var suffix = '';
    for (final entry in {3: 'K', 6: 'M', 9: 'B', 12: 'T', 15: 'Q'}.entries) {
      final candidate = BigInt.from(10).pow(entry.key);
      if (whole >= candidate) {
        divisor = candidate;
        suffix = entry.value;
      }
    }
    String amount;
    if (whole.toString().length > 18) {
      amount = '${whole.toString()[0]}e${whole.toString().length - 1}';
    } else if (suffix.isNotEmpty) {
      final tenth = (whole * BigInt.from(10)) ~/ divisor;
      amount =
          '${tenth ~/ BigInt.from(10)}${tenth % BigInt.from(10) == BigInt.zero ? '' : '.${tenth % BigInt.from(10)}'}$suffix';
    } else if (units % factor != BigInt.zero) {
      amount = '$whole.${(units % factor).toString().padLeft(2, '0')}';
    } else {
      amount = whole.toString();
    }
    return snapshot.currency == 'USD' ? '\$$amount' : '$amount៛';
  }

  @override
  bool shouldRepaint(_DailyPainter old) =>
      old.snapshot != snapshot ||
      old.showIncome != showIncome ||
      old.selected != selected ||
      old.color != color ||
      old.highlight != highlight ||
      old.grid != grid ||
      old.text != text;
}
