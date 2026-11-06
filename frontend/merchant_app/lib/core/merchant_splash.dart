import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

class MerchantSplash extends StatelessWidget {
  const MerchantSplash({this.animate = true, super.key});
  final bool animate;

  @override
  Widget build(BuildContext context) => KesorBrandSplash(
    merchant: true,
    animate: animate,
    logo: Stack(
      clipBehavior: Clip.none,
      children: [
        // Original exported vector layers, positioned in the 126px Figma logo.
        for (final part in const [
          ('07cc4', 17.86, 25.35, 60.11, 47.21),
          ('13752', 44.57, 52.14, 39.95, 32.93),
          ('7ef0d', 23.33, 33.00, 19.37, 12.89),
          ('5b640', 21.51, 27.35, 23.03, 6.35),
          ('9407b', 25.11, 22.62, 15.81, 4.99),
          ('ff0b0', 27.87, 18.95, 10.29, 3.49),
          ('49b9f', 31.57, 8.73, 2.96, 7.62),
          ('4feaa', 30.29, 16.35, 5.45, 2.13),
          ('ba8ef', 19.20, 56.85, 18.70, 28.45),
          ('2383d', 28.43, 79.44, 9.47, 5.86),
          ('1c1a3', 19.20, 56.85, 18.65, 28.45),
          // The exported lotus includes the source stroke's expanded bounds.
          ('24223', 24.555, 70.053, 52.6996, 25.1795),
        ])
          Positioned(
            left: part.$2 * 1.26,
            top: part.$3 * 1.26,
            width: part.$4 * 1.26,
            height: part.$5 * 1.26,
            child: SvgPicture.asset('assets/splash/${part.$1}.svg'),
          ),
      ],
    ),
  );
}
