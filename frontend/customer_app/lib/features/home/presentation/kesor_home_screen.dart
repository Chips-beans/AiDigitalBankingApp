import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/app_theme.dart';
import '../../../app/app_preferences.dart';
import '../../../shared/widgets/kesor_layout.dart';
import '../../../shared/widgets/kesor_bottom_bar.dart';
import '../../../app/design_system/design_system.dart';
import '../home_data.dart';
export '../home_data.dart';

/// Kesor Bank Home, translated from Figma frame 9:43 (440 × 999).
///
/// Native system bars remain native. [showDeviceChrome] reproduces the Figma
/// status bar and home indicator for the explicit design preview and goldens.
class KesorHomeScreen extends StatefulWidget {
  const KesorHomeScreen({
    required this.data,
    this.showDeviceChrome = false,
    this.showNavigation = true,
    this.loading = false,
    this.balanceVisible,
    this.onBalanceVisibilityChanged,
    this.onAccounts,
    this.onTransfer,
    this.onActivity,
    this.onProfile,
    this.onTransaction,
    this.onRefresh,
    this.errorMessage,
    this.pendingTransfer = false,
    super.key,
  });

  final KesorHomeData data;
  final bool? balanceVisible;
  final ValueChanged<bool>? onBalanceVisibilityChanged;
  final bool showDeviceChrome, pendingTransfer, showNavigation, loading;
  final VoidCallback? onAccounts, onTransfer, onActivity, onProfile;
  final ValueChanged<HomeTransaction>? onTransaction;
  final Future<void> Function()? onRefresh;
  final String? errorMessage;

  @override
  State<KesorHomeScreen> createState() => _KesorHomeScreenState();
}

AppColors _homeColors(BuildContext context) =>
    Theme.of(context).extension<AppColors>() ??
    AppColors.forBrightness(Theme.of(context).brightness);
Color _homeAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppPalette.navy100
    : AppPalette.navy500;

TextStyle _text(
  BuildContext context,
  double size,
  double lineHeight, {
  Color? color,
  FontWeight weight = FontWeight.w400,
  String? family,
}) => TextStyle(
  fontFamily:
      family ??
      ((AppPreferences.maybeOf(context)?.isKhmer ?? true)
          ? AppTypography.khmerFamily
          : AppTypography.englishFamily),
  fontFamilyFallback: AppTypography.fallbackFamilies,
  fontSize: size,
  fontWeight: weight,
  height: lineHeight / size,
  color: color ?? _homeColors(context).foreground,
  letterSpacing: 0,
);

class _KesorHomeScreenState extends State<KesorHomeScreen> {
  bool _localBalanceVisible = true;
  bool get _balanceVisible => widget.balanceVisible ?? _localBalanceVisible;
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  bool get _khmer => AppPreferences.maybeOf(context)?.isKhmer ?? true;
  String _tr(String english, String khmer) => _khmer ? khmer : english;
  final _actionsScroll = ScrollController();
  final List<HomeRecipient> _addedRecipients = [];

  @override
  void dispose() {
    _actionsScroll.dispose();
    super.dispose();
  }

  void _showPanel(String title, String message, {Widget? content}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _homeColors(context).background,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: _text(context, 20, 28, weight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: _text(
                  context,
                  14,
                  22,
                  color: _homeColors(context).disabledBackground,
                ),
              ),
              if (content != null) ...[const SizedBox(height: 20), content],
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('បិទ · Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRecipients() {
    _showPanel(
      _tr('Recipients', 'បញ្ជីរអ្នកទទួល'),
      'Recipients',
      content: Column(
        children: [
          for (final person in [...widget.data.recipients, ..._addedRecipients])
            ListTile(
              leading: _Avatar(
                person.name,
                asset: person.avatarAsset,
                size: 48,
              ),
              title: Text(
                person.name,
                style: _text(context, 14, 22, family: 'Poppins'),
              ),
              onTap: () {
                Navigator.pop(context);
                _recipient(person);
              },
            ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: const Text('បន្ថែម · Add recipient'),
            onTap: () {
              Navigator.pop(context);
              _addRecipient();
            },
          ),
        ],
      ),
    );
  }

  void _recipient(HomeRecipient person) {
    if (widget.onTransfer != null) {
      widget.onTransfer!();
    } else {
      _showPanel(person.name, 'អ្នកទទួល · Recipient');
    }
  }

  Future<void> _addRecipient() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('បន្ថែមអ្នកទទួល', style: _text(context, 20, 28)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'ឈ្មោះ · Name'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(dialogContext, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('បោះបង់ · Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('បន្ថែម · Add'),
          ),
        ],
      ),
    );
    // The dialog's reverse transition must finish before disposing its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (mounted && name != null) {
      setState(() => _addedRecipients.add(HomeRecipient(name)));
    }
  }

  void _activity() {
    if (widget.onActivity != null) {
      widget.onActivity!();
    } else {
      _showPanel(
        _tr('Recent transactions', 'ប្រតិបត្តិការថ្មីៗ'),
        'Recent activity',
        content: _transactionCard(),
      );
    }
  }

  void _transaction(HomeTransaction transaction) {
    if (widget.onTransaction != null) {
      widget.onTransaction!(transaction);
    } else {
      _showPanel(
        transaction.name,
        '${transaction.time}\n${transaction.amount}',
        content: Center(
          child: _Avatar(
            transaction.name,
            asset: transaction.avatarAsset,
            size: 48,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topInset = widget.showDeviceChrome ? 54.0 : media.padding.top;
    final bottomInset = widget.showDeviceChrome
        ? 24.0
        : math.max(24.0, media.padding.bottom);
    final screen = AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (Theme.of(context).brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: _homeColors(context).background,
              ),
      child: Theme(
        data: Theme.of(context).extension<AppColors>() == null
            ? AppTheme.build(
                Theme.of(context).brightness,
                locale: Locale(_khmer ? 'km' : 'en'),
              )
            : Theme.of(context),
        child: Scaffold(
          backgroundColor: _homeColors(context).background,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: KesorLayout.frameWidth,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scroll = SingleChildScrollView(
                    key: const PageStorageKey('kesor-home-scroll'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(20, topInset + 10, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(),
                        if (widget.loading) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            key: const ValueKey('home-loading'),
                            semanticsLabel: _tr(
                              'Loading Home',
                              'កំពុងផ្ទុកទំព័រដើម',
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _balanceCard(),
                        if (widget.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              widget.errorMessage!,
                              style: _text(
                                context,
                                14,
                                22,
                                color: _homeColors(context).error,
                              ),
                            ),
                          ),
                        if (widget.pendingTransfer)
                          TextButton(
                            onPressed: widget.onTransfer,
                            child: const Text('Review saved transfer'),
                          ),
                        const SizedBox(height: 29),
                        _sectionHeader(
                          'recipients.svg',
                          _tr('Recipients', 'បញ្ជីរអ្នកទទួល'),
                          _openRecipients,
                        ),
                        const SizedBox(height: 9),
                        _recipients(),
                        const SizedBox(height: 23),
                        _sectionHeader(
                          'transactions.svg',
                          _tr('Recent transactions', 'ប្រតិបត្តិការថ្មីៗ'),
                          _activity,
                        ),
                        const SizedBox(height: 9),
                        _transactionCard(),
                      ],
                    ),
                  );
                  return Stack(
                    children: [
                      Positioned.fill(
                        // Keep scrolling rows above the floating bar on shorter
                        // devices; the 999px reference ends exactly at y=892.
                        bottom:
                            bottomInset + KesorBottomBar.height(context) + 19,
                        child: widget.onRefresh == null
                            ? scroll
                            : RefreshIndicator(
                                onRefresh: widget.onRefresh!,
                                child: scroll,
                              ),
                      ),
                      if (widget.showDeviceChrome)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: MediaQuery.withNoTextScaling(
                            child: const _PreviewStatusBar(),
                          ),
                        ),
                      if (widget.showNavigation)
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: bottomInset,
                          child: _navigation(),
                        ),
                      if (widget.showDeviceChrome)
                        Positioned(
                          bottom: 5,
                          left: (constraints.maxWidth - 134) / 2,
                          child: Container(
                            width: 134,
                            height: 5,
                            decoration: BoxDecoration(
                              color: _homeColors(context).foreground,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    if (!widget.showDeviceChrome) return screen;
    return ColoredBox(
      color: const Color(0xFF999999),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(38),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(38),
            border: Border.all(color: const Color(0xFFEBECE8)),
          ),
          child: screen,
        ),
      ),
    );
  }

  Widget _header() => SizedBox(
    height: 56,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _Tap(
          label: 'View accounts',
          onTap:
              widget.onAccounts ??
              () => _showPanel('គណនីរបស់ខ្ញុំ', 'My accounts'),
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              children: [
                Positioned(
                  left: 9.3333,
                  top: 5.3333,
                  child: _Svg('kesor-logo.svg'),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 72,
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Tap(
                label: 'Inbox',
                onTap: () => _showPanel(
                  'ប្រអប់សារ',
                  'មិនមានសារថ្មីទេ · No new messages',
                ),
                child: const SizedBox(
                  width: 28,
                  height: 44,
                  child: Center(child: _Svg('inbox.svg')),
                ),
              ),
              _Tap(
                label: 'My QR',
                onTap: () => _showPanel('កូដ QR របស់ខ្ញុំ', 'My QR'),
                child: SizedBox(
                  width: 28,
                  height: 44,
                  child: Center(
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppPalette.semanticError,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(child: _Svg('khqr-mark.svg')),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _balanceCard() {
    final extra = (MediaQuery.textScalerOf(context).scale(14) / 14 - 1).clamp(
      0.0,
      2.0,
    );
    return ClipRRect(
      key: const ValueKey('home-balance-card'),
      borderRadius: BorderRadius.circular(24),
      child: CustomPaint(
        foregroundPainter: _BalanceBorder(
          color: _homeColors(context).primary200,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment(0, 2.6526),
              colors: _dark
                  ? [
                      _homeColors(context).background,
                      _homeColors(context).surface,
                      AppPalette.gold700.withValues(alpha: .16),
                      AppPalette.gold700.withValues(alpha: .18),
                      AppPalette.gold600.withValues(alpha: .2),
                    ]
                  : [
                      _homeColors(context).background.withValues(alpha: .7),
                      AppPalette.gold50.withValues(alpha: .7),
                      AppPalette.gold100.withValues(alpha: .7),
                      AppPalette.gold100.withValues(alpha: .7),
                      AppPalette.gold200.withValues(alpha: .7),
                    ],
              stops: [0, .33, .59, .79, 1],
            ),
          ),
          child: Stack(
            children: [
              const Positioned(
                right: -46.335,
                top: -17.3583,
                child: KesorBalanceMotif(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 17, 23, 21),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 36 + extra * 12,
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: Center(child: _Svg('rosette.svg')),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _tr('Balance', 'សមតុល្យ'),
                              style: _text(
                                context,
                                16,
                                24,
                                color: _dark
                                    ? AppPalette.gold400
                                    : AppPalette.gold700,
                                weight: FontWeight.w500,
                              ),
                            ),
                          ),
                          _Tap(
                            label: _balanceVisible
                                ? 'Hide balance'
                                : 'Show balance',
                            onTap: () => setState(() {
                              _localBalanceVisible = !_balanceVisible;
                              widget.onBalanceVisibilityChanged?.call(
                                _localBalanceVisible,
                              );
                            }),
                            child: _FigmaGlass(
                              radius: 26,
                              blurRadius: 10,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _homeColors(context).accent
                                      .withValues(alpha: .3),
                                  borderRadius: BorderRadius.circular(26),
                                ),
                                child: Center(
                                  child: _balanceVisible
                                      ? const _Svg('balance-visibility.svg')
                                      : Icon(
                                          Icons.visibility_outlined,
                                          size: 24,
                                          color: _homeColors(context)
                                              .foreground,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Tap(
                      label: 'View account details',
                      onTap:
                          widget.onAccounts ??
                          () => _showPanel('គណនីរបស់ខ្ញុំ', 'My accounts'),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: 124 + extra * 100,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: _balanceVisible
                                        ? widget.data.khrBalance
                                        : '••••',
                                    style: _text(
                                      context,
                                      20,
                                      28,
                                      weight: FontWeight.w500,
                                      family: 'Poppins',
                                    ),
                                  ),
                                  TextSpan(
                                    text: '៛',
                                    style: _text(
                                      context,
                                      20,
                                      28,
                                      weight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              key: const ValueKey('home-khr-balance'),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _tr('Total in riel', 'ប្រាក់រៀលសរុប'),
                              style: _text(
                                context,
                                14,
                                22,
                                color: _homeColors(context).disabledBackground,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _balanceVisible
                                  ? widget.data.usdBalance
                                  : r'$••••',
                              key: const ValueKey('home-usd-balance'),
                              style: _text(
                                context,
                                20,
                                28,
                                weight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _tr('Total in dollars', 'ប្រាក់ដុល្លារសរុប'),
                              style: _text(
                                context,
                                14,
                                22,
                                color: _homeColors(context).disabledBackground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = (constraints.maxWidth - 16) / 3;
                        return Scrollbar(
                          controller: _actionsScroll,
                          child: SingleChildScrollView(
                            controller: _actionsScroll,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (int i = 0; i < 6; i++) ...[
                                  if (i != 0) const SizedBox(width: 8),
                                  _quickAction(i, width, 82 + extra * 70),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
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

  Widget _quickAction(int index, double width, double height) {
    final qr = index == 1;
    final transfer = index == 2 || index == 5;
    final label = qr
        ? _tr('Scan QR', 'ស្កេនកូដ QR')
        : index == 5
        ? _tr('Transfer', 'ផ្ទេរប្រាក់')
        : _tr('Payments', 'ទូទាត់ប្រាក់');
    return _Tap(
      label: qr
          ? 'Scan QR'
          : transfer
          ? 'Transfer'
          : 'Payments',
      onTap: transfer
          ? widget.onTransfer ??
                () => _showPanel('ផ្ទេរប្រាក់', 'Internal transfer')
          : () => _showPanel(
              qr ? _tr('Scan QR', 'ស្កេនកូដ QR') : 'ទូទាត់ប្រាក់',
              qr ? 'QR scanner' : 'Payments',
            ),
      child: _FigmaGlass(
        radius: 16,
        blurRadius: 69,
        child: Container(
          width: width,
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: index == 5
                  ? const [Color(0xF0E1F9D9), Color(0xF0D5F0E5)]
                  : index == 3 || index == 4
                  ? const [Color(0x66EEDAB5), Color(0x5ECDA32F)]
                  : const [Color(0x1CEEDAB5), Color(0x12CDA32F)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: Center(
                  child: _Svg(
                    qr
                        ? 'qr-scan.svg'
                        : transfer
                        ? 'transfer.svg'
                        : 'payment-card.svg',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: _text(
                  context,
                  14,
                  22,
                  weight: FontWeight.w500,
                  family: _khmer
                      ? AppTypography.khmerFamily
                      : AppTypography.englishFamily,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String icon, String title, VoidCallback onAll) => Row(
    children: [
      SizedBox(width: 24, height: 28, child: Center(child: _Svg(icon))),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: _text(
            context,
            16,
            24,
            color: _homeAccent(context),
            weight: FontWeight.w500,
          ),
        ),
      ),
      _Tap(
        label: title == _tr('Recipients', 'បញ្ជីរអ្នកទទួល')
            ? 'All recipients'
            : 'All transactions',
        onTap: onAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Row(
            children: [
              Text(
                _tr('All', 'ទាំងអស់'),
                style: _text(
                  context,
                  14,
                  22,
                  color: _homeColors(context).disabledBackground,
                ),
              ),
              const _Svg('chevron.svg'),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _recipients() {
    final people = [...widget.data.recipients, ..._addedRecipients];
    final extra = (MediaQuery.textScalerOf(context).scale(12) / 12 - 1).clamp(
      0.0,
      2.0,
    );
    double recipientWidth(HomeRecipient person) {
      final measure = TextPainter(
        text: TextSpan(
          text: person.name,
          style: _text(context, 12, 18, family: 'Poppins'),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = (measure.width + 8).clamp(65.0, 144.0);
      measure.dispose();
      return width;
    }

    final children = [
      for (final person in people)
        _Tap(
          label: person.name,
          onTap: () => _recipient(person),
          child: SizedBox(
            width: recipientWidth(person),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Avatar(person.name, asset: person.avatarAsset, size: 48),
                const SizedBox(height: 2),
                SizedBox(
                  height: 18 + extra * 18,
                  child: Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: _text(
                      context,
                      12,
                      18,
                      color: _homeColors(context).foreground,
                      family: 'Poppins',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      _Tap(
        label: 'Add recipient',
        onTap: _addRecipient,
        child: SizedBox(
          width: 48 + extra * 48,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _homeColors(context).surface,
                ),
                child: const Center(child: _Svg('plus.svg')),
              ),
              const SizedBox(height: 2),
              Text(
                _tr('Add', 'បន្ថែម'),
                maxLines: 1,
                softWrap: false,
                style: _text(
                  context,
                  14,
                  18,
                  color: _homeColors(context).foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
    return Container(
      key: const ValueKey('home-recipients-card'),
      constraints: const BoxConstraints(minHeight: 94),
      decoration: BoxDecoration(
        color: _homeColors(context).surface,
        border: Border.all(color: _homeColors(context).border),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i != 0) const SizedBox(width: 8),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _transactionCard() {
    final groups = <String, List<HomeTransaction>>{};
    for (final entry in widget.data.transactions) {
      final label =
          entry.dateLabel ??
          (entry.previousDay
              ? _tr('Yesterday', 'ម្សិលមិញ')
              : _tr('Today', 'ថ្ងៃនេះ'));
      groups.putIfAbsent(label, () => []).add(entry);
    }
    return Container(
      key: const ValueKey('home-transactions-card'),
      decoration: BoxDecoration(
        color: _homeColors(context).surface,
        border: Border.all(color: _homeColors(context).border),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.data.transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                widget.loading
                    ? _tr('Loading activity…', 'កំពុងផ្ទុកប្រតិបត្តិការ…')
                    : _tr('No activity yet', 'មិនទាន់មានប្រតិបត្តិការ'),
                style: _text(
                  context,
                  14,
                  22,
                  color: _homeColors(context).disabledBackground,
                ),
              ),
            ),
          for (final group in groups.entries) ...[
            if (group.key != groups.keys.first) const SizedBox(height: 12),
            Text(
              group.key,
              style: _text(
                context,
                14,
                22,
                color: _homeColors(context).disabledBackground,
              ),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < group.value.length; i++) ...[
              if (i != 0) const SizedBox(height: 10),
              _transactionRow(
                group.value[i],
                first: group.key == _tr('Today', 'ថ្ងៃនេះ') && i == 0,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _transactionRow(HomeTransaction entry, {bool first = false}) => _Tap(
    label: '${entry.name}, ${entry.amount}, ${entry.time}',
    onTap: () => _transaction(entry),
    child: Row(
      children: [
        _Avatar(entry.name, asset: entry.avatarAsset, size: 36),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _text(
                  context,
                  14,
                  first ? 24 : 18,
                  color: _homeColors(context).foreground,
                  family: 'Poppins',
                ),
              ),
              Text(
                entry.time,
                style: _text(
                  context,
                  12,
                  16,
                  color: _homeColors(context).disabledBackground,
                  family: 'Poppins',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(160, MediaQuery.sizeOf(context).width * .35),
          ),
          child: Text(
            entry.amount,
            textAlign: TextAlign.right,
            style: _text(
              context,
              14,
              first ? 28 : 18,
              color: entry.internal
                  ? _homeColors(context).disabledBackground
                  : entry.incoming
                  ? _homeAccent(context)
                  : AppPalette.semanticError,
              family: first ? 'Google Sans' : 'Poppins',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _navigation() => KesorBottomBar(
    selectedIndex: 0,
    onSelected: (index) {
      if (index == 1) _activity();
      if (index == 2) {
        if (widget.onProfile != null) {
          widget.onProfile!();
        } else {
          _showPanel(_tr('Settings', 'ការកំណត់'), 'Settings');
        }
      }
    },
    onAssistant: () =>
        _showPanel(_tr('AI assistant', 'ជំនួយការ AI'), 'AI assistant'),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name, {required this.size, this.asset});
  final String name;
  final String? asset;
  final double size;
  @override
  Widget build(BuildContext context) => asset != null
      ? Image.asset(
          'assets/home/$asset',
          width: size,
          height: size,
          excludeFromSemantics: true,
        )
      : CircleAvatar(
          radius: size / 2,
          backgroundColor: _homeColors(context).accent,
          child: Text(
            name.characters.first.toUpperCase(),
            style: _text(
              context,
              size / 3,
              size / 2,
              color: _homeAccent(context),
            ),
          ),
        );
}

class _Tap extends StatelessWidget {
  const _Tap({required this.label, required this.onTap, required this.child});
  final String label;
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: ExcludeSemantics(child: child),
        ),
      ),
    ),
  );
}

/// Native SVG dimensions are retained; only the surrounding design slot scales.
class _Svg extends StatelessWidget {
  const _Svg(this.name);
  final String name;
  static const _sizes = <String, Size>{
    'kesor-logo.svg': Size(37.3334, 46.6627),
    'khqr-mark.svg': Size(15, 16),
    'rosette.svg': Size(18.675, 18.5323),
    'inbox.svg': Size(28, 28),
    'balance-visibility.svg': Size(24, 24),
    'payment-card.svg': Size(24.0175, 18.4708),
    'qr-scan.svg': Size(26, 26),
    'transfer.svg': Size(15.1667, 17.3333),
    'recipients.svg': Size(24, 24),
    'transactions.svg': Size(24, 24),
    'chevron.svg': Size(16, 16),
    'plus.svg': Size(14.8333, 14.8333),
    'nav-home.svg': Size(20, 20),
    'nav-analytics.svg': Size(20, 20),
    'nav-settings.svg': Size(20, 20),
    'ai-sun.svg': Size(30, 30),
    'status-levels.svg': Size(143.003, 54),
    'balance-motif.svg': Size(208.13, 206.609),
  };
  @override
  Widget build(BuildContext context) {
    final size = _sizes[name]!;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: FittedBox(
        child: SvgPicture.asset(
          'assets/home/$name',
          width: size.width,
          height: size.height,
          excludeFromSemantics: true,
          colorFilter:
              Theme.of(context).brightness == Brightness.dark &&
                  !{
                    'kesor-logo.svg',
                    'khqr-mark.svg',
                    'rosette.svg',
                    'balance-motif.svg',
                    'ai-sun.svg',
                  }.contains(name)
              ? ColorFilter.mode(_homeAccent(context), BlendMode.srcIn)
              : null,
        ),
      ),
    );
  }
}

/// Figma GLASS is expressed with a clipped backdrop and directional lighting.
/// The fill above it retains the exact exported opacity and gradient stops.
class _FigmaGlass extends StatelessWidget {
  const _FigmaGlass({
    required this.radius,
    required this.blurRadius,
    required this.child,
  });
  final double radius, blurRadius;
  final Widget child;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(
        sigmaX: blurRadius / 2,
        sigmaY: blurRadius / 2,
      ),
      child: CustomPaint(painter: const _GlassLighting(), child: child),
    ),
  );
}

class _GlassLighting extends CustomPainter {
  const _GlassLighting();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x04000000), Color(0x00FFFFFF), Color(0x30FFFFFF)],
          stops: [0, .45, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassLighting oldDelegate) => false;
}

class _BalanceBorder extends CustomPainter {
  const _BalanceBorder({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(.5), const Radius.circular(23.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _BalanceBorder oldDelegate) =>
      oldDelegate.color != color;
}

/// Keeps the exported SVG intact and translates Figma's progressive layer blur.
/// Flutter's SVG renderer ignores SVG filter tags, so the blur is applied here.
class KesorBalanceMotif extends StatelessWidget {
  const KesorBalanceMotif({this.asset, super.key});
  final String? asset;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 186.9292,
    height: 186.32825,
    child: Transform(
      alignment: Alignment.topLeft,
      transform: Matrix4.identity()
        ..setEntry(0, 0, .9659258723)
        ..setEntry(0, 1, -.5)
        ..setEntry(1, 0, .2588190734)
        ..setEntry(1, 1, .8660253882),
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 208.13,
        maxWidth: 208.13,
        minHeight: 206.609,
        maxHeight: 206.609,
        child: Transform.translate(
          offset: const Offset(-10.6, -10.14),
          child: SizedBox(
            width: 208.13,
            height: 206.609,
            child: Stack(
              children: [
                for (int i = 0; i < 12; i++)
                  Positioned.fill(
                    child: ClipRect(
                      clipper: _BlurBand(i),
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: .35 + i * .28,
                          sigmaY: .35 + i * .28,
                        ),
                        child: asset == null
                            ? const _Svg('balance-motif.svg')
                            : SvgPicture.asset(
                                asset!,
                                excludeFromSemantics: true,
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
  );
}

class _BlurBand extends CustomClipper<Rect> {
  const _BlurBand(this.index);
  final int index;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    size.height * index / 12,
    size.width,
    size.height * (index + 1) / 12,
  );
  @override
  bool shouldReclip(_BlurBand oldClipper) => oldClipper.index != index;
}

class _PreviewStatusBar extends StatelessWidget {
  const _PreviewStatusBar();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      color: _homeColors(context).background,
      height: 54,
      child: Stack(
        children: [
          Positioned(
            left: 35.4545,
            top: 16,
            child: Text(
              '9:41',
              style: _text(context, 17, 22, weight: FontWeight.w500),
            ),
          ),
          const Positioned(right: -4, top: 0, child: _Svg('status-levels.svg')),
        ],
      ),
    ),
  );
}
