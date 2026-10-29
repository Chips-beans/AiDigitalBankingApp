import '../core/network/api_client.dart';

/// Nonnegative, bounded banking money. No conversion through double.
class Money {
  const Money._(this.minorUnits, this.currency);
  final BigInt minorUnits;
  final String currency;

  String get decimal {
    final digits = minorUnits.toString().padLeft(
      currency == 'USD' ? 3 : 1,
      '0',
    );
    return currency == 'USD'
        ? '${digits.substring(0, digits.length - 2)}.${digits.substring(digits.length - 2)}'
        : digits;
  }

  factory Money.parse(Object? value, String currency) {
    if (!{'USD', 'KHR'}.contains(currency) ||
        (value is! String && value is! int)) {
      throw invalidMoney;
    }
    final match = RegExp(r'^([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$')
        .firstMatch(value.toString());
    if (match == null || value.toString().length > 80) throw invalidMoney;
    final exponent = int.tryParse(match[3] ?? '0');
    if (exponent == null || exponent.abs() > 18) throw invalidMoney;
    final fraction = match[2] ?? '';
    final digits = BigInt.parse('${match[1]}$fraction');
    final places = (currency == 'USD' ? 2 : 0) + exponent - fraction.length;
    BigInt units;
    if (places >= 0) {
      units = digits * BigInt.from(10).pow(places);
    } else {
      final divisor = BigInt.from(10).pow(-places);
      if (digits.remainder(divisor) != BigInt.zero) throw invalidMoney;
      units = digits ~/ divisor;
    }
    final limit = BigInt.parse(
      currency == 'USD' ? '999999999999999' : '9999999999999',
    );
    if (units > limit) throw invalidMoney;
    return Money._(units, currency);
  }

  String get formatted {
    final scale = currency == 'USD' ? 2 : 0;
    final digits = minorUnits.toString().padLeft(scale + 1, '0');
    final whole = scale == 0 ? digits : digits.substring(0, digits.length - 2);
    final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$currency $grouped${scale == 0 ? '' : '.${digits.substring(digits.length - 2)}'}';
  }

  static const invalidMoney = ApiFailure(
    'INVALID_RESPONSE',
    'The service returned an unsupported amount or currency. Refresh to try again.',
  );
}
