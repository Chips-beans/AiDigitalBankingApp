import 'package:flutter/foundation.dart';

import '../collect/merchant_collect.dart';
import '../shop/merchant_shop.dart';

/// Private history belongs to one signed-in owner. Generation invalidates every
/// old page on refresh/filter change/disposal, including its error/finally path.
class SalesController extends ChangeNotifier {
  SalesController(this.gateway, {SalesFilter? filter, this.onExpired})
    : filter = filter ?? SalesFilter.today();
  final MerchantCollectGateway gateway;
  final VoidCallback? onExpired;
  SalesFilter filter;
  final items = <ShopReceipt>[];
  List<CurrencyTotal> totals = const [];
  String? nextCursor;
  bool loading = false;
  ShopFailure? failure;
  int _generation = 0;
  bool _disposed = false;

  Future<void> change(SalesFilter value) async {
    filter = value;
    await refresh();
  }

  Future<void> refresh() async {
    _generation++;
    items.clear();
    totals = const [];
    nextCursor = null;
    await _load(reset: true);
  }

  Future<void> more() async {
    if (loading || nextCursor == null || _disposed) return;
    await _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    if (_disposed) return;
    final generation = _generation;
    loading = true;
    failure = null;
    notifyListeners();
    try {
      final page = await gateway.sales(
        filter,
        cursor: reset ? null : nextCursor,
      );
      if (_disposed || generation != _generation) return;
      final seen = items.map((r) => r.reference).toSet();
      items.addAll(page.items.where((r) => seen.add(r.reference)));
      totals = page.totals;
      nextCursor = page.nextCursor;
    } catch (error) {
      if (_disposed || generation != _generation) return;
      failure = error is ShopFailure
          ? error
          : const ShopFailure('INVALID_RESPONSE');
      if (failure!.expired) onExpired?.call();
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    items.clear();
    totals = const [];
    super.dispose();
  }
}
