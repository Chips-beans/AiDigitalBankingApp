import 'package:flutter/material.dart';

import '../../app/app_labels.dart';

class NoticePanel extends StatelessWidget {
  const NoticePanel(
    this.message, {
    this.error = false,
    this.focusNode,
    super.key,
  });
  final String message;
  final bool error;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: focusNode,
      child: Semantics(
        liveRegion: true,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: error ? scheme.errorContainer : scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  error ? Icons.error_outline : Icons.info_outline,
                  color: error
                      ? scheme.onErrorContainer
                      : scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: error
                        ? scheme.onErrorContainer
                        : scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BusyButton extends StatelessWidget {
  const BusyButton({
    required this.label,
    required this.busy,
    required this.onPressed,
    super.key,
  });
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(tx(context, 'Please wait…'))),
              ],
            )
          : Text(label),
    ),
  );
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({this.message, this.onRetry, super.key});
  final String? message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message == null)
                  const CircularProgressIndicator(
                    semanticsLabel: 'Restoring your session',
                  )
                else ...[
                  NoticePanel(message!, error: true),
                  BusyButton(
                    label: 'Retry secure setup',
                    busy: false,
                    onPressed: onRetry,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
