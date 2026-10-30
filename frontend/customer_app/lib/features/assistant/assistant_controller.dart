import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../auth/session_controller.dart';
import 'assistant_gateway.dart';
import 'assistant_models.dart';
import 'assistant_store.dart';

class AssistantController extends ChangeNotifier {
  AssistantController(this.session, this.gateway, this.store)
    : user = session.identity!.userId,
      sessionId = session.identity!.sessionId {
    session.addListener(_sessionChanged);
  }
  final SessionController session;
  final AssistantGateway gateway;
  final AssistantPendingStore store;
  final int user;
  final String sessionId;
  bool busy = false,
      available = false,
      initialized = false,
      visible = false,
      notFound = false;
  bool _disposed = false;
  int _epoch = 0, _pollCount = 0;
  Timer? _poll;
  DateTime? _pollUntil;
  ApiFailure? error, storageError;
  AiPending? pending;
  AiTurn? lastTurn;
  String? lastQuestion, currentId, conversationCursor, messageCursor;
  List<AiConversation> conversations = [];
  List<AiMessage> messages = [];
  List<AiCard> extraCards = [];
  final _loadedPages = <String>{};
  String _pageKey(AiAction action) =>
      '${jsonEncode(action.filters)}:${action.cursor}';
  bool hasLoadedPage(AiAction action) =>
      _loadedPages.contains(_pageKey(action));
  String locale = 'en';
  bool get current =>
      !_disposed &&
      session.phase == SessionPhase.signedIn &&
      !session.privacyCovered &&
      session.identity?.userId == user &&
      session.identity?.sessionId == sessionId;
  bool _live(int epoch) => current && epoch == _epoch;
  bool get canSend =>
      current &&
      initialized &&
      available &&
      !busy &&
      pending == null &&
      storageError == null;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (!current) {
      _epoch++;
      _poll?.cancel();
      busy = false;
      initialized = false;
      conversations = [];
      messages = [];
      extraCards = [];
      _loadedPages.clear();
      pending = null;
      lastTurn = null;
      lastQuestion = null;
      currentId = null;
      error = storageError = null;
      conversationCursor = messageCursor = null;
      _emit();
    } else if (visible && !initialized) {
      unawaited(initialize());
    }
  }

  void setVisible(bool value) {
    if (visible == value) return;
    visible = value;
    if (!value) {
      _epoch++;
      _poll?.cancel();
      busy = false;
      initialized = false; // Re-read the durable pointer after any in-flight local transition.
    } else if (current) {
      _pollUntil = null;
      _pollCount = 0;
      if (!initialized) {
        unawaited(initialize());
      } else if (pending != null) {
        unawaited(checkPending());
      }
    }
  }

  Future<void> _run(Future<void> Function(int) work) async {
    if (!current || busy) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    _emit();
    try {
      await work(epoch);
    } on ApiFailure catch (e) {
      if (_live(epoch)) {
        if (e.code == 'AI_STORAGE') {
          storageError = e;
        } else {
          error = e;
        }
      }
    } catch (_) {
      if (_live(epoch)) error = invalidAssistant;
    } finally {
      if (_live(epoch)) {
        busy = false;
        _emit();
        _schedule();
      }
    }
  }

  Future<void> initialize() => _run((epoch) async {
    storageError = null;
    try {
      final saved = await store.read(user);
      if (!_live(epoch)) return;
      pending = saved;
    } catch (_) {
      if (_live(epoch)) storageError = assistantStorageFailure;
    }
    final enabled = await session.authorizedRead(gateway.available);
    if (!_live(epoch)) return;
    available = enabled;
    final page = await session.authorizedRead(
      (token) => gateway.conversations(token),
    );
    if (!_live(epoch)) return;
    conversations = page.items;
    conversationCursor = page.cursor;
    initialized = true;
    if (pending != null) await _check(epoch);
  });
  void navigationFailure() {
    if (!current) return;
    error = const ApiFailure(
      'RESOURCE_NOT_FOUND',
      'The requested account or transaction is unavailable.',
    );
    setVisible(true);
    _emit();
  }

  Future<void> refreshConversations({bool more = false}) => _run((epoch) async {
    if (more && conversationCursor == null) return;
    final page = await session.authorizedRead(
      (token) => gateway.conversations(
        token,
        cursor: more ? conversationCursor : null,
      ),
    );
    if (!_live(epoch)) return;
    conversations = more
        ? {
            for (final c in [...conversations, ...page.items]) c.id: c,
          }.values.toList()
        : page.items;
    conversationCursor = page.cursor;
  });
  Future<void> open(AiConversation conversation) => _run((epoch) async {
    final page = await session.authorizedRead(
      (token) => gateway.messages(token, conversation.id),
    );
    if (!_live(epoch)) return;
    currentId = conversation.id;
    messages = page.items;
    messageCursor = page.cursor;
    lastTurn = null;
    lastQuestion = null;
    extraCards = [];
    _loadedPages.clear();
  });
  Future<void> _loadMessages(int epoch) async {
    final id = currentId;
    if (id == null) return;
    final page = await session.authorizedRead(
      (token) => gateway.messages(token, id),
    );
    if (!_live(epoch) || currentId != id) return;
    messages = page.items;
    messageCursor = page.cursor;
  }

  Future<void> olderMessages() => _run((epoch) async {
    final id = currentId, cursor = messageCursor;
    if (id == null || cursor == null) return;
    final page = await session.authorizedRead(
      (token) => gateway.messages(token, id, cursor: cursor),
    );
    if (!_live(epoch) || currentId != id) return;
    messages = {
      for (final m in [...messages, ...page.items]) m.id: m,
    }.values.toList()..sort((a, b) => b.id.compareTo(a.id));
    messageCursor = page.cursor;
  });
  void newChat() {
    if (!current || busy || pending != null) return;
    _epoch++;
    currentId = null;
    messages = [];
    extraCards = [];
    lastTurn = null;
    lastQuestion = null;
    error = null;
    messageCursor = null;
    _loadedPages.clear();
    _emit();
  }

  static bool sensitive(String text) => RegExp(
    r'\b(?:pin|otp|passcode)\s*(?:is|:|=)?\s*[0-9០-៩]{4,8}\b|\b(?:password|secret|token)\s*(?:is|:|=)\s*\S+|\bBearer\s+[A-Za-z0-9._-]+|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.',
    caseSensitive: false,
  ).hasMatch(text);
  Future<void> send(String text, String language) async {
    if (!canSend) return;
    text = text.trim();
    if (text.isEmpty ||
        text.length > 2000 ||
        !{'en', 'km'}.contains(language)) {
      error = const ApiFailure(
        'INVALID_REQUEST',
        'Enter a question of up to 2,000 characters.',
      );
      _emit();
      return;
    }
    if (sensitive(text)) {
      error = const ApiFailure(
        'AI_SENSITIVE_INPUT',
        'Do not send PINs, OTPs, passwords or authentication tokens.',
      );
      _emit();
      return;
    }
    await _run((epoch) async {
      locale = language;
      var record = AiPending.create(text, language);
      if (currentId != null) record = record.forMessage(currentId!);
      await store.claim(user, record);
      if (!_live(epoch)) return;
      pending = record;
      lastTurn = null;
      lastQuestion = null;
      extraCards = [];
      _loadedPages.clear();
      notFound = false;
      _pollCount = 0;
      _pollUntil = null;
      await _submit(epoch);
    });
  }

  Future<void> _submit(int epoch) async {
    var record = pending;
    if (record == null || !_live(epoch)) return;
    try {
      if (record.phase == 'CREATE') {
        final conversation = await session.authorizedMutation(
          (token) => gateway.create(token, record!.key),
        );
        if (!_live(epoch)) return;
        final next = record.forMessage(conversation.id);
        await store.replace(user, record.key, next);
        if (!_live(epoch)) return;
        pending = record = next;
        currentId = conversation.id;
        conversations = {
          conversation.id: conversation,
          for (final c in conversations) c.id: c,
        }.values.toList();
      }
      final result = await session.authorizedMutation(
        (token) => gateway.send(token, record!),
      );
      if (!_live(epoch)) return;
      await _settle(epoch, record, result);
    } on ApiFailure catch (failure) {
      if (!_live(epoch)) return;
      error = failure;
      // A status lookup is safe. Never infer from an HTTP timeout whether the question was accepted.
      if (pending?.phase == 'MESSAGE' && failure.code != 'AI_STORAGE') {
        try {
          final result = await session.authorizedRead(
            (token) => gateway.status(token, pending!),
          );
          if (_live(epoch)) await _settle(epoch, pending!, result);
        } on ApiFailure catch (check) {
          if (_live(epoch) && check.status == 404) notFound = true;
        }
      }
      if (_live(epoch) && failure.code == 'AI_STORAGE') storageError = failure;
    }
  }

  Future<void> _settle(int epoch, AiPending record, AiTurn result) async {
    if (!_live(epoch)) return;
    if (result.status == 'COMPLETED') {
      await store.replace(user, record.key, null);
      if (!_live(epoch)) return;
      pending = null;
      currentId = record.conversation;
      lastTurn = result;
      lastQuestion = record.message;
      error = null;
      notFound = false;
      _poll?.cancel();
      await _loadMessages(epoch);
    } else if (result.status == 'FAILED') {
      final failed = record.failure();
      await store.replace(user, record.key, failed);
      if (!_live(epoch)) return;
      pending = failed;
      lastTurn = result;
      error = ApiFailure(
        result.errorCode!,
        ApiFailure.messageFor(result.errorCode!),
      );
      _poll?.cancel();
    } else {
      lastTurn = result;
      notFound = false;
    }
  }

  Future<void> _check(int epoch) async {
    final record = pending;
    if (record == null || record.failed || !_live(epoch)) return;
    try {
      if (record.phase == 'CREATE') {
        final conversation = await session.authorizedRead(
          (token) => gateway.recoverCreation(token, record.key),
        );
        if (!_live(epoch)) return;
        final next = record.forMessage(conversation.id);
        await store.replace(user, record.key, next);
        if (!_live(epoch)) return;
        pending = next;
        currentId = conversation.id;
        notFound = true;
        await _loadMessages(epoch); // Creation recovered. Sending still requires the explicit retry button.
      } else {
        final result = await session.authorizedRead(
          (token) => gateway.status(token, record),
        );
        if (!_live(epoch)) return;
        currentId = record.conversation;
        await _settle(epoch, record, result);
      }
    } on ApiFailure catch (failure) {
      if (!_live(epoch)) return;
      if (failure.status == 404) {
        notFound = true;
        error = null;
      } else {
        rethrow;
      }
    }
  }

  Future<void> checkPending() => _run((epoch) async {
    await _check(epoch);
  });
  Future<void> retry() => _run((epoch) async {
    var record = pending;
    if (record == null || storageError != null) return;
    if (record.failed) {
      final next = record.retryNew();
      await store.replace(user, record.key, next);
      if (!_live(epoch)) return;
      record = next;
      pending = next;
      lastTurn = null;
    }
    notFound = false;
    _pollCount = 0;
    _pollUntil = null;
    await _submit(epoch);
  });
  Future<void> dismissPending() => _run((epoch) async {
    final record = pending;
    if (record == null) return;
    await store.replace(user, record.key, null);
    if (!_live(epoch)) return;
    pending = null;
    lastTurn = null;
    lastQuestion = null;
    notFound = false;
    _poll?.cancel();
  });
  Future<void> rename(AiConversation conversation, String title) =>
      _run((epoch) async {
        final value = await session.authorizedMutation(
          (token) => gateway.rename(token, conversation.id, title.trim()),
        );
        if (!_live(epoch)) return;
        conversations = conversations
            .map((c) => c.id == value.id ? value : c)
            .toList();
      });
  Future<void> delete(AiConversation conversation) => _run((epoch) async {
    await session.authorizedMutation(
      (token) => gateway.delete(token, conversation.id),
    );
    if (!_live(epoch)) return;
    if (pending?.conversation == conversation.id) {
      await store.replace(user, pending!.key, null);
      if (!_live(epoch)) return;
      pending = null;
      lastTurn = null;
    }
    conversations = conversations
        .where((c) => c.id != conversation.id)
        .toList();
    if (currentId == conversation.id) {
      currentId = null;
      messages = [];
      extraCards = [];
      lastTurn = null;
      lastQuestion = null;
    }
  });
  Future<void> more(AiAction action, String language) => _run((epoch) async {
    if (hasLoadedPage(action)) return;
    final page = await session.authorizedRead(
      (token) => gateway.more(token, action, language),
    );
    if (!_live(epoch)) return;
    _loadedPages.add(_pageKey(action));
    extraCards = [...extraCards, ...page.items];
    // Keep each continuation local to its immutable filter set; repeated clicks are suppressed by the UI.
    if (page.cursor != null) {
      extraCards.add(
        AiCard('MORE', '', const [], [
          AiAction('MORE', filters: action.filters, cursor: page.cursor),
        ]),
      );
    }
  });
  void _schedule() {
    _poll?.cancel();
    if (!current ||
        !visible ||
        busy ||
        pending == null ||
        pending!.failed ||
        pending!.phase != 'MESSAGE' ||
        notFound ||
        _pollCount >= 15) {
      return;
    }
    _pollUntil ??= DateTime.now().add(const Duration(seconds: 30));
    if (DateTime.now().isAfter(_pollUntil!)) return;
    _poll = Timer(const Duration(seconds: 2), () {
      if (current && visible && !busy) {
        _pollCount++;
        unawaited(checkPending());
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _poll?.cancel();
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
