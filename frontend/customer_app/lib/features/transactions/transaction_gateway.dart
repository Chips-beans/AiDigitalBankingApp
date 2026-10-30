import '../../core/network/api_client.dart';
import '../accounts/account_gateway.dart';
import 'transfer_models.dart';

class PostingPage {
  const PostingPage(this.content, this.page, this.last, this.total);
  final List<RecentPosting> content;
  final int page, total;
  final bool last;
}

abstract interface class TransactionGateway {
  /// [pinProof] is required for a new key; a replay of a completed key needs none.
  Future<RecentPosting> transfer(
    String token,
    SavedTransfer operation, {
    String? pinProof,
  });
  Future<PostingPage> history(String token, String account, int page);
  Future<RecentPosting> detail(String token, String account, String reference);
}

class HttpTransactionGateway implements TransactionGateway {
  HttpTransactionGateway(this.client);
  final ApiClient client;
  @override
  Future<RecentPosting> transfer(
    String token,
    SavedTransfer operation, {
    String? pinProof,
  }) async {
    final response = await client.request(
      'POST',
      operation.draft.isQr ? '/payments/qr/transfer' : '/transactions/transfer',
      accessToken: token,
      idempotencyKey: operation.key,
      pinProof: pinProof,
      body: operation.draft.isQr
          ? operation.draft.qrPayload
          : operation.draft.payload,
      expectedStatus: 200,
    );
    final posting = RecentPosting.fromJson(
      operation.draft.isQr
          ? objectData(response['data'])['transaction']
          : response['data'],
      operation.draft.source,
    );
    validateReceipt(posting, operation);
    return posting;
  }

  static void validateReceipt(RecentPosting posting, SavedTransfer operation) {
    final draft = operation.draft;
    if (posting.type != 'TRANSFER' ||
        posting.status != 'SUCCESS' ||
        posting.source != draft.source ||
        posting.destination != draft.destination ||
        posting.amount.currency != draft.amount.currency ||
        posting.amount.minorUnits != draft.amount.minorUnits ||
        posting.fee.minorUnits != BigInt.zero ||
        posting.remark != draft.remark) {
      throw invalidAccountData;
    }
  }

  @override
  Future<PostingPage> history(String token, String account, int page) async {
    final response = await client.request(
      'GET',
      '/transactions/account/${Uri.encodeComponent(account)}',
      accessToken: token,
      query: {'page': '$page', 'size': '20'},
    );
    final data = objectData(response['data']);
    if (data['pageNo'] != page ||
        data['pageSize'] != 20 ||
        data['last'] is! bool ||
        data['totalElements'] is! int ||
        (data['totalElements'] as int) < 0 ||
        data['totalPages'] is! int ||
        (data['totalPages'] as int) < 0 ||
        data['content'] is! List ||
        (data['content'] as List).length > 20 ||
        (data['last'] == false && (data['content'] as List).isEmpty)) {
      throw invalidAccountData;
    }
    final content = (data['content'] as List)
        .map((p) => RecentPosting.fromJson(p, account))
        .toList();
    if (content.map((p) => p.reference).toSet().length != content.length) {
      throw invalidAccountData;
    }
    return PostingPage(
      content,
      page,
      data['last'] as bool,
      data['totalElements'] as int,
    );
  }

  @override
  Future<RecentPosting> detail(
    String token,
    String account,
    String reference,
  ) async {
    final posting = RecentPosting.fromJson(
      (await client.request(
        'GET',
        '/transactions/${Uri.encodeComponent(reference)}',
        accessToken: token,
      ))['data'],
      account,
    );
    if (posting.reference != reference) throw invalidAccountData;
    return posting;
  }
}

/// Explicit demo preview: history is empty and real transfers are unavailable.
class PreviewTransactionGateway implements TransactionGateway {
  @override
  Future<PostingPage> history(String token, String account, int page) async =>
      const PostingPage([], 0, true, 0);
  @override
  Future<RecentPosting> detail(
    String token,
    String account,
    String reference,
  ) async => throw const ApiFailure(
    'PREVIEW_ONLY',
    'Transaction details are unavailable in this preview.',
  );
  @override
  Future<RecentPosting> transfer(
    String token,
    SavedTransfer operation, {
    String? pinProof,
  }) async => throw const ApiFailure(
        'PREVIEW_ONLY',
        'Sending transfers requires the native app and real API.',
      );
}
