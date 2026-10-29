import 'package:flutter/material.dart';

import 'app/app_theme.dart';
import 'app/design_system/design_system.dart';
import 'features/home/presentation/kesor_home_screen.dart';

/// Offline browser preview. The normal app entry point remains main.dart.
void main() => runApp(const DesignSystemPreview());

class DesignSystemPreview extends StatefulWidget {
  const DesignSystemPreview({super.key});

  @override
  State<DesignSystemPreview> createState() => _DesignSystemPreviewState();
}

class _DesignSystemPreviewState extends State<DesignSystemPreview> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kesor Bank · Design preview',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.build(Brightness.light),
    darkTheme: AppTheme.build(Brightness.dark),
    themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
    home: DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kesor Bank · Preview'),
          actions: [
            IconButton(
              tooltip: _dark ? 'Switch to light mode' : 'Switch to dark mode',
              onPressed: () => setState(() => _dark = !_dark),
              icon: Icon(_dark ? Icons.light_mode : Icons.dark_mode),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Colors'),
              Tab(text: 'Typography'),
              Tab(text: 'Home'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ColorsPreview(),
            _TypographyPreview(),
            Center(
              child: SizedBox(
                width: 440,
                child: KesorHomeScreen(data: KesorHomeData.designPreview),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ColorsPreview extends StatelessWidget {
  const _ColorsPreview();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Color palette', style: AppTextStyles.of(context).titleXL),
              const SizedBox(height: 8),
              const Text(
                'Exact Figma tokens · Use the sun/moon button to change mode.',
              ),
              for (final group in [
                'Neutral',
                'Primary',
                'Accent',
                'Semantic',
              ]) ...[
                const SizedBox(height: 28),
                Text(group, style: AppTextStyles.of(context).titleL),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 20,
                  children: [
                    for (final token in colors.tokens.entries.where(
                      (entry) => entry.key.startsWith('$group/'),
                    ))
                      SizedBox(
                        width: 165,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 72,
                              decoration: BoxDecoration(
                                color: token.value,
                                border: Border.all(color: colors.border),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(token.key.split('/').last),
                            SelectableText(
                              '#${token.value.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypographyPreview extends StatefulWidget {
  const _TypographyPreview();

  @override
  State<_TypographyPreview> createState() => _TypographyPreviewState();
}

class _TypographyPreviewState extends State<_TypographyPreview> {
  bool _khmer = false;

  @override
  Widget build(BuildContext context) {
    final styles = _khmer ? AppTypography.khmer : AppTypography.english;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Typography', style: AppTextStyles.of(context).titleXL),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('English')),
                    ButtonSegment(value: true, label: Text('Khmer')),
                  ],
                  selected: {_khmer},
                  onSelectionChanged: (value) =>
                      setState(() => _khmer = value.single),
                ),
                const SizedBox(height: 16),
                Text(
                  _khmer ? 'Google Sans · Khmer' : 'Poppins · English / Latin',
                ),
                for (final role in styles.roles.entries) ...[
                  const SizedBox(height: 28),
                  Text(
                    '${role.key} · ${role.value.fontSize!.toInt()}px / '
                    '${(role.value.height! * role.value.fontSize!).round()}px line height · '
                    '${role.value.fontWeight!.value}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _khmer
                        ? 'អក្សរធនាគារកេសរ'
                        : 'Banking with Kesor · ${role.key}',
                    style: role.value.copyWith(
                      color: AppColors.of(context).foreground,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
