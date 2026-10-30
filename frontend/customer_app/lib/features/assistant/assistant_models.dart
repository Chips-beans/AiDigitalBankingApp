import 'dart:math';

import '../../core/network/api_client.dart';

const invalidAssistant = ApiFailure(
  'AI_INVALID_RESPONSE',
  'The assistant response could not be verified.',
);
Map<String, dynamic> objectData(Object? value) {
  if (value is! Map<String, dynamic>) throw invalidAssistant;
  return value;
}

const assistantStorageFailure = ApiFailure(
  'AI_STORAGE',
  'The saved question could not be read or saved. Sending is blocked.',
);
String aiKey() =>
    'ai-${List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
bool aiId(String value) => RegExp(
  r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
).hasMatch(value);
String aiString(Object? value, {int max = 4000}) {
  if (value is! String || value.length > max) throw invalidAssistant;
  return value;
}

DateTime aiDate(Object? value) {
  final date = DateTime.tryParse(aiString(value, max: 80));
  if (date == null) throw invalidAssistant;
  return date;
}

Map<String, String?> aiFilters(Object? value) {
  final map = objectData(value);
  const keys = {
    'currency',
    'accountNumber',
    'month',
    'from',
    'to',
    'amount',
    'direction',
    'type',
    'status',
    'reference',
  };
  if (map.keys.any((k) => !keys.contains(k))) throw invalidAssistant;
  return {
    for (final e in map.entries)
      e.key: e.value == null ? null : aiString(e.value, max: 100),
  };
}

class AiAction {
  const AiAction(
    this.type, {
    this.value,
    this.accountNumber,
    this.currency,
    this.month,
    this.filters,
    this.cursor,
  });
  factory AiAction.fromJson(Object? value) {
    final m = objectData(value),
        type = aiString(objectData(value)['type'], max: 30);
    if (!{
      'ACCOUNT',
      'ACCOUNTS',
      'TRANSACTION',
      'ANALYTICS',
      'HELP_SCREEN',
      'MORE',
    }.contains(type)) {
      throw invalidAssistant;
    }
    String? optional(String key) => m[key] == null
        ? null
        : aiString(m[key], max: key == 'cursor' ? 180 : 100);
    final account = optional('accountNumber'),
        currency = optional('currency'),
        month = optional('month'),
        target = optional('value');
    if (account != null && !RegExp(r'^[0-9]{10,20}$').hasMatch(account)) {
      throw invalidAssistant;
    }
    if (currency != null && !{'USD', 'KHR'}.contains(currency)) {
      throw invalidAssistant;
    }
    if (month != null &&
        !RegExp(r'^[0-9]{4}-(0[1-9]|1[0-2])$').hasMatch(month)) {
      throw invalidAssistant;
    }
    if (type == 'ACCOUNT' && account == null ||
        type == 'TRANSACTION' &&
            (account == null ||
                target == null ||
                !RegExp(r'^[A-Za-z0-9_-]{1,36}$').hasMatch(target)) ||
        type == 'ANALYTICS' && (currency == null || month == null) ||
        type == 'HELP_SCREEN' &&
            !{'ACCOUNTS', 'TRANSFER', 'MY_QR', 'SCAN_QR'}.contains(target)) {
      throw invalidAssistant;
    }
    final filters = m['filters'] == null ? null : aiFilters(m['filters']);
    final cursor = optional('cursor');
    if (type == 'MORE' &&
        (filters == null || cursor == null || cursor.isEmpty)) {
      throw invalidAssistant;
    }
    return AiAction(
      type,
      value: target,
      accountNumber: account,
      currency: currency,
      month: month,
      filters: filters,
      cursor: cursor,
    );
  }
  final String type;
  final String? value, accountNumber, currency, month, cursor;
  final Map<String, String?>? filters;
}

class AiField {
  const AiField(this.label, this.value);
  factory AiField.fromJson(Object? value) {
    final m = objectData(value);
    return AiField(
      aiString(m['label'], max: 200),
      aiString(m['value'], max: 1000),
    );
  }
  final String label, value;
}

class AiCard {
  const AiCard(this.type, this.title, this.fields, this.actions);
  factory AiCard.fromJson(Object? value) {
    final m = objectData(value),
        type = aiString(objectData(value)['type'], max: 30);
    if (!{'BALANCE', 'MONTHLY', 'TRANSACTION', 'HELP', 'MORE'}.contains(type)) {
      throw invalidAssistant;
    }
    return AiCard(
      type,
      aiString(m['title'], max: 200),
      aiList(m['fields'], AiField.fromJson, 50),
      aiList(m['actions'], AiAction.fromJson, 20),
    );
  }
  final String type, title;
  final List<AiField> fields;
  final List<AiAction> actions;
}

List<T> aiList<T>(Object? value, T Function(Object?) parse, int max) {
  if (value is! List || value.length > max) throw invalidAssistant;
  return value.map(parse).toList(growable: false);
}

class AiAnswer {
  const AiAnswer(this.reply, this.cards, this.asOf, this.explanationStatus);
  factory AiAnswer.fromJson(Object? value) {
    final m = objectData(value),
        status = aiString(objectData(value)['explanationStatus'], max: 30);
    if (!{'AI', 'FALLBACK', 'NOT_NEEDED'}.contains(status)) {
      throw invalidAssistant;
    }
    return AiAnswer(
      aiString(m['reply'], max: 5000),
      aiList(m['cards'], AiCard.fromJson, 60),
      aiDate(m['asOf']),
      status,
    );
  }
  final String reply, explanationStatus;
  final List<AiCard> cards;
  final DateTime asOf;
}

class AiTurn {
  const AiTurn(this.id, this.status, {this.answer, this.errorCode});
  factory AiTurn.fromJson(Object? value) {
    final m = objectData(value),
        id = aiString(objectData(value)['requestId'], max: 40),
        status = aiString(objectData(value)['status'], max: 20);
    if (!aiId(id) || !{'PENDING', 'COMPLETED', 'FAILED'}.contains(status)) {
      throw invalidAssistant;
    }
    final answer = m['answer'] == null ? null : AiAnswer.fromJson(m['answer']);
    final error = m['errorCode'] == null
        ? null
        : aiString(m['errorCode'], max: 80);
    if (status == 'COMPLETED' && answer == null ||
        status != 'COMPLETED' && answer != null ||
        status == 'FAILED' && error == null) {
      throw invalidAssistant;
    }
    return AiTurn(id, status, answer: answer, errorCode: error);
  }
  final String id, status;
  final AiAnswer? answer;
  final String? errorCode;
}

class AiConversation {
  const AiConversation(this.id, this.title, this.createdAt, this.updatedAt);
  factory AiConversation.fromJson(Object? value) {
    final m = objectData(value),
        id = aiString(objectData(value)['id'], max: 40);
    if (!aiId(id)) throw invalidAssistant;
    return AiConversation(
      id,
      aiString(m['title'], max: 80),
      aiDate(m['createdAt']),
      aiDate(m['updatedAt']),
    );
  }
  final String id, title;
  final DateTime createdAt, updatedAt;
}

class AiMessage {
  const AiMessage(
    this.id,
    this.question,
    this.locale,
    this.answer,
    this.createdAt,
  );
  factory AiMessage.fromJson(Object? value) {
    final m = objectData(value);
    if (m['id'] is! int ||
        (m['id'] as int) < 1 ||
        !{'en', 'km'}.contains(m['locale'])) {
      throw invalidAssistant;
    }
    return AiMessage(
      m['id'] as int,
      aiString(m['message'], max: 2000),
      m['locale'] as String,
      AiAnswer.fromJson(m['answer']),
      aiDate(m['createdAt']),
    );
  }
  final int id;
  final String question, locale;
  final AiAnswer answer;
  final DateTime createdAt;
}

class AiPage<T> {
  const AiPage(this.items, this.cursor);
  final List<T> items;
  final String? cursor;
  factory AiPage.fromJson(Object? value, T Function(Object?) parse) {
    final m = objectData(value),
        cursor = mCursor(objectData(value)['nextCursor']);
    return AiPage(aiList(m['items'], parse, 50), cursor);
  }
  static String? mCursor(Object? value) =>
      value == null || value == '' ? null : aiString(value, max: 180);
}

class AiPending {
  const AiPending({
    required this.phase,
    required this.key,
    required this.message,
    required this.locale,
    required this.createdAt,
    this.conversation,
    this.failed = false,
  });
  factory AiPending.create(String message, String locale) => AiPending(
    phase: 'CREATE',
    key: aiKey(),
    message: message,
    locale: locale,
    createdAt: DateTime.now().toUtc(),
  );
  factory AiPending.fromJson(Object? value) {
    final m = objectData(value);
    if (m['version'] != 1 ||
        !{'CREATE', 'MESSAGE'}.contains(m['phase']) ||
        !{'en', 'km'}.contains(m['locale']) ||
        m['failed'] is! bool) {
      throw assistantStorageFailure;
    }
    final key = aiString(m['key'], max: 100),
        conversation = m['conversation'] == null
            ? null
            : aiString(m['conversation'], max: 40);
    if (!RegExp(r'^[A-Za-z0-9_-]{8,100}$').hasMatch(key) ||
        conversation != null && !aiId(conversation) ||
        m['phase'] == 'MESSAGE' && conversation == null) {
      throw assistantStorageFailure;
    }
    return AiPending(
      phase: m['phase'] as String,
      key: key,
      message: aiString(m['message'], max: 2000),
      locale: m['locale'] as String,
      createdAt: aiDate(m['createdAt']),
      conversation: conversation,
      failed: m['failed'] as bool,
    );
  }
  final String phase, key, message, locale;
  final String? conversation;
  final DateTime createdAt;
  final bool failed;
  Map<String, Object?> get body => {
    'message': message,
    'locale': locale,
    'context': null,
  };
  Map<String, Object?> toJson() => {
    'version': 1,
    'phase': phase,
    'key': key,
    'message': message,
    'locale': locale,
    'createdAt': createdAt.toIso8601String(),
    'conversation': conversation,
    'failed': failed,
  };
  AiPending forMessage(String id) => AiPending(
    phase: 'MESSAGE',
    key: aiKey(),
    message: message,
    locale: locale,
    createdAt: createdAt,
    conversation: id,
  );
  AiPending failure() => AiPending(
    phase: phase,
    key: key,
    message: message,
    locale: locale,
    createdAt: createdAt,
    conversation: conversation,
    failed: true,
  );
  AiPending retryNew() => AiPending(
    phase: phase,
    key: aiKey(),
    message: message,
    locale: locale,
    createdAt: DateTime.now().toUtc(),
    conversation: conversation,
  );
}
