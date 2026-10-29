import 'package:flutter/material.dart';

/// Read-only, selectable values with a native Android-sized interaction area.
class CopyableValue extends StatelessWidget {
  const CopyableValue(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey(value),
    initialValue: value,
    readOnly: true,
    maxLines: null,
  );
}
