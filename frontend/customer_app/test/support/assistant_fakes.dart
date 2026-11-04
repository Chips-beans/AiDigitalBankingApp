import 'dart:async';

import 'package:customer_app/core/network/api_client.dart';
import 'package:customer_app/features/assistant/assistant_gateway.dart';
import 'package:customer_app/features/assistant/assistant_models.dart';

const aiConversationId = '11111111-2222-4333-8444-555555555555';
const aiSecondConversationId = '11111111-2222-4333-8444-666666666666';
AiAnswer fixtureAnswer({String locale = 'en', String? mode}) => AiAnswer(
  locale == 'km'
      ? 'នេះជាសមតុល្យគណនីដែលបានផ្ទៀងផ្ទាត់របស់អ្នក។'
      : 'Here are your verified account balances.',
  [
    AiCard(
      'BALANCE',
      'USD',
      [
        AiField(locale == 'km' ? 'សមតុល្យសរុប' : 'Total balance', 'USD 190.00'),
        const AiField('•••• 0001', 'USD 190.00 · ACTIVE'),
      ],
      const [
        AiAction(
          'ACCOUNT',
          value: '1000000001',
          accountNumber: '1000000001',
          currency: 'USD',
        ),
      ],
    ),
    AiCard(
      'BALANCE',
      'KHR',
      [AiField(locale == 'km' ? 'សមតុល្យសរុប' : 'Total balance', 'KHR 90000')],
      const [AiAction('ACCOUNTS')],
    ),
  ],
  DateTime.utc(2026, 10, 30, 7, 15),
  'AI',
  mode: mode,
);

class FakeAssistant implements AssistantGateway {
  bool enabled = true, loseSendResponse = false, loseCreateResponse = false;
  String? answerMode;
  ApiFailure? sendFailure, statusFailure, listFailure;
  Completer<void>? sendGate;
  int creates = 0, statusReads = 0, creationReads = 0, listReads = 0;
  final requests = <AiPending>[];
  final created = <String, AiConversation>{};
  final turns = <String, AiTurn>{};
  final history = <String, List<AiMessage>>{};
  final conversationsData = <AiConversation>[];
  @override
  Future<bool> available(String token) async => enabled;
  @override
  Future<AiPage<AiConversation>> conversations(
    String token, {
    String? cursor,
  }) async {
    listReads++;
    if (listFailure != null) throw listFailure!;
    return AiPage(List.of(conversationsData), null);
  }

  @override
  Future<AiConversation> create(String token, String key) async {
    creates++;
    final value = created.putIfAbsent(key, () {
      final c = AiConversation(
        conversationsData.isEmpty ? aiConversationId : aiSecondConversationId,
        'New conversation',
        DateTime.utc(2026, 10, 30),
        DateTime.utc(2026, 10, 30),
      );
      conversationsData.add(c);
      return c;
    });
    if (loseCreateResponse) {
      loseCreateResponse = false;
      throw const ApiFailure('TIMEOUT', 'Timed out');
    }
    return value;
  }

  @override
  Future<AiConversation> recoverCreation(String token, String key) async {
    creationReads++;
    return created[key] ??
        (throw const ApiFailure(
          'RESOURCE_NOT_FOUND',
          'Unavailable',
          status: 404,
        ));
  }

  @override
  Future<AiConversation> rename(String token, String id, String title) async {
    final old = conversationsData.firstWhere((c) => c.id == id),
        value = AiConversation(id, title, old.createdAt, old.updatedAt);
    conversationsData[conversationsData.indexOf(old)] = value;
    return value;
  }

  @override
  Future<void> delete(String token, String id) async {
    conversationsData.removeWhere((c) => c.id == id);
    history.remove(id);
  }

  @override
  Future<AiPage<AiMessage>> messages(
    String token,
    String id, {
    String? cursor,
  }) async => AiPage(List.of(history[id] ?? []), null);
  @override
  Future<AiTurn> send(String token, AiPending pending) async {
    requests.add(pending);
    await sendGate?.future;
    if (sendFailure != null) {
      turns[pending.key] = AiTurn(
        'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        'FAILED',
        errorCode: sendFailure!.code,
      );
      throw sendFailure!;
    }
    final turn = turns.putIfAbsent(pending.key, () {
      final answer = fixtureAnswer(locale: pending.locale, mode: answerMode);
      (history[pending.conversation!] ??= []).insert(
        0,
        AiMessage(
          requests.length,
          pending.message,
          pending.locale,
          answer,
          DateTime.utc(2026, 10, 30),
        ),
      );
      return AiTurn(
        'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        'COMPLETED',
        answer: answer,
      );
    });
    if (loseSendResponse) {
      loseSendResponse = false;
      throw const ApiFailure('TIMEOUT', 'Timed out');
    }
    return turn;
  }

  @override
  Future<AiTurn> status(String token, AiPending pending) async {
    statusReads++;
    if (statusFailure != null) throw statusFailure!;
    return turns[pending.key] ??
        (throw const ApiFailure(
          'RESOURCE_NOT_FOUND',
          'Unavailable',
          status: 404,
        ));
  }

  @override
  Future<AiPage<AiCard>> more(
    String token,
    AiAction action,
    String locale,
  ) async => const AiPage([], null);
}
