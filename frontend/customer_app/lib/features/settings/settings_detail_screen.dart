import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_preferences.dart';
import '../../app/design_system/design_system.dart';
import '../auth/session_controller.dart';
import '../auth/presentation/profile_photo_card.dart';
import 'settings_platform.dart';
import 'settings_screen.dart';

class SettingsDetailScreen extends StatefulWidget {
  const SettingsDetailScreen({
    required this.page,
    required this.session,
    required this.onBack,
    required this.onAssistant,
    this.platform,
    super.key,
  });
  final String page;
  final SessionController session;
  final VoidCallback onBack, onAssistant;
  final SettingsPlatform? platform;
  @override
  State<SettingsDetailScreen> createState() => _SettingsDetailScreenState();
}

class _SettingsDetailScreenState extends State<SettingsDetailScreen>
    with WidgetsBindingObserver {
  final form = GlobalKey<FormState>();
  late final first = TextEditingController(
    text: widget.session.identity?.firstName ?? '',
  );
  late final last = TextEditingController(
    text: widget.session.identity?.lastName ?? '',
  );
  final current = TextEditingController(),
      pin = TextEditingController(),
      confirm = TextEditingController();
  late final platform = widget.platform ?? SettingsPlatform();
  bool sending = false;
  bool? notificationsAllowed;
  String? message;
  bool error = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.page == 'notifications') _notificationStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final field in [first, last, current, pin, confirm]) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.page == 'notifications') {
      _notificationStatus();
    }
  }

  Future<void> _notificationStatus() async {
    try {
      final value = await platform.notificationsEnabled();
      if (mounted) setState(() => notificationsAllowed = value);
    } catch (_) {
      if (mounted) setState(() => notificationsAllowed = false);
    }
  }

  void feedback(String text, {bool failed = false}) {
    if (mounted) {
      setState(() {
        message = text;
        error = failed;
      });
    }
  }

  Future<void> save() async {
    if (sending || !(form.currentState?.validate() ?? false)) return;
    setState(() {
      sending = true;
      message = null;
    });
    try {
      final success = widget.page == 'profile'
          ? await widget.session.updateProfileDetails(first.text, last.text)
          : await widget.session.changePin(
              current.text,
              pin.text,
              confirm.text,
            );
      if (!mounted) return;
      current.clear();
      pin.clear();
      confirm.clear();
      if (success) {
        feedback(
          tr(
            context,
            widget.page == 'profile'
                ? 'Profile saved.'
                : 'PIN changed. Other sessions have been signed out.',
            widget.page == 'profile'
                ? 'បានរក្សាទុកប្រវត្តិរូប។'
                : 'បានប្តូរលេខ PIN និងបិទការចូលនៅឧបករណ៍ផ្សេង។',
          ),
        );
      } else {
        feedback(
          widget.session.failure?.message ??
              tr(
                context,
                'Could not confirm the change. Refresh before retrying.',
                'មិនអាចបញ្ជាក់ការផ្លាស់ប្តូរ។ សូមធ្វើបច្ចុប្បន្នភាពមុនព្យាយាមម្តងទៀត។',
              ),
          failed: true,
        );
      }
    } catch (_) {
      if (!mounted) return;
      feedback(
        tr(
          context,
          'Could not confirm the change. Please try again.',
          'មិនអាចបញ្ជាក់ការផ្លាស់ប្តូរ។ សូមព្យាយាមម្តងទៀត។',
        ),
        failed: true,
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  String t(String en, String km) => tr(context, en, km);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final prefs = AppPreferences.of(context);
      final title = switch (widget.page) {
        'profile' => t('Personal details', 'ព័ត៌មានផ្ទាល់ខ្លួន'),
        'pin' => t('Change PIN', 'ប្តូរលេខ PIN'),
        'notifications' => t('Notifications', 'ការជូនដំណឹង'),
        'language' => t('Language', 'ភាសា'),
        'appearance' => t('Appearance', 'រូបរាង'),
        'help' => t('Help & support', 'ជំនួយ និងការគាំទ្រ'),
        'legal' => t('Terms & privacy', 'លក្ខខណ្ឌ និងឯកជនភាព'),
        _ => t('Sign out', 'ចាកចេញ'),
      };
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !sending) widget.onBack();
        },
        child: Scaffold(
          backgroundColor: AppColors.of(context).background,
          appBar: AppBar(
            leading: IconButton(
              tooltip: t('Back', 'ត្រឡប់'),
              onPressed: sending ? null : widget.onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            title: Text(title),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    if (widget.page == 'profile') ..._profile(),
                    if (widget.page == 'pin') ..._pin(),
                    if (widget.page == 'language') ...[
                      _choice(
                        'English',
                        prefs.locale.languageCode == 'en',
                        () => prefs.setLanguage(const Locale('en')),
                      ),
                      _choice(
                        'ខ្មែរ',
                        prefs.locale.languageCode == 'km',
                        () => prefs.setLanguage(const Locale('km')),
                      ),
                    ],
                    if (widget.page == 'appearance') ...[
                      _choice(
                        t('System', 'តាមប្រព័ន្ធ'),
                        prefs.themeMode == ThemeMode.system,
                        () => prefs.setThemeMode(ThemeMode.system),
                      ),
                      _choice(
                        t('Light', 'ភ្លឺ'),
                        prefs.themeMode == ThemeMode.light,
                        () => prefs.setThemeMode(ThemeMode.light),
                      ),
                      _choice(
                        t('Dark', 'ងងឹត'),
                        prefs.themeMode == ThemeMode.dark,
                        () => prefs.setThemeMode(ThemeMode.dark),
                      ),
                    ],
                    if (widget.page == 'notifications')
                      ..._notifications(prefs),
                    if (widget.page == 'help') ..._help(),
                    if (widget.page == 'legal') ..._legal(),
                    if (widget.page == 'signout') ...[
                      Text(
                        t(
                          'Sign out of Kesor Bank on this device?',
                          'ចាកចេញពីកេសរ នៅលើឧបករណ៍នេះ?',
                        ),
                        style: settingsText(
                          context,
                          18,
                          28,
                          weight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t(
                          'You can sign in again with your verified email or Telegram account.',
                          'អ្នកអាចចូលវិញជាមួយអ៊ីមែល ឬគណនី Telegram ដែលបានផ្ទៀងផ្ទាត់។',
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const ValueKey('confirm-signout'),
                        onPressed: sending
                            ? null
                            : () async {
                                setState(() => sending = true);
                                await widget.session.signOut();
                              },
                        child: Text(t('Sign out', 'ចាកចេញ')),
                      ),
                      TextButton(
                        onPressed: sending ? null : widget.onBack,
                        child: Text(t('Cancel', 'បោះបង់')),
                      ),
                    ],
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            message!,
                            style: settingsText(
                              context,
                              14,
                              22,
                              color: error
                                  ? AppPalette.semanticError
                                  : settingsNavy(context),
                            ),
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
    },
  );
  Widget _choice(String label, bool selected, VoidCallback onTap) => Semantics(
    checked: selected,
    inMutuallyExclusiveGroup: true,
    child: Card(
      child: ListTile(
        title: Text(label),
        onTap: onTap,
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? AppPalette.gold600 : null,
        ),
        selected: selected,
      ),
    ),
  );
  List<Widget> _profile() => [
    ProfilePhotoCard(widget.session),
    const SizedBox(height: 24),
    Form(
      key: form,
      child: Column(
        children: [
          _nameField(first, t('First name', 'នាមខ្លួន'), 'settings-first-name'),
          const SizedBox(height: 16),
          _nameField(last, t('Last name', 'នាមត្រកូល'), 'settings-last-name'),
          const SizedBox(height: 24),
          _saveButton(),
        ],
      ),
    ),
    const SizedBox(height: 24),
    Text(
      t('Contact information', 'ព័ត៌មានទំនាក់ទំនង'),
      style: settingsText(context, 14, 22, weight: FontWeight.w600),
    ),
    const SizedBox(height: 12),
    SelectableText(
      widget.session.identity?.email ??
          t('No recovery email connected', 'មិនមានអ៊ីមែលសង្គ្រោះ'),
    ),
    if (widget.session.identity?.email == null)
      TextButton(
        onPressed: widget.session.busy
            ? null
            : () => widget.session.openEmail(link: true),
        child: Text(t('Add recovery email', 'បន្ថែមអ៊ីមែលសង្គ្រោះ')),
      ),
    const SizedBox(height: 16),
    Text(
      widget.session.identity?.telegramLinked == true
          ? t('Telegram connected', 'បានភ្ជាប់ Telegram')
          : t('Telegram not connected', 'មិនទាន់ភ្ជាប់ Telegram'),
    ),
    if (widget.session.identity?.telegramLinked != true)
      TextButton(
        onPressed: widget.session.busy ? null : widget.session.continueTelegram,
        child: Text(t('Connect Telegram', 'ភ្ជាប់ Telegram')),
      ),
    if (widget.session.telegramPending)
      TextButton(
        onPressed: widget.session.cancelTelegram,
        child: Text(t('Cancel Telegram approval', 'បោះបង់ការយល់ព្រម Telegram')),
      ),
    TextButton(
      onPressed: widget.session.busy
          ? null
          : () async {
              await widget.session.refreshProfile();
              if (mounted) {
                feedback(
                  widget.session.failure?.message ??
                      t(
                        'Profile refreshed.',
                        'បានធ្វើបច្ចុប្បន្នភាពប្រវត្តិរូប។',
                      ),
                  failed: widget.session.failure != null,
                );
              }
            },
      child: Text(t('Refresh profile', 'ធ្វើបច្ចុប្បន្នភាពប្រវត្តិរូប')),
    ),
    if (widget.session.failure != null)
      Text(
        widget.session.failure!.message,
        style: const TextStyle(color: AppPalette.semanticError),
      ),
  ];
  Widget _nameField(
    TextEditingController controller,
    String label,
    String id,
  ) => TextFormField(
    key: ValueKey(id),
    controller: controller,
    enabled: !sending,
    maxLength: 50,
    textCapitalization: TextCapitalization.words,
    decoration: InputDecoration(labelText: label),
    validator: (value) => value == null || value.trim().isEmpty
        ? t('Enter your name.', 'សូមបញ្ចូលឈ្មោះ។')
        : null,
  );
  List<Widget> _pin() => [
    Text(
      t(
        'Enter your current PIN, then choose and confirm a new four-digit PIN. Other sessions will be signed out.',
        'បញ្ចូលលេខ PIN បច្ចុប្បន្ន រួចជ្រើសរើស និងបញ្ជាក់លេខ PIN ថ្មី ៤ ខ្ទង់។ ការចូលនៅឧបករណ៍ផ្សេងនឹងត្រូវបិទ។',
      ),
    ),
    const SizedBox(height: 24),
    Form(
      key: form,
      child: Column(
        children: [
          _pinField(
            current,
            t('Current PIN', 'លេខ PIN បច្ចុប្បន្ន'),
            'current-pin',
          ),
          const SizedBox(height: 16),
          _pinField(pin, t('New PIN', 'លេខ PIN ថ្មី'), 'new-pin'),
          const SizedBox(height: 16),
          _pinField(
            confirm,
            t('Confirm new PIN', 'បញ្ជាក់លេខ PIN ថ្មី'),
            'confirm-pin',
          ),
          const SizedBox(height: 24),
          _saveButton(),
        ],
      ),
    ),
  ];
  Widget _pinField(TextEditingController controller, String label, String id) =>
      TextFormField(
        key: ValueKey(id),
        controller: controller,
        enabled: !sending,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        enableIMEPersonalizedLearning: false,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          if (!RegExp(r'^[0-9]{4}$').hasMatch(value ?? '')) {
            return t('Enter four digits.', 'បញ្ចូលលេខ ៤ ខ្ទង់។');
          }
          if (controller == confirm && value != pin.text) {
            return t('PINs do not match.', 'លេខ PIN មិនត្រូវគ្នា។');
          }
          if (controller == pin && value == current.text) {
            return t('Choose a different PIN.', 'ជ្រើសរើសលេខ PIN ផ្សេង។');
          }
          return null;
        },
      );
  Widget _saveButton() => SizedBox(
    width: double.infinity,
    child: FilledButton(
      key: const ValueKey('settings-save'),
      onPressed: sending || widget.session.busy ? null : save,
      child: Text(
        sending
            ? t('Saving…', 'កំពុងរក្សាទុក…')
            : t('Save changes', 'រក្សាទុកការផ្លាស់ប្តូរ'),
      ),
    ),
  );
  List<Widget> _notifications(AppPreferences prefs) => [
    Text(
      t('Manage alerts on this device', 'គ្រប់គ្រងការជូនដំណឹងលើឧបករណ៍នេះ'),
      style: settingsText(context, 18, 28, weight: FontWeight.w500),
    ),
    const SizedBox(height: 12),
    Text(
      t(
        'Local alerts are shown after a transfer or account opening is confirmed while you use the app. They contain no balances or account numbers. Background push alerts are not included.',
        'ការជូនដំណឹងបង្ហាញបន្ទាប់ពីការផ្ទេរ ឬការបើកគណនីត្រូវបានបញ្ជាក់ ខណៈប្រើកម្មវិធី។ មិនបង្ហាញសមតុល្យ ឬលេខគណនីទេ។ មិនរួមបញ្ចូល Push នៅផ្ទៃខាងក្រោយទេ។',
      ),
    ),
    const SizedBox(height: 16),
    if (platform.supportsNotifications) ...[
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(t('Account activity alerts', 'ការជូនដំណឹងសកម្មភាពគណនី')),
        value: prefs.activityAlerts,
        onChanged: prefs.setActivityAlerts,
      ),
      Text(
        notificationsAllowed == null
            ? t('Checking Android permission…', 'កំពុងពិនិត្យសិទ្ធិ Android…')
            : notificationsAllowed!
            ? t(
                'Android notifications are allowed.',
                'Android អនុញ្ញាតការជូនដំណឹង។',
              )
            : t(
                'Allow notifications in Android settings to receive alerts.',
                'អនុញ្ញាតការជូនដំណឹងក្នុងការកំណត់ Android។',
              ),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () async {
          try {
            await platform.openNotifications();
          } catch (_) {
            feedback(
              t(
                'Could not open Android settings.',
                'មិនអាចបើកការកំណត់ Android។',
              ),
              failed: true,
            );
          }
        },
        child: Text(
          t(
            'Open Android notification settings',
            'បើកការកំណត់ការជូនដំណឹង Android',
          ),
        ),
      ),
      TextButton(
        onPressed: !prefs.activityAlerts
            ? null
            : () async {
                try {
                  final sent = await platform.activityAlert();
                  if (mounted) {
                    feedback(
                      sent
                          ? t(
                              'Test alert displayed.',
                              'បានបង្ហាញការជូនដំណឹងសាកល្បង។',
                            )
                          : t(
                              'Allow Android notifications first.',
                              'សូមអនុញ្ញាតការជូនដំណឹង Android ជាមុន។',
                            ),
                      failed: !sent,
                    );
                  }
                } catch (_) {
                  if (mounted) {
                    feedback(
                      t(
                        'Check Android notification permission.',
                        'ពិនិត្យសិទ្ធិការជូនដំណឹង Android។',
                      ),
                      failed: true,
                    );
                  }
                }
              },
        child: Text(t('Send test alert', 'ផ្ញើការជូនដំណឹងសាកល្បង')),
      ),
    ] else
      Text(
        t(
          'Device notifications are available in the Kesor Bank Android app.',
          'ការជូនដំណឹងមានក្នុងកម្មវិធីកេសរ លើ Android។',
        ),
      ),
  ];
  List<Widget> _help() => [
    Text(
      t('How can we help?', 'តើយើងអាចជួយអ្វីបាន?'),
      style: settingsText(context, 20, 30, weight: FontWeight.w600),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: widget.onAssistant,
      child: Text(t('Ask the AI Assistant', 'សួរជំនួយការ AI')),
    ),
    Text(
      t(
        'The assistant can explain banking activity and answer questions in English or Khmer. It cannot submit payments.',
        'ជំនួយការអាចពន្យល់សកម្មភាពធនាគារ និងឆ្លើយជាភាសាអង់គ្លេស ឬខ្មែរ។ វាមិនអាចផ្ញើប្រាក់បានទេ។',
      ),
    ),
    const SizedBox(height: 20),
    SelectableText(
      'reachsteav2@gmail.com',
      style: settingsText(context, 15, 24, color: settingsNavy(context)),
    ),
    TextButton(
      onPressed: () async {
        try {
          if (await platform.emailSupport()) return;
        } catch (_) {
          /* Copy remains available without an email app. */
        }
        if (mounted) {
          feedback(
            t(
              'No email app is available. Copy the address below to contact support.',
              'មិនមានកម្មវិធីអ៊ីមែល។ ចម្លងអាសយដ្ឋានខាងក្រោមដើម្បីទាក់ទងជំនួយ។',
            ),
          );
        }
      },
      child: Text(t('Email support', 'ផ្ញើអ៊ីមែលសុំជំនួយ')),
    ),
    TextButton(
      onPressed: () async {
        await Clipboard.setData(
          const ClipboardData(text: 'reachsteav2@gmail.com'),
        );
        if (mounted) {
          feedback(t('Support email copied.', 'បានចម្លងអ៊ីមែលជំនួយ។'));
        }
      },
      child: Text(t('Copy email address', 'ចម្លងអាសយដ្ឋានអ៊ីមែល')),
    ),
    Text(
      t(
        'Never email your PIN, passwords or verification codes.',
        'កុំផ្ញើលេខ PIN ពាក្យសម្ងាត់ ឬកូដផ្ទៀងផ្ទាត់តាមអ៊ីមែល។',
      ),
    ),
    const SizedBox(height: 24),
    _faq(
      t('Transfers and receipts', 'ការផ្ទេរ និងបង្កាន់ដៃ'),
      t(
        'Choose Home → Transfer, select a funded account, enter the receiver account and review the amount and currency before confirming. If a result is uncertain, recover the existing request instead of making another payment. Open Activity to view the confirmed receipt.',
        'ជ្រើសរើស ទំព័រដើម → ផ្ទេរប្រាក់ ហើយពិនិត្យគណនីអ្នកទទួល ចំនួនប្រាក់ និងរូបិយប័ណ្ណមុនបញ្ជាក់។ បើលទ្ធផលមិនច្បាស់ សូមសង្គ្រោះសំណើដែលមានស្រាប់ មុនផ្ញើម្តងទៀត។ មើលបង្កាន់ដៃក្នុងសកម្មភាព។',
      ),
    ),
    _faq(
      t('Forgot your PIN?', 'ភ្លេចលេខ PIN?'),
      t(
        'Lock or reopen the app, choose Forgot PIN and verify your identity again using your email or Telegram. Five incorrect attempts require identity verification.',
        'ចាក់សោ ឬបើកកម្មវិធីឡើងវិញ ជ្រើសរើស ភ្លេចលេខ PIN ហើយផ្ទៀងផ្ទាត់អត្តសញ្ញាណតាមអ៊ីមែល ឬ Telegram។ បញ្ចូលខុស ៥ ដង ត្រូវផ្ទៀងផ្ទាត់អត្តសញ្ញាណ។',
      ),
    ),
    _faq(
      t('Receiving with QR', 'ទទួលប្រាក់តាម QR'),
      t(
        'Open My QR from Home and select your USD or KHR account. Check the currency before sharing. A QR code is a payment request; confirm receipt in account activity.',
        'បើក QR របស់ខ្ញុំ ពីទំព័រដើម រួចជ្រើសរើសគណនី USD ឬ KHR។ ពិនិត្យរូបិយប័ណ្ណមុនចែករំលែក និងបញ្ជាក់ការទទួលប្រាក់ក្នុងសកម្មភាពគណនី។',
      ),
    ),
  ];
  Widget _faq(String title, String body) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text(title),
    children: [
      Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(body)),
    ],
  );
  List<Widget> _legal() => [
    Text(
      t('Demo terms & privacy', 'លក្ខខណ្ឌ និងឯកជនភាពសាកល្បង'),
      style: settingsText(context, 20, 30, weight: FontWeight.w600),
    ),
    const SizedBox(height: 12),
    Text(
      t(
        'Demo data · 31 October 2026. These sample notices describe this development app and are not production banking agreements.',
        'ទិន្នន័យសាកល្បង · ៣១ តុលា ២០២៦។ សេចក្តីជូនដំណឹងគំរូនេះសម្រាប់កម្មវិធីអភិវឌ្ឍន៍ មិនមែនជាកិច្ចព្រមព្រៀងធនាគារផ្លូវការទេ។',
      ),
    ),
    const SizedBox(height: 24),
    Text(
      t('Terms of use', 'លក្ខខណ្ឌប្រើប្រាស់'),
      style: settingsText(context, 18, 28, weight: FontWeight.w500),
    ),
    const SizedBox(height: 8),
    Text(
      t(
        'Use only an email or Telegram identity you control. Keep your PIN and verification codes private. Review the receiver, currency and amount before confirming transfers. Test funds are for development testing. Creating a profile does not itself open a financial account. The AI Assistant is read-only and cannot execute payments.',
        'ប្រើតែអ៊ីមែល ឬ Telegram របស់អ្នក។ រក្សាលេខ PIN និងកូដជាសម្ងាត់។ ពិនិត្យអ្នកទទួល រូបិយប័ណ្ណ និងចំនួនប្រាក់មុនផ្ទេរ។ ប្រាក់សាកល្បងសម្រាប់ការធ្វើតេស្ត។ ការបង្កើតប្រវត្តិរូបមិនបើកគណនីហិរញ្ញវត្ថុទេ។ ជំនួយការ AI មិនអាចផ្ញើប្រាក់បានទេ។',
      ),
    ),
    const SizedBox(height: 24),
    Text(
      t('Privacy notice', 'សេចក្តីជូនដំណឹងឯកជនភាព'),
      style: settingsText(context, 18, 28, weight: FontWeight.w500),
    ),
    const SizedBox(height: 8),
    Text(
      t(
        'The app uses your verified identity, profile name and optional photo to maintain your account. Session and security records protect access; banking records support balances, transfers and history. Profile photos require authenticated access. Language, appearance and alert choices are saved on this device. Assistant questions and answers are saved to your conversation history; when enabled, the AI service processes banking context to answer questions. Do not include PINs, passwords or verification codes in chats. Contact support for questions about this demo.',
        'កម្មវិធីប្រើអត្តសញ្ញាណ ឈ្មោះ និងរូបថតជាជម្រើសសម្រាប់គណនី។ កំណត់ត្រាសុវត្ថិភាពការពារការចូល។ ទិន្នន័យធនាគារគាំទ្រសមតុល្យ ការផ្ទេរ និងប្រវត្តិ។ រូបថតត្រូវការការចូលដែលបានផ្ទៀងផ្ទាត់។ ភាសា រូបរាង និងចំណូលចិត្តការជូនដំណឹងរក្សាទុកលើឧបករណ៍នេះ។ សំណួរ និងចម្លើយជំនួយការរក្សាទុកក្នុងប្រវត្តិសន្ទនា ហើយសេវា AI អាចប្រើបរិបទធនាគារដើម្បីឆ្លើយនៅពេលបើក។ កុំបញ្ចូលលេខ PIN ពាក្យសម្ងាត់ ឬកូដក្នុងសន្ទនា។ ទាក់ទងជំនួយសម្រាប់សំណួរអំពីការសាកល្បងនេះ។',
      ),
    ),
    const SizedBox(height: 24),
    const SelectableText('reachsteav2@gmail.com'),
  ];
}
