import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../../../shared/widgets/kesor_layout.dart';
import '../../../shared/widgets/preference_controls.dart';

/// Layout of Figma 252:150 / 256:150 / 258:150. Native builds use OS chrome.
class EmailAuthLayout extends StatelessWidget {
  const EmailAuthLayout({
    required this.children,
    required this.onBack,
    this.verification = false,
    this.showDeviceChrome = false,
    super.key,
  });
  final List<Widget> children;
  final VoidCallback? onBack;
  final bool verification, showDeviceChrome;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        top: !showDeviceChrome,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: KesorLayout.frameWidth),
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDeviceChrome)
                            ExcludeSemantics(
                              child: SizedBox(
                                height: 54,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 37,
                                    right: 30,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '9:41',
                                        style: TextStyle(
                                          fontFamily: 'Google Sans',
                                          fontSize: 17,
                                          color: colors.foreground,
                                        ),
                                      ),
                                      SvgPicture.asset(
                                        'assets/auth/email-device-status.svg',
                                        width: 75.67,
                                        height: 13,
                                        colorFilter:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? ColorFilter.mode(
                                                colors.foreground,
                                                BlendMode.srcIn,
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          SizedBox(
                            height: 54,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 22,
                                right: 24,
                                top: 6,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    key: const ValueKey('email-auth-back'),
                                    tooltip: tr(context, 'Back', 'ត្រឡប់ក្រោយ'),
                                    onPressed: onBack,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 48,
                                      height: 48,
                                    ),
                                    icon: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: colors.surface,
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: SvgPicture.asset(
                                        'assets/auth/${verification ? 'email-verification-back' : 'email-back'}.svg',
                                        width: 22,
                                        height: 22,
                                        excludeFromSemantics: true,
                                        colorFilter:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? ColorFilter.mode(
                                                colors.foreground,
                                                BlendMode.srcIn,
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                                  if (AppPreferences.maybeOf(context) != null)
                                    PreferenceControls(
                                      emailAuth: true,
                                      verification: verification,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 39, 24, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: children,
                            ),
                          ),
                        ],
                      ),
                      const EmailAuthLegal(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showAuthPolicy(BuildContext context, bool privacy) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(
      tr(
        context,
        privacy ? 'Privacy Policy' : 'Terms & Conditions',
        privacy ? 'គោលការណ៍ឯកជនភាព' : 'លក្ខខណ្ឌប្រើប្រាស់',
      ),
    ),
    content: SingleChildScrollView(
      child: Text(
        tr(
          context,
          privacy
              ? 'Kesor Bank uses your verified identity, name and optional profile photo to provide your customer profile. Verification codes and session information help secure access. Your photo is stored with your profile and is available only through authenticated access.'
              : 'Use an identity that you control and keep verification codes private. Creating a customer profile does not open a financial account. Contact the service operator for the full agreements applicable to banking services.',
          privacy
              ? 'កេសរប្រើអត្តសញ្ញាណដែលបានផ្ទៀងផ្ទាត់ ឈ្មោះ និងរូបថតជាជម្រើសសម្រាប់ប្រវត្តិរូបរបស់អ្នក។ រូបថតអាចមើលបានតែតាមការចូលគណនីដែលបានផ្ទៀងផ្ទាត់។'
              : 'ប្រើអត្តសញ្ញាណរបស់អ្នក និងរក្សាលេខកូដជាសម្ងាត់។ ការបង្កើតប្រវត្តិរូបមិនបើកគណនីហិរញ្ញវត្ថុទេ។ សូមទាក់ទងប្រតិបត្តិករសម្រាប់កិច្ចព្រមព្រៀងពេញលេញ។',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, 'Close', 'បិទ')),
      ),
    ],
  ),
);

class EmailAuthLegal extends StatelessWidget {
  const EmailAuthLegal({super.key});
  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.of(context).caption
        .copyWith(color: AppColors.of(context).disabledBackground);
    final terms = tr(context, 'Terms & Conditions', 'លក្ខខណ្ឌប្រើប្រាស់');
    final privacy = tr(context, 'Privacy Policy', 'គោលការណ៍ឯកជនភាព');
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      child: LayoutBuilder(
        builder: (context, box) {
          double width(String value) {
            final painter = TextPainter(
              text: TextSpan(text: value, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final result = painter.width;
            painter.dispose();
            return result;
          }

          final wraps = width('$terms • $privacy') > box.maxWidth;
          Widget link(String label, bool private) => TextButton(
            onPressed: () => showAuthPolicy(context, private),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.of(context).disabledBackground,
              padding: wraps
                  ? const EdgeInsets.symmetric(vertical: 8)
                  : EdgeInsets.zero,
              minimumSize: const Size(48, 48),
              textStyle: style,
              alignment: wraps ? Alignment.center : Alignment.bottomCenter,
            ),
            child: Text(label, textAlign: TextAlign.center),
          );
          return Column(
            children: [
              if (wraps)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [link(terms, false), link(privacy, true)],
                )
              else
                SizedBox(
                  height: 48,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      link(terms, false),
                      Text(' • ', style: style),
                      link(privacy, true),
                    ],
                  ),
                ),
              Text(
                '© 2026 Kesor Bank Plc. All rights reserved.',
                style: style,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

class EmailAuthButton extends StatelessWidget {
  const EmailAuthButton({
    required this.label,
    required this.busy,
    required this.onPressed,
    super.key,
  });
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.of(context).primary500,
      foregroundColor: AppPalette.neutralLightBackground,
      minimumSize: const Size(double.infinity, 54),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: AppTextStyles.of(context).button,
    ),
    child: busy
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.of(context).foreground,
              semanticsLabel: tr(context, 'Please wait', 'សូមរង់ចាំ'),
            ),
          )
        : Text(label, textAlign: TextAlign.center),
  );
}

class EmailAuthField extends StatelessWidget {
  const EmailAuthField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.fieldKey,
    required this.validator,
    this.enabled = true,
    this.email = false,
    this.autofillHints,
    this.action = TextInputAction.done,
    this.onSubmitted,
    this.errorText,
    super.key,
  });
  final String label, hint;
  final TextEditingController controller;
  final Key fieldKey;
  final FormFieldValidator<String> validator;
  final bool enabled, email;
  final Iterable<String>? autofillHints;
  final TextInputAction action;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = AppTextStyles.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: text.button.copyWith(
            color: dark ? colors.foreground : colors.accent500,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          child: TextFormField(
            key: fieldKey,
            controller: controller,
            enabled: enabled,
            keyboardType: email
                ? TextInputType.emailAddress
                : TextInputType.name,
            autofillHints: autofillHints,
            textCapitalization: email
                ? TextCapitalization.none
                : TextCapitalization.words,
            textInputAction: action,
            autocorrect: false,
            enableSuggestions: !email,
            style: text.body.copyWith(color: colors.foreground),
            validator: validator,
            onFieldSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: text.body.copyWith(color: colors.disabledBackground),
              floatingLabelBehavior: FloatingLabelBehavior.never,
              label: null,
              semanticCounterText: label,
              errorText: errorText,
              errorMaxLines: 4,
              constraints: const BoxConstraints(minHeight: 56),
              filled: false,
              isDense: true,
              contentPadding: const EdgeInsets.all(16),
              prefixIcon: email
                  ? Padding(
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      child: SvgPicture.asset(
                        'assets/auth/email-input.svg',
                        width: 24,
                        height: 24,
                        excludeFromSemantics: true,
                        colorFilter: dark
                            ? ColorFilter.mode(
                                colors.disabledBackground,
                                BlendMode.srcIn,
                              )
                            : null,
                      ),
                    )
                  : null,
              prefixIconConstraints: email
                  ? const BoxConstraints.tightFor(width: 48, height: 24)
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.foreground, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
