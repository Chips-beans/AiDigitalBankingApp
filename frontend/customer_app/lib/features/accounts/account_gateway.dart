import '../../core/network/api_client.dart';
import '../../shared/money.dart';

const invalidAccountData = ApiFailure(
  'INVALID_RESPONSE',
  'Account information could not be read. Refresh to try again.',
);

Map<String, dynamic> objectData(Object? value) {
  if (value is! Map<String, dynamic>) throw invalidAccountData;
  return value;
}

String textField(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String || value.isEmpty) throw invalidAccountData;
  return value;
}

DateTime dateField(Map<String, dynamic> data, String key) {
  final date = DateTime.tryParse(textField(data, key));
  if (date == null) throw invalidAccountData;
  return date;
}

class BankAccount {
  BankAccount({
    required this.id,
    required this.number,
    required this.type,
    required this.balance,
    required this.status,
    required this.createdAt,
  });
  factory BankAccount.fromJson(Object? value) {
    final data = objectData(value);
    final id = data['id'];
    final number = textField(data, 'accountNumber');
    final type = textField(data, 'accountType');
    final status = textField(data, 'status');
    if (id is! int ||
        id <= 0 ||
        !RegExp(r'^[0-9]{10,20}$').hasMatch(number) ||
        !types.contains(type) ||
        !statuses.contains(status)) {
      throw invalidAccountData;
    }
    return BankAccount(
      id: id,
      number: number,
      type: type,
      balance: Money.parse(data['balance'], textField(data, 'currency')),
      status: status,
      createdAt: dateField(data, 'createdAt'),
    );
  }
  static const types = ['SAVINGS', 'CHECKING', 'PAYROLL'];
  static const statuses = ['ACTIVE', 'FROZEN', 'CLOSED'];
  final int id;
  final String number, type, status;
  final Money balance;
  final DateTime createdAt;
  String get currency => balance.currency;
  String get label =>
      '${type[0]}${type.substring(1).toLowerCase()} · $currency · $number';
}

class RecentPosting {
  RecentPosting({
    required this.reference,
    required this.source,
    required this.destination,
    required this.amount,
    required this.fee,
    required this.type,
    required this.status,
    required this.createdAt,
    this.remark,
    Money? debit,
    this.sourceName,
    this.destinationName,
    this.bankSource = false,
    this.operation,
    this.exchangeRate,
  }) : debit = debit ?? amount;
  factory RecentPosting.fromJson(Object? value, String accountNumber) {
    final data = objectData(value);
    final source = data['sourceAccountNumber'];
    final destination = data['destinationAccountNumber'];
    final type = textField(data, 'transactionType');
    final status = textField(data, 'status');
    if ((source != null && source is! String) ||
        (destination != null && destination is! String) ||
        (source != accountNumber && destination != accountNumber) ||
        !{'TRANSFER', 'DEPOSIT', 'WITHDRAWAL'}.contains(type) ||
        !{'PENDING', 'SUCCESS', 'FAILED', 'REVERSED'}.contains(status)) {
      throw invalidAccountData;
    }
    final currency = textField(data, 'currency');
    if (data['remark'] != null && data['remark'] is! String) {
      throw invalidAccountData;
    }
    String? optionalText(String key) {
      final v = data[key];
      if (v != null && (v is! String || v.length > 200)) {
        throw invalidAccountData;
      }
      return v as String?;
    }

    final debit = Money.parse(data['amount'], currency);
    // Older servers omit the credit side; it then equals the debit.
    final credit = data['creditAmount'] == null
        ? debit
        : Money.parse(data['creditAmount'], textField(data, 'creditCurrency'));
    // The receiving account sees what it was credited; everyone else sees the debit.
    final received = destination == accountNumber && source != accountNumber;
    return RecentPosting(
      reference: textField(data, 'referenceNumber'),
      source: source as String?,
      destination: destination as String?,
      amount: received ? credit : debit,
      debit: debit,
      fee: Money.parse(data['fee'], currency),
      type: type,
      status: status,
      createdAt: dateField(data, 'createdAt'),
      remark: data['remark'] as String?,
      sourceName: optionalText('sourceName'),
      destinationName: optionalText('destinationName'),
      bankSource: data['bankSource'] == true,
      operation: optionalText('operation'),
      exchangeRate: data['exchangeRate'] == null
          ? null
          : '${data['exchangeRate']}',
    );
  }
  final String reference, type, status;
  final String? source, destination;
  final String? remark, sourceName, destinationName, operation, exchangeRate;
  final bool bankSource;

  /// [amount] is from this account's perspective; [debit] is what the source paid.
  final Money amount, fee, debit;
  final DateTime createdAt;
  bool get converted => debit.currency != amount.currency || exchangeRate != null;
  String direction(String number) => type == 'DEPOSIT'
      ? 'Deposit'
      : source == number
      ? 'Outgoing'
      : 'Incoming';
}

abstract interface class AccountGateway {
  Future<List<BankAccount>> list(String token, int page);
  Future<BankAccount> detail(String token, String number);
  Future<BankAccount> open(String token, String type, String currency);
  Future<List<RecentPosting>> recent(String token, String number);
}

class OpeningPolicy {
  const OpeningPolicy(this.testFundingEnabled, this.usd, this.khr);
  factory OpeningPolicy.fromJson(Object? value) {
    final data = objectData(value);
    final usd = Money.parse(data['usdOpeningBalance'], 'USD');
    final khr = Money.parse(data['khrOpeningBalance'], 'KHR');
    if (data['testFundingEnabled'] is! bool ||
        usd.minorUnits < BigInt.zero ||
        khr.minorUnits < BigInt.zero) {
      throw invalidAccountData;
    }
    return OpeningPolicy(data['testFundingEnabled'] as bool, usd, khr);
  }
  final bool testFundingEnabled;
  final Money usd, khr;
}

class AccountPairResult {
  const AccountPairResult(this.accounts, this.testFundingApplied);
  factory AccountPairResult.fromJson(Object? value, String type) {
    final data = objectData(value);
    if (data['accounts'] is! List || data['testFundingApplied'] is! bool) {
      throw invalidAccountData;
    }
    final accounts = (data['accounts'] as List)
        .map(BankAccount.fromJson)
        .toList();
    final funded = data['testFundingApplied'] as bool;
    if (accounts.length != 2 ||
        accounts.map((a) => a.currency).toSet().length != 2 ||
        accounts.map((a) => a.number).toSet().length != 2 ||
        accounts.any(
          (a) =>
              a.type != type ||
              a.status != 'ACTIVE' ||
              a.balance.minorUnits !=
                  (funded
                      ? BigInt.from(a.currency == 'USD' ? 20000 : 100000)
                      : BigInt.zero),
        )) {
      throw invalidAccountData;
    }
    return AccountPairResult(accounts, funded);
  }
  final List<BankAccount> accounts;
  final bool testFundingApplied;
}

abstract interface class AccountPairGateway {
  Future<OpeningPolicy> openingPolicy(String token);
  Future<AccountPairResult> openPair(String token, String type, String key);
}

class HttpAccountGateway implements AccountGateway, AccountPairGateway {
  HttpAccountGateway(this.client);
  final ApiClient client;
  @override
  Future<OpeningPolicy> openingPolicy(String token) async =>
      OpeningPolicy.fromJson(
        (await client.request(
          'GET',
          '/accounts/opening-policy',
          accessToken: token,
        ))['data'],
      );
  @override
  Future<AccountPairResult> openPair(
    String token,
    String type,
    String key,
  ) async => AccountPairResult.fromJson(
    (await client.request(
      'POST',
      '/accounts/pairs',
      accessToken: token,
      idempotencyKey: key,
      expectedStatus: 201,
      body: {'accountType': type},
    ))['data'],
    type,
  );
  @override
  Future<List<BankAccount>> list(String token, int page) async {
    final response = await client.request(
      'GET',
      '/accounts/me',
      accessToken: token,
      query: {'page': '$page', 'size': '20'},
    );
    if (response['data'] is! List) throw invalidAccountData;
    return (response['data'] as List).map(BankAccount.fromJson).toList();
  }

  @override
  Future<BankAccount> detail(String token, String number) async =>
      BankAccount.fromJson(
        (await client.request(
          'GET',
          '/accounts/${Uri.encodeComponent(number)}',
          accessToken: token,
        ))['data'],
      );
  @override
  Future<BankAccount> open(String token, String type, String currency) async {
    final account = BankAccount.fromJson(
      (await client.request(
        'POST',
        '/accounts',
        accessToken: token,
        expectedStatus: 201,
        body: {'accountType': type, 'currency': currency, 'initialDeposit': 0},
      ))['data'],
    );
    if (account.type != type ||
        account.currency != currency ||
        account.balance.minorUnits != BigInt.zero) {
      throw invalidAccountData;
    }
    return account;
  }

  @override
  Future<List<RecentPosting>> recent(String token, String number) async {
    final response = await client.request(
      'GET',
      '/transactions/account/${Uri.encodeComponent(number)}',
      accessToken: token,
      query: {'page': '0', 'size': '5'},
    );
    final data = objectData(response['data']);
    if (data['content'] is! List || (data['content'] as List).length > 5) {
      throw invalidAccountData;
    }
    return (data['content'] as List)
        .map((p) => RecentPosting.fromJson(p, number))
        .toList();
  }
}

/// Selected only by explicit APP_MODE=demo. Contains no live financial data.
class DemoAccountGateway implements AccountGateway, AccountPairGateway {
  final List<BankAccount> _accounts = [];
  final Map<String, AccountPairResult> _pairs = {};
  @override
  Future<OpeningPolicy> openingPolicy(String token) async => OpeningPolicy(
    true,
    Money.parse('200.00', 'USD'),
    Money.parse('100000', 'KHR'),
  );
  @override
  Future<AccountPairResult> openPair(
    String token,
    String type,
    String key,
  ) async {
    if (_pairs[key] case final result?) return result;
    final created = <BankAccount>[];
    for (final currency in ['USD', 'KHR']) {
      final account = BankAccount(
        id: _accounts.length + 1,
        number: '${8000000000 + _accounts.length}',
        type: type,
        balance: Money.parse(currency == 'USD' ? '200.00' : '100000', currency),
        status: 'ACTIVE',
        createdAt: DateTime.now(),
      );
      _accounts.add(account);
      created.add(account);
    }
    return _pairs[key] = AccountPairResult(created, true);
  }

  void clearSession() {
    _accounts.clear();
    _pairs.clear();
  }

  @override
  Future<List<BankAccount>> list(String token, int page) async =>
      _accounts.skip(page * 20).take(20).toList();
  @override
  Future<BankAccount> detail(String token, String number) async =>
      _accounts.firstWhere((a) => a.number == number);
  @override
  Future<BankAccount> open(String token, String type, String currency) async {
    final account = BankAccount(
      id: _accounts.length + 1,
      number: '${8000000000 + _accounts.length}',
      type: type,
      balance: Money.parse('0', currency),
      status: 'ACTIVE',
      createdAt: DateTime.now(),
    );
    _accounts.add(account);
    return account;
  }

  @override
  Future<List<RecentPosting>> recent(String token, String number) async => [];
}
