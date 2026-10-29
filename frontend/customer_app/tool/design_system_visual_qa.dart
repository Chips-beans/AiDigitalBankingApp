// Offline specimen: uses the actual bundled fonts and the imported theme.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:customer_app/app/app_theme.dart';
import 'package:customer_app/app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render imported colors and both language typography ramps', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final family in {
        'Poppins': [
          'Poppins-Light.ttf',
          'Poppins-Regular.ttf',
          'Poppins-Medium.ttf',
          'Poppins-SemiBold.ttf',
        ],
        'Google Sans': [
          'GoogleSans-Regular.ttf',
          'GoogleSans-Medium.ttf',
          'GoogleSans-Bold.ttf',
        ],
        'Noto Sans Khmer': ['NotoSansKhmer-Variable.ttf'],
      }.entries) {
        final loader = FontLoader(family.key);
        for (final file in family.value) {
          loader.addFont(rootBundle.load('assets/fonts/$file'));
        }
        await loader.load();
      }
    });
    tester.view.physicalSize = const Size(1200, 1420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(brightness),
          home: RepaintBoundary(key: key, child: const _Specimen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final name = brightness.name;
        final file = File('.local/qa/design-system/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
  });
}

class _Specimen extends StatelessWidget {
  const _Specimen();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final groups = [
      colors.tokens.entries.where((e) => e.key.startsWith('Neutral/')),
      colors.tokens.entries.where((e) => e.key.startsWith('Primary/')),
      colors.tokens.entries.where((e) => e.key.startsWith('Accent/')),
      colors.tokens.entries.where((e) => e.key.startsWith('Semantic/')),
    ];
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kesor Bank · Colors & Typography',
              style: AppTypography.english.titleXL.copyWith(
                color: colors.foreground,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Figma 206:233 / 230:208 / 230:302 · ${Theme.of(context).brightness.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 28),
            for (final group in groups) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final token in group)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: token.value,
                                border: Border.all(color: colors.border),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              token.key,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            Text(
                              '#${token.value.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ramp(
                    context,
                    'English · Poppins',
                    AppTypography.english,
                    false,
                  ),
                ),
                const SizedBox(width: 48),
                Expanded(
                  child: _ramp(
                    context,
                    'Khmer · Google Sans',
                    AppTypography.khmer,
                    true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ramp(
    BuildContext context,
    String heading,
    AppTextStyles styles,
    bool khmer,
  ) {
    final color = AppColors.of(context).foreground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 20),
        for (final role in styles.roles.entries)
          SizedBox(
            height: 78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${role.key} · ${role.value.fontSize!.toInt()} / '
                  '${(role.value.height! * role.value.fontSize!).round()}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  khmer ? 'អក្សរធនាគារកេសរ' : _english[role.key]!,
                  style: role.value.copyWith(color: color),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static const _english = {
    'hero': 'Text Hero',
    'titleXL': 'Title–XL',
    'titleL': 'Title–L',
    'titleM': 'Title–M',
    'bodyL': 'Body–L',
    'body': 'Body–Primary',
    'button': 'Button / Action',
    'caption': 'Caption',
    'micro': 'Micro/Overline',
  };
}
