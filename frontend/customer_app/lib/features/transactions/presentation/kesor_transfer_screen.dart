import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/app_labels.dart';
import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/kesor_layout.dart';
import '../../accounts/account_gateway.dart';
import '../../accounts/accounts_controller.dart';
import '../../auth/session_controller.dart';
import '../recipient_favorites.dart';
import '../transfer_controller.dart';
import '../transfer_models.dart';
import 'transfer_panel.dart';

/// Native Flutter implementation of Kesor Figma frame 273:356 (440 × 956).
/// System chrome is only reproduced by the visual fixture, never over native bars.
class KesorTransferScreen extends StatefulWidget {
  const KesorTransferScreen({
    required this.controller,
    required this.accounts,
    required this.enabled,
    required this.onBack,
    required this.favorites,
    this.showDeviceChrome = false,
    super.key,
  });
  final TransferController controller;
  final AccountsController accounts;
  final RecipientFavoritesStore favorites;
  final bool enabled, showDeviceChrome;
  final VoidCallback onBack;
  @override
  State<KesorTransferScreen> createState() => _KesorTransferScreenState();
}

class _KesorTransferScreenState extends State<KesorTransferScreen> {
  final destination = TextEditingController(),
      amount = TextEditingController(),
      remark = TextEditingController();
  final form = GlobalKey<FormState>();
  final errorFocus = FocusNode();
  late final int user;
  late final String sessionId;
  late final Listenable changes;
  bool saveFavorite = false, favoriteBusy = false;
  String? favoriteError;
  List<FavoriteRecipient> savedRecipients = [];
  final attempted = <String>{}, bookmarked = <String>{};
  TransferController get model => widget.controller;
  bool get current =>
      mounted &&
      model.session.phase == SessionPhase.signedIn &&
      !model.session.privacyCovered &&
      model.session.identity?.userId == user &&
      model.session.identity?.sessionId == sessionId;
  BankAccount? get selected => widget.accounts.accounts
      .where((a) => a.number == widget.accounts.selected?.number)
      .firstOrNull;
  bool get entry => model.review == null && model.saved == null;
  @override
  void initState() {
    super.initState();
    user = model.session.identity!.userId;
    sessionId = model.session.identity!.sessionId;
    changes = Listenable.merge([model, widget.accounts]);
    model.addListener(_transferChanged);
    model.session.addListener(_sessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (current) _loadFavorites();
    });
  }

  @override
  void dispose() {
    model.removeListener(_transferChanged);
    model.session.removeListener(_sessionChanged);
    destination.dispose();
    amount.dispose();
    remark.dispose();
    errorFocus.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    try {
      final list = await widget.favorites.read(user);
      if (current) {
        setState(() {
          savedRecipients = list;
          favoriteError = null;
        });
      }
    } catch (_) {
      if (current) {
        setState(() => favoriteError = FavoriteRecipient.unavailable.message);
      }
    }
  }

  void _sessionChanged() {
    if (current) {
      _transferChanged();
      return;
    }
    if (model.session.phase != SessionPhase.signedIn ||
        model.session.identity?.userId != user ||
        model.session.identity?.sessionId != sessionId) {
      destination.clear();
      amount.clear();
      remark.clear();
      savedRecipients = [];
      saveFavorite = false;
      favoriteError = null;
    }
  }

  void _transferChanged() {
    final saved = model.saved;
    if (current &&
        saveFavorite &&
        saved?.outcome == 'success' &&
        attempted.add(saved!.key)) {
      _bookmark(saved);
    }
  }

  Future<void> _bookmark(SavedTransfer transfer) async {
    if (!current || favoriteBusy || transfer.outcome != 'success') return;
    favoriteBusy = true;
    try {
      await widget.favorites.add(
        user,
        FavoriteRecipient(
          transfer.draft.destination,
          transfer.draft.amount.currency,
        ),
      );
      if (!current) return;
      bookmarked.add(transfer.key);
      await _loadFavorites();
    } catch (_) {
      if (current) {
        setState(
          () => favoriteError =
              'Transfer confirmed. The recipient could not be saved.',
        );
      }
    } finally {
      if (mounted) setState(() => favoriteBusy = false);
    }
  }

  String _walletName(BankAccount account) => tx(
    context,
    account.currency == 'USD' ? 'US Dollar Wallet' : 'Khmer Riel Wallet',
  );
  String _balance(BankAccount account) => account.currency == 'USD'
      ? '\$${account.balance.formatted.substring(4)} USD'
      : account.balance.formatted;

  Future<void> _chooseAccount() async {
    if (!current || model.busy) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _TransferPrivateSheet(
        session: model.session,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .7,
            ),
            child: ListenableBuilder(
              listenable: widget.accounts,
              builder: (context, _) => ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tx(context, 'Select your account'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  for (final account in widget.accounts.accounts)
                    ListTile(
                      title: Text(_walletName(account)),
                      subtitle: Text(
                        '${account.number}\n${account.balance.formatted}',
                      ),
                      isThreeLine: true,
                      enabled: account.status == 'ACTIVE',
                      selected: selected?.number == account.number,
                      trailing: account.status == 'ACTIVE'
                          ? null
                          : Text(account.status),
                      onTap: () {
                        if (!current || model.busy) return;
                        Navigator.pop(context);
                        widget.accounts.select(account);
                      },
                    ),
                  if (widget.accounts.hasMore)
                    TextButton(
                      onPressed: widget.accounts.loadingMore
                          ? null
                          : widget.accounts.loadMore,
                      child: Text(tx(context, 'Load more accounts')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseFavorite() async {
    if (!current || model.busy) return;
    await _loadFavorites();
    if (!mounted || !current || favoriteError != null) return;
    var list = savedRecipients
        .where((r) => selected == null || r.currency == selected!.currency)
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _TransferPrivateSheet(
        session: model.session,
        child: StatefulBuilder(
          builder: (context, update) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .7,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tx(context, 'Saved recipients'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        tx(context, 'No saved recipients for this wallet yet.'),
                      ),
                    ),
                  for (final recipient in list)
                    ListTile(
                      title: Text(recipient.number),
                      subtitle: Text(recipient.currency),
                      onTap: () {
                        if (!current || model.busy) return;
                        destination.text = recipient.number;
                        model.edit();
                        Navigator.pop(sheetContext);
                      },
                      trailing: IconButton(
                        tooltip: tx(context, 'Remove saved recipient'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          try {
                            await widget.favorites.remove(user, recipient);
                            if (!current || !sheetContext.mounted) return;
                            update(
                              () => list = list
                                  .where((r) => !r.same(recipient))
                                  .toList(),
                            );
                            await _loadFavorites();
                          } catch (_) {
                            if (current) {
                              setState(
                                () => favoriteError =
                                    FavoriteRecipient.unavailable.message,
                              );
                            }
                          }
                        },
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text(tx(context, 'Close')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _continue() {
    if (!current ||
        !widget.enabled ||
        !model.ready ||
        model.busy ||
        model.storageError != null ||
        selected == null ||
        selected!.status != 'ACTIVE' ||
        widget.accounts.loadingDetail) {
      return;
    }
    if (!form.currentState!.validate()) return;
    if (!model.prepare(selected!, destination.text, amount.text, remark.text)) {
      errorFocus.requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  Widget _messages() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!widget.enabled)
        NoticePanel(
          tx(
            context,
            'Sending transfers is available in the native app with the real API. This preview does not send payments.',
          ),
        ),
      if (model.busy || widget.accounts.loadingDetail)
        const LinearProgressIndicator(),
      if (model.storageError != null) ...[
        NoticePanel(tx(context, model.storageError!.message), error: true),
        TextButton(
          onPressed: model.busy ? null : model.initialize,
          child: Text(tx(context, 'Retry transfer secure setup')),
        ),
      ],
      if (model.error != null)
        NoticePanel(
          tx(context, model.error!.message),
          error: true,
          focusNode: errorFocus,
        ),
      if (widget.accounts.detailError != null ||
          widget.accounts.listError != null) ...[
        NoticePanel(
          tx(
            context,
            (widget.accounts.detailError ?? widget.accounts.listError)!.message,
          ),
          error: true,
        ),
        TextButton(
          onPressed: widget.accounts.loading ? null : widget.accounts.refresh,
          child: Text(tx(context, 'Retry')),
        ),
      ],
      if (favoriteError != null) ...[
        NoticePanel(tx(context, favoriteError!), error: true),
        TextButton(
          onPressed: favoriteBusy ? null : _loadFavorites,
          child: Text(tx(context, 'Retry saved recipients')),
        ),
      ],
    ],
  );
  Widget _fields() {
    final account = selected, colors = AppColors.of(context);
    return Form(
      key: form,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 510),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 9.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _messages(),
              _label('Select your account'),
              const SizedBox(height: 8),
              Semantics(
                label:
                    '${tx(context, 'Select your account')}${account == null ? '' : ', ${account.number}'}',
                button: true,
                child: Material(
                  color: colors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: colors.border),
                  ),
                  child: InkWell(
                    key: const ValueKey('transfer-wallet-picker'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: model.busy ? null : _chooseAccount,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 60),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            _fieldIcon('card.svg', const Size(22, 22)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    account == null
                                        ? tx(context, 'Choose an account')
                                        : _walletName(account),
                                    style: _type(context, 15, 24),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    account == null ? '—' : _balance(account),
                                    style: _type(
                                      context,
                                      12,
                                      18,
                                      color: AppPalette.gold500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                color: AppPalette.neutralLightAccent,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: TransferAsset('chevron-down.svg'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.accounts.accounts.isEmpty && !widget.accounts.loading)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tx(
                      context,
                      'Open an account from Home before making a transfer.',
                    ),
                    style: _type(context, 12, 18),
                  ),
                ),
              const SizedBox(height: 8.75),
              _label('Receiver account number'),
              const SizedBox(height: 8),
              _TransferInput(
                key: const ValueKey('transfer-receiver-frame'),
                controller: destination,
                fieldKey: const ValueKey('transfer-destination'),
                semanticLabel: tx(context, 'Receiver account number'),
                hint: '1000000002',
                enabled: !model.busy,
                keyboard: TextInputType.number,
                action: TextInputAction.next,
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 12),
                  child: _fieldIcon('contact.svg', const Size(22, 22)),
                ),
                suffix: SizedBox(
                  width: 48,
                  height: 56,
                  child: Semantics(
                    button: true,
                    label: tx(context, 'Saved recipients'),
                    child: InkWell(
                      onTap: model.busy ? null : _chooseFavorite,
                      borderRadius: BorderRadius.circular(10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppPalette.neutralLightSurface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: TransferAsset('favorites.svg'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                validator: (value) =>
                    RegExp(r'^[0-9]{10,20}$').hasMatch(value?.trim() ?? '')
                    ? null
                    : tx(context, 'Enter 10–20 digits.'),
              ),
              const SizedBox(height: 8),
              _hint('Enter the receiver’s Kesor account number.'),
              const SizedBox(height: 8.75),
              _label('Amount'),
              const SizedBox(height: 8),
              _TransferInput(
                key: const ValueKey('transfer-amount-frame'),
                controller: amount,
                fieldKey: const ValueKey('transfer-amount'),
                semanticLabel:
                    '${tx(context, 'Amount')} (${account?.currency ?? 'USD'})',
                hint: account?.currency == 'KHR' ? '0' : '25.00',
                enabled: !model.busy,
                keyboard: TextInputType.numberWithOptions(
                  decimal: account?.currency != 'KHR',
                ),
                action: TextInputAction.next,
                leftPadding: 16,
                suffix: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: SizedBox(
                            width: 26,
                            height: 18,
                            child: account?.currency == 'KHR'
                                ? ColoredBox(
                                    color: colors.accent,
                                    child: Center(
                                      child: Text(
                                        '៛',
                                        style: _type(context, 12, 18),
                                      ),
                                    ),
                                  )
                                : Image.asset(
                                    'assets/transfer/flag-us.png',
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        account?.currency ?? 'USD',
                        style: _type(context, 14, 22),
                      ),
                    ],
                  ),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? tx(context, 'Enter an amount.')
                    : null,
              ),
              const SizedBox(height: 8),
              _hint('Transfer currency follows your selected wallet.'),
              const SizedBox(height: 8.75),
              _label('Remark'),
              const SizedBox(height: 8),
              _TransferInput(
                key: const ValueKey('transfer-remark-frame'),
                controller: remark,
                fieldKey: const ValueKey('transfer-remark'),
                semanticLabel: tx(context, 'Remark (optional)'),
                hint: tx(context, 'Add a note...'),
                enabled: !model.busy,
                keyboard: TextInputType.text,
                action: TextInputAction.done,
                leftPadding: 16,
                rightPadding: 16,
                validator: (value) => (value?.length ?? 0) > 255
                    ? tx(context, 'Remark must be 255 characters or fewer.')
                    : null,
              ),
              const SizedBox(height: 6.25),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppPalette.gold100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: Center(child: TransferAsset('save.svg')),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx(context, 'Save to Favorites'),
                            style: _type(
                              context,
                              16,
                              24,
                              weight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 1),
                          _hint('Quick access for future transfers'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      label: tx(context, 'Save to Favorites'),
                      toggled: saveFavorite,
                      enabled: !model.busy,
                      child: InkWell(
                        key: const ValueKey('transfer-favorite-toggle'),
                        onTap: model.busy
                            ? null
                            : () =>
                                  setState(() => saveFavorite = !saveFavorite),
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: saveFavorite
                                ? Container(
                                    width: 44,
                                    height: 26,
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: AppPalette.gold500,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  )
                                : const TransferAsset('toggle.svg'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String value) => Text(
    tx(context, value),
    style: _type(
      context,
      14,
      22,
      color: Theme.of(context).brightness == Brightness.dark
          ? AppPalette.navy100
          : AppPalette.navy500,
    ),
  );
  Widget _hint(String value) => Text(
    tx(context, value),
    style: _type(
      context,
      12,
      18,
      color: AppColors.of(context).foreground.withValues(alpha: .45),
    ),
  );
  Widget _fieldIcon(String asset, Size box) => Container(
    width: box.width,
    height: box.height,
    decoration: Theme.of(context).brightness == Brightness.dark
        ? BoxDecoration(
            color: AppPalette.gold100,
            borderRadius: BorderRadius.circular(4),
          )
        : null,
    child: Center(child: TransferAsset(asset)),
  );
  Widget _footer() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
    child: Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: double.infinity,
            minHeight: 54,
          ),
          child: FilledButton(
            key: const ValueKey('transfer-continue'),
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.gold500,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: _type(context, 14, 22, weight: FontWeight.w500),
            ),
            onPressed:
                !widget.enabled ||
                    !model.ready ||
                    model.busy ||
                    model.storageError != null ||
                    selected == null ||
                    selected!.status != 'ACTIVE' ||
                    widget.accounts.loadingDetail
                ? null
                : _continue,
            child: Text(tx(context, 'Continue to review')),
          ),
        ),
        const SizedBox(height: 8),
        _safeBottom(),
      ],
    ),
  );
  Widget _safeBottom() => SizedBox(
    height: widget.showDeviceChrome
        ? 20
        : math.max(20, MediaQuery.paddingOf(context).bottom),
    child: widget.showDeviceChrome
        ? Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 134,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.of(context).foreground.withValues(alpha: .2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          )
        : null,
  );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: AppColors.of(context).background,
      systemNavigationBarIconBrightness:
          Theme.of(context).brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    ),
    child: Scaffold(
      backgroundColor: AppPalette.navy500,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: KesorLayout.frameWidth),
          child: ListenableBuilder(
            listenable: changes,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final top = widget.showDeviceChrome
                    ? 54.0
                    : MediaQuery.paddingOf(context).top;
                final extra = math.max(
                  0.0,
                  constraints.maxHeight - top - 234 - 510 - 98,
                );
                final body = SingleChildScrollView(
                  key: const ValueKey('transfer-scroll'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.showDeviceChrome)
                        SizedBox(
                          height: 54,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 37, right: 30),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '9:41',
                                  style: _type(
                                    context,
                                    20,
                                    28,
                                    weight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const TransferAsset('device-status.svg'),
                              ],
                            ),
                          ),
                        )
                      else
                        SizedBox(height: top),
                      SizedBox(
                        height: 60,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: Row(
                            children: [
                              Semantics(
                                button: true,
                                label: tx(context, 'Back'),
                                child: InkWell(
                                  key: const ValueKey('transfer-back'),
                                  borderRadius: BorderRadius.circular(24),
                                  onTap: () {
                                    FocusScope.of(context).unfocus();
                                    widget.onBack();
                                  },
                                  child: const SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Center(
                                      child: TransferAsset('back.svg'),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  tx(context, 'Transfer'),
                                  textAlign: TextAlign.center,
                                  style: _type(
                                    context,
                                    20,
                                    28,
                                    weight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: Column(
                          children: [
                            Container(
                              key: const ValueKey('transfer-emblem'),
                              width: 72,
                              height: 72,
                              decoration: const BoxDecoration(
                                color: AppPalette.gold100,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: 7.875,
                                        top: 7.875,
                                        child: TransferAsset(
                                          'emblem-transfer.svg',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              tx(context, 'Kesor Transfer'),
                              style: _type(
                                context,
                                20,
                                28,
                                weight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tx(context, 'Fast, secure wallet transfers'),
                              style: _type(
                                context,
                                12,
                                18,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        key: const ValueKey('transfer-form-panel'),
                        decoration: BoxDecoration(
                          color: AppColors.of(context).background,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(32),
                          ),
                        ),
                        child: entry
                            ? Column(
                                children: [
                                  _fields(),
                                  SizedBox(height: extra),
                                  _footer(),
                                ],
                              )
                            : Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    TransferPanel(
                                      controller: model,
                                      accounts: widget.accounts,
                                      enabled: widget.enabled,
                                      onDone: () => setState(() {
                                        destination.clear();
                                        amount.clear();
                                        remark.clear();
                                        saveFavorite = false;
                                        favoriteError = null;
                                      }),
                                    ),
                                    if (model.saved?.outcome == 'success' &&
                                        !bookmarked.contains(model.saved!.key))
                                      TextButton.icon(
                                        onPressed: favoriteBusy
                                            ? null
                                            : () => _bookmark(model.saved!),
                                        icon: const Icon(
                                          Icons.bookmark_add_outlined,
                                        ),
                                        label: Text(
                                          tx(context, 'Save recipient'),
                                        ),
                                      ),
                                    if (favoriteError != null)
                                      NoticePanel(
                                        tx(context, favoriteError!),
                                        error: true,
                                      ),
                                    _safeBottom(),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                );
                return widget.showDeviceChrome
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(38),
                        child: body,
                      )
                    : body;
              },
            ),
          ),
        ),
      ),
    ),
  );
}

TextStyle _type(
  BuildContext context,
  double size,
  double height, {
  FontWeight weight = FontWeight.w400,
  Color? color,
}) => AppTextStyles.of(context).body.copyWith(
  fontSize: size,
  height: height / size,
  fontWeight: weight,
  color: color ?? AppColors.of(context).foreground,
  fontFamily: AppPreferences.maybeOf(context)?.isKhmer == true
      ? AppTypography.khmerFamily
      : AppTypography.englishFamily,
);

/// Intrinsic export bounds are retained, including the exact shared album icon.
class TransferAsset extends StatelessWidget {
  const TransferAsset(this.name, {super.key});
  final String name;
  static const sizes = <String, Size>{
    'back.svg': Size(44, 44),
    'card.svg': Size(20.4475, 15.7542),
    'chevron-down.svg': Size(12, 12),
    'contact.svg': Size(22, 22),
    'device-status.svg': Size(75.67, 13),
    'emblem-transfer.svg': Size(20.25, 23.25),
    'favorites.svg': Size(24, 24),
    'save.svg': Size(20, 19.9992),
    'toggle.svg': Size(44, 26),
  };
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.fromSize(
      size: sizes[name]!,
      child: SvgPicture.asset(
        name == 'favorites.svg'
            ? 'assets/home/recipients.svg'
            : 'assets/transfer/$name',
      ),
    ),
  );
}

class _TransferInput extends StatefulWidget {
  const _TransferInput({
    required this.controller,
    required this.fieldKey,
    required this.semanticLabel,
    required this.hint,
    required this.enabled,
    required this.keyboard,
    required this.action,
    this.prefix,
    this.suffix,
    this.leftPadding = 0,
    this.rightPadding = 0,
    this.validator,
    super.key,
  });
  final TextEditingController controller;
  final Key fieldKey;
  final String semanticLabel, hint;
  final bool enabled;
  final TextInputType keyboard;
  final TextInputAction action;
  final Widget? prefix, suffix;
  final double leftPadding, rightPadding;
  final String? Function(String?)? validator;
  @override
  State<_TransferInput> createState() => _TransferInputState();
}

class _TransferInputState extends State<_TransferInput> {
  final focus = FocusNode();
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: focus,
    builder: (context, _) {
      final colors = AppColors.of(context);
      return Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: focus.hasFocus ? AppPalette.gold500 : colors.border,
          ),
        ),
        child: Row(
          children: [
            if (widget.prefix != null)
              widget.prefix!
            else
              SizedBox(width: widget.leftPadding),
            Expanded(
              child: Semantics(
                label: widget.semanticLabel,
                textField: true,
                child: TextFormField(
                  key: widget.fieldKey,
                  controller: widget.controller,
                  focusNode: focus,
                  style: _type(context, 15, 24),
                  keyboardType: widget.keyboard,
                  textInputAction: widget.action,
                  enabled: widget.enabled,
                  validator: widget.validator,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    hintText: widget.hint,
                    hintStyle: _type(
                      context,
                      15,
                      24,
                      color: colors.disabledBackground,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            if (widget.suffix != null)
              widget.suffix!
            else
              SizedBox(width: widget.rightPadding),
          ],
        ),
      );
    },
  );
}

class _TransferPrivateSheet extends StatefulWidget {
  const _TransferPrivateSheet({required this.session, required this.child});
  final SessionController session;
  final Widget child;
  @override
  State<_TransferPrivateSheet> createState() => _TransferPrivateSheetState();
}

class _TransferPrivateSheetState extends State<_TransferPrivateSheet> {
  late final int? owner;
  late final String? sessionId;
  bool closing = false;
  bool get allowed =>
      widget.session.phase == SessionPhase.signedIn &&
      !widget.session.privacyCovered &&
      widget.session.identity?.userId == owner &&
      widget.session.identity?.sessionId == sessionId;
  @override
  void initState() {
    super.initState();
    owner = widget.session.identity?.userId;
    sessionId = widget.session.identity?.sessionId;
    widget.session.addListener(_changed);
  }

  void _changed() {
    if (allowed || closing) return;
    closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) => allowed ? widget.child : const SizedBox.shrink(),
  );
}
