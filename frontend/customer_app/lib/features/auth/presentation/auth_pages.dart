import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/app_states.dart';
import '../session_controller.dart';

class AuthLayout extends StatelessWidget {
  const AuthLayout({required this.children, this.onBack, super.key});
  final List<Widget> children;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onBack != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: onBack,
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class WelcomePage extends StatelessWidget {
  const WelcomePage(this.session, {super.key});
  final SessionController session;
  @override
  Widget build(BuildContext context) => AuthLayout(
    children: [
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF142D4E),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.account_balance_outlined,
                color: Color(0xFFF5D99D),
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'DIGITAL BANKING',
              style: TextStyle(
                color: Color(0xFFF5D99D),
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'A simpler start\nto everyday banking.',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your profile. Your session.\nReady when you are.',
              style: TextStyle(
                color: Color(0xFFD7E2F0),
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 32),
      Text('Welcome', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      const Text('Sign in or create your customer profile to get started.'),
      const SizedBox(height: 24),
      if (session.notice != null) NoticePanel(session.notice!),
      BusyButton(
        label: 'Sign in',
        busy: session.busy,
        onPressed: () => session.openForm(register: false),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: session.busy ? null : () => session.openForm(register: true),
        child: const Text('Create a profile'),
      ),
      const SizedBox(height: 24),
      const Text(
        'We’ll send an email code each time you sign in.',
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class CredentialsPage extends StatefulWidget {
  const CredentialsPage(this.session, {required this.register, super.key});
  final SessionController session;
  final bool register;
  @override
  State<CredentialsPage> createState() => _CredentialsPageState();
}

class _CredentialsPageState extends State<CredentialsPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _username = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  final _summary = FocusNode();
  bool _visible = false, _submitted = false;
  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    _summary.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    setState(() => _submitted = true);
    if (!_form.currentState!.validate()) {
      _summary.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    final success = await widget.session.begin(
      email: _email.text,
      password: _password.text,
      username: _username.text,
      register: widget.register,
    );
    if (success) {
      _password.clear();
      _confirm.clear();
    }
    if (!success && mounted) _summary.requestFocus();
  }

  Widget _field({
    required String label,
    required String name,
    required TextEditingController controller,
    required String? Function(String) validate,
    bool secret = false,
    TextInputType? keyboard,
    Iterable<String>? autofill,
    TextInputAction action = TextInputAction.next,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: TextFormField(
      key: ValueKey(name),
      controller: controller,
      enabled: !widget.session.busy,
      obscureText: secret && !_visible,
      enableSuggestions: !secret,
      autocorrect: false,
      keyboardType: keyboard,
      autofillHints: autofill,
      textInputAction: action,
      onFieldSubmitted: action == TextInputAction.done
          ? (_) => _continue()
          : null,
      validator: (value) => validate(value ?? ''),
      decoration: InputDecoration(
        labelText: label,
        errorMaxLines: 4,
        errorText: widget.session.failure?.fields[name],
        suffixIcon: secret && name == 'password'
            ? IconButton(
                onPressed: () => setState(() => _visible = !_visible),
                tooltip: _visible ? 'Hide password' : 'Show password',
                icon: Icon(
                  _visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              )
            : null,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AuthLayout(
      onBack: session.busy ? null : session.back,
      children: [
        Text(
          widget.register ? 'Create your profile' : 'Welcome back',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Enter your details, then confirm the code sent to your email.',
        ),
        const SizedBox(height: 24),
        if (session.failure != null)
          NoticePanel(
            session.failure!.message,
            error: true,
            focusNode: _summary,
          )
        else if (_submitted)
          NoticePanel(
            'Check your details below before continuing.',
            focusNode: _summary,
          )
        else if (session.notice != null)
          NoticePanel(session.notice!),
        AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              children: [
                if (widget.register)
                  _field(
                    label: 'Username',
                    name: 'username',
                    controller: _username,
                    autofill: const [AutofillHints.newUsername],
                    validate: (v) =>
                        RegExp(r'^[a-zA-Z0-9._-]{3,50}$').hasMatch(v.trim())
                        ? null
                        : 'Use 3–50 letters, numbers, dots, dashes or underscores.',
                  ),
                _field(
                  label: 'Email address',
                  name: 'email',
                  controller: _email,
                  keyboard: TextInputType.emailAddress,
                  autofill: const [AutofillHints.email],
                  validate: (v) =>
                      v.trim().length <= 100 &&
                          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(v.trim())
                      ? null
                      : 'Enter a valid email address.',
                ),
                _field(
                  label: 'Password',
                  name: 'password',
                  controller: _password,
                  secret: true,
                  autofill: [
                    widget.register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  action: widget.register
                      ? TextInputAction.next
                      : TextInputAction.done,
                  validate: (v) {
                    if (v.trim().isEmpty) return 'Enter your password.';
                    if (widget.register && v.length < 8) {
                      return 'Use at least 8 characters.';
                    }
                    if (utf8.encode(v).length > 72) {
                      return 'Use a password of at most 72 UTF-8 bytes.';
                    }
                    return null;
                  },
                ),
                if (widget.register)
                  _field(
                    label: 'Confirm password',
                    name: 'confirmPassword',
                    controller: _confirm,
                    secret: true,
                    action: TextInputAction.done,
                    validate: (v) =>
                        v == _password.text ? null : 'Passwords must match.',
                  ),
                BusyButton(
                  label: 'Send email code',
                  busy: session.busy,
                  onPressed: _continue,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: session.busy
              ? null
              : () => session.openForm(register: !widget.register),
          child: Text(
            widget.register
                ? 'Already have a profile? Sign in'
                : 'New here? Create a profile',
          ),
        ),
      ],
    );
  }
}

class OtpPage extends StatefulWidget {
  const OtpPage(this.session, {required this.demo, super.key});
  final SessionController session;
  final bool demo;
  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      widget.session.expirePendingIfNeeded();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final success = await widget.session.verifyCode(_code.text);
    if (success) TextInput.finishAutofillContext();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AuthLayout(
      onBack: session.busy ? null : session.back,
      children: [
        const ExcludeSemantics(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.mark_email_read_outlined, size: 40),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Check your email',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          'If eligible, a 6-digit code was sent to ${session.otpEmail}. Check your spam folder too.',
        ),
        const SizedBox(height: 24),
        if (widget.demo)
          const NoticePanel('Demo mode: use code 123456. No email is sent.'),
        if (session.failure != null)
          NoticePanel(session.failure!.message, error: true),
        if (session.notice != null) NoticePanel(session.notice!),
        Form(
          key: _form,
          child: TextFormField(
            key: const ValueKey('otpCode'),
            controller: _code,
            enabled: !session.busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              labelText: 'Email code',
              hintText: '6 digits',
            ),
            validator: (v) => v?.length == 6 ? null : 'Enter the 6-digit code.',
            onFieldSubmitted: (_) => _verify(),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          session.expirySeconds > 0
              ? 'Code expires in ${session.expirySeconds ~/ 60}:${(session.expirySeconds % 60).toString().padLeft(2, '0')}'
              : 'This code has expired. Request a new one.',
        ),
        const SizedBox(height: 24),
        BusyButton(
          label: session.registering ? 'Create profile' : 'Sign in',
          busy: session.busy,
          onPressed: session.expirySeconds == 0 ? null : _verify,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: session.busy || session.resendSeconds > 0
              ? null
              : () async {
                  _code.clear();
                  await session.resend();
                },
          child: Text(
            session.resendSeconds > 0
                ? 'Resend code in ${session.resendSeconds}s'
                : 'Resend code',
          ),
        ),
        TextButton(
          onPressed: session.busy ? null : session.back,
          child: const Text('Change your details'),
        ),
      ],
    );
  }
}

class SignedInPage extends StatelessWidget {
  const SignedInPage(this.session, {super.key});
  final SessionController session;
  @override
  Widget build(BuildContext context) => AuthLayout(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Your profile',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          IconButton(
            onPressed: session.busy ? null : session.refreshProfile,
            tooltip: 'Refresh profile',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const SizedBox(height: 32),
      const ExcludeSemantics(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.check_circle_outline, size: 48),
        ),
      ),
      const SizedBox(height: 24),
      Text(
        'You’re signed in.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('USERNAME'),
              const SizedBox(height: 8),
              Text(
                session.identity!.username,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              const Text('EMAIL'),
              const SizedBox(height: 8),
              SelectableText(session.identity!.email),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      if (session.failure != null)
        NoticePanel(session.failure!.message, error: true),
      if (session.notice != null) NoticePanel(session.notice!),
      BusyButton(
        label: 'Sign out',
        busy: session.busy,
        onPressed: session.signOut,
      ),
    ],
  );
}
