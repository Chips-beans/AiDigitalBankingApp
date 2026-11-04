import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import 'package:kesor_auth_handoff/kesor_auth_handoff.dart'
    show HandoffStore, MemoryHandoffStore, NativeHandoff;

import '../core/merchant_preferences.dart';
import '../core/merchant_strings.dart';
import '../core/merchant_ui.dart';
import '../features/settings/merchant_settings.dart';
import '../features/sales/reports_page.dart';
import '../features/sales/requests_page.dart';
import '../features/auth/merchant_session.dart';
import '../features/collect/collect_controller.dart';
import '../features/collect/collect_view.dart';
import '../features/collect/wallet_page.dart';
import '../features/feed/payment_banner.dart';
import '../features/feed/payment_feed_controller.dart';
import '../features/sales/sales_controller.dart';
import '../features/sales/sales_view.dart';
import '../features/sales/receipt_page.dart';
import '../features/shop/merchant_shop.dart';
import '../features/shop/register_shop_page.dart';
import '../features/shop/shop_controller.dart';
import '../features/shop/shop_form.dart';
import '../features/shop/shop_home.dart';
import '../features/shop/shop_profile_page.dart';
import '../features/transfer/owner_transfer_controller.dart';

export '../core/merchant_strings.dart' show MerchantStrings;

class MerchantApp extends StatefulWidget {
  const MerchantApp({
    required this.preferences,
    required this.session,
    this.shopGateway,
    this.shopStore,
    this.pickLogo = pickLogoFile,
    this.alertEffects = const SystemAlertEffects(),
    this.transferNative = const NativeHandoff(),
    super.key,
  });
  final MerchantPreferences preferences;
  final MerchantSession session;

  /// Null keeps shop registration fail-closed (unavailable).
  final MerchantShopGateway? shopGateway;
  final HandoffStore? shopStore;
  final LogoPicker pickLogo;

  /// Sound and vibration for new payments; tests replace it with a silent one.
  final AlertEffects alertEffects;

  /// Return links and opening Kesor Bank for owner transfers; replaced in tests.
  final NativeHandoff transferNative;
  @override
  State<MerchantApp> createState() => _MerchantAppState();
}

class _MerchantAppState extends State<MerchantApp> with WidgetsBindingObserver {
  bool covered = false;
  Timer? validation;
  ShopController? shop;
  CollectController? collect;
  SalesController? sales;
  PaymentFeedController? feed;
  OwnerTransferController? transfer;
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
      if (shop?.ownerId == identity.ownerId) {
        _updateFeed();
        return;
      }
      shop?.dispose();
      collect?.dispose();
      sales?.dispose();
      feed?.dispose();
      transfer?.dispose();
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
        // A payment the Collect screen already confirmed must not alert again.
        onReceipt: (receipt) => feed?.markSeen(receipt.reference),
        onExpired: session.expire,
      );
      sales = SalesController(widget.shopGateway!, onExpired: session.expire);
      feed = PaymentFeedController(
        widget.shopGateway!,
        effects: widget.alertEffects,
        soundEnabled: () => widget.preferences.alertSound,
        vibrationEnabled: () => widget.preferences.alertVibration,
        // New QR payments (including the reusable shop QR) refresh balances.
        onNewPayments: (_) => unawaited(owned.refresh()),
        onExpired: session.expire,
      );
      transfer = OwnerTransferController(
        widget.shopGateway!,
        _shopStore,
        ownerId: identity.ownerId,
        native: widget.transferNative,
        // Approved in Kesor Bank: balances and activity change.
        onCompleted: () => unawaited(owned.refresh()),
        onExpired: session.expire,
      );
      unawaited(owned.initialize());
      unawaited(collect!.resume());
      unawaited(transfer!.resume());
      _updateFeed();
    } else if (session.phase == MerchantPhase.signedOut && shop != null) {
      shop!.dispose();
      collect?.dispose();
      shop = null;
      collect = null;
      sales?.dispose();
      sales = null;
      feed?.dispose();
      feed = null;
      transfer?.dispose();
      transfer = null;
    } else {
      feed?.running = false;
    }
  }

  /// The feed runs only while the app is in front and the shop can collect.
  void _updateFeed() {
    feed?.running = !covered && widget.session.phase == MerchantPhase.ready;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_syncShop);
    validation?.cancel();
    shop?.dispose();
    collect?.dispose();
    sales?.dispose();
    feed?.dispose();
    transfer?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => covered = state != AppLifecycleState.resumed);
    _updateFeed();
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
        theme: merchantTheme(Brightness.light, prefs.locale),
        darkTheme: merchantTheme(Brightness.dark, prefs.locale),
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
            MerchantPhase.recoveryRequired => _AccountReview(
              session: widget.session,
            ),
            MerchantPhase.ready || MerchantPhase.restricted => _ShopShell(
              key: ValueKey(widget.session.identity!.shop!.id),
              preferences: prefs,
              session: widget.session,
              shop: shop,
              collect: collect,
              sales: sales,
              feed: feed,
              transfer: transfer,
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
    'The request was declined in Kesor Bank. Nothing changed in your shop.',
    'សំណើត្រូវបានបដិសេធក្នុងធនាគារកេសរ។ គ្មានអ្វីផ្លាស់ប្ដូរក្នុងហាងរបស់អ្នកទេ។',
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
    if (session.failure != null) return _SignInFailure(session: session);
    Widget feature(String asset, String en, String km) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          QIcon(asset),
          const SizedBox(width: 14),
          Expanded(
            child: Text(t(context, en, km), style: mText(context, 15, 24)),
          ),
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 72, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: QIcon('3633f', darkAdaptive: false),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            t(
                              context,
                              'Your shop,\nready for business.',
                              'ហាងរបស់អ្នក\nត្រៀមសម្រាប់អាជីវកម្ម។',
                            ),
                            style: mText(
                              context,
                              32,
                              43,
                              weight: FontWeight.w300,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            t(
                              context,
                              'Collect payments in riel and dollars, see every sale, and move money to your own wallet.',
                              'ទទួលការទូទាត់ជាប្រាក់រៀល និងដុល្លារ តាមដានការលក់ ហើយផ្ទេរទៅកាបូបផ្ទាល់ខ្លួន។',
                            ),
                            style: mText(
                              context,
                              15,
                              24,
                              color: colors.disabledBackground,
                            ),
                          ),
                          const SizedBox(height: 32),
                          const Spacer(),
                          feature(
                            'a83fb',
                            'QR payments in KHR and USD',
                            'ការទូទាត់ QR ជាប្រាក់រៀល និងដុល្លារ',
                          ),
                          feature(
                            '156fc',
                            'A receipt for every sale',
                            'បង្កាន់ដៃសម្រាប់ការលក់នីមួយៗ',
                          ),
                          feature(
                            'd8c8d',
                            'Transfers to your own wallet',
                            'ផ្ទេរទៅកាបូបផ្ទាល់ខ្លួន',
                          ),
                          const Spacer(),
                          const SizedBox(height: 32),
                          if (session.busy) ...[
                            const LinearProgressIndicator(),
                            Text(
                              t(
                                context,
                                'Finishing your previous request…',
                                'កំពុងបញ្ចប់សំណើមុនរបស់អ្នក…',
                              ),
                            ),
                          ],
                          FilledButton(
                            key: const ValueKey('continue-with-kesor'),
                            onPressed: session.busy ? null : session.signIn,
                            child: Text(
                              t(
                                context,
                                'Continue with Kesor Bank',
                                'បន្តជាមួយធនាគារកេសរ',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t(
                              context,
                              'You approve in Kesor Bank. No new password or PIN.',
                              'អ្នកអនុម័តក្នុងធនាគារកេសរ។ មិនត្រូវការពាក្យសម្ងាត់ ឬ PIN ថ្មីទេ។',
                            ),
                            textAlign: TextAlign.center,
                            style: mText(
                              context,
                              13,
                              18,
                              color: colors.disabledBackground,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 18),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => prefs.setLanguage(
                                  prefs.isKhmer ? 'en' : 'km',
                                ),
                                child: Text(
                                  prefs.isKhmer ? 'ខ្មែរ' : 'English',
                                ),
                              ),
                              Text(
                                '·',
                                style: mText(
                                  context,
                                  13,
                                  18,
                                  color: merchantNavy(context),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 18),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => MerchantAppearancePage(
                                      preferences: prefs,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  themeLabel(context, prefs.themeMode),
                                ),
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
      ),
    );
  }
}

class _SignInFailure extends StatelessWidget {
  const _SignInFailure({required this.session});
  final MerchantSession session;
  @override
  Widget build(BuildContext context) {
    final issue = session.failure!;
    return QPage(
      title: t(context, 'Sign in', 'ចូលប្រើ'),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            key: const ValueKey('continue-with-kesor'),
            onPressed: session.busy
                ? null
                : issue == MerchantAuthIssue.uncertain
                ? session.recover
                : session.signIn,
            child: Text(
              issue == MerchantAuthIssue.uncertain
                  ? t(context, 'Recover sign-in result', 'យកលទ្ធផលចូលប្រើវិញ')
                  : t(context, 'Try again', 'ព្យាយាមម្ដងទៀត'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: session.cancel,
            child: Text(t(context, 'Back to welcome', 'ត្រឡប់ទៅទំព័រស្វាគមន៍')),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 96),
        child: Column(
          children: [
            const QStatusIcon('00600', tone: 'error'),
            const SizedBox(height: 12),
            Text(
              issue == MerchantAuthIssue.denied
                  ? t(
                      context,
                      'Sign-in not approved',
                      'ការចូលប្រើមិនត្រូវបានអនុម័ត',
                    )
                  : t(context, 'Unable to sign in', 'មិនអាចចូលប្រើបាន'),
              textAlign: TextAlign.center,
              style: mText(context, 20, 27, weight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Text(
              _authMessage(context, issue),
              key: const ValueKey('merchant-auth-unavailable'),
              textAlign: TextAlign.center,
              style: mText(
                context,
                15,
                24,
                color: AppColors.of(context).disabledBackground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalWaiting extends StatefulWidget {
  const _ApprovalWaiting({required this.session});
  final MerchantSession session;
  @override
  State<_ApprovalWaiting> createState() => _ApprovalWaitingState();
}

class _ApprovalWaitingState extends State<_ApprovalWaiting> {
  Timer? tick;
  MerchantSession get session => widget.session;
  @override
  void initState() {
    super.initState();
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) session.cancel();
    },
    child: QPage(
      title: t(context, 'Sign in', 'ចូលប្រើ'),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: session.reopen,
            child: Text(t(context, 'Open Kesor Bank', 'បើកធនាគារកេសរ')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: session.cancel,
            child: Text(t(context, 'Cancel', 'បោះបង់')),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const QStatusIcon('c0d59'),
            const SizedBox(height: 16),
            Text(
              t(context, 'Continue in Kesor Bank', 'បន្តក្នុងធនាគារកេសរ'),
              textAlign: TextAlign.center,
              style: mText(context, 20, 27, weight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            Text(
              t(
                context,
                'Approve this sign-in with your Kesor Bank PIN, then come back here.',
                'អនុម័តការចូលប្រើដោយ PIN ធនាគារកេសរ រួចត្រឡប់មកទីនេះ។',
              ),
              textAlign: TextAlign.center,
              style: mText(
                context,
                15,
                24,
                color: AppColors.of(context).disabledBackground,
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              minHeight: 4,
              value: session.approvalRemaining == null
                  ? null
                  : (session.approvalRemaining!.inSeconds / 120).clamp(0, 1),
              color: merchantNavy(context),
              backgroundColor: AppColors.of(context).surface,
            ),
            if (session.approvalRemaining != null) ...[
              const SizedBox(height: 8),
              Text(
                '${t(context, 'Expires in', 'ផុតកំណត់ក្នុង')} ${session.approvalRemaining!.inMinutes}:${(session.approvalRemaining!.inSeconds % 60).toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: mText(
                  context,
                  13,
                  18,
                  color: AppColors.of(context).disabledBackground,
                ),
              ),
            ],
            if (session.failure != null) ...[
              const SizedBox(height: 12),
              Text(_authMessage(context, session.failure!)),
            ],
            const SizedBox(height: 40),
            for (final step in [
              t(
                context,
                'Kesor Bank opens on this phone',
                'ធនាគារកេសរបើកលើទូរស័ព្ទនេះ',
              ),
              t(
                context,
                'Check the shop app and device',
                'ពិនិត្យកម្មវិធីហាង និងឧបករណ៍',
              ),
              t(context, 'Approve with your PIN', 'អនុម័តដោយ PIN របស់អ្នក'),
            ].asMap().entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${step.key + 1}',
                        style: mText(
                          context,
                          15,
                          24,
                          color: AppColors.of(context).disabledBackground,
                        ),
                      ),
                    ),
                    Expanded(child: Text(step.value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _AccountReview extends StatelessWidget {
  const _AccountReview({required this.session});
  final MerchantSession session;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: QStage(
            footer: OutlinedButton(
              onPressed: session.signOut,
              child: Text(t(context, 'Sign out', 'ចាកចេញ')),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 132),
              child: Column(
                children: [
                  const QStatusIcon('6e46a', tone: 'warning'),
                  const SizedBox(height: 12),
                  Text(
                    t(
                      context,
                      'Your account needs a review',
                      'គណនីរបស់អ្នកត្រូវការពិនិត្យ',
                    ),
                    textAlign: TextAlign.center,
                    style: mText(context, 20, 27, weight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t(
                      context,
                      'More than one shop is linked to you. Support will help you continue with the right one.',
                      'មានហាងច្រើនជាងមួយភ្ជាប់នឹងអ្នក។ ផ្នែកគាំទ្រនឹងជួយអ្នកបន្តជាមួយហាងត្រឹមត្រូវ។',
                    ),
                    textAlign: TextAlign.center,
                    style: mText(
                      context,
                      15,
                      24,
                      color: AppColors.of(context).disabledBackground,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const MerchantSupportCard(),
                ],
              ),
            ),
          ),
        ),
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
    this.feed,
    this.transfer,
    this.gateway,
    super.key,
  });
  final MerchantPreferences preferences;
  final MerchantSession session;
  final ShopController? shop;
  final CollectController? collect;
  final SalesController? sales;
  final PaymentFeedController? feed;
  final OwnerTransferController? transfer;
  final MerchantShopGateway? gateway;
  final LogoPicker pickLogo;
  @override
  State<_ShopShell> createState() => _ShopShellState();
}

class _ShopShellState extends State<_ShopShell> {
  int tab = 0;
  @override
  void initState() {
    super.initState();
    widget.collect?.addListener(_collectionChanged);
  }

  void _collectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.collect?.removeListener(_collectionChanged);
    super.dispose();
  }

  Widget _withBanner(Widget body) {
    final feed = widget.feed;
    if (feed == null) return body;
    return PaymentBannerHost(controller: feed, onOpen: _openSales, child: body);
  }

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
          transfer: widget.transfer,
          shopActive: widget.session.identity?.shop?.active == true,
        ),
      ),
    );
  }

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  void _openSales() {
    if (widget.sales == null) {
      _push(
        QPage(
          title: t(context, 'Sales', 'ការលក់'),
          child: _Unavailable(
            title: t(context, 'Sales unavailable', 'ការលក់មិនអាចប្រើបាន'),
            message: t(
              context,
              'Your payment history could not be loaded.',
              'មិនអាចទាញយកប្រវត្តិការទូទាត់របស់អ្នកបានទេ។',
            ),
          ),
        ),
      );
      return;
    }
    _push(
      Scaffold(
        appBar: AppBar(
          leadingWidth: 52,
          leading: const QBack(),
          title: Text(t(context, 'Sales', 'ការលក់')),
          actions: [
            IconButton(
              key: const ValueKey('sales-reports'),
              tooltip: t(context, 'Reports', 'របាយការណ៍'),
              icon: const QIcon('7b0e4'),
              onPressed: _openReports,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SalesView(
                controller: widget.sales!,
                showHeader: false,
                onRequest: _openRequest,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openRequest(String id) async {
    await widget.collect?.openRequest(id);
    if (mounted) setState(() => tab = 1);
  }

  void _openReports() {
    if (widget.gateway != null) {
      _push(
        ReportsPage(gateway: widget.gateway!, onExpired: widget.session.expire),
      );
    }
  }

  void _openRequests() {
    if (widget.gateway != null) {
      _push(
        RequestsPage(
          gateway: widget.gateway!,
          onExpired: widget.session.expire,
          onWaiting: _openRequest,
        ),
      );
    }
  }

  void _openQr() {
    if (widget.gateway != null) {
      _push(MerchantShopQrPage(gateway: widget.gateway!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = widget.session.identity!.shop!;
    final controller = widget.shop;
    final titles = [
      t(context, 'Home', 'ទំព័រដើម'),
      t(context, 'Collect', 'ទទួលប្រាក់'),
      t(context, 'More', 'បន្ថែម'),
    ];
    final active = identity.active;
    final colors = AppColors.of(context);
    Widget home() => RefreshIndicator(
      onRefresh: () async {
        await controller?.refresh();
        await widget.session.validate();
      },
      child: ListView(
        key: const PageStorageKey('shop-tab-0'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          20,
          controller?.shop?.active == false ? 8 : 4,
          20,
          24,
        ),
        children: [
          if (controller != null)
            ShopHomeView(
              controller: controller,
              fallbackName: identity.name,
              onCollect: active ? () => setState(() => tab = 1) : null,
              onSales: _openSales,
              onEditShop: () => _push(const MerchantSupportPage()),
              onOpenWallet: widget.gateway == null ? null : _openWallet,
              onSeeSales: _openSales,
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
              title: identity.name,
              message: t(
                context,
                'Shop details are currently unavailable.',
                'ព័ត៌មានហាងមិនអាចប្រើបានបណ្ដោះអាសន្ន។',
              ),
            ),
        ],
      ),
    );
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => tab = 0);
      },
      child: _withBanner(
        Scaffold(
          appBar: AppBar(
            leadingWidth: 52,
            leading: tab == 1 && widget.collect?.waiting == true
                ? QBack(onPressed: () => setState(() => tab = 0))
                : Builder(
                    builder: (context) => IconButton(
                      key: const ValueKey('merchant-menu'),
                      tooltip: t(context, 'Menu', 'ម៉ឺនុយ'),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const QIcon('56124'),
                    ),
                  ),
            title: tab == 0 && controller != null
                ? ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) =>
                        Text(controller.shop?.storeName ?? identity.name),
                  )
                : tab == 1 && widget.collect != null
                ? ListenableBuilder(
                    listenable: widget.collect!,
                    builder: (context, _) => Text(
                      widget.collect!.waiting
                          ? t(
                              context,
                              'Waiting for payment',
                              'កំពុងរង់ចាំការទូទាត់',
                            )
                          : titles[tab],
                    ),
                  )
                : Text(tab == 0 ? identity.name : titles[tab]),
            actions: tab == 0
                ? [
                    IconButton(
                      tooltip: t(context, 'Refresh', 'ធ្វើបច្ចុប្បន្នភាព'),
                      onPressed: controller?.refresh,
                      icon: const QIcon('8d19a'),
                    ),
                  ]
                : null,
          ),
          drawer: Drawer(
            width: 296,
            backgroundColor: colors.background,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(right: Radius.circular(16)),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller?.shop?.storeName ?? identity.name,
                          style: mText(
                            context,
                            17,
                            23,
                            weight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          controller?.shop?.merchantId ?? '',
                          style: mText(
                            context,
                            13,
                            18,
                            color: colors.disabledBackground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            for (final item in <(String, String, VoidCallback)>[
                              (
                                titles[0],
                                '5bdf3',
                                () => setState(() => tab = 0),
                              ),
                              (
                                titles[1],
                                'cc139',
                                () => setState(() => tab = 1),
                              ),
                              (
                                t(context, 'Sales', 'ការលក់'),
                                '5e757',
                                _openSales,
                              ),
                              (
                                t(
                                  context,
                                  'Collections report',
                                  'របាយការណ៍ប្រាក់ទទួល',
                                ),
                                '8b848',
                                _openReports,
                              ),
                              (
                                t(context, 'Payment requests', 'សំណើទូទាត់'),
                                'dc524',
                                _openRequests,
                              ),
                              (
                                t(
                                  context,
                                  'Business wallets',
                                  'កាបូបអាជីវកម្ម',
                                ),
                                '58f29',
                                () => _push(
                                  MerchantWalletsPage(
                                    controller: controller,
                                    onOpen: _openWallet,
                                  ),
                                ),
                              ),
                              (
                                t(context, 'Shop QR', 'QR ហាង'),
                                '875aa',
                                _openQr,
                              ),
                            ])
                              ListTile(
                                key: ValueKey('merchant-menu-${item.$2}'),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                leading: QIcon(item.$2),
                                title: Text(
                                  item.$1,
                                  style: mText(context, 15, 24),
                                ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  item.$3();
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      t(
                        context,
                        'Settings and sign out are in More.',
                        'ការកំណត់ និងចាកចេញនៅក្នុងបន្ថែម។',
                      ),
                      style: mText(
                        context,
                        13,
                        18,
                        color: colors.disabledBackground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: tab == 0
                  ? home()
                  : tab == 1 && widget.collect != null && widget.gateway != null
                  ? CollectView(
                      controller: widget.collect!,
                      gateway: widget.gateway!,
                      storeName: controller?.shop?.storeName ?? identity.name,
                      active: active,
                    )
                  : tab == 2
                  ? MerchantMoreView(
                      preferences: widget.preferences,
                      controller: controller,
                      fallbackName: identity.name,
                      onProfile: _openProfile,
                      onSignOut: widget.session.signOut,
                    )
                  : _Unavailable(
                      title: titles[tab],
                      message: t(
                        context,
                        'Collection unavailable',
                        'មិនអាចទទួលប្រាក់បាន',
                      ),
                    ),
            ),
          ),

          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        child: Semantics(
                          key: ValueKey('merchant-tab-$i'),
                          selected: tab == i,
                          button: true,
                          child: InkWell(
                            onTap: () => setState(() => tab = i),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 56,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: tab == i
                                          ? colors.accent50
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: QIcon(
                                      i == 0
                                          ? (tab == 0 ? '19f2d' : '5b56c')
                                          : i == 1
                                          ? (tab == 1 ? 'e306f' : 'f6e9c')
                                          : (tab == 2 ? 'be895' : 'ff372'),
                                      darkAdaptive: tab != i,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    titles[i],
                                    textAlign: TextAlign.center,
                                    style: mText(
                                      context,
                                      11,
                                      14,
                                      weight: FontWeight.w500,
                                      color: tab == i
                                          ? merchantNavy(context)
                                          : colors.disabledBackground,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
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
