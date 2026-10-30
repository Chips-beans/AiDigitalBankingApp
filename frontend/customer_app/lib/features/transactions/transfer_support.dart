import 'dart:convert';
import 'dart:typed_data';

import '../../core/network/api_client.dart';
import '../../shared/money.dart';
import '../accounts/account_gateway.dart';
import '../auth/session_controller.dart';

/// A receiver resolved by the server from an account number.
class Recipient {
  const Recipient(this.accountNumber, this.currency, this.name, this.hasPhoto);
  factory Recipient.fromJson(Object? value) {
    final data = objectData(value);
    final number = textField(data, 'accountNumber');
    final currency = textField(data, 'currency');
    final name = textField(data, 'displayName');
    if (!RegExp(r'^[0-9]{10,20}$').hasMatch(number) ||
        !{'USD', 'KHR'}.contains(currency) ||
        name.isEmpty ||
        name.length > 120 ||
        data['hasPhoto'] is! bool) {
      throw const ApiFailure(
        'INVALID_RESPONSE',
        'Recipient details could not be verified.',
      );
    }
    return Recipient(number, currency, name, data['hasPhoto'] as bool);
  }
  final String accountNumber, currency, name;
  final bool hasPhoto;
}

/// Exact amounts the server will debit and credit for a transfer.
class TransferQuote {
  const TransferQuote(this.debit, this.credit, this.rate, this.converted);
  factory TransferQuote.fromJson(Object? value) {
    final data = objectData(value);
    final converted = data['converted'];
    if (converted is! bool) {
      throw const ApiFailure('INVALID_RESPONSE', 'The quote could not be verified.');
    }
    return TransferQuote(
      Money.parse(data['debitAmount'], textField(data, 'debitCurrency')),
      Money.parse(data['creditAmount'], textField(data, 'creditCurrency')),
      '${data['rate']}',
      converted,
    );
  }
  final Money debit, credit;
  final String rate;
  final bool converted;
}

/// Fixed internal rate (server `app.fx.khr-per-usd`); the server stays authoritative.
const khrPerUsd = 4000;

/// The exact debit needed to pay a fixed [credit] from a [sourceCurrency] wallet,
/// or null when it cannot be paid exactly (mirrors the server's CONVERSION_NOT_EXACT).
Money? exactDebitFor(Money credit, String sourceCurrency) {
  if (credit.currency == sourceCurrency) return credit;
  final rielPerCent = BigInt.from(khrPerUsd ~/ 100);
  if (sourceCurrency == 'USD') {
    // Whole riel -> cents (riel / 40); the "e-2" exponent keeps it exact.
    if (credit.minorUnits.remainder(rielPerCent) != BigInt.zero) return null;
    return Money.parse('${credit.minorUnits ~/ rielPerCent}e-2', 'USD');
  }
  // Cents -> whole riel (cents * 40).
  return Money.parse('${credit.minorUnits * rielPerCent}', 'KHR');
}

abstract interface class TransferSupportGateway {
  Future<Recipient> lookup(String token, String accountNumber);
  Future<Uint8List?> photo(String token, String accountNumber);
  Future<TransferQuote> quote(
    String token,
    String source,
    String destination,
    Money amount,
  );

  /// Verifies the PIN and returns a one-time, two-minute transfer proof.
  Future<String> transferProof(String token, String pin);
}

class HttpTransferSupportGateway implements TransferSupportGateway {
  HttpTransferSupportGateway(this.client);
  final ApiClient client;

  @override
  Future<Recipient> lookup(String token, String accountNumber) async =>
      Recipient.fromJson(
        (await client.request(
          'GET',
          '/accounts/lookup',
          accessToken: token,
          query: {'number': accountNumber},
        ))['data'],
      );

  @override
  Future<Uint8List?> photo(String token, String accountNumber) async {
    try {
      final data = objectData(
        (await client.request(
          'GET',
          '/accounts/lookup/photo',
          accessToken: token,
          query: {'number': accountNumber},
        ))['data'],
      );
      final bytes = base64Decode(textField(data, 'imageBase64'));
      return bytes.length > 5 * 1024 * 1024 ? null : bytes;
    } on ApiFailure catch (e) {
      if (e.status == 404) return null;
      rethrow;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<TransferQuote> quote(
    String token,
    String source,
    String destination,
    Money amount,
  ) async => TransferQuote.fromJson(
    (await client.request(
      'GET',
      '/transactions/quote',
      accessToken: token,
      query: {
        'sourceAccountNumber': source,
        'destinationAccountNumber': destination,
        'amount': amount.decimal,
      },
    ))['data'],
  );

  @override
  Future<String> transferProof(String token, String pin) async {
    final data = objectData(
      (await client.request(
        'POST',
        '/auth/pin/transfer-proof',
        accessToken: token,
        body: {'pin': pin},
        expectedStatus: 200,
      ))['data'],
    );
    final proof = textField(data, 'proof');
    if (proof.isEmpty || proof.length > 128) {
      throw const ApiFailure('INVALID_RESPONSE', 'PIN confirmation failed.');
    }
    return proof;
  }
}

/// Session-lifetime cache so lists of recipients don't repeat lookups.
class RecipientDirectory {
  RecipientDirectory(this.session, this.gateway);
  final SessionController session;
  final TransferSupportGateway gateway;
  final _recipients = <String, Future<Recipient?>>{};
  final _photos = <String, Future<Uint8List?>>{};

  /// Null when no active Kesor account has this number.
  Future<Recipient?> lookup(String number) =>
      _recipients.putIfAbsent(number, () async {
        try {
          return await session.authorizedRead(
            (token) => gateway.lookup(token, number),
          );
        } on ApiFailure catch (e) {
          if (e.status == 404) return null;
          _recipients.remove(number);
          rethrow;
        }
      });

  Future<Uint8List?> photo(String number) =>
      _photos.putIfAbsent(number, () async {
        try {
          return await session.authorizedRead(
            (token) => gateway.photo(token, number),
          );
        } catch (_) {
          _photos.remove(number);
          return null;
        }
      });

  void clear() {
    _recipients.clear();
    _photos.clear();
  }
}
