import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/app_preferences.dart';
import '../../app/design_system/design_system.dart';
import '../../shared/widgets/kesor_bottom_bar.dart';
import '../auth/session_controller.dart';

TextStyle settingsText(
  BuildContext context,
  double size,
  double line, {
  Color? color,
  FontWeight weight = FontWeight.w400,
}) => AppTextStyles.of(context).body.copyWith(
  fontSize: size,
  height: line / size,
  fontWeight: weight,
  letterSpacing: 0,
  color: color ?? AppColors.of(context).foreground,
);
Color settingsNavy(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppPalette.navy100
    : AppPalette.navy500;

class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.name, {this.size = 22, this.color, super.key});
  final String name;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/settings/$name.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
    colorFilter: color != null
        ? ColorFilter.mode(color!, BlendMode.srcIn)
        : Theme.of(context).brightness == Brightness.dark
        ? ColorFilter.mode(AppPalette.navy100, BlendMode.srcIn)
        : null,
  );
}

/// Figma 320:308. Native system bars are provided by Android, not painted here.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.session,
    required this.onOpen,
    super.key,
  });
  final SessionController session;
  final ValueChanged<String> onOpen;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.session.loadProfilePhoto());
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final colors = AppColors.of(context);
      final prefs = AppPreferences.maybeOf(context);
      final name = widget.session.identity?.displayName;
      final displayName = name?.isNotEmpty == true
          ? name!
          : widget.session.identity?.username ?? '';
      final photo = widget.session.profilePhoto;
      Widget group(String title, List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: settingsText(
              context,
              14,
              22,
              color: settingsNavy(context),
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 50, right: 16),
                        child: Divider(
                          height: 0,
                          thickness: 1,
                          color: colors.border,
                        ),
                      ),
                    rows[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      );
      return SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          key: const ValueKey('settings-scroll'),
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            KesorBottomBar.height(context) +
                math.max(24, MediaQuery.paddingOf(context).bottom) +
                30,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(context, 'Settings', 'ការកំណត់'),
                style: settingsText(
                  context,
                  24,
                  36,
                  color: settingsNavy(context),
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr(
                  context,
                  'Your account, security and app preferences.',
                  'គណនី សុវត្ថិភាព និងចំណូលចិត្តកម្មវិធីរបស់អ្នក។',
                ),
                style: settingsText(
                  context,
                  12,
                  20,
                  color: colors.disabledBackground,
                ),
              ),
              const SizedBox(height: 20),
              Material(
                color: Theme.of(context).brightness == Brightness.dark
                    ? colors.surface
                    : AppPalette.gold50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppPalette.gold200),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('settings-profile'),
                  onTap: () => widget.onOpen('profile'),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 84),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          ClipOval(
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: photo != null
                                  ? Image.memory(
                                      photo.bytes,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                      excludeFromSemantics: true,
                                      errorBuilder: (_, _, _) =>
                                          _initial(context, displayName),
                                    )
                                  : _initial(context, displayName),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  key: const ValueKey('settings-name'),
                                  style: settingsText(
                                    context,
                                    15,
                                    24,
                                    color: settingsNavy(context),
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  tr(
                                    context,
                                    'Personal details & contact information',
                                    'ព័ត៌មានផ្ទាល់ខ្លួន និងទំនាក់ទំនង',
                                  ),
                                  style: settingsText(
                                    context,
                                    12,
                                    20,
                                    color: colors.disabledBackground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          const SettingsIcon('chevron-right', size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              group(
                tr(context, 'Security & sign-in', 'សុវត្ថិភាព និងការចូលគណនី'),
                [
                  _row(
                    context,
                    'pin',
                    'lock-keyhole',
                    tr(context, 'Change PIN', 'ប្តូរលេខ PIN'),
                    subtitle: tr(
                      context,
                      'Update your sign-in PIN',
                      'ធ្វើបច្ចុប្បន្នភាពលេខ PIN ចូលគណនី',
                    ),
                    height: 64,
                  ),
                  _row(
                    context,
                    'biometric',
                    'fingerprint',
                    tr(context, 'Biometric sign-in', 'ចូលដោយជីវមាត្រ'),
                    subtitle: tr(
                      context,
                      'Use Face ID or fingerprint',
                      'ប្រើស្កេនមុខ ឬស្នាមម្រាមដៃ',
                    ),
                    height: 64,
                    disabled: true,
                  ),
                  _row(
                    context,
                    'merchant-sessions',
                    'lock-keyhole',
                    tr(context, 'Merchant sessions', 'វគ្គប្រើប្រាស់ Merchant'),
                    height: 64,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              group(tr(context, 'Preferences', 'ចំណូលចិត្ត'), [
                _row(
                  context,
                  'notifications',
                  'bell',
                  tr(context, 'Notifications', 'ការជូនដំណឹង'),
                  value: tr(context, 'Manage alerts', 'គ្រប់គ្រងការជូនដំណឹង'),
                ),
                _row(
                  context,
                  'language',
                  'languages',
                  tr(context, 'Language', 'ភាសា'),
                  value: prefs?.isKhmer == true ? 'ខ្មែរ' : 'English',
                ),
                _row(
                  context,
                  'appearance',
                  'sun-moon',
                  tr(context, 'Appearance', 'រូបរាង'),
                  value: switch (prefs?.themeMode ?? ThemeMode.system) {
                    ThemeMode.system => tr(context, 'System', 'តាមប្រព័ន្ធ'),
                    ThemeMode.light => tr(context, 'Light', 'ភ្លឺ'),
                    ThemeMode.dark => tr(context, 'Dark', 'ងងឹត'),
                  },
                ),
              ]),
              const SizedBox(height: 20),
              group(tr(context, 'Support & legal', 'ជំនួយ និងលក្ខខណ្ឌ'), [
                _row(
                  context,
                  'help',
                  'headset',
                  tr(context, 'Help & support', 'ជំនួយ និងការគាំទ្រ'),
                  height: 56,
                ),
                _row(
                  context,
                  'legal',
                  'file-text',
                  tr(context, 'Terms & privacy', 'លក្ខខណ្ឌ និងឯកជនភាព'),
                  height: 56,
                ),
              ]),
              const SizedBox(height: 20),
              OutlinedButton(
                key: const ValueKey('settings-signout'),
                onPressed: () => widget.onOpen('signout'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  side: BorderSide(color: colors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SettingsIcon(
                      'logout',
                      size: 20,
                      color: AppPalette.semanticError,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      tr(context, 'Sign out', 'ចាកចេញ'),
                      style: settingsText(
                        context,
                        14,
                        22,
                        color: AppPalette.semanticError,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget _initial(BuildContext context, String name) => ColoredBox(
    color: AppPalette.gold100,
    child: Center(
      child: name.trim().isEmpty
          ? const SettingsIcon(
              'user-round',
              size: 24,
              color: AppPalette.navy500,
            )
          : Text(
              name.trim().characters.first.toUpperCase(),
              style: settingsText(
                context,
                20,
                28,
                color: AppPalette.navy500,
                weight: FontWeight.w500,
              ),
            ),
    ),
  );

  Widget _row(
    BuildContext context,
    String id,
    String icon,
    String title, {
    String? subtitle,
    String? value,
    double height = 60,
    bool disabled = false,
  }) {
    final colors = AppColors.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(15) / 15;
    final stacked =
        value != null &&
        (MediaQuery.sizeOf(context).width < 360 || scale > 1.25);
    return Semantics(
      button: !disabled,
      enabled: !disabled,
      label: disabled ? '$title, ${tr(context, 'Disabled', 'បិទ')}' : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('settings-$id'),
          onTap: disabled ? null : () => widget.onOpen(id),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  SettingsIcon(
                    icon,
                    color: disabled ? AppPalette.navy100 : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: settingsText(
                            context,
                            15,
                            24,
                            color: disabled ? colors.disabledBackground : null,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            style: settingsText(
                              context,
                              12,
                              20,
                              color: colors.disabledBackground,
                            ),
                          ),
                        if (stacked)
                          Text(
                            value,
                            style: settingsText(
                              context,
                              12,
                              20,
                              color: colors.disabledBackground,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (value != null && !stacked) ...[
                    const SizedBox(width: 12),
                    Text(
                      value,
                      style: settingsText(
                        context,
                        12,
                        20,
                        color: colors.disabledBackground,
                      ),
                    ),
                  ],
                  const SizedBox(width: 12),
                  if (disabled)
                    ExcludeSemantics(
                      child: SvgPicture.asset(
                        'assets/settings/biometrics-off.svg',
                        width: 44,
                        height: 26,
                      ),
                    )
                  else
                    const SettingsIcon('chevron-right', size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
