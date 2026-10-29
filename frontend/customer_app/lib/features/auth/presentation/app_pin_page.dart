import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../session_controller.dart';

class AppPinPage extends StatefulWidget {
  const AppPinPage(this.session, {super.key});
  final SessionController session;
  @override
  State<AppPinPage> createState() => _AppPinPageState();
}

class _AppPinPageState extends State<AppPinPage> {
  final input = TextEditingController();
  final focus = FocusNode();
  late PinStage lastStage;
  late int lastEntryRevision;
  @override
  void initState() {
    super.initState();
    lastStage = widget.session.pinStage;
    lastEntryRevision = widget.session.pinEntryRevision;
    widget.session.addListener(changed);
  }

  void changed() {
    final session = widget.session;
    if (lastStage != session.pinStage ||
        lastEntryRevision != session.pinEntryRevision ||
        (!session.busy && session.failure != null)) {
      input.clear();
    }
    lastStage = session.pinStage;
    lastEntryRevision = session.pinEntryRevision;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(changed);
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  void enter(String value) {
    if (widget.session.busy) return;
    setState(
      () => input.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      ),
    );
    if (value.length == 4) unawaited(widget.session.submitPin(value));
  }

  void back() {
    if (widget.session.busy) return;
    if (widget.session.pinStage == PinStage.confirm) {
      widget.session.restartPinSetup();
    } else {
      unawaited(widget.session.signOut());
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) back();
    },
    child: PinScreen(
      stage: widget.session.pinStage,
      name:
          widget.session.pinChallenge?.displayName ??
          widget.session.identity?.displayName ??
          '',
      enteredDigits: input.text.length,
      busy: widget.session.busy || widget.session.pinStage == PinStage.checking,
      message: widget.session.failure?.message,
      blocked: widget.session.pinChallenge?.recoveryRequired ?? false,
      attemptsRemaining: widget.session.pinChallenge?.attemptsRemaining,
      photoBytes: widget.session.profilePhoto?.bytes,
      input: input,
      focus: focus,
      onChanged: enter,
      onNumber: (value) {
        if (input.text.length < 4) enter('${input.text}$value');
      },
      onClear: () => enter(''),
      onDelete: () {
        if (input.text.isNotEmpty) {
          enter(input.text.substring(0, input.text.length - 1));
        }
      },
      onForgot: () => widget.session.forgotPin(),
      onBack: back,
      onRetry: () => widget.session.restorePinStatus(),
    ),
  );
}

/// Live controls from Figma 264:630, 253:1161 and 253:1309.
/// Decorative backdrop contains no customer accounts, history or network calls.
class PinScreen extends StatelessWidget {
  const PinScreen({
    required this.stage,
    required this.name,
    this.enteredDigits = 0,
    this.busy = false,
    this.blocked = false,
    this.message,
    this.attemptsRemaining,
    this.photoBytes,
    this.input,
    this.focus,
    this.onChanged,
    this.onNumber,
    this.onClear,
    this.onDelete,
    this.onForgot,
    this.onBack,
    this.onRetry,
    this.showDeviceChrome = false,
    super.key,
  });
  final PinStage stage;
  final String name;
  final int enteredDigits;
  final bool busy, blocked, showDeviceChrome;
  final String? message;
  final int? attemptsRemaining;
  final Uint8List? photoBytes;
  final TextEditingController? input;
  final FocusNode? focus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<int>? onNumber;
  final VoidCallback? onClear, onDelete, onForgot, onBack, onRetry;
  bool get unlock => stage == PinStage.unlock;
  @override
  Widget build(BuildContext context) {
    final title = stage == PinStage.confirm
        ? tr(context, 'Confirm PIN', 'បញ្ជាក់លេខសម្ងាត់')
        : unlock
        ? tr(context, 'Enter PIN', 'បញ្ចូលលេខសម្ងាត់')
        : tr(context, 'Create your PIN', 'បង្កើតលេខសម្ងាត់របស់អ្នក');
    final description = stage == PinStage.confirm
        ? tr(
            context,
            'Fill your 4-digit PIN again to Confirm',
            'បញ្ចូលលេខសម្ងាត់ ៤ ខ្ទង់ម្ដងទៀតដើម្បីបញ្ជាក់',
          )
        : tr(
            context,
            'Set up a 4-digit PIN to secure Account',
            'បង្កើតលេខសម្ងាត់ ៤ ខ្ទង់ដើម្បីការពារគណនី',
          );
    final khmer = AppPreferences.maybeOf(context)?.isKhmer ?? false;
    TextStyle text(
      double size,
      double height,
      FontWeight weight, [
      Color color = Colors.white,
    ]) => TextStyle(
      fontFamily: khmer
          ? AppTypography.khmerFamily
          : AppTypography.englishFamily,
      fontFamilyFallback: AppTypography.fallbackFamilies,
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      color: color,
      letterSpacing: 0,
    );
    return Scaffold(
      backgroundColor: AppPalette.navy700,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(showDeviceChrome ? 38 : 0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ExcludeSemantics(
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.noScaling),
                    child: const RepaintBoundary(child: _PinBackdrop()),
                  ),
                ),
                ColoredBox(
                  color: const Color(0xFF091C32).withValues(alpha: .35),
                ),
                BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: ColoredBox(
                    color: AppPalette.navy700.withValues(alpha: .6),
                  ),
                ),
                SafeArea(
                  top: !showDeviceChrome,
                  bottom: !showDeviceChrome,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final keypadWidth = math.min(356.0, box.maxWidth - 32);
                      final gap = box.maxWidth < 350 ? 24.0 : 28.0;
                      final keySize = (keypadWidth - 2 * gap) / 3;
                      Widget key(int? digit, {bool remove = false}) {
                        final disabled = busy || (blocked && digit != null);
                        final label =
                            digit?.toString() ??
                            (remove
                                ? tr(context, 'Delete digit', 'លុបលេខមួយខ្ទង់')
                                : unlock
                                ? tr(context, 'Forgot PIN?', 'ភ្លេចលេខសម្ងាត់?')
                                : tr(context, 'Clear', 'សម្អាត'));
                        return SizedBox(
                          width: keySize,
                          height: keySize,
                          child: TextButton(
                            key: ValueKey(
                              digit == null
                                  ? remove
                                        ? 'pin-delete'
                                        : unlock
                                        ? 'pin-forgot'
                                        : 'pin-clear'
                                  : 'pin-digit-$digit',
                            ),
                            onPressed: disabled
                                ? null
                                : digit != null
                                ? () => onNumber?.call(digit)
                                : remove
                                ? onDelete
                                : unlock
                                ? onForgot
                                : onClear,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              foregroundColor: digit == null && !remove
                                  ? AppPalette.gold400
                                  : Colors.white,
                              disabledForegroundColor: Colors.white54,
                              backgroundColor: digit == null
                                  ? Colors.transparent
                                  : Colors.white.withValues(alpha: .07),
                              shape: CircleBorder(
                                side: digit == null
                                    ? BorderSide.none
                                    : BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: .31,
                                        ),
                                        width: 1.5,
                                      ),
                              ),
                              textStyle: digit == null
                                  ? text(14, 21, FontWeight.w500)
                                  : text(28, 36, FontWeight.w300),
                            ),
                            child: remove
                                ? SvgPicture.asset(
                                    'assets/pin/delete.svg',
                                    width: 28,
                                    height: 28,
                                    semanticsLabel: label,
                                  )
                                : Text(label, textAlign: TextAlign.center),
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: showDeviceChrome ? 86 : 32,
                              bottom: 30,
                            ),
                            child: Column(
                              children: [
                                Container(
                                  key: const ValueKey('pin-avatar'),
                                  width: 80,
                                  height: 80,
                                  decoration: const BoxDecoration(
                                    color: AppPalette.gold100,
                                    shape: BoxShape.circle,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  alignment: Alignment.center,
                                  child: photoBytes == null
                                      ? SvgPicture.asset(
                                          'assets/auth/email-profile-user.svg',
                                          width: 36,
                                          height: 36,
                                          excludeFromSemantics: true,
                                        )
                                      : Image.memory(
                                          photoBytes!,
                                          fit: BoxFit.cover,
                                          width: 80,
                                          height: 80,
                                          semanticLabel: tr(
                                            context,
                                            'Your profile photo',
                                            'រូបថតប្រវត្តិរូបរបស់អ្នក',
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 10),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Text(
                                    name,
                                    style: text(18, 27, FontWeight.w600),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 36),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                  ),
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      title,
                                      style: text(26, 39, FontWeight.w700),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                if (!unlock) ...[
                                  const SizedBox(height: 6),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 32,
                                    ),
                                    child: Text(
                                      description,
                                      style: text(
                                        14,
                                        22,
                                        FontWeight.w400,
                                        Colors.white.withValues(alpha: .69),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 27),
                                Semantics(
                                  label: tr(
                                    context,
                                    'Four-digit PIN',
                                    'លេខសម្ងាត់ ៤ ខ្ទង់',
                                  ),
                                  value: tr(
                                    context,
                                    '$enteredDigits of 4 digits entered',
                                    'បានបញ្ចូល $enteredDigits ខ្ទង់ ក្នុងចំណោម ៤ ខ្ទង់',
                                  ),
                                  child: SizedBox(
                                    width: 148,
                                    height: 48,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        ExcludeSemantics(
                                          child: SizedBox(
                                            width: 148,
                                            height: 22,
                                            child: Stack(
                                              children: [
                                                SvgPicture.asset(
                                                  'assets/pin/indicators.svg',
                                                  width: 148,
                                                  height: 22,
                                                ),
                                                for (
                                                  int i = 0;
                                                  i < enteredDigits.clamp(0, 4);
                                                  i++
                                                )
                                                  Positioned(
                                                    left: i * 42,
                                                    width: 22,
                                                    height: 22,
                                                    child: const DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        color:
                                                            AppPalette.gold400,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                  ),
                                                if (enteredDigits > 0 &&
                                                    enteredDigits < 4)
                                                  Positioned(
                                                    left: enteredDigits * 42,
                                                    width: 22,
                                                    height: 22,
                                                    child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: AppPalette
                                                              .gold400,
                                                          width: 2,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (input != null)
                                          Positioned.fill(
                                            child: TextField(
                                              key: const ValueKey('pin-input'),
                                              controller: input,
                                              focusNode: focus,
                                              enabled: !busy && !blocked,
                                              keyboardType: TextInputType.none,
                                              obscureText: true,
                                              showCursor: false,
                                              autocorrect: false,
                                              enableSuggestions: false,
                                              style: const TextStyle(
                                                fontSize: 1,
                                                color: Colors.transparent,
                                              ),
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                                LengthLimitingTextInputFormatter(
                                                  4,
                                                ),
                                              ],
                                              decoration: const InputDecoration(
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                disabledBorder:
                                                    InputBorder.none,
                                                filled: false,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                              onChanged: onChanged,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (busy)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 12),
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: AppPalette.gold400,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                if (message != null || blocked)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      12,
                                      24,
                                      0,
                                    ),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        blocked
                                            ? tr(
                                                context,
                                                'Five incorrect attempts. Verify your identity to reset your PIN.',
                                                'បញ្ចូលខុសប្រាំដង។ សូមផ្ទៀងផ្ទាត់អត្តសញ្ញាណដើម្បីកំណត់លេខសម្ងាត់ឡើងវិញ។',
                                              )
                                            : message!,
                                        style: text(
                                          14,
                                          22,
                                          FontWeight.w400,
                                          AppPalette.gold100,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                if (message != null &&
                                    !blocked &&
                                    attemptsRemaining != null &&
                                    unlock &&
                                    attemptsRemaining! < 5)
                                  Text(
                                    tr(
                                      context,
                                      '$attemptsRemaining attempts remaining',
                                      'នៅសល់ $attemptsRemaining ដង',
                                    ),
                                    style: text(
                                      12,
                                      20,
                                      FontWeight.w400,
                                      Colors.white70,
                                    ),
                                  ),
                                if (message != null &&
                                    !blocked &&
                                    (message!.contains('connection') ||
                                        message!.contains('reach') ||
                                        message!.contains('long')))
                                  TextButton(
                                    onPressed: busy ? null : onRetry,
                                    child: Text(
                                      tr(
                                        context,
                                        'Try again',
                                        'ព្យាយាមម្ដងទៀត',
                                      ),
                                      style: text(
                                        14,
                                        22,
                                        FontWeight.w500,
                                        AppPalette.gold400,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 31),
                                SizedBox(
                                  width: keypadWidth,
                                  child: Column(
                                    children: [
                                      for (final row in [
                                        [1, 2, 3],
                                        [4, 5, 6],
                                        [7, 8, 9],
                                      ]) ...[
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: row.map(key).toList(),
                                        ),
                                        const SizedBox(height: 14),
                                      ],
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          key(null),
                                          key(0),
                                          key(null, remove: true),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (stage == PinStage.confirm &&
                                    message != null)
                                  TextButton(
                                    onPressed: busy ? null : onBack,
                                    child: Text(
                                      tr(
                                        context,
                                        'Change PIN',
                                        'ប្ដូរលេខសម្ងាត់',
                                      ),
                                      style: text(
                                        12,
                                        20,
                                        FontWeight.w500,
                                        AppPalette.gold400,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (showDeviceChrome)
                  Positioned(
                    bottom: 8,
                    left: 153,
                    width: 134,
                    height: 5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .38),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma's empty Home scaffold is decorative and never instantiates banking controllers.
class _PinBackdrop extends StatelessWidget {
  const _PinBackdrop();
  @override
  Widget build(BuildContext context) {
    Widget svg(String name) => SvgPicture.asset('assets/pin/$name.svg');
    TextStyle body(
      double size, {
      FontWeight weight = FontWeight.w400,
      Color color = AppPalette.navy500,
    }) => TextStyle(
      fontFamily: 'Poppins',
      fontSize: size,
      height: 1.5,
      fontWeight: weight,
      color: color,
    );
    Widget card(Widget child, {double radius = 16}) => Container(
      decoration: BoxDecoration(
        color: AppPalette.neutralLightSurface,
        border: Border.all(color: AppPalette.neutralLightBorder),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
    return FittedBox(
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 440,
        height: 999,
        child: ColoredBox(
          color: Colors.white,
          child: Stack(
            children: [
              Positioned(
                left: 29.33,
                top: 69.33,
                width: 37.34,
                height: 46.66,
                child: svg('logo'),
              ),
              Positioned(
                left: 348,
                top: 78,
                width: 28,
                height: 28,
                child: svg('inbox'),
              ),
              Positioned(
                left: 392,
                top: 78,
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppPalette.semanticError,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: svg('smartphone'),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                top: 132,
                width: 400,
                height: 312,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppPalette.gold200),
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, AppPalette.gold100],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: svg('crosshair'),
                          ),
                          const SizedBox(width: 8),
                          Text('សមតុល្យ', style: body(16)),
                          const Spacer(),
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: svg('eye-off'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text('0 ៛', style: body(20, weight: FontWeight.w500)),
                      Text('ប្រាក់រៀលសរុប', style: body(14)),
                      Text(r'$0.00', style: body(20, weight: FontWeight.w500)),
                      Text('ប្រាក់ដុល្លារសរុប', style: body(14)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final entry in [
                            ('card', 'ទូទាត់ប្រាក់'),
                            ('qr', 'ស្កេនកូដ QR'),
                            ('transfer', 'ផ្ទេរប្រាក់'),
                          ]) ...[
                            if (entry.$1 != 'card') const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 82,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE1F9D9),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: Center(child: svg(entry.$1)),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(entry.$2, style: body(14)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                top: 473,
                width: 400,
                child: Text('បញ្ជីរអ្នកទទួល', style: body(18)),
              ),
              Positioned(
                left: 20,
                top: 513,
                width: 400,
                height: 94,
                child: card(
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your people, one tap away',
                          style: body(14, weight: FontWeight.w600),
                        ),
                        Text(
                          'Add a recipient after your first transfer.',
                          style: body(12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                top: 627,
                width: 400,
                child: Text('ប្រតិបត្តិការថ្មីៗ', style: body(18)),
              ),
              Positioned(
                left: 20,
                top: 662,
                width: 400,
                height: 228,
                child: card(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 36, height: 36, child: svg('receipt')),
                      const SizedBox(height: 12),
                      Text(
                        'Ready for your first transaction',
                        style: body(14, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your riel and dollar wallets are ready to use.',
                        style: body(12),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                top: 911,
                width: 320,
                height: 64,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppPalette.neutralLightSurface,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Row(
                    children: [
                      for (final name in ['home', 'analytics', 'settings'])
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: name == 'home'
                                  ? AppPalette.gold100
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: svg('nav-$name'),
                                ),
                                Text(name, style: body(11)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 356,
                top: 911,
                width: 64,
                height: 64,
                child: svg('assistant'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
