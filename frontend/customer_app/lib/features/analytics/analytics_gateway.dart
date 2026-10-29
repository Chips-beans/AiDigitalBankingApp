import '../../core/network/api_client.dart';

const invalidAnalytics = ApiFailure(
  'INVALID_RESPONSE',
  'Analytics could not be read. Pull down to retry.',
);

String monthKey(DateTime month) =>
    '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

DateTime bankingMonth(DateTime now) {
  final local = now.toUtc().add(const Duration(hours: 7));
  return DateTime.utc(local.year, local.month);
}

/// Aggregate amounts are intentionally not bounded by a single posting's limit.
/// Only the rendering layer may convert a normalized ratio to double.
BigInt analyticsUnits(Object? value, String currency) {
  if (value is! String || value.length > 80) throw invalidAnalytics;
  final pattern = currency == 'USD' ? r'^[0-9]+\.[0-9]{2}$' : r'^[0-9]+$';
  if (!RegExp(pattern).hasMatch(value)) throw invalidAnalytics;
  return BigInt.parse(value.replaceAll('.', ''));
}

String analyticsMoney(BigInt units, String currency) {
  final digits = units.toString().padLeft(currency == 'USD' ? 3 : 1, '0');
  final whole = currency == 'USD'
      ? digits.substring(0, digits.length - 2)
      : digits;
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return currency == 'USD'
      ? '\$$grouped.${digits.substring(digits.length - 2)}'
      : '$grouped ៛';
}

class AnalyticsDay {
  const AnalyticsDay(this.date, this.income, this.expense);
  final DateTime date;
  final BigInt income, expense;
}

class AnalyticsSnapshot {
  AnalyticsSnapshot(
    this.month,
    this.currency,
    this.income,
    this.expense,
    List<AnalyticsDay> daily,
  ) : daily = List.unmodifiable(daily);
  final DateTime month;
  final String currency;
  final BigInt income, expense;
  final List<AnalyticsDay> daily;
  bool get empty => income == BigInt.zero && expense == BigInt.zero;

  factory AnalyticsSnapshot.fromJson(
    Object? value,
    DateTime requested,
    String currency,
  ) {
    if (!{'USD', 'KHR'}.contains(currency) || value is! Map<String, dynamic>) {
      throw invalidAnalytics;
    }
    if (value['currency'] != currency ||
        value['month'] != monthKey(requested) ||
        value['timeZone'] != 'Asia/Phnom_Penh') {
      throw invalidAnalytics;
    }
    final rows = value['daily'];
    final count = DateTime.utc(requested.year, requested.month + 1, 0).day;
    if (rows is! List || rows.length != count) throw invalidAnalytics;
    final days = <AnalyticsDay>[];
    var income = BigInt.zero, expense = BigInt.zero;
    for (var i = 0; i < count; i++) {
      final row = rows[i];
      final date = DateTime.utc(requested.year, requested.month, i + 1);
      final expected =
          '${monthKey(requested)}-${(i + 1).toString().padLeft(2, '0')}';
      if (row is! Map<String, dynamic> || row['date'] != expected) {
        throw invalidAnalytics;
      }
      final inUnits = analyticsUnits(row['totalIncome'], currency);
      final outUnits = analyticsUnits(row['totalExpense'], currency);
      days.add(AnalyticsDay(date, inUnits, outUnits));
      income += inUnits;
      expense += outUnits;
    }
    if (income != analyticsUnits(value['totalIncome'], currency) ||
        expense != analyticsUnits(value['totalExpense'], currency)) {
      throw invalidAnalytics;
    }
    return AnalyticsSnapshot(
      DateTime.utc(requested.year, requested.month),
      currency,
      income,
      expense,
      days,
    );
  }
}

abstract interface class AnalyticsGateway {
  Future<AnalyticsSnapshot> load(String token, DateTime month, String currency);
}

class UnavailableAnalyticsGateway implements AnalyticsGateway {
  @override
  Future<AnalyticsSnapshot> load(
    String token,
    DateTime month,
    String currency,
  ) async => throw const ApiFailure(
    'ANALYTICS_UNAVAILABLE',
    'Analytics is unavailable. Pull down to retry.',
  );
}

class HttpAnalyticsGateway implements AnalyticsGateway {
  HttpAnalyticsGateway(this.client);
  final ApiClient client;
  @override
  Future<AnalyticsSnapshot> load(
    String token,
    DateTime month,
    String currency,
  ) async {
    final response = await client.request(
      'GET',
      '/analytics/monthly-overview',
      accessToken: token,
      query: {
        'year': '${month.year}',
        'month': '${month.month}',
        'currency': currency,
      },
    );
    if (response['success'] != true) throw invalidAnalytics;
    return AnalyticsSnapshot.fromJson(response['data'], month, currency);
  }
}

/// Explicit demo/visual fixture only. Never selected because a request failed.
class DemoAnalyticsGateway implements AnalyticsGateway {
  @override
  Future<AnalyticsSnapshot> load(
    String token,
    DateTime month,
    String currency,
  ) async => sampleAnalytics(month, currency);
}

AnalyticsSnapshot sampleAnalytics(DateTime month, String currency) {
  final count = DateTime.utc(month.year, month.month + 1, 0).day;
  final days = List.generate(
    count,
    (i) => AnalyticsDay(
      DateTime.utc(month.year, month.month, i + 1),
      BigInt.from((i * 37 % 97 + 10) * (currency == 'USD' ? 100 : 4000)),
      BigInt.from((i * 23 % 89 + 8) * (currency == 'USD' ? 100 : 4000)),
    ),
  );
  return AnalyticsSnapshot(
    month,
    currency,
    days.fold(BigInt.zero, (sum, d) => sum + d.income),
    days.fold(BigInt.zero, (sum, d) => sum + d.expense),
    days,
  );
}
