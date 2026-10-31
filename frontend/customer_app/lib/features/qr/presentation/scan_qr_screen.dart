import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/app_labels.dart';
import '../../../app/design_system/design_system.dart';

/// Camera-first scanner composition. The footer lists only supported Kesor QR
/// currencies, rather than suggesting external payment-network acceptance.
class ScanQrScreen extends StatelessWidget {
  const ScanQrScreen({
    required this.cameraBuilder,
    required this.onClose,
    this.onFlash,
    this.onUpload,
    this.onRetry,
    this.flashOn = false,
    this.busy = false,
    this.message,
    super.key,
  });

  final Widget Function(Rect scanWindow) cameraBuilder;
  final VoidCallback onClose;
  final VoidCallback? onFlash, onUpload, onRetry;
  final bool flashOn, busy;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final type = AppTextStyles.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppPalette.navy700,
      ),
      child: ColoredBox(
        color: AppPalette.navy700,
        child: LayoutBuilder(
          builder: (context, bounds) {
            final height = bounds.hasBoundedHeight
                ? bounds.maxHeight
                : math.max(600.0, MediaQuery.sizeOf(context).height - 40);
            final landscape = bounds.maxWidth > height;
            final camera = ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(36),
              ),
              child: LayoutBuilder(
                builder: (context, cameraBounds) {
                  final inset = MediaQuery.paddingOf(context).top;
                  final side = math.min(
                    380.0,
                    math.min(
                      cameraBounds.maxWidth * .72,
                      (cameraBounds.maxHeight - inset) * .52,
                    ),
                  );
                  final window = Rect.fromCenter(
                    center: Offset(
                      cameraBounds.maxWidth / 2,
                      inset + (cameraBounds.maxHeight - inset) * .51,
                    ),
                    width: side,
                    height: side,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: AppPalette.neutralDarkBackground),
                      cameraBuilder(window),
                      IgnorePointer(
                        child: CustomPaint(painter: _ScanFrame(window)),
                      ),
                      Positioned(
                        top: inset + 8,
                        left: 12,
                        right: 12,
                        child: Row(
                          children: [
                            const SizedBox(width: 48),
                            Expanded(
                              child: Text(
                                tx(context, 'Kesor Scan'),
                                textAlign: TextAlign.center,
                                style: type.titleL.copyWith(
                                  color:
                                      AppPalette.neutralDarkForegroundAndBase,
                                  shadows: const [Shadow(blurRadius: 12)],
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('scan-close'),
                              tooltip: tx(context, 'Close'),
                              onPressed: onClose,
                              color: AppPalette.neutralDarkForegroundAndBase,
                              style: IconButton.styleFrom(
                                backgroundColor: AppPalette.navy700.withValues(
                                  alpha: .6,
                                ),
                              ),
                              icon: const Icon(Icons.close, size: 26),
                            ),
                          ],
                        ),
                      ),
                      if (busy)
                        Positioned(
                          bottom: 24,
                          left: 32,
                          right: 32,
                          child: Semantics(
                            label: tx(context, 'Reading QR code…'),
                            child: const LinearProgressIndicator(
                              color: AppPalette.gold400,
                              backgroundColor: AppPalette.navy600,
                            ),
                          ),
                        )
                      else if (message != null)
                        Positioned(
                          bottom: 12,
                          left: 16,
                          right: 16,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: 440,
                                maxHeight: cameraBounds.maxHeight * .38,
                              ),
                              child: Material(
                                color: AppPalette.navy700,
                                borderRadius: BorderRadius.circular(20),
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Semantics(
                                        liveRegion: true,
                                        child: Text(
                                          message!,
                                          textAlign: TextAlign.center,
                                          style: type.body.copyWith(
                                            color: AppPalette
                                                .neutralDarkForegroundAndBase,
                                          ),
                                        ),
                                      ),
                                      if (onRetry != null)
                                        TextButton(
                                          onPressed: onRetry,
                                          style: TextButton.styleFrom(
                                            foregroundColor: AppPalette.gold200,
                                          ),
                                          child: Text(
                                            tx(context, 'Scan again'),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
            final footer = SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LayoutBuilder(
                      builder: (context, controls) {
                        final stack =
                            controls.maxWidth < 300 ||
                            MediaQuery.textScalerOf(context).scale(14) > 21;
                        final flash = _ScanAction(
                          label: tx(context, 'Flash'),
                          icon: flashOn
                              ? Icons.flashlight_on
                              : Icons.flashlight_on_outlined,
                          onPressed: onFlash,
                          selected: flashOn,
                        );
                        final upload = _ScanAction(
                          label: tx(context, 'Upload QR'),
                          icon: Icons.qr_code_2,
                          onPressed: onUpload,
                        );
                        return stack
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  flash,
                                  const SizedBox(height: 12),
                                  upload,
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: flash),
                                  const SizedBox(width: 16),
                                  Expanded(child: upload),
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          'assets/home/kesor-logo.svg',
                          width: 22,
                          height: 28,
                          excludeFromSemantics: true,
                          colorFilter: const ColorFilter.mode(
                            AppPalette.gold400,
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Kesor Bank',
                            style: type.titleM.copyWith(
                              color: AppPalette.gold200,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tx(context, 'Kesor account QR · USD / KHR'),
                      textAlign: TextAlign.center,
                      style: type.caption.copyWith(color: AppPalette.navy100),
                    ),
                  ],
                ),
              ),
            );
            return SizedBox(
              height: height,
              child: landscape
                  ? Row(
                      children: [
                        Expanded(flex: 3, child: camera),
                        Expanded(flex: 2, child: Center(child: footer)),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: camera),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: height * .48),
                          child: footer,
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _ScanAction extends StatelessWidget {
  const _ScanAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.selected = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: selected ? true : null,
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 24),
      label: Text(label, textAlign: TextAlign.center),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: const StadiumBorder(),
        backgroundColor: selected ? AppPalette.gold400 : AppPalette.navy500,
        foregroundColor: selected
            ? AppPalette.navy700
            : AppPalette.neutralDarkForegroundAndBase,
        disabledForegroundColor: AppPalette.navy200,
        textStyle: AppTextStyles.of(context).bodyL,
      ),
    ),
  );
}

class _ScanFrame extends CustomPainter {
  const _ScanFrame(this.window);
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(window, const Radius.circular(32)));
    canvas.drawPath(
      scrim,
      Paint()..color = AppPalette.navy700.withValues(alpha: .32),
    );
    final paint = Paint()
      ..color = AppPalette.gold400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final radius = math.min(32.0, window.width * .12);
    final arm = window.width * .19;
    final corner = Path()
      ..moveTo(window.left, window.top + arm)
      ..lineTo(window.left, window.top + radius)
      ..quadraticBezierTo(
        window.left,
        window.top,
        window.left + radius,
        window.top,
      )
      ..lineTo(window.left + arm, window.top);
    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.translate(window.center.dx, window.center.dy);
      canvas.rotate(i * math.pi / 2);
      canvas.translate(-window.center.dx, -window.center.dy);
      canvas.drawPath(corner, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ScanFrame oldDelegate) => oldDelegate.window != window;
}
