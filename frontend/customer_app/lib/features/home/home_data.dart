import 'package:flutter/foundation.dart';

/// Presentation values only. The Home screen has no network dependencies.
@immutable
class HomeRecipient {
  const HomeRecipient(
    this.name, {
    this.avatarAsset,
    this.accountNumber,
    this.knownName,
  });
  final String name;
  final String? avatarAsset;

  /// Set for real counterparties; tapping opens a transfer pre-filled with it.
  final String? accountNumber;

  /// The server-reported profile name, when the history included one.
  final String? knownName;
}

@immutable
class HomeTransaction {
  const HomeTransaction({
    required this.name,
    required this.time,
    required this.amount,
    required this.incoming,
    this.avatarAsset,
    this.previousDay = false,
    this.reference,
    this.accountNumber,
    this.dateLabel,
    this.internal = false,
    this.bank = false,
    this.counterpartyNumber,
  });
  final String name, time, amount;

  /// [bank]: posted by Kesor Bank itself (opening credit or deposit).
  final bool incoming, previousDay, internal, bank;
  final String? avatarAsset, reference, dateLabel, accountNumber;

  /// The other customer's account, used to show their profile photo.
  final String? counterpartyNumber;
}

@immutable
class KesorHomeData {
  const KesorHomeData({
    required this.khrBalance,
    required this.usdBalance,
    this.recipients = const [],
    this.transactions = const [],
  });

  /// Figma content is used by the explicit, offline design preview only.
  static const designPreview = KesorHomeData(
    khrBalance: '2,000',
    usdBalance: r'$168.00',
    recipients: [
      HomeRecipient('Elon Musk', avatarAsset: 'recipient-elon.png'),
      HomeRecipient('Jeff Bezos', avatarAsset: 'recipient-jeff.png'),
      HomeRecipient('Warren Buffett', avatarAsset: 'recipient-warren.png'),
    ],
    transactions: [
      HomeTransaction(
        name: 'Jeff Bezos',
        time: '9:36 AM',
        amount: '-100000 ៛',
        incoming: false,
        avatarAsset: 'transaction-jeff.png',
      ),
      HomeTransaction(
        name: 'Elon Musk',
        time: '7:34 AM',
        amount: r'-$2.8',
        incoming: false,
        avatarAsset: 'transaction-elon.png',
      ),
      HomeTransaction(
        name: 'Warrent Buffet',
        time: '9:24 PM',
        amount: r'+168$',
        incoming: true,
        previousDay: true,
        avatarAsset: 'transaction-warren.png',
      ),
    ],
  );

  final String khrBalance, usdBalance;

  /// People the customer saved to Favorites; never derived from history.
  final List<HomeRecipient> recipients;
  final List<HomeTransaction> transactions;

  KesorHomeData withRecipients(List<HomeRecipient> recipients) => KesorHomeData(
    khrBalance: khrBalance,
    usdBalance: usdBalance,
    recipients: recipients,
    transactions: transactions,
  );
}
