class HomeUnlockTarget {
  const HomeUnlockTarget(
    this.page, {
    this.tab = 0,
    this.reference,
    this.recipient,
  });
  final String? page;
  final int tab;
  final String? reference, recipient;
}
