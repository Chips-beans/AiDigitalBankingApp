import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../shared/widgets/app_states.dart';
import '../session_controller.dart';
import 'auth_pages.dart';

class ContinueWelcomePage extends StatelessWidget {
  const ContinueWelcomePage(this.session, {super.key});
  final SessionController session;
  static const navy = Color(0xFF142D4E), gold = Color(0xFFCEA528);
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
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                minHeight: constraints.maxHeight,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, box) => ExcludeSemantics(
                          child: SizedBox(
                            height: box.maxWidth * .96,
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                maxHeight: double.infinity,
                                child: Image.asset(
                                  'assets/auth/welcome-reference.png',
                                  width: box.maxWidth,
                                  fit: BoxFit.fitWidth,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SvgPicture.asset(
                        'assets/home/kesor-logo.svg',
                        width: 88,
                        height: 104,
                        semanticsLabel: 'Kesor Bank',
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text.rich(
                          const TextSpan(
                            children: [
                              TextSpan(text: 'Elegance in '),
                              TextSpan(
                                text: 'Simplicity.',
                                style: TextStyle(color: Color(0xFF916B13)),
                              ),
                              TextSpan(text: '\nBanking without '),
                              TextSpan(
                                text: 'Complexity.',
                                style: TextStyle(color: Color(0xFF916B13)),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 23,
                            height: 1.55,
                            color: navy,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (session.failure != null)
                              NoticePanel(
                                session.failure!.message,
                                error: true,
                              ),
                            if (session.notice != null)
                              NoticePanel(session.notice!),
                            FilledButton.icon(
                              onPressed: session.busy
                                  ? null
                                  : session.continueTelegram,
                              style: FilledButton.styleFrom(
                                backgroundColor: gold,
                                foregroundColor: navy,
                                minimumSize: const Size(48, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 15,
                                ),
                              ),
                              icon: ExcludeSemantics(
                                child: SvgPicture.asset(
                                  'assets/auth/telegram.svg',
                                  width: 24,
                                  height: 24,
                                ),
                              ),
                              label: Text(
                                session.telegramPending
                                    ? 'Waiting for Telegram…'
                                    : 'Continue with Telegram',
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: session.busy
                                  ? null
                                  : session.openEmail,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFF3F3F3),
                                foregroundColor: navy,
                                minimumSize: const Size(48, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 15,
                                ),
                              ),
                              icon: const ExcludeSemantics(
                                child: Icon(
                                  Icons.mail_outline_rounded,
                                  size: 24,
                                ),
                              ),
                              label: const Text('Continue with Email'),
                            ),
                            if (session.telegramPending) ...[
                              const SizedBox(height: 16),
                              const Text(
                                'Approve in the Telegram window, then return here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: navy),
                              ),
                              TextButton(
                                onPressed: session.cancelTelegram,
                                child: const Text(
                                  'Cancel Telegram approval',
                                  style: TextStyle(color: navy),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                    child: Column(
                      children: [
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => _policy(context, false),
                              child: const Text(
                                'Terms & Conditions',
                                style: TextStyle(color: navy, fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _policy(context, true),
                              child: const Text(
                                'Privacy Policy',
                                style: TextStyle(color: navy, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          '© 2026 Kesor Bank PLC. All rights reserved.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF4C5260),
                            fontFamily: 'Poppins',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
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
          session.linkingEmail ? 'Connect your email' : 'Continue with email',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          session.linkingEmail
              ? 'Verify an email you control. If it already has a profile, we’ll help you use that profile.'
              : 'We’ll send a verification code. Your profile will be ready whether you’re new or returning.',
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
                    labelText: 'Email address',
                    errorText: session.failure?.fields['email'],
                  ),
                  validator: (value) =>
                      value != null &&
                          value.trim().length <= 100 &&
                          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(value.trim())
                      ? null
                      : 'Enter a valid email address.',
                  onFieldSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 24),
                BusyButton(
                  label: 'Send verification code',
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
          'A little about you',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Your identity is verified. Complete your details to make this profile yours.',
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
                  (first, 'firstName', 'First name', AutofillHints.givenName),
                  (last, 'lastName', 'Last name', AutofillHints.familyName),
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
                        ? 'Enter your ${entry.$3.toLowerCase()}.'
                        : v.trim().length > 50
                        ? 'Use at most 50 characters.'
                        : null,
                    onFieldSubmitted: entry.$2 == 'lastName'
                        ? (_) => submit()
                        : null,
                  ),
                  const SizedBox(height: 20),
                ],
                BusyButton(
                  label: 'Continue to Kesor',
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
            child: const Text('Connect an existing email profile'),
          ),
        ],
        const SizedBox(height: 24),
        TextButton(
          onPressed: session.signOut,
          child: const Text('Use another identity'),
        ),
      ],
    );
  }
}
