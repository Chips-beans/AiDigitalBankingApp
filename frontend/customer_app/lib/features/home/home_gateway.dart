import 'package:flutter/material.dart';

import '../accounts/account_gateway.dart';
import 'home_data.dart';

abstract interface class HomeGateway {
  Future<HomeSnapshot> load(String token);
}

/// Reads the existing owned-account and account-history Spring Boot endpoints.
/// No Figma/sample data enters this adapter.
class AccountHomeGateway implements HomeGateway {
  AccountHomeGateway(this.accounts);
  final AccountGateway accounts;

  @override
  Future<HomeSnapshot> load(String token) async {
    final owned = <String, BankAccount>{};
    for (var page = 0; ; page++) {
      if (page >= 1000) throw invalidAccountData;
      final batch = await accounts.list(token, page);
      if (batch.length > 20) throw invalidAccountData;
      for (final account in batch) {
        if (owned.containsKey(account.number)) throw invalidAccountData;
        owned[account.number] = account;
      }
      if (batch.length < 20) break;
    }
    final all = owned.values.toList();
    final postings = <String, RecentPosting>{};
    // Bound concurrency instead of opening one connection per account at once.
    for (var start = 0; start < all.length; start += 4) {
      final batch = all.skip(start).take(4).toList();
      final histories = await Future.wait(
        batch.map((account) => accounts.recent(token, account.number)),
      );
      for (var i = 0; i < batch.length; i++) {
        for (final posting in histories[i]) {
          if (posting.amount.currency != batch[i].currency ||
              (posting.source != batch[i].number &&
                  posting.destination != batch[i].number)) {
            throw invalidAccountData;
          }
          final existing = postings[posting.reference];
          if (existing != null &&
              (existing.amount.minorUnits != posting.amount.minorUnits ||
                  existing.amount.currency != posting.amount.currency ||
                  existing.source != posting.source ||
                  existing.destination != posting.destination ||
                  existing.status != posting.status)) {
            throw invalidAccountData;
          }
          postings[posting.reference] = posting;
        }
      }
    }
    final recent = postings.values.toList()
      ..sort((a, b) {
        final time = b.createdAt.compareTo(a.createdAt);
        return time != 0 ? time : a.reference.compareTo(b.reference);
      });
    return HomeSnapshot(
      List.unmodifiable(all),
      List.unmodifiable(recent.take(5)),
    );
  }
}

@immutable
class HomeSnapshot {
  const HomeSnapshot(this.accounts, this.postings);
  final List<BankAccount> accounts;
  final List<RecentPosting> postings;

  KesorHomeData presentation(Locale locale, {DateTime? now}) {
    final khmer = locale.languageCode == 'km';
    String label(String en, String km) => khmer ? km : en;
    final numbers = accounts.map((a) => a.number).toSet();
    BigInt total(String currency) => accounts
        .where((a) => a.currency == currency)
        .fold(BigInt.zero, (sum, a) => sum + a.balance.minorUnits);
    final usd = total('USD');
    final khr = total('KHR')
        .toString()
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    final clock = (now ?? DateTime.now()).toLocal();
    final today = DateTime(clock.year, clock.month, clock.day);
    final yesterday = today.subtract(const Duration(days: 1));
    String? counterpart(RecentPosting p) =>
        numbers.contains(p.source) && !numbers.contains(p.destination)
        ? p.destination
        : !numbers.contains(p.source) && numbers.contains(p.destination)
        ? p.source
        : null;
    final recipients = <String>{};
    for (final p in postings) {
      final number = counterpart(p);
      if (p.type == 'TRANSFER' && p.status == 'SUCCESS' && number != null) {
        recipients.add(number);
      }
    }
    return KesorHomeData(
      khrBalance: khr,
      usdBalance:
          '\$${usd ~/ BigInt.from(100)}.${(usd % BigInt.from(100)).toString().padLeft(2, '0')}',
      recipients: recipients
          .take(3)
          .map((number) => HomeRecipient(number))
          .toList(),
      transactions: postings.map((p) {
        final date = p.createdAt.toLocal();
        final day = DateTime(date.year, date.month, date.day);
        final internal =
            numbers.contains(p.source) && numbers.contains(p.destination);
        final incoming = numbers.contains(p.destination) && !internal;
        final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
        final amount = p.amount.currency == 'KHR'
            ? '${p.amount.decimal} ៛'
            : '\$${p.amount.decimal}';
        final description = p.remark?.trim().isNotEmpty == true
            ? p.remark!.trim()
            : internal
            ? label('Between your accounts', 'ផ្ទេររវាងគណនីរបស់អ្នក')
            : p.type == 'DEPOSIT'
            ? label('Deposit', 'ដាក់ប្រាក់')
            : p.type == 'WITHDRAWAL'
            ? label('Withdrawal', 'ដកប្រាក់')
            : counterpart(p) ?? label('Transfer', 'ផ្ទេរប្រាក់');
        final status = switch (p.status) {
          'SUCCESS' => '',
          'FAILED' => label(' · Failed', ' · បរាជ័យ'),
          'PENDING' => label(' · Pending', ' · កំពុងរង់ចាំ'),
          _ => label(' · Reversed', ' · បានបង្វិលត្រឡប់'),
        };
        return HomeTransaction(
          name: description + status,
          time:
              '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}',
          amount:
              '${internal
                  ? '↔ '
                  : incoming
                  ? '+'
                  : '-'}$amount',
          incoming: incoming,
          internal: internal,
          reference: p.reference,
          accountNumber: numbers.contains(p.source) ? p.source : p.destination,
          previousDay: day != today,
          dateLabel: day == today || day == yesterday
              ? null
              : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        );
      }).toList(),
    );
  }
}
