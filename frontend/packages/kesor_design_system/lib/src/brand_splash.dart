import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Figma 420:752 / 418:6159. The supplied logo retains its original vector layout.
class KesorBrandSplash extends StatefulWidget {
  const KesorBrandSplash({
    required this.logo,
    this.merchant = false,
    this.animate = true,
    super.key,
  });
  final Widget logo;
  final bool merchant, animate;

  @override
  State<KesorBrandSplash> createState() => _KesorBrandSplashState();
}

class _KesorBrandSplashState extends State<KesorBrandSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
      if (!motion.isAnimating) motion.repeat();
    } else {
      motion.stop();
      motion.value = 1;
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: widget.merchant
        ? SystemUiOverlayStyle.dark
        : SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: widget.merchant ? Colors.white : AppPalette.navy500,
      body: Semantics(
        label: widget.merchant ? 'Kesor Merchant' : 'Kesor Bank',
        child: ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Center(
                  child: AnimatedBuilder(
                    animation: motion,
                    child: SizedBox.square(dimension: 126, child: widget.logo),
                    builder: (context, child) {
                      // Figma: hold 120 ms; fade by 850 ms, scale by 1050 ms;
                      // hold the finished logo until the 2000 ms loop boundary.
                      final fade = Curves.easeOut.transform(
                        ((motion.value - .06) / .365).clamp(0.0, 1.0),
                      );
                      final scale = Curves.easeOut.transform(
                        ((motion.value - .06) / .465).clamp(0.0, 1.0),
                      );
                      return Opacity(
                        opacity: fade,
                        child: Transform.scale(
                          scale: .88 + .12 * scale,
                          child: child,
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: constraints.maxHeight / 2 + 67,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '.',
                          style: TextStyle(
                            color: widget.merchant
                                ? AppPalette.navy500
                                : Colors.white,
                          ),
                        ),
                        TextSpan(text: widget.merchant ? 'Merchant' : 'Bank'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.gold500,
                    ),
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
