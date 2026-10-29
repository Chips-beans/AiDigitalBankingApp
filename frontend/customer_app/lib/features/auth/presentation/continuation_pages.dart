import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/design_system/design_system.dart';
import '../../../app/app_preferences.dart';
import '../../../app/app_labels.dart';
import '../../../shared/widgets/kesor_layout.dart';
import '../../../shared/widgets/preference_controls.dart';
import '../../../shared/widgets/app_states.dart';
import '../session_controller.dart';
import 'auth_pages.dart';

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
  const EmailContinuePage(this.session, {super.key});
  final SessionController session;
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
    return AuthLayout(
      onBack: session.busy ? null : session.back,
      children: [
        const Icon(Icons.mail_outline_rounded, size: 36),
        const SizedBox(height: 24),
        Text(
          session.linkingEmail
              ? tx(context, 'Connect your email')
              : tx(context, 'Continue with email'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          session.linkingEmail
              ? tx(
                  context,
                  'Verify an email you control. If it already has a profile, we’ll help you use that profile.',
                )
              : tx(
                  context,
                  'We’ll send a verification code. Your profile will be ready whether you’re new or returning.',
                ),
        ),
        const SizedBox(height: 32),
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
              children: [
                TextFormField(
                  key: const ValueKey('email'),
                  controller: email,
                  enabled: !session.busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: tx(context, 'Email address'),
                    errorText: session.failure?.fields['email'],
                  ),
                  validator: (value) =>
                      value != null &&
                          value.trim().length <= 100 &&
                          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(value.trim())
                      ? null
                      : tx(context, 'Enter a valid email address.'),
                  onFieldSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 24),
                BusyButton(
                  label: tx(context, 'Send verification code'),
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
  const InformationPage(this.session, {super.key});
  final SessionController session;
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
  @override
  void dispose() {
    first.dispose();
    last.dispose();
    summary.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await widget.session.completeInformation(first.text, last.text);
    if (mounted && widget.session.failure != null) summary.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AuthLayout(
      children: [
        Text(
          tx(context, 'A little about you'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          tx(
            context,
            'Your identity is verified. Complete your details to make this profile yours.',
          ),
        ),
        const SizedBox(height: 32),
        if (session.failure != null)
          NoticePanel(
            session.failure!.message,
            error: true,
            focusNode: summary,
          ),
        Form(
          key: form,
          child: AutofillGroup(
            child: Column(
              children: [
                for (final entry in [
                  (
                    first,
                    'firstName',
                    tx(context, 'First name'),
                    AutofillHints.givenName,
                  ),
                  (
                    last,
                    'lastName',
                    tx(context, 'Last name'),
                    AutofillHints.familyName,
                  ),
                ]) ...[
                  TextFormField(
                    key: ValueKey(entry.$2),
                    controller: entry.$1,
                    enabled: !session.busy,
                    autofillHints: [entry.$4],
                    textCapitalization: TextCapitalization.words,
                    textInputAction: entry.$2 == 'lastName'
                        ? TextInputAction.done
                        : TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: entry.$3,
                      errorText: session.failure?.fields[entry.$2],
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? tr(
                            context,
                            'Enter your ${entry.$3.toLowerCase()}.',
                            'សូមបញ្ចូល${entry.$3}។',
                          )
                        : v.trim().length > 50
                        ? tx(context, 'Use at most 50 characters.')
                        : null,
                    onFieldSubmitted: entry.$2 == 'lastName'
                        ? (_) => submit()
                        : null,
                  ),
                  const SizedBox(height: 20),
                ],
                BusyButton(
                  label: tx(context, 'Continue to Kesor'),
                  busy: session.busy,
                  onPressed: submit,
                ),
              ],
            ),
          ),
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
        const SizedBox(height: 24),
        TextButton(
          onPressed: session.signOut,
          child: Text(tx(context, 'Use another identity')),
        ),
      ],
    );
  }
}
