import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kesor_design_system/kesor_design_system.dart';

import '../core/merchant_preferences.dart';
import '../features/auth/merchant_session.dart';

class MerchantApp extends StatefulWidget {
  const MerchantApp({
    required this.preferences,
    required this.session,
    super.key,
  });
  final MerchantPreferences preferences;
  final MerchantSession session;
  @override
  State<MerchantApp> createState() => _MerchantAppState();
}

class _MerchantAppState extends State<MerchantApp> with WidgetsBindingObserver {
  bool covered = false;
  Timer? validation;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    validation = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!covered) unawaited(widget.session.validate());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    validation?.cancel();
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
        home: MerchantStrings(
          khmer: prefs.isKhmer,
          child: covered
              ? const Scaffold(body: Center(child: _Brand()))
              : switch (widget.session.phase) {
                  MerchantPhase.signedOut => _Welcome(
                    prefs: prefs,
                    session: widget.session,
                  ),
                  MerchantPhase.approving => _ApprovalWaiting(
                    session: widget.session,
                  ),
                  MerchantPhase.shopRequired => _RegisterShop(
                    session: widget.session,
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
                  ),
                },
        ),
      );
    },
  );
}

class MerchantStrings extends InheritedWidget {
  const MerchantStrings({required this.khmer, required super.child, super.key});
  final bool khmer;
  @override
  bool updateShouldNotify(MerchantStrings oldWidget) =>
      oldWidget.khmer != khmer;
  static String text(BuildContext context, String en, String km) =>
      context.dependOnInheritedWidgetOfExactType<MerchantStrings>()?.khmer ==
          true
      ? km
      : en;
}

String _t(BuildContext c, String en, String km) =>
    MerchantStrings.text(c, en, km);

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

class _RegisterShop extends StatefulWidget {
  const _RegisterShop({required this.session});
  final MerchantSession session;
  @override
  State<_RegisterShop> createState() => _RegisterShopState();
}

class _RegisterShopState extends State<_RegisterShop> {
  final name = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_t(context, 'Register your shop', 'ចុះឈ្មោះហាងរបស់អ្នក')),
      actions: [
        IconButton(
          tooltip: _t(context, 'Sign out', 'ចាកចេញ'),
          onPressed: widget.session.signOut,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: _Page(
      children: [
        Text(
          _t(context, 'Make it your business', 'បង្កើតអាជីវកម្មរបស់អ្នក'),
          style: AppTextStyles.of(context).titleXL,
        ),
        const SizedBox(height: 8),
        Text(
          _t(
            context,
            'Your shop gets separate KHR and USD wallets.',
            'ហាងរបស់អ្នកទទួលបានកាបូបប្រាក់រៀល និងដុល្លារដាច់ដោយឡែក។',
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: CircleAvatar(
            radius: 36,
            backgroundColor: AppColors.of(context).primary100,
            foregroundColor: AppPalette.navy700,
            child: Text(
              name.text.trim().isEmpty
                  ? 'K'
                  : name.text.trim().characters.first.toUpperCase(),
              style: AppTextStyles.of(context).titleXL,
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: name,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: _t(context, 'Shop name', 'ឈ្មោះហាង'),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: InputDecoration(
            labelText: _t(context, 'Business category', 'ប្រភេទអាជីវកម្ម'),
          ),
          items: [
            DropdownMenuItem(
              value: 'retail',
              child: Text(_t(context, 'Retail', 'លក់រាយ')),
            ),
            DropdownMenuItem(
              value: 'food',
              child: Text(_t(context, 'Food & drinks', 'អាហារ និងភេសជ្ជៈ')),
            ),
            DropdownMenuItem(
              value: 'services',
              child: Text(_t(context, 'Services', 'សេវាកម្ម')),
            ),
          ],
          onChanged: (_) {},
        ),
        const SizedBox(height: 16),
        TextField(
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: _t(context, 'Business phone', 'លេខទូរស័ព្ទអាជីវកម្ម'),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(labelText: _t(context, 'City', 'ក្រុង')),
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(
            labelText: _t(context, 'Address', 'អាសយដ្ឋាន'),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _t(
            context,
            'Shop registration is currently unavailable. Please try again later.',
            'ការចុះឈ្មោះហាងមិនទាន់អាចប្រើបាន។ សូមព្យាយាមម្ដងទៀតនៅពេលក្រោយ។',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: null,
          child: Text(_t(context, 'Register shop', 'ចុះឈ្មោះហាង')),
        ),
      ],
    ),
  );
}

class _ShopShell extends StatefulWidget {
  const _ShopShell({
    required this.preferences,
    required this.session,
    super.key,
  });
  final MerchantPreferences preferences;
  final MerchantSession session;
  @override
  State<_ShopShell> createState() => _ShopShellState();
}

class _ShopShellState extends State<_ShopShell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final shop = widget.session.identity!.shop!;
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
        appBar: AppBar(title: Text(titles[tab])),
        body: _Page(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: colors.primary100,
                  foregroundColor: AppPalette.navy700,
                  child: Text(shop.name.characters.first.toUpperCase()),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    shop.name,
                    style: AppTextStyles.of(context).titleL,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (!shop.active) ...[
              _Unavailable(
                title: _t(
                  context,
                  'Shop access is restricted',
                  'ការចូលប្រើហាងត្រូវបានកម្រិត',
                ),
                message: _t(
                  context,
                  'Contact support for help with your shop status.',
                  'ទាក់ទងផ្នែកគាំទ្រសម្រាប់ជំនួយអំពីស្ថានភាពហាង។',
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (tab == 0) ...[
              Text(
                _t(context, 'Business wallets', 'កាបូបប្រាក់អាជីវកម្ម'),
                style: AppTextStyles.of(context).titleM,
              ),
              const SizedBox(height: 16),
              for (final currency in ['KHR', 'USD']) ...[
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(currency),
                        Text('—', style: AppTextStyles.of(context).titleXL),
                        Text(
                          _t(
                            context,
                            'Balance unavailable',
                            'សមតុល្យមិនអាចប្រើបាន',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                onPressed: shop.active ? () => setState(() => tab = 1) : null,
                icon: const Icon(Icons.qr_code_2),
                label: Text(titles[1]),
              ),
              const SizedBox(height: 24),
              _Unavailable(
                title: _t(
                  context,
                  'Today’s collections',
                  'ប្រាក់ទទួលបានថ្ងៃនេះ',
                ),
                message: _t(
                  context,
                  'Payment information is currently unavailable.',
                  'ព័ត៌មានការទូទាត់មិនអាចប្រើបានបណ្ដោះអាសន្ន។',
                ),
              ),
            ] else if (tab == 1) ...[
              Text(
                _t(context, 'Collect a payment', 'ទទួលការទូទាត់'),
                style: AppTextStyles.of(context).titleXL,
              ),
              const SizedBox(height: 16),
              _Unavailable(
                title: _t(
                  context,
                  'Collection unavailable',
                  'មិនអាចទទួលប្រាក់បាន',
                ),
                message: _t(
                  context,
                  'Please try again later. No payment request has been created.',
                  'សូមព្យាយាមម្ដងទៀតនៅពេលក្រោយ។ មិនមានសំណើទូទាត់ត្រូវបានបង្កើតទេ។',
                ),
              ),
            ] else if (tab == 2) ...[
              _Unavailable(
                title: _t(context, 'Sales unavailable', 'ការលក់មិនអាចប្រើបាន'),
                message: _t(
                  context,
                  'Your payment history could not be loaded.',
                  'មិនអាចទាញយកប្រវត្តិការទូទាត់របស់អ្នកបានទេ។',
                ),
              ),
            ] else ...[
              Text(
                _t(context, 'Preferences', 'ចំណូលចិត្ត'),
                style: AppTextStyles.of(context).titleM,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(widget.preferences.locale.languageCode),
                initialValue: widget.preferences.locale.languageCode,
                decoration: InputDecoration(
                  labelText: _t(context, 'Language', 'ភាសា'),
                ),
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'km', child: Text('ខ្មែរ')),
                ],
                onChanged: (v) {
                  if (v != null) widget.preferences.setLanguage(v);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ThemeMode>(
                key: ValueKey(widget.preferences.themeMode),
                initialValue: widget.preferences.themeMode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _t(context, 'Appearance', 'រូបរាង'),
                ),
                items: [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text(_t(context, 'System', 'ប្រព័ន្ធ')),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.support_agent_outlined),
                title: Text(_t(context, 'Support', 'ជំនួយ')),
                subtitle: const Text('reachsteav2@gmail.com'),
                onTap: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: 'reachsteav2@gmail.com'),
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
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: widget.session.signOut,
                icon: const Icon(Icons.logout),
                label: Text(_t(context, 'Sign out', 'ចាកចេញ')),
              ),
            ],
          ],
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
                label: titles[0],
              ),
              NavigationDestination(
                icon: const Icon(Icons.qr_code_2),
                label: titles[1],
              ),
              NavigationDestination(
                icon: const Icon(Icons.receipt_long_outlined),
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
