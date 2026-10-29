import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_labels.dart';
import '../../../app/design_system/design_system.dart';

/// One native editable field retains paste, autofill, selection and backspace.
/// The six decorative slots follow Figma 256:188.
class EmailOtpField extends StatefulWidget {
  const EmailOtpField({
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
    super.key,
  });
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmitted;
  @override
  State<EmailOtpField> createState() => _EmailOtpFieldState();
}

class _EmailOtpFieldState extends State<EmailOtpField> {
  final focus = FocusNode();
  @override
  void initState() {
    super.initState();
    focus.addListener(changed);
    widget.controller.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final code = widget.controller.text;
    final active = widget.controller.selection.extentOffset.clamp(0, 5);
    final height = MediaQuery.textScalerOf(context)
        .scale(28)
        .clamp(76.0, double.infinity);
    return FormField<String>(
      validator: (_) => widget.controller.text.length == 6
          ? null
          : tx(context, 'Enter the 6-digit code.'),
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: Stack(
              children: [
                ExcludeSemantics(
                  child: Row(
                    children: [
                      for (var i = 0; i < 6; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            key: ValueKey('otp-slot-$i'),
                            alignment: Alignment.center,
                            height: height,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: state.hasError
                                    ? colors.error
                                    : i < code.length ||
                                          (focus.hasFocus && i == active)
                                    ? colors.foreground
                                    : colors.border,
                                width:
                                    i < code.length ||
                                        (focus.hasFocus && i == active)
                                    ? 2
                                    : 1,
                              ),
                            ),
                            child: i < code.length
                                ? Text(
                                    code[i],
                                    style: AppTextStyles.of(context).bodyL
                                        .copyWith(color: colors.foreground),
                                  )
                                : focus.hasFocus && i == active
                                ? Container(
                                    width: 2,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: colors.foreground,
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  )
                                : Text(
                                    '–',
                                    style: AppTextStyles.of(context).titleM
                                        .copyWith(
                                          color: colors.disabledBackground,
                                        ),
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned.fill(
                  child: Semantics(
                    label: tx(context, 'Verification code'),
                    child: TextFormField(
                      key: const ValueKey('otpCode'),
                      controller: widget.controller,
                      focusNode: focus,
                      enabled: widget.enabled,
                      showCursor: false,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      style: const TextStyle(
                        color: Colors.transparent,
                        fontSize: 1,
                      ),
                      cursorColor: Colors.transparent,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      onFieldSubmitted: (_) => widget.onSubmitted(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.errorText!,
                style: AppTextStyles.of(context).caption
                    .copyWith(color: colors.error),
              ),
            ),
        ],
      ),
    );
  }
}
