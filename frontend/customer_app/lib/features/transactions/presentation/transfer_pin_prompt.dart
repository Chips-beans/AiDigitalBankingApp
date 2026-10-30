import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../auth/presentation/app_pin_page.dart';
import '../../auth/session_controller.dart';

/// Collects the 4-digit PIN for one transfer confirmation. The digits are returned
/// to the caller, exchanged once for a server proof, and never stored.
Future<String?> askTransferPin(
  BuildContext context, {
  required String name,
  Uint8List? photo,
  String? message,
}) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) =>
        _TransferPinPrompt(name: name, photo: photo, message: message),
  ),
);

class _TransferPinPrompt extends StatefulWidget {
  const _TransferPinPrompt({required this.name, this.photo, this.message});
  final String name;
  final Uint8List? photo;
  final String? message;
  @override
  State<_TransferPinPrompt> createState() => _TransferPinPromptState();
}

class _TransferPinPromptState extends State<_TransferPinPrompt> {
  final input = TextEditingController();
  final focus = FocusNode();
  bool done = false;

  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  void enter(String value) {
    if (done) return;
    setState(
      () => input.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      ),
    );
    if (value.length == 4) {
      done = true;
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) => PinScreen(
    stage: PinStage.unlock,
    name: widget.name,
    enteredDigits: input.text.length,
    message: widget.message,
    photoBytes: widget.photo,
    input: input,
    focus: focus,
    onChanged: enter,
    onNumber: (value) {
      if (input.text.length < 4) enter('${input.text}$value');
    },
    onClear: () => enter(''),
    onDelete: () {
      if (input.text.isNotEmpty) {
        enter(input.text.substring(0, input.text.length - 1));
      }
    },
    onBack: () => Navigator.of(context).pop(),
  );
}
