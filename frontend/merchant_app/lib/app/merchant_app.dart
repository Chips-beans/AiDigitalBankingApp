import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import 'package:kesor_auth_handoff/kesor_auth_handoff.dart'
    show HandoffStore, MemoryHandoffStore;

import '../core/merchant_preferences.dart';
import '../core/merchant_strings.dart';
import '../features/auth/merchant_session.dart';
import '../features/collect/collect_controller.dart';
import '../features/collect/collect_view.dart';
import '../features/collect/wallet_page.dart';
import '../features/sales/sales_controller.dart';
import '../features/sales/sales_view.dart';
import '../features/sales/receipt_page.dart';
import '../features/shop/merchant_shop.dart';
import '../features/shop/register_shop_page.dart';
import '../features/shop/shop_controller.dart';
import '../features/shop/shop_form.dart';
import '../features/shop/shop_home.dart';
import '../features/shop/shop_profile_page.dart';
import '../features/shop/shop_widgets.dart';

export '../core/merchant_strings.dart' show MerchantStrings;

class MerchantApp extends StatefulWidget {
  const MerchantApp({
    required this.preferences,
    required this.session,
    this.shopGateway,
    this.shopStore,
    this.pickLogo = pickLogoFile,
    super.key,
  });
  final MerchantPreferences preferences;
  final MerchantSession session;

  /// Null keeps shop registration fail-closed (unavailable).
  final MerchantShopGateway? shopGateway;
  final HandoffStore? shopStore;
  final LogoPicker pickLogo;
  @override
  State<MerchantApp> createState() => _MerchantAppState();
}

class _MerchantAppState extends State<MerchantApp> with WidgetsBindingObserver {
  bool covered = false;
  Timer? validation;
  ShopController? shop;
  CollectController? collect;
  SalesController? sales;
  final navigator = GlobalKey<NavigatorState>();
  MerchantPhase? _phase;
  late final HandoffStore _shopStore = widget.shopStore ?? MemoryHandoffStore();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_syncShop);
    _syncShop();
    validation = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!covered) unawaited(widget.session.validate());
    });
  }

  /// One shop controller per signed-in owner; dropped on sign-out.
  void _syncShop() {
    final session = widget.session;
    final identity = session.identity;
    // Pages pushed over the shop (profile editing) never outlive its session.
    if (session.phase != _phase) {
      _phase = session.phase;
      navigator.currentState?.popUntil((route) => route.isFirst);
    }
    final wanted =
        widget.shopGateway != null &&
        identity != null &&
        const {
          MerchantPhase.shopRequired,
          MerchantPhase.ready,
          MerchantPhase.restricted,
        }.contains(session.phase);
    if (wanted) {
      if (shop?.ownerId == identity.ownerId) return;
      shop?.dispose();
      collect?.dispose();
      sales?.dispose();
      final owned = ShopController(
        widget.shopGateway!,
        _shopStore,
        ownerId: identity.ownerId,
        onExpired: session.expire,
      );
      shop = owned;
      // A confirmed payment refreshes balances and today's totals.
      collect = CollectController(
        widget.shopGateway!,
        _shopStore,
        ownerId: identity.ownerId,
        onPaid: () => unawaited(owned.refresh()),
        onExpired: session.expire,
      );
      sales = SalesController(widget.shopGateway!, onExpired: session.expire);
      unawaited(owned.initialize());
      unawaited(collect!.resume());
    } else if (session.phase == MerchantPhase.signedOut && shop != null) {
      shop!.dispose();
      collect?.dispose();
      shop = null;
      collect = null;
      sales?.dispose();
      sales = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_syncShop);
    validation?.cancel();
    shop?.dispose();
    collect?.dispose();
    sales?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => covered = state != AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.session.validate());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.preferences, widget.session]),
    builder: (context, _) {
      final prefs = widget.preferences;
      return MaterialApp(
        title: 'Kesor Merchant',
        debugShowCheckedModeBanner: false,
        locale: prefs.locale,
        supportedLocales: const [Locale('en'), Locale('km')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.build(Brightness.light, locale: prefs.locale),
        darkTheme: AppTheme.build(Brightness.dark, locale: prefs.locale),
        themeMode: prefs.themeMode,
        // The privacy cover overlays the screen instead of replacing it, so an
        // in-progress form survives the system logo picker.
        // Strings sit above the Navigator so pushed pages are localized too.
        navigatorKey: navigator,
        builder: (context, child) => MerchantStrings(
          khmer: prefs.isKhmer,
          child: Stack(
            children: [
              // Offstage keeps state (form text, picked logo) without painting it.
              if (child != null) Offstage(offstage: covered, child: child),
              if (covered)
                const Positioned.fill(
                  child: Scaffold(body: Center(child: _Brand())),
                ),
            ],
          ),
        ),
        home: Builder(
          builder: (context) => switch (widget.session.phase) {
            MerchantPhase.signedOut => _Welcome(
              prefs: prefs,
              session: widget.session,
            ),
            MerchantPhase.approving => _ApprovalWaiting(
              session: widget.session,
            ),
            MerchantPhase.shopRequired => RegisterShopPage(
              key: ValueKey('register-${widget.session.identity?.ownerId}'),
              controller: shop,
              pickLogo: widget.pickLogo,
              onRegistered: widget.session.validate,
              onSignOut: widget.session.signOut,
            ),
            MerchantPhase.recoveryRequired => Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Kesor Merchant')),
                body: _Page(
                  children: [
                    Text(
                      _t(
                        context,
                        'Your shop needs support review. Contact Kesor Bank.',
                        'សូមទាក់ទងធនាគារកេសរ ដើម្បីពិនិត្យហាងរបស់អ្នក។',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: widget.session.signOut,
                      child: Text(_t(context, 'Sign out', 'ចាកចេញ')),
                    ),
                  ],
                ),
              ),
            ),
            MerchantPhase.ready || MerchantPhase.restricted => _ShopShell(
              key: ValueKey(widget.session.identity!.shop!.id),
              preferences: prefs,
              session: widget.session,
              shop: shop,
              collect: collect,
              sales: sales,
              gateway: widget.shopGateway,
              pickLogo: widget.pickLogo,
            ),
          },
        ),
      );
    },
  );
}

String _t(BuildContext c, String en, String km) => t(c, en, km);

String _authMessage(
  BuildContext context,
  MerchantAuthIssue issue,
) => switch (issue) {
  MerchantAuthIssue.uncertain => _t(
    context,
    'The sign-in result is uncertain. Recover the saved result within 60 seconds, or cancel.',
    'លទ្ធផលចូលប្រើមិនច្បាស់។ សូមយកលទ្ធផលដែលបានរក្សាទុកក្នុង ៦០ វិនាទី ឬបោះបង់។',
  ),
  MerchantAuthIssue.rateLimited => _t(
    context,
    'Too many requests. Please wait one minute.',
    'មានសំណើច្រើនពេក។ សូមរង់ចាំមួយនាទី។',
  ),
  MerchantAuthIssue.offline => _t(
    context,
    'You’re offline. Connect to the internet and try again.',
    'អ្នកគ្មានអ៊ីនធឺណិត។ សូមភ្ជាប់អ៊ីនធឺណិត ហើយព្យាយាមម្ដងទៀត។',
  ),
  MerchantAuthIssue.expired => _t(
    context,
    'Your session has ended. Continue with Kesor Bank again.',
    'វគ្គប្រើប្រាស់របស់អ្នកបានបញ្ចប់។ សូមបន្តជាមួយធនាគារកេសរម្ដងទៀត។',
  ),
  MerchantAuthIssue.denied => _t(
    context,
    'Sign-in was declined. You can start a new request.',
    'ការចូលប្រើត្រូវបានបដិសេធ។ អ្នកអាចចាប់ផ្ដើមសំណើថ្មី។',
  ),
  MerchantAuthIssue.customerMissing => _t(
    context,
    'Install Kesor Bank and sign in there to continue.',
    'សូមដំឡើងធនាគារកេសរ ហើយចូលប្រើនៅទីនោះដើម្បីបន្ត។',
  ),
  MerchantAuthIssue.unavailable => _t(
    context,
    'Sign-in is temporarily unavailable. Please try again.',
    'ការចូលប្រើមិនអាចប្រើបានបណ្ដោះអាសន្ន។ សូមព្យាយាមម្ដងទៀត។',
  ),
};

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppPalette.gold50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SvgPicture.asset(
          'assets/kesor-logo.svg',
          package: 'kesor_design_system',
          width: 32,
          height: 40,
          semanticsLabel: 'Kesor Bank',
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text('Kesor Merchant', style: AppTextStyles.of(context).titleM),
      ),
    ],
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.prefs, required this.session});
  final MerchantPreferences prefs;
  final MerchantSession session;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTextStyles.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: LayoutBuilder(
              builder: (context, bounds) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: bounds.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: _Brand()),
                            IconButton(
                              tooltip: _t(
                                context,
                                'Change language',
                                'ប្ដូរភាសា',
                              ),
                              onPressed: () => prefs.setLanguage(
                                prefs.isKhmer ? 'en' : 'km',
                              ),
                              icon: const Icon(Icons.translate),
                            ),
                            IconButton(
                              tooltip: _t(
                                context,
                                'Change appearance',
                                'ប្ដូររូបរាង',
                              ),
                              onPressed: () => prefs.setTheme(
                                Theme.of(context).brightness == Brightness.dark
                                    ? ThemeMode.light
                                    : ThemeMode.dark,
                              ),
                              icon: const Icon(Icons.contrast),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: colors.primary50,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const Icon(
                                  Icons.storefront_outlined,
                                  color: AppPalette.navy500,
                                  size: 40,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                _t(
                                  context,
                                  'Your shop.\nYour payments.',
                                  'ហាងរបស់អ្នក។\nការទូទាត់របស់អ្នក។',
                                ),
                                style: type.titleXL.copyWith(
                                  fontSize: 32,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _t(
                                  context,
                                  'Collect payments and keep your business moving with Kesor Bank.',
                                  'ទទួលការទូទាត់ និងគ្រប់គ្រងអាជីវកម្មរបស់អ្នកជាមួយធនាគារកេសរ។',
                                ),
                                style: type.bodyL,
                              ),
                              const SizedBox(height: 32),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _Feature(
                                    label: _t(
                                      context,
                                      'USD & KHR',
                                      'ដុល្លារ និងរៀល',
                                    ),
                                    icon: Icons.account_balance_wallet_outlined,
                                  ),
                                  _Feature(
                                    label: _t(
                                      context,
                                      'QR payments',
                                      'ការទូទាត់តាម QR',
                                    ),
                                    icon: Icons.qr_code_2,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (session.failure != null) ...[
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _authMessage(context, session.failure!),
                                  key: const ValueKey(
                                    'merchant-auth-unavailable',
                                  ),
                                  style: type.body,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (session.busy) ...[
                              const LinearProgressIndicator(),
                              const SizedBox(height: 12),
                              Text(
                                _t(
                                  context,
                                  'Finishing your previous request…',
                                  'កំពុងបញ្ចប់សំណើមុនរបស់អ្នក…',
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (session.failure ==
                                MerchantAuthIssue.uncertain) ...[
                              FilledButton(
                                onPressed: session.recover,
                                child: Text(
                                  _t(
                                    context,
                                    'Recover sign-in result',
                                    'យកលទ្ធផលចូលប្រើវិញ',
                                  ),
                                ),
                              ),
                              OutlinedButton(
                                onPressed: session.cancel,
                                child: Text(
                                  _t(context, 'Cancel request', 'បោះបង់សំណើ'),
                                ),
                              ),
                            ] else
                              FilledButton.icon(
                                key: const ValueKey('continue-with-kesor'),
                                onPressed: session.busy ? null : session.signIn,
                                icon: const Icon(Icons.open_in_new),
                                label: Text(
                                  _t(
                                    context,
                                    'Continue with Kesor Bank',
                                    'បន្តជាមួយធនាគារកេសរ',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            const SizedBox(height: 16),
                            Text(
                              _t(
                                context,
                                'Approve securely in your Kesor Bank app. Your shop uses the same owner account.',
                                'អនុម័តដោយសុវត្ថិភាពក្នុងកម្មវិធីធនាគារកេសរ។ ហាងរបស់អ្នកប្រើគណនីម្ចាស់ដដែល។',
                              ),
                              textAlign: TextAlign.center,
                              style: type.body,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.label, required this.icon});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.of(context).surface,
      border: Border.all(color: AppColors.of(context).border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Flexible(child: Text(label, style: AppTextStyles.of(context).body)),
      ],
    ),
  );
}

class _ApprovalWaiting extends StatelessWidget {
  const _ApprovalWaiting({required this.session});
  final MerchantSession session;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) session.cancel();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(_t(context, 'Approve sign-in', 'អនុម័តការចូលប្រើ')),
      ),
      body: _Page(
        children: [
          const Icon(Icons.phonelink_lock_outlined, size: 64),
          const SizedBox(height: 24),
          Text(
            _t(context, 'Continue in Kesor Bank', 'បន្តក្នុងធនាគារកេសរ'),
            style: AppTextStyles.of(context).titleXL,
          ),
          const SizedBox(height: 16),
          Text(
            _t(
              context,
              'Confirm this request in your Customer App, then return here.',
              'បញ្ជាក់សំណើនេះក្នុងកម្មវិធីអតិថិជន រួចត្រឡប់មកទីនេះវិញ។',
            ),
          ),
          const SizedBox(height: 32),
          const LinearProgressIndicator(),
          const SizedBox(height: 24),
          TextButton(
            onPressed: session.reopen,
            child: Text(_t(context, 'Open Kesor Bank', 'បើកធនាគារកេសរ')),
          ),
          OutlinedButton(
            onPressed: session.cancel,
            child: Text(_t(context, 'Cancel', 'បោះបង់')),
          ),
        ],
      ),
    ),
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(padding: const EdgeInsets.all(24), children: children),
      ),
    ),
  );
}

class _ShopShell extends StatefulWidget {
  const _ShopShell({
    required this.preferences,
    required this.session,
    required this.shop,
    required this.pickLogo,
    this.collect,
    this.sales,
    this.gateway,
    super.key,
  });
  final MerchantPreferences preferences;
  final MerchantSession session;
  final ShopController? shop;
  final CollectController? collect;
  final SalesController? sales;
  final MerchantShopGateway? gateway;
  final LogoPicker pickLogo;
  @override
  State<_ShopShell> createState() => _ShopShellState();
}

class _ShopShellState extends State<_ShopShell> {
  int tab = 0;

  void _openProfile() {
    final controller = widget.shop;
    if (controller?.shop == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ShopProfilePage(controller: controller!, pickLogo: widget.pickLogo),
      ),
    );
  }

  void _openWallet(ShopWallet wallet) {
    final gateway = widget.gateway;
    if (gateway == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WalletDetailPage(
          gateway: gateway,
          wallet: wallet,
          onExpired: widget.session.expire,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identityShop = widget.session.identity!.shop!;
    final controller = widget.shop;
    final colors = AppColors.of(context);
    final titles = [
      _t(context, 'Home', 'ទំព័រដើម'),
      _t(context, 'Collect', 'ទទួលប្រាក់'),
      _t(context, 'Sales', 'ការលក់'),
      _t(context, 'More', 'បន្ថែម'),
    ];
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => tab = 0);
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: tab == 2 && widget.sales != null
                  ? SalesView(
                      controller: widget.sales!,
                      onRequest: (id) async {
                        await widget.collect?.openRequest(id);
                        if (mounted) setState(() => tab = 1);
                      },
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        await controller?.refresh();
                        await widget.session.validate();
                      },
                      child: ListView(
                        key: PageStorageKey('shop-tab-$tab'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        children: [
                          Text(
                            titles[tab],
                            style: mText(
                              context,
                              20,
                              28,
                              weight: FontWeight.w600,
                            ),
                          ),
                          if (tab == 0 && controller != null)
                            ListenableBuilder(
                              listenable: controller,
                              builder: (context, _) {
                                final owner =
                                    controller.profile?.ownerName ?? '';
                                if (owner.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  _t(context, 'Hello, $owner', 'សួស្ដី $owner'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: mText(
                                    context,
                                    13,
                                    20,
                                    color: colors.disabledBackground,
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 16),
                          if (tab == 0)
                            if (controller != null)
                              ShopHomeView(
                                controller: controller,
                                fallbackName: identityShop.name,
                                onCollect: identityShop.active
                                    ? () => setState(() => tab = 1)
                                    : null,
                                onSales: () => setState(() => tab = 2),
                                onEditShop: _openProfile,
                                onOpenWallet: widget.gateway == null
                                    ? null
                                    : _openWallet,
                                onSeeSales: () => setState(() => tab = 2),
                                onReceipt: widget.gateway == null
                                    ? null
                                    : (r) => openReceipt(
                                        context,
                                        widget.gateway!,
                                        r.reference,
                                        onExpired: widget.session.expire,
                                      ),
                              )
                            else
                              _Unavailable(
                                title: identityShop.name,
                                message: _t(
                                  context,
                                  'Shop details are currently unavailable.',
                                  'ព័ត៌មានហាងមិនអាចប្រើបានបណ្ដោះអាសន្ន។',
                                ),
                              )
                          else if (tab == 1 &&
                              widget.collect != null &&
                              widget.gateway != null)
                            CollectView(
                              controller: widget.collect!,
                              gateway: widget.gateway!,
                              storeName:
                                  controller?.shop?.storeName ??
                                  identityShop.name,
                              active: identityShop.active,
                            )
                          else if (tab == 1)
                            _Unavailable(
                              title: _t(
                                context,
                                'Collection unavailable',
                                'មិនអាចទទួលប្រាក់បាន',
                              ),
                              message: _t(
                                context,
                                'No payment request has been created. Your business wallets are ready to receive payments once collection is enabled.',
                                'មិនមានសំណើទូទាត់ត្រូវបានបង្កើតទេ។ កាបូបអាជីវកម្មរបស់អ្នករួចរាល់សម្រាប់ទទួលការទូទាត់ពេលការទទួលប្រាក់ត្រូវបានបើក។',
                              ),
                            )
                          else if (tab == 2)
                            _Unavailable(
                              title: _t(
                                context,
                                'Sales unavailable',
                                'ការលក់មិនអាចប្រើបាន',
                              ),
                              message: _t(
                                context,
                                'Your payment history could not be loaded.',
                                'មិនអាចទាញយកប្រវត្តិការទូទាត់របស់អ្នកបានទេ។',
                              ),
                            )
                          else ...[
                            if (controller != null) ...[
                              ShopProfileCard(
                                controller: controller,
                                fallbackName: identityShop.name,
                                onEdit: _openProfile,
                              ),
                              const SizedBox(height: 24),
                            ],
                            SectionTitle(
                              _t(context, 'Preferences', 'ចំណូលចិត្ត'),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              key: ValueKey(
                                widget.preferences.locale.languageCode,
                              ),
                              initialValue:
                                  widget.preferences.locale.languageCode,
                              decoration: InputDecoration(
                                labelText: _t(context, 'Language', 'ភាសា'),
                                prefixIcon: const Icon(Icons.translate_rounded),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'en',
                                  child: Text('English'),
                                ),
                                DropdownMenuItem(
                                  value: 'km',
                                  child: Text('ខ្មែរ'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  widget.preferences.setLanguage(v);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<ThemeMode>(
                              key: ValueKey(widget.preferences.themeMode),
                              initialValue: widget.preferences.themeMode,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: _t(context, 'Appearance', 'រូបរាង'),
                                prefixIcon: const Icon(Icons.contrast_rounded),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: ThemeMode.system,
                                  child: Text(
                                    _t(context, 'System', 'ប្រព័ន្ធ'),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: ThemeMode.light,
                                  child: Text(_t(context, 'Light', 'ភ្លឺ')),
                                ),
                                DropdownMenuItem(
                                  value: ThemeMode.dark,
                                  child: Text(_t(context, 'Dark', 'ងងឹត')),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) widget.preferences.setTheme(v);
                              },
                            ),
                            const SizedBox(height: 24),
                            SectionTitle(_t(context, 'Help', 'ជំនួយ')),
                            const SizedBox(height: 8),
                            Material(
                              color: colors.surface,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(color: colors.border),
                              ),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.support_agent_outlined,
                                ),
                                title: Text(_t(context, 'Support', 'ជំនួយ')),
                                subtitle: const Text('reachsteav2@gmail.com'),
                                trailing: const Icon(
                                  Icons.copy_rounded,
                                  size: 20,
                                ),
                                onTap: () async {
                                  await Clipboard.setData(
                                    const ClipboardData(
                                      text: 'reachsteav2@gmail.com',
                                    ),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _t(
                                            context,
                                            'Support address copied',
                                            'បានចម្លងអាសយដ្ឋានជំនួយ',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 24),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(48, 52),
                                foregroundColor: colors.error,
                                side: BorderSide(color: colors.border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: widget.session.signOut,
                              icon: const Icon(Icons.logout),
                              label: Text(_t(context, 'Sign out', 'ចាកចេញ')),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: tab,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (v) => setState(() => tab = v),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_rounded),
                label: titles[0],
              ),
              NavigationDestination(
                icon: const Icon(Icons.qr_code_2),
                label: titles[1],
              ),
              NavigationDestination(
                icon: const Icon(Icons.receipt_long_outlined),
                selectedIcon: const Icon(Icons.receipt_long_rounded),
                label: titles[2],
              ),
              NavigationDestination(
                icon: const Icon(Icons.more_horiz),
                label: titles[3],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.title, required this.message});
  final String title, message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.of(context).surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.of(context).border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.of(context).titleM),
        const SizedBox(height: 8),
        Text(message),
      ],
    ),
  );
}
