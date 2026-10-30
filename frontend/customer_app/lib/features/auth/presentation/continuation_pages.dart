import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/design_system/design_system.dart';
import '../../../app/app_preferences.dart';
import '../../../app/app_labels.dart';
import '../../../shared/widgets/kesor_layout.dart';
import '../../../shared/widgets/preference_controls.dart';
import '../../../shared/widgets/app_states.dart';
import '../session_controller.dart';
import 'email_auth_layout.dart';
import 'profile_photo_card.dart';

class ContinueWelcomePage extends StatelessWidget {
  const ContinueWelcomePage(this.session, {super.key});
  final SessionController session;
  void _policy(BuildContext context, bool privacy) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(privacy ? 'Privacy Policy' : 'Terms & Conditions'),
      content: SingleChildScrollView(
        child: Text(
          privacy
              ? 'Kesor Bank uses your verified email or Telegram identity to recognize your profile. Your name completes your profile. Device and session information helps secure access. Email verification sends a code to the address you provide. Telegram receives your request to approve access; your banking activity is not sent as part of that request.'
              : 'Continue using an email or Telegram identity that you control. Keep verification codes private and use the app only for authorized activity. Creating a customer profile does not itself open a bank account. Contact the service operator for the agreements applicable to banking services.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _welcomeAction({
    required Key key,
    required Color background,
    required Color foreground,
    required String icon,
    required String label,
    required VoidCallback? onPressed,
  }) => FilledButton(
    key: key,
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      minimumSize: const Size(48, KesorLayout.actionHeight),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KesorLayout.actionRadius),
      ),
      textStyle: AppTypography.khmer.body,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          icon,
          width: 24,
          height: 24,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 16),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    ),
  );

  Widget _policyLinks(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.clamp(0.0, 280.0);
      final style =
          (AppPreferences.of(context).isKhmer
                  ? AppTypography.khmer.caption
                  : AppTypography.english.caption)
              .copyWith(
                height: 18 / 12,
                color: AppColors.of(context).disabledBackground,
              );
      final text = tr(
        context,
        'Terms & Conditions • Privacy Policy',
        'លក្ខខណ្ឌប្រើប្រាស់ • គោលការណ៍ឯកជនភាព',
      );
      final measure = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: width);
      final height = measure.height.clamp(48.0, double.infinity);
      measure.dispose();
      return SizedBox(
        width: width,
        height: height,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            ExcludeSemantics(
              child: Text(text, textAlign: TextAlign.center, style: style),
            ),
            Positioned.fill(
              child: Row(
                children: [
                  for (final privacy in [false, true])
                    Expanded(
                      child: TextButton(
                        onPressed: () => _policy(context, privacy),
                        child: Semantics(
                          label: privacy
                              ? tr(context, 'Privacy Policy', 'គោលការណ៍ឯកជនភាព')
                              : tr(
                                  context,
                                  'Terms & Conditions',
                                  'លក្ខខណ្ឌប្រើប្រាស់',
                                ),
                          child: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final khmer = AppPreferences.of(context).isKhmer;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: KesorLayout.frameWidth,
                  minHeight: viewport.maxHeight,
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final scale = box.maxWidth / KesorLayout.frameWidth;
                    return Stack(
                      children: [
                        Positioned(
                          top: dark ? -2 * scale : 0,
                          left: -6 * scale,
                          child: Image.asset(
                            'assets/auth/${dark ? 'auth-night' : 'auth-day'}.png',
                            width: 447 * scale,
                            height: 447 * scale,
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                          ),
                        ),
                        Positioned(
                          top: 268.2 * scale,
                          left: 0,
                          right: 0,
                          height: (dark ? 160.68 : 178.55) * scale,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  colors.background.withValues(alpha: 0),
                                  colors.background,
                                ],
                              ),
                            ),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: viewport.maxHeight,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                children: [
                                  SizedBox(height: 428.2 * scale - 4),
                                  const Padding(
                                    padding: EdgeInsets.only(right: 19),
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: PreferenceControls(),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 126 * scale,
                                    height: 126 * scale,
                                    child: Padding(
                                      padding: EdgeInsets.only(top: 12 * scale),
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: SvgPicture.asset(
                                          'assets/auth/auth-logo-${dark ? 'dark' : 'light'}.svg',
                                          width: 84 * scale,
                                          height: 105 * scale,
                                          semanticsLabel: 'Kesor Bank',
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 12 * scale),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: khmer
                                                ? 'ភាពប្រណីតក្នុង '
                                                : 'Elegance in ',
                                          ),
                                          TextSpan(
                                            text: khmer
                                                ? 'ភាពសាមញ្ញ។'
                                                : 'Simplicity.',
                                            style: TextStyle(
                                              color: dark
                                                  ? colors.primary500
                                                  : colors.primary700,
                                            ),
                                          ),
                                          TextSpan(
                                            text: khmer
                                                ? '\nធនាគារគ្មាន '
                                                : '\nBanking without ',
                                          ),
                                          TextSpan(
                                            text: khmer
                                                ? 'ភាពស្មុគស្មាញ។'
                                                : 'Complexity.',
                                            style: TextStyle(
                                              color: dark
                                                  ? colors.primary500
                                                  : colors.primary700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      textAlign: TextAlign.center,
                                      style:
                                          (khmer
                                                  ? AppTypography.khmer.titleXL
                                                  : AppTypography
                                                        .english
                                                        .titleXL)
                                              .copyWith(
                                                fontSize: box.maxWidth < 400
                                                    ? 22
                                                    : 24,
                                                color: colors.foreground,
                                              ),
                                    ),
                                  ),
                                  const SizedBox(height: 44),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (session.failure != null)
                                          NoticePanel(
                                            session.failure!.message,
                                            error: true,
                                          ),
                                        if (session.notice != null)
                                          NoticePanel(session.notice!),
                                        _welcomeAction(
                                          key: const ValueKey(
                                            'welcome-telegram',
                                          ),
                                          background: colors.primary500,
                                          foreground: Colors.white,
                                          icon:
                                              'assets/auth/auth-telegram-${dark ? 'dark' : 'light'}.svg',
                                          onPressed: session.busy
                                              ? null
                                              : session.continueTelegram,
                                          label: session.telegramPending
                                              ? tr(
                                                  context,
                                                  'Waiting for Telegram…',
                                                  'កំពុងរង់ចាំ Telegram…',
                                                )
                                              : tr(
                                                  context,
                                                  'Continue with Telegram',
                                                  'បន្តជាមួយ Telegram',
                                                ),
                                        ),
                                        const SizedBox(height: 16),
                                        _welcomeAction(
                                          key: const ValueKey('welcome-email'),
                                          background: colors.surface,
                                          foreground: colors.foreground,
                                          icon:
                                              'assets/auth/auth-email-${dark ? 'dark' : 'light'}.svg',
                                          onPressed: session.busy
                                              ? null
                                              : session.openEmail,
                                          label: tr(
                                            context,
                                            'Continue with Email',
                                            'បន្តជាមួយអ៊ីមែល',
                                          ),
                                        ),
                                        if (session.telegramPending) ...[
                                          const SizedBox(height: 16),
                                          Text(
                                            tr(
                                              context,
                                              'Approve in the Telegram window, then return here.',
                                              'យល់ព្រមក្នុងផ្ទាំង Telegram រួចត្រឡប់មកទីនេះ។',
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          TextButton(
                                            onPressed: session.cancelTelegram,
                                            child: Text(
                                              tr(
                                                context,
                                                'Cancel Telegram approval',
                                                'បោះបង់ការយល់ព្រម Telegram',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  24,
                                  20,
                                  18,
                                ),
                                child: Column(
                                  children: [
                                    _policyLinks(context),
                                    Text(
                                      '© 2026 Kesor Bank Plc. All rights reserved.',
                                      textAlign: TextAlign.center,
                                      style: AppTypography.english.caption
                                          .copyWith(
                                            fontWeight: FontWeight.w300,
                                            height: 18 / 12,
                                            color: colors.disabledBackground,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EmailContinuePage extends StatefulWidget {
  const EmailContinuePage(
    this.session, {
    this.showDeviceChrome = false,
    super.key,
  });
  final SessionController session;
  final bool showDeviceChrome;
  @override
  State<EmailContinuePage> createState() => _EmailContinuePageState();
}

class _EmailContinuePageState extends State<EmailContinuePage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final summary = FocusNode();
  @override
  void dispose() {
    email.dispose();
    summary.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final ok = await widget.session.beginEmail(email.text);
    if (!ok && mounted) summary.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return EmailAuthLayout(
      showDeviceChrome: widget.showDeviceChrome,
      onBack: session.busy ? null : session.back,
      children: [
        if (session.linkingEmail) ...[
          Text(
            tx(context, 'Connect your email'),
            style: AppTextStyles.of(context).titleXL,
          ),
          const SizedBox(height: 8),
          Text(
            tx(
              context,
              'Verify an email you control. If it already has a profile, we’ll help you use that profile.',
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (session.failure != null)
          NoticePanel(
            session.failure!.message,
            error: true,
            focusNode: summary,
          ),
        if (session.notice != null) NoticePanel(session.notice!),
        Form(
          key: form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EmailAuthField(
                  label: tx(context, 'Email address'),
                  hint: 'example@gmail.com',
                  controller: email,
                  fieldKey: const ValueKey('email'),
                  enabled: !session.busy,
                  email: true,
                  autofillHints: const [AutofillHints.email],
                  errorText: session.failure?.fields['email'],
                  validator: (value) =>
                      value != null &&
                          value.trim().length <= 100 &&
                          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(value.trim())
                      ? null
                      : tx(context, 'Enter a valid email address.'),
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 24),
                EmailAuthButton(
                  label: tx(context, 'Send Code'),
                  busy: session.busy,
                  onPressed: submit,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class InformationPage extends StatefulWidget {
  const InformationPage(
    this.session, {
    this.showDeviceChrome = false,
    super.key,
  });
  final SessionController session;
  final bool showDeviceChrome;
  @override
  State<InformationPage> createState() => _InformationPageState();
}

class _InformationPageState extends State<InformationPage> {
  final form = GlobalKey<FormState>();
  final summary = FocusNode();
  late final first = TextEditingController(
    text: widget.session.identity?.firstName ?? '',
  );
  late final last = TextEditingController(
    text: widget.session.identity?.lastName ?? '',
  );
  bool agreed = false, consentError = false;
  @override
  void dispose() {
    first.dispose();
    last.dispose();
    summary.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final valid = form.currentState!.validate();
    setState(() => consentError = !agreed);
    if (!valid || !agreed) return;
    FocusScope.of(context).unfocus();
    await widget.session.completeInformation(first.text, last.text);
    if (mounted && widget.session.failure != null) summary.requestFocus();
  }

  Widget nameField(bool given) => EmailAuthField(
    label: tx(context, given ? 'First Name' : 'Last Name'),
    hint: tx(context, given ? 'Your First Name' : 'Your Last Name'),
    controller: given ? first : last,
    fieldKey: ValueKey(given ? 'firstName' : 'lastName'),
    enabled: !widget.session.busy,
    autofillHints: [given ? AutofillHints.givenName : AutofillHints.familyName],
    action: given ? TextInputAction.next : TextInputAction.done,
    errorText: widget.session.failure?.fields[given ? 'firstName' : 'lastName'],
    validator: (value) => value == null || value.trim().isEmpty
        ? tr(
            context,
            'Enter your ${given ? 'first' : 'last'} name.',
            given ? 'សូមបញ្ចូលនាមខ្លួន។' : 'សូមបញ្ចូលនាមត្រកូល។',
          )
        : value.trim().length > 50
        ? tx(context, 'Use at most 50 characters.')
        : null,
    onSubmitted: given ? null : (_) => submit(),
  );
  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final colors = AppColors.of(context);
    final text = AppTextStyles.of(context);
    final navy = Theme.of(context).brightness == Brightness.dark
        ? colors.foreground
        : colors.accent500;
    return EmailAuthLayout(
      showDeviceChrome: widget.showDeviceChrome,
      verification: true,
      onBack: session.busy || session.photoBusy ? null : session.signOut,
      children: [
        Text(
          tx(context, 'Create profile'),
          style: text.titleXL.copyWith(color: navy),
        ),
        const SizedBox(height: 8),
        Text(
          tx(
            context,
            'Let’s get to know you. Add your details to get started.',
          ),
          style: text.body.copyWith(color: colors.disabledBackground),
        ),
        const SizedBox(height: 24),
        ListenableBuilder(
          listenable: Listenable.merge([first, last]),
          builder: (context, _) => ProfilePhotoCard(
            session,
            displayName: first.text.trim().isEmpty ? last.text : first.text,
          ),
        ),
        const SizedBox(height: 24),
        if (session.failure != null)
          NoticePanel(
            session.failure!.message,
            error: true,
            focusNode: summary,
          ),
        Form(
          key: form,
          child: AutofillGroup(
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20) {
                  return Column(
                    children: [
                      nameField(true),
                      const SizedBox(height: 20),
                      nameField(false),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: nameField(true)),
                    const SizedBox(width: 20),
                    Expanded(child: nameField(false)),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: tx(
            context,
            'I agree to the Terms & Conditions and Privacy Policy',
          ),
          checked: agreed,
          child: InkWell(
            key: const ValueKey('profile-consent'),
            onTap: session.busy
                ? null
                : () => setState(() {
                    agreed = !agreed;
                    consentError = false;
                  }),
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: agreed ? colors.primary500 : colors.background,
                        border: Border.all(
                          color: consentError ? colors.error : colors.border,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: agreed
                          ? const Icon(
                              Icons.check,
                              size: 13,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tx(
                          context,
                          'I agree to the Terms & Conditions and Privacy Policy',
                        ),
                        style: text.caption.copyWith(color: navy),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (consentError)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                tx(
                  context,
                  'Please agree to the terms and privacy policy to continue.',
                ),
                style: text.caption.copyWith(color: colors.error),
              ),
            ),
          ),
        EmailAuthButton(
          label: tx(context, 'Create Account'),
          busy: session.busy,
          onPressed: session.photoBusy ? null : submit,
        ),
        if (session.identity!.telegramLinked &&
            session.identity!.email == null) ...[
          const SizedBox(height: 24),
          TextButton(
            onPressed: session.busy
                ? null
                : () => session.openEmail(link: true),
            child: Text(tx(context, 'Connect an existing email profile')),
          ),
        ],
      ],
    );
  }
}
