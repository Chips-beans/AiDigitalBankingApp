import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/kesor_layout.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../app/app_labels.dart';
import '../../../app/app_preferences.dart';
import '../../../shared/widgets/preference_controls.dart';
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
          constraints: const BoxConstraints(maxWidth: KesorLayout.frameWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KesorLayout.gutter),
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
                if (AppPreferences.maybeOf(context) != null) ...[
                  const Align(
                    alignment: Alignment.centerRight,
                    child: PreferenceControls(),
                  ),
                  const SizedBox(height: 20),
                ],
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
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
          tx(context, 'Check your email'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            context,
            'If eligible, a 6-digit code was sent to ${session.otpEmail}. Check your spam folder too.',
            'បើអាចប្រើបាន លេខកូដ ៦ ខ្ទង់ត្រូវបានផ្ញើទៅ ${session.otpEmail}។ សូមពិនិត្យថតសារឥតបានការផងដែរ។',
          ),
        ),
        const SizedBox(height: 24),
        if (widget.demo)
          NoticePanel(
            tx(context, 'Demo mode: use code 123456. No email is sent.'),
          ),
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
            decoration: InputDecoration(
              labelText: tx(context, 'Email code'),
              hintText: tx(context, '6 digits'),
            ),
            validator: (v) =>
                v?.length == 6 ? null : tx(context, 'Enter the 6-digit code.'),
            onFieldSubmitted: (_) => _verify(),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          session.expirySeconds > 0
              ? '${tr(context, 'Code expires in', 'លេខកូដផុតកំណត់ក្នុង')} ${session.expirySeconds ~/ 60}:${(session.expirySeconds % 60).toString().padLeft(2, '0')}'
              : tx(context, 'This code has expired. Request a new one.'),
        ),
        const SizedBox(height: 24),
        BusyButton(
          label: tx(context, 'Verify and continue'),
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
                ? '${tr(context, 'Resend code in', 'ផ្ញើម្ដងទៀតក្នុង')} ${session.resendSeconds}s'
                : tx(context, 'Resend code'),
          ),
        ),
        TextButton(
          onPressed: session.busy ? null : session.back,
          child: Text(tx(context, 'Change your details')),
        ),
      ],
    );
  }
}
