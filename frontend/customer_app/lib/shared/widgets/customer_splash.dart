import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

class CustomerSplash extends StatelessWidget {
  const CustomerSplash({this.animate = true, super.key});
  final bool animate;

  @override
  Widget build(BuildContext context) => KesorBrandSplash(
    animate: animate,
    logo: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 22.5036,
          top: 10.9997,
          width: 83.9916,
          height: 108.9959,
          child: SvgPicture.asset('assets/splash/67d0e.svg'),
        ),
      ],
    ),
  );
}
