import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  final bool showDeviceChrome, pendingTransfer;
  final VoidCallback? onAccounts, onTransfer, onActivity, onProfile;
  final ValueChanged<HomeTransaction>? onTransaction;
  final Future<void> Function()? onRefresh;
  final String? errorMessage;

  @override
  State<KesorHomeScreen> createState() => _KesorHomeScreenState();
}

abstract final class _Palette {
  static const ink = Color(0xFF191B19);
  static const navy = Color(0xFF133358);
  static const gold = Color(0xFFB8944F);
  static const muted = Color(0xFF8E958E);
  static const border = Color(0xFFE5E7E3);
}

TextStyle _text(
  double size,
  double lineHeight, {
  Color color = _Palette.ink,
  FontWeight weight = FontWeight.w400,
  String family = 'Google Sans',
}) => TextStyle(
  fontFamily: family,
  fontFamilyFallback: const ['Noto Sans Khmer'],
  fontSize: size,
  fontWeight: weight,
  height: lineHeight / size,
  color: color,
  letterSpacing: 0,
);

class _KesorHomeScreenState extends State<KesorHomeScreen> {
  bool _balanceVisible = true;
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
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: _text(20, 28, weight: FontWeight.w500)),
              const SizedBox(height: 12),
              Text(message, style: _text(14, 22, color: _Palette.muted)),
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
      'បញ្ជីរអ្នកទទួល',
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
              title: Text(person.name, style: _text(14, 22, family: 'Poppins')),
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
        title: Text('បន្ថែមអ្នកទទួល', style: _text(20, 28)),
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
        'ប្រតិបត្តិការថ្មីៗ',
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
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
      ),
      child: Theme(
        data: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          fontFamily: 'Google Sans',
          colorScheme: ColorScheme.fromSeed(seedColor: _Palette.navy),
          scaffoldBackgroundColor: Colors.white,
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: _Palette.navy),
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scroll = SingleChildScrollView(
                    key: const PageStorageKey('kesor-home-scroll'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      20,
                      topInset + 10,
                      20,
                      bottomInset + 83,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(),
                        const SizedBox(height: 12),
                        _balanceCard(),
                        if (widget.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              widget.errorMessage!,
                              style: _text(
                                14,
                                22,
                                color: const Color(0xFFB42318),
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
                          'បញ្ជីរអ្នកទទួល',
                          _openRecipients,
                        ),
                        const SizedBox(height: 9),
                        _recipients(),
                        const SizedBox(height: 23),
                        _sectionHeader(
                          'transactions.svg',
                          'ប្រតិបត្តិការថ្មីៗ',
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
                              color: const Color(0xFF1C201C),
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
                  child: Center(child: _Svg('inbox.svg', scale: 28 / 24)),
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
                        color: const Color(0xFFCC0001),
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
      borderRadius: BorderRadius.circular(24),
      child: CustomPaint(
        foregroundPainter: const _BalanceBorder(),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment(0, 2.6526),
              colors: [
                Color(0xB3FFFFFF),
                Color(0xB3F7F1E8),
                Color(0xB3F3E7D2),
                Color(0xB3F0E2C8),
                Color(0xB3EAD8B8),
              ],
              stops: [0, .33, .59, .79, 1],
            ),
          ),
          child: Stack(
            children: [
              const Positioned(
                right: -46.335,
                top: -17.3583,
                child: _BalanceMotif(),
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
                              'សមតុល្យ',
                              style: _text(
                                16,
                                24,
                                color: const Color(0xFFCDA12F),
                                weight: FontWeight.w500,
                              ),
                            ),
                          ),
                          _Tap(
                            label: _balanceVisible
                                ? 'Hide balance'
                                : 'Show balance',
                            onTap: () => setState(
                              () => _balanceVisible = !_balanceVisible,
                            ),
                            child: _FigmaGlass(
                              radius: 26,
                              blurRadius: 10,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0x4DEAEAEA),
                                  borderRadius: BorderRadius.circular(26),
                                ),
                                child: Center(
                                  child: _balanceVisible
                                      ? const _Svg('balance-visibility.svg')
                                      : const Icon(
                                          Icons.visibility_outlined,
                                          size: 24,
                                          color: _Palette.ink,
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
                                      20,
                                      28,
                                      weight: FontWeight.w500,
                                      family: 'Poppins',
                                    ),
                                  ),
                                  TextSpan(
                                    text: '៛',
                                    style: _text(
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
                              'ប្រាក់រៀលសរុប',
                              style: _text(14, 22, color: _Palette.muted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _balanceVisible
                                  ? widget.data.usdBalance
                                  : r'$••••',
                              key: const ValueKey('home-usd-balance'),
                              style: _text(20, 28, weight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ប្រាក់ដុល្លារសរុប',
                              style: _text(14, 22, color: _Palette.muted),
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
        ? 'ស្កេនកូដ QR'
        : index == 5
        ? 'ផ្ទេរប្រាក់'
        : 'ទូទាត់ប្រាក់';
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
              qr ? 'ស្កេនកូដ QR' : 'ទូទាត់ប្រាក់',
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
                  14,
                  22,
                  weight: FontWeight.w500,
                  family: qr ? 'Noto Sans Khmer' : 'Google Sans',
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
          style: _text(16, 24, color: _Palette.navy, weight: FontWeight.w500),
        ),
      ),
      _Tap(
        label: title == 'បញ្ជីរអ្នកទទួល'
            ? 'All recipients'
            : 'All transactions',
        onTap: onAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Row(
            children: [
              Text('ទាំងអស់', style: _text(14, 22, color: _Palette.muted)),
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
      if (extra == 0) return 65;
      final measure = TextPainter(
        text: TextSpan(
          text: person.name,
          style: _text(12, 18, family: 'Poppins'),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = math.max(65.0, measure.width + 16);
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
                  child: OverflowBox(
                    minWidth: math.max(100, recipientWidth(person)),
                    maxWidth: math.max(100, recipientWidth(person)),
                    child: Text(
                      person.name,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: _text(
                        12,
                        18,
                        color: Colors.black,
                        family: 'Poppins',
                      ),
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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFEEEEEE),
                ),
                child: const Center(child: _Svg('plus.svg')),
              ),
              const SizedBox(height: 2),
              Text(
                'បន្ថែម',
                maxLines: 1,
                softWrap: false,
                style: _text(14, 18, color: Colors.black),
              ),
            ],
          ),
        ),
      ),
    ];
    return Container(
      constraints: const BoxConstraints(minHeight: 94),
      decoration: BoxDecoration(
        border: Border.all(color: _Palette.border),
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
              children: children,
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
          entry.dateLabel ?? (entry.previousDay ? 'ម្សិលមិញ' : 'ថ្ងៃនេះ');
      groups.putIfAbsent(label, () => []).add(entry);
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _Palette.border),
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
                'មិនទាន់មានប្រតិបត្តិការ · No activity yet',
                style: _text(14, 22, color: _Palette.muted),
              ),
            ),
          for (final group in groups.entries) ...[
            if (group.key != groups.keys.first) const SizedBox(height: 12),
            Text(group.key, style: _text(14, 22, color: _Palette.muted)),
            const SizedBox(height: 12),
            for (int i = 0; i < group.value.length; i++) ...[
              if (i != 0) const SizedBox(height: 10),
              _transactionRow(
                group.value[i],
                first: group.key == 'ថ្ងៃនេះ' && i == 0,
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
                  14,
                  first ? 24 : 18,
                  color: const Color(0xFF0A0A0B),
                  family: 'Poppins',
                ),
              ),
              Text(
                entry.time,
                style: _text(
                  12,
                  16,
                  color: const Color(0xFF717182),
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
              14,
              first ? 28 : 18,
              color: entry.incoming ? _Palette.navy : const Color(0xFFEF4444),
              family: first ? 'Google Sans' : 'Poppins',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _navigation() => Row(
    children: [
      Expanded(
        child: Container(
          height: 64,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F1EE),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Row(
            children: [
              _navItem('nav-home.svg', 'ទំព័រដើម', 'Home', true, () {}),
              _navItem(
                'nav-analytics.svg',
                'ការវិភាគ',
                'Activity',
                false,
                _activity,
              ),
              _navItem(
                'nav-settings.svg',
                'ការកំណត់',
                'Profile',
                false,
                widget.onProfile ?? () => _showPanel('ការកំណត់', 'Settings'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 16),
      _Tap(
        label: 'AI assistant',
        onTap: () => _showPanel('ជំនួយការ AI', 'AI assistant'),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF9DCE9), Color(0xFFF5F6EA), Color(0xFFDFF4E2)],
              stops: [0, .5, 1],
            ),
          ),
          child: const Center(child: _Svg('ai-sun.svg')),
        ),
      ),
    ],
  );

  Widget _navItem(
    String icon,
    String text,
    String label,
    bool selected,
    VoidCallback onTap,
  ) => Expanded(
    child: _Tap(
      label: label,
      selected: selected,
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: selected ? const Color(0x33B8944F) : null,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Svg(icon),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: _text(
                  11,
                  16,
                  color: selected ? _Palette.gold : const Color(0xFF222722),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
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
          backgroundColor: const Color(0xFFF0E9DB),
          child: Text(
            name.characters.first.toUpperCase(),
            style: _text(size / 3, size / 2, color: _Palette.navy),
          ),
        );
}

class _Tap extends StatelessWidget {
  const _Tap({
    required this.label,
    required this.onTap,
    required this.child,
    this.selected,
  });
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool? selected;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    selected: selected,
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
  const _Svg(this.name, {this.scale = 1});
  final String name;
  final double scale;
  static const _sizes = <String, Size>{
    'kesor-logo.svg': Size(37.3334, 46.6627),
    'khqr-mark.svg': Size(15, 16),
    'rosette.svg': Size(18.675, 18.5323),
    'inbox.svg': Size(24, 24),
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
      width: size.width * scale,
      height: size.height * scale,
      child: FittedBox(
        child: SvgPicture.asset(
          'assets/home/$name',
          width: size.width,
          height: size.height,
          excludeFromSemantics: true,
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
  const _BalanceBorder();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(.5), const Radius.circular(23.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x80B8944F), Color(0xCCE5E7E3)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _BalanceBorder oldDelegate) => false;
}

/// Keeps the exported SVG intact and translates Figma's progressive layer blur.
/// Flutter's SVG renderer ignores SVG filter tags, so the blur is applied here.
class _BalanceMotif extends StatelessWidget {
  const _BalanceMotif();
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
                        child: const _Svg('balance-motif.svg'),
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
      color: Colors.white,
      height: 54,
      child: Stack(
        children: [
          Positioned(
            left: 35.4545,
            top: 16,
            child: Text('9:41', style: _text(17, 22, weight: FontWeight.w500)),
          ),
          const Positioned(right: -4, top: 0, child: _Svg('status-levels.svg')),
        ],
      ),
    ),
  );
}
