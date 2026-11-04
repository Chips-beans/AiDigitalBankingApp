import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/figma_presentation.dart';
import '../assistant_controller.dart';
import '../assistant_labels.dart';
import '../assistant_models.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    required this.controller,
    required this.onAction,
    required this.bottomClearance,
    this.keyboardVisible = false,
    this.onBack,
    super.key,
  });
  final AssistantController controller;
  final ValueChanged<AiAction> onAction;
  final double bottomClearance;
  final bool keyboardVisible;
  final VoidCallback? onBack;
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with WidgetsBindingObserver {
  final draft = TextEditingController(), scroll = ScrollController();
  final consumed = <String>{};
  AssistantController get model => widget.controller;
  String get language =>
      AppPreferences.maybeOf(context)?.isKhmer == true ? 'km' : 'en';
  Object? _lastUpdate;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) model.setVisible(true);
    });
  }

  void _changed() {
    if (!model.current) {
      draft.clear();
      FocusManager.instance.primaryFocus?.unfocus();
    }
    final update = (
      model.pending?.key,
      model.lastTurn?.id,
      model.lastTurn?.status,
    );
    if (update != _lastUpdate) {
      _lastUpdate = update;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients && model.visible) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      model.setVisible(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.removeListener(_changed);
    model.setVisible(false);
    draft.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? question]) async {
    if (!model.canSend) return;
    final text = question ?? draft.text;
    draft.clear();
    FocusScope.of(context).unfocus();
    await model.send(text, language);
  }

  Future<void> _history() async {
    await model.refreshConversations();
    if (!mounted || !model.current) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => _PrivateOverlay(
        model: model,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheet).height * .8,
            ),
            child: ListenableBuilder(
              listenable: model,
              builder: (context, _) => ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Text(
                    aiText(context, 'Conversation history'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    aiText(
                      context,
                      'Conversations expire after 30 days. You can delete them earlier.',
                    ),
                  ),
                  if (model.busy) const LinearProgressIndicator(),
                  if (model.error != null)
                    NoticePanel(
                      aiText(context, model.error!.message),
                      error: true,
                    ),
                  if (model.conversations.isEmpty && !model.busy)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(aiText(context, 'No conversations yet.')),
                    ),
                  for (final c in model.conversations)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(aiText(context, c.title)),
                      subtitle: Text(_date(c.updatedAt)),
                      onTap: model.busy
                          ? null
                          : () {
                              Navigator.pop(sheet);
                              unawaited(model.open(c));
                            },
                      trailing: PopupMenuButton<String>(
                        tooltip: aiText(context, 'Conversation history'),
                        enabled: !model.busy,
                        onSelected: (value) {
                          Navigator.pop(sheet);
                          if (value == 'rename') {
                            unawaited(_rename(c));
                          } else {
                            unawaited(_delete(c));
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text(aiText(context, 'Rename conversation')),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(aiText(context, 'Delete conversation')),
                          ),
                        ],
                      ),
                    ),
                  if (model.conversationCursor != null)
                    TextButton(
                      onPressed: model.busy
                          ? null
                          : () => model.refreshConversations(more: true),
                      child: Text(aiText(context, 'Load more conversations')),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheet),
                    child: Text(aiText(context, 'Close')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rename(AiConversation c) async {
    if (!mounted || !model.current) return;
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => _PrivateOverlay(
        model: model,
        child: _RenameDialog(title: aiText(context, c.title)),
      ),
    );
    if (value != null && mounted && model.current && value.trim().isNotEmpty) {
      await model.rename(c, value);
    }
  }

  Future<bool> _confirm(String title, String text, String action) async {
    if (!mounted || !model.current) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialog) => _PrivateOverlay(
            model: model,
            child: AlertDialog(
              title: Text(aiText(dialog, title)),
              content: Text(aiText(dialog, text)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: Text(aiText(dialog, 'Cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: Text(aiText(dialog, action)),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _delete(AiConversation c) async {
    if (await _confirm(
          'Delete this conversation?',
          'This removes the conversation from your history.',
          'Delete',
        ) &&
        mounted &&
        model.current) {
      await model.delete(c);
    }
  }

  Future<void> _dismiss() async {
    if (await _confirm(
          'Stop recovering this question?',
          'A question already sent may still finish and appear in server history. This does not cancel provider processing.',
          'Dismiss saved question',
        ) &&
        mounted &&
        model.current) {
      await model.dismissPending();
    }
  }

  String _date(DateTime date) {
    final d = date.toUtc().add(const Duration(hours: 7));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _welcome(BuildContext context) {
    final colors = AppColors.of(context);
    final name =
        model.session.identity?.firstName ??
        model.session.identity?.username ??
        '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              Tooltip(
                message: aiText(context, 'Conversation history'),
                child: InkWell(
                  onTap: _history,
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primary50,
                      shape: BoxShape.circle,
                    ),
                    child: const CustomerDesignIcon('68b0e', size: 76),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name.isEmpty
                    ? tr(context, 'Hi there', 'សួស្ដី')
                    : tr(context, 'Hi, $name', 'សួស្ដី $name'),
                textAlign: TextAlign.center,
                style: customerText(context, 15, 24, color: colors.primary700),
              ),
              const SizedBox(height: 8),
              Text(
                aiText(context, 'How can I help you today?'),
                textAlign: TextAlign.center,
                style: customerText(
                  context,
                  32,
                  44,
                  color: customerNavy(context),
                  weight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 356),
                child: Text(
                  aiText(
                    context,
                    'Ask about your spending, your accounts, or money in general.',
                  ),
                  textAlign: TextAlign.center,
                  style: customerText(
                    context,
                    15,
                    24,
                    color: colors.disabledBackground,
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          aiText(context, 'Try asking'),
          style: customerText(
            context,
            14,
            22,
            color: customerNavy(context),
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        for (final suggestion in [
          ('How much have I spent this month?', '2d864'),
          ('Compare this month with last month', '9653a'),
          ('How can I build an emergency fund?', 'c3050'),
          ('How can I keep my account secure?', 'c3050'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: model.canSend
                    ? () => _send(aiText(context, suggestion.$1))
                    : null,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? colors.accent
                              : AppPalette.navy50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CustomerDesignIcon(
                          suggestion.$2,
                          size: 22,
                          color: customerNavy(context),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          aiText(context, suggestion.$1),
                          style: customerText(context, 15, 24),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CustomerDesignIcon(
                        '38515',
                        size: 20,
                        color: colors.disabledBackground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          aiText(
            context,
            'Your question and only the figures needed to answer it are sent to the AI service; names and account numbers are not. General answers are information, not financial advice. Conversations are kept for 30 days.',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _answer(AiAnswer answer) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SelectableText(answer.reply),
      const SizedBox(height: 12),
      for (final card in answer.cards) _card(card),
      if (answer.mode != 'GENERAL')
        Text(
          '${aiText(context, 'Data as of')} ${_date(answer.asOf)} · Asia/Phnom_Penh',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      if (answer.explanationStatus != 'NOT_NEEDED')
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            aiText(
              context,
              answer.explanationStatus != 'AI'
                  ? 'AI explanation unavailable · Verified figures shown'
                  : answer.mode == 'GENERAL'
                  ? 'AI-written general information'
                  : answer.mode == 'MIXED'
                  ? 'AI-written general information · Account figures are verified'
                  : 'AI explanation',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  );
  Widget _card(AiCard card) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (card.title.isNotEmpty)
            Text(card.title, style: Theme.of(context).textTheme.titleMedium),
          for (final field in card.fields)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    field.label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  SelectableText(field.value),
                ],
              ),
            ),
          for (final action in card.actions)
            Builder(
              builder: (context) {
                final tag = '${jsonEncode(action.filters)}:${action.cursor}',
                    used =
                        action.type == 'MORE' &&
                        (consumed.contains(tag) || model.hasLoadedPage(action));
                final label = switch (action.type) {
                  'ACCOUNT' => 'View account',
                  'ACCOUNTS' => 'View accounts',
                  'TRANSACTION' => 'View receipt',
                  'ANALYTICS' => 'Open Analytics',
                  'MORE' => 'More transactions',
                  _ => 'Open screen',
                };
                return Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: model.busy || used
                        ? null
                        : () async {
                            if (action.type == 'MORE') {
                              setState(() => consumed.add(tag));
                              await model.more(action, language);
                              if (mounted && model.error != null) {
                                setState(() => consumed.remove(tag));
                              }
                            } else {
                              FocusScope.of(context).unfocus();
                              widget.onAction(action);
                            }
                          },
                    icon: Icon(
                      used ? Icons.check : Icons.arrow_forward,
                      size: 18,
                    ),
                    label: Text(
                      aiText(context, used ? 'Already loaded' : label),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _pending() {
    final pending = model.pending!;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.of(context).accent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            aiText(context, 'Saved question'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(pending.message),
          const SizedBox(height: 8),
          Text(
            aiText(
              context,
              pending.failed
                  ? 'The request failed. Retry sends a new assistant request.'
                  : model.notFound
                  ? 'No saved result was found. An explicit retry uses the original request key.'
                  : 'The result is not confirmed yet. Checking status does not resend your question.',
            ),
          ),
          const SizedBox(height: 8),
          if (!pending.failed)
            TextButton(
              onPressed: model.busy ? null : model.checkPending,
              child: Text(aiText(context, 'Check status')),
            ),
          FilledButton(
            onPressed:
                model.busy ||
                    model.storageError != null ||
                    model.lastTurn?.status == 'PENDING' && !model.notFound
                ? null
                : model.retry,
            child: Text(aiText(context, 'Retry saved question')),
          ),
          TextButton(
            onPressed: model.busy ? null : _dismiss,
            child: Text(aiText(context, 'Dismiss saved question')),
          ),
        ],
      ),
    );
  }

  Widget _header(bool compact) => CustomerPageHeader(
    title: aiText(context, 'AI Assistant'),
    onBack: widget.onBack ?? () => Navigator.maybePop(context),
    trailing:
        model.messages.isEmpty &&
            model.pending == null &&
            model.lastTurn == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: aiText(context, 'Conversation history'),
                onPressed: model.busy ? null : _history,
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: aiText(context, 'New conversation'),
                onPressed: model.busy || model.pending != null
                    ? null
                    : () {
                        draft.clear();
                        consumed.clear();
                        model.newChat();
                      },
                icon: const Icon(Icons.edit_square),
              ),
            ],
          ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final colors = AppColors.of(context);
        final keyboard =
            widget.keyboardVisible ||
            MediaQuery.viewInsetsOf(context).bottom > 0;
        final compact =
            constraints.maxHeight < 600 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        final shortLayout = constraints.maxHeight < 430;
        final entries = <Widget>[
          if (model.messages.isEmpty &&
              model.lastTurn?.answer == null &&
              model.pending == null)
            _welcome(context),
          if (model.messageCursor != null)
            TextButton(
              onPressed: model.busy ? null : model.olderMessages,
              child: Text(aiText(context, 'Load earlier messages')),
            ),
          for (final message in model.messages.reversed) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                margin: const EdgeInsets.only(top: 16, bottom: 12, left: 32),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? colors.accent
                      : AppPalette.gold100,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: SelectableText(message.question),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: _answer(message.answer),
            ),
          ],
          if (model.lastTurn?.answer != null &&
              !model.messages.any(
                (m) => m.answer.asOf == model.lastTurn!.answer!.asOf,
              ))
            _answer(model.lastTurn!.answer!),
          for (final card in model.extraCards) _card(card),
          if (model.pending != null) _pending(),
          if (model.busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(aiText(context, 'Thinking…'))),
                  ],
                ),
              ),
            ),
          if (model.storageError != null) ...[
            NoticePanel(
              aiText(context, model.storageError!.message),
              error: true,
            ),
            TextButton(
              onPressed: model.busy ? null : model.initialize,
              child: Text(aiText(context, 'Retry secure setup')),
            ),
          ],
          if (model.error != null) ...[
            NoticePanel(aiText(context, model.error!.message), error: true),
            if (!model.initialized)
              TextButton(
                onPressed: model.busy ? null : model.initialize,
                child: Text(aiText(context, 'Retry assistant setup')),
              ),
          ],
          if (model.initialized && !model.available) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: NoticePanel(
                aiText(
                  context,
                  'The assistant is unavailable. Your banking services remain available.',
                ),
              ),
            ),
            TextButton(
              onPressed: model.busy ? null : model.initialize,
              child: Text(aiText(context, 'Retry assistant setup')),
            ),
          ],
        ];
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value:
              (Theme.of(context).brightness == Brightness.light
                      ? SystemUiOverlayStyle.dark
                      : SystemUiOverlayStyle.light)
                  .copyWith(
                    statusBarColor: Colors.transparent,
                    systemNavigationBarColor: colors.background,
                    systemNavigationBarIconBrightness:
                        Theme.of(context).brightness == Brightness.dark
                        ? Brightness.light
                        : Brightness.dark,
                  ),
          child: CustomerAssistantBackground(
            child: SafeArea(
              top: true,
              bottom: false,
              child: Column(
                children: [
                  if (!shortLayout && !(compact && keyboard)) _header(compact),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('assistant-messages'),
                      controller: scroll,
                      padding: EdgeInsets.fromLTRB(
                        shortLayout ? 0 : 20,
                        0,
                        shortLayout ? 0 : 20,
                        16,
                      ),
                      children: [
                        if (shortLayout && !keyboard) _header(compact),
                        for (final entry in entries)
                          Padding(
                            padding: shortLayout
                                ? const EdgeInsets.symmetric(horizontal: 24)
                                : EdgeInsets.zero,
                            child: entry,
                          ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: EdgeInsets.fromLTRB(20, compact ? 8 : 24, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colors.border),
                          ),
                          padding: const EdgeInsets.only(left: 12, right: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('assistant-question'),
                                  controller: draft,
                                  minLines: 1,
                                  maxLines: compact ? 1 : 3,
                                  maxLength: 2000,
                                  enabled: model.canSend,
                                  keyboardType: TextInputType.multiline,
                                  style: customerText(context, 15, 24),
                                  buildCounter: (
                                    context, {
                                    required currentLength,
                                    required isFocused,
                                    required maxLength,
                                  }) => null,
                                  decoration: InputDecoration(
                                    hintText: aiText(
                                      context,
                                      'Ask Kesor Assistant…',
                                    ),
                                    hintStyle: customerText(
                                      context,
                                      15,
                                      24,
                                      color: colors.disabledBackground,
                                    ),
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              ValueListenableBuilder(
                                valueListenable: draft,
                                builder: (context, value, _) => IconButton(
                                  key: const ValueKey('assistant-send'),
                                  tooltip: aiText(context, 'Send question'),
                                  onPressed:
                                      model.canSend &&
                                          value.text.trim().isNotEmpty
                                      ? () => _send()
                                      : null,
                                  icon: Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: colors.primary100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: CustomerDesignIcon(
                                      '6fd29',
                                      size: 22,
                                      color: customerNavy(context),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!keyboard) ...[
                          const SizedBox(height: 12),
                          Text(
                            aiText(
                              context,
                              'Never share your PIN, password or OTP.',
                            ),
                            textAlign: TextAlign.center,
                            style: customerText(
                              context,
                              12,
                              20,
                              color: colors.disabledBackground,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    height: keyboard
                        ? MediaQuery.paddingOf(context).bottom
                        : widget.bottomClearance +
                              MediaQuery.paddingOf(context).bottom,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.title});
  final String title;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController title = TextEditingController(
    text: widget.title,
  );
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(aiText(context, 'Rename conversation')),
    content: TextField(
      controller: title,
      maxLength: 80,
      decoration: InputDecoration(
        labelText: aiText(context, 'Conversation title'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(aiText(context, 'Cancel')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, title.text),
        child: Text(aiText(context, 'Save')),
      ),
    ],
  );
}

/// Route overlays live above the home widget; hide and dismiss them on any privacy transition.
class _PrivateOverlay extends StatefulWidget {
  const _PrivateOverlay({required this.model, required this.child});
  final AssistantController model;
  final Widget child;
  @override
  State<_PrivateOverlay> createState() => _PrivateOverlayState();
}

class _PrivateOverlayState extends State<_PrivateOverlay> {
  bool closing = false;
  @override
  void initState() {
    super.initState();
    widget.model.session.addListener(_changed);
  }

  void _changed() {
    if (widget.model.current || closing) return;
    closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    widget.model.session.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model.session,
    builder: (context, _) =>
        widget.model.current ? widget.child : const SizedBox.shrink(),
  );
}
