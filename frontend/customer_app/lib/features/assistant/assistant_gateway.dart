import '../../core/network/api_client.dart';
import 'assistant_models.dart';

abstract interface class AssistantGateway {
  Future<bool> available(String token);
  Future<AiPage<AiConversation>> conversations(String token, {String? cursor});
  Future<AiConversation> create(String token, String key);
  Future<AiConversation> recoverCreation(String token, String key);
  Future<AiConversation> rename(String token, String id, String title);
  Future<void> delete(String token, String id);
  Future<AiPage<AiMessage>> messages(String token, String id, {String? cursor});
  Future<AiTurn> send(String token, AiPending pending);
  Future<AiTurn> status(String token, AiPending pending);
  Future<AiPage<AiCard>> more(String token, AiAction action, String locale);
}

class HttpAssistantGateway implements AssistantGateway {
  HttpAssistantGateway(this.client);
  final ApiClient client;
  String path(String id) {
    if (!aiId(id)) throw invalidAssistant;
    return '/ai/conversations/$id';
  }

  Future<Object?> _request(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? key,
  }) async => (await client.request(
    method,
    path,
    accessToken: token,
    body: body,
    query: query,
    idempotencyKey: key,
  ))['data'];
  @override
  Future<bool> available(String token) async {
    final data = objectData(await _request(token, 'GET', '/ai/capabilities'));
    if (data['available'] is! bool ||
        data['retentionDays'] != 30 ||
        data['maxMessageLength'] != 2000) {
      throw invalidAssistant;
    }
    return data['available'] as bool;
  }

  @override
  Future<AiPage<AiConversation>> conversations(
    String token, {
    String? cursor,
  }) async => AiPage.fromJson(
    await _request(
      token,
      'GET',
      '/ai/conversations',
      query: {'size': '20', 'cursor': ?cursor},
    ),
    AiConversation.fromJson,
  );
  @override
  Future<AiConversation> create(String token, String key) async =>
      AiConversation.fromJson(
        await _request(token, 'POST', '/ai/conversations', key: key),
      );
  @override
  Future<AiConversation> recoverCreation(String token, String key) async {
    final result = AiPage<AiConversation>.fromJson(
      await _request(
        token,
        'GET',
        '/ai/conversations',
        query: {'requestKey': key},
      ),
      AiConversation.fromJson,
    );
    if (result.items.length != 1) throw invalidAssistant;
    return result.items.single;
  }

  @override
  Future<AiConversation> rename(String token, String id, String title) async =>
      AiConversation.fromJson(
        await _request(token, 'PATCH', path(id), body: {'title': title}),
      );
  @override
  Future<void> delete(String token, String id) async {
    await _request(token, 'DELETE', path(id));
  }

  @override
  Future<AiPage<AiMessage>> messages(
    String token,
    String id, {
    String? cursor,
  }) async => AiPage.fromJson(
    await _request(
      token,
      'GET',
      '${path(id)}/messages',
      query: {'size': '20', 'cursor': ?cursor},
    ),
    AiMessage.fromJson,
  );
  @override
  Future<AiTurn> send(String token, AiPending pending) async => AiTurn.fromJson(
    await _request(
      token,
      'POST',
      '${path(pending.conversation!)}/messages',
      key: pending.key,
      body: pending.body,
    ),
  );
  @override
  Future<AiTurn> status(
    String token,
    AiPending pending,
  ) async => AiTurn.fromJson(
    await _request(
      token,
      'GET',
      '${path(pending.conversation!)}/requests/${Uri.encodeComponent(pending.key)}',
    ),
  );
  @override
  Future<AiPage<AiCard>> more(
    String token,
    AiAction action,
    String locale,
  ) async {
    if (action.type != 'MORE' ||
        action.filters == null ||
        action.cursor == null) {
      throw invalidAssistant;
    }
    final data = objectData(
      await _request(
        token,
        'GET',
        '/transactions/search',
        query: {
          for (final e in action.filters!.entries)
            if (e.value != null) e.key: e.value!,
          'cursor': action.cursor!,
          'size': '20',
          'locale': locale,
        },
      ),
    );
    return AiPage(
      aiList(data['cards'], AiCard.fromJson, 50),
      AiPage.mCursor(data['nextCursor']),
    );
  }
}

class UnavailableAssistantGateway implements AssistantGateway {
  static const failure = ApiFailure(
    'AI_UNAVAILABLE',
    'The assistant is unavailable. Your banking services remain available.',
  );
  @override
  Future<bool> available(String token) async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(failure);
}
