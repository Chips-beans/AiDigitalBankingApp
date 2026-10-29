import 'package:flutter/material.dart';

import 'features/home/presentation/kesor_home_screen.dart';

/// Offline entry point for the Figma Home screen. No authentication is needed.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KesorHomePreview());
}

class KesorHomePreview extends StatelessWidget {
  const KesorHomePreview({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Kesor Bank · Home',
    home: Scaffold(
      backgroundColor: Color(0xFFE8E8E5),
      body: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 440,
            height: 999,
            child: KesorHomeScreen(
              data: KesorHomeData.designPreview,
              showDeviceChrome: true,
            ),
          ),
        ),
      ),
    ),
  );
}
