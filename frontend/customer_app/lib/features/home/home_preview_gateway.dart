import '../../core/network/api_client.dart';

class HomePreviewEntry {
  const HomePreviewEntry(
    this.reference,
    this.name,
    this.createdAt,
    this.direction,
    this.status,
  );
  final String reference, name, direction, status;
  final DateTime createdAt;
  factory HomePreviewEntry.parse(Object? row) {
    if (row is! Map ||
        row['name'] is! String ||
        row['reference'] is! String ||
        row['createdAt'] is! String ||
        !{'INTERNAL', 'INCOMING', 'OUTGOING'}.contains(row['direction']) ||
        !{'SUCCESS', 'FAILED', 'PENDING', 'REVERSED'}.contains(row['status'])) {
      throw const FormatException('Invalid preview');
    }
    return HomePreviewEntry(
      row['reference'] as String,
      row['name'] as String,
      DateTime.parse(row['createdAt'] as String),
      row['direction'] as String,
      row['status'] as String,
    );
  }
}

abstract interface class HomePreviewGateway {
  Future<List<HomePreviewEntry>> load(String ticket);
}

class HttpHomePreviewGateway implements HomePreviewGateway {
  HttpHomePreviewGateway(this.client);
  final ApiClient client;
  @override
  Future<List<HomePreviewEntry>> load(String ticket) async {
    final response = await client.request(
      'POST',
      '/auth/pin/home-preview',
      body: {'ticket': ticket},
    );
    final rows = response['data'];
    if (rows is! List || rows.length > 5) {
      throw const FormatException('Invalid preview');
    }
    return rows.map(HomePreviewEntry.parse).toList(growable: false);
  }
}
