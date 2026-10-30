import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/app_labels.dart';
import '../../../core/platform/image_picker.dart';
import '../../../shared/widgets/app_states.dart';
import '../../accounts/accounts_controller.dart';
import '../../auth/session_controller.dart';
import '../../transactions/transfer_controller.dart';
import '../../transactions/presentation/transfer_panel.dart';
import '../qr_controller.dart';
import '../qr_gateway.dart';

class ScanQrPanel extends StatefulWidget {
  const ScanQrPanel({
    required this.session,
    required this.gateway,
    required this.accounts,
    required this.transfers,
    required this.enabled,
    this.chooseImage,
    this.onScanned,
    super.key,
  });
  final SessionController session;
  final QrGateway gateway;
  final AccountsController accounts;
  final TransferController transfers;
  final bool enabled;
  final Future<XFile?> Function()? chooseImage;

  /// When set, a verified scan is handed to the normal transfer screen instead of
  /// continuing in this panel.
  final ValueChanged<QrPreview>? onScanned;
  @override
  State<ScanQrPanel> createState() => _ScanQrPanelState();
}

class _ScanQrPanelState extends State<ScanQrPanel> with WidgetsBindingObserver {
  late final QrController model;
  final camera = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final amount = TextEditingController();
  String? source, inputError;
  bool captured = false, importing = false, starting = false, foreground = true;
  bool get supported =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);
  bool get active =>
      mounted && foreground && widget.session.phase == SessionPhase.signedIn;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model = QrController(widget.session, widget.gateway);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  Future<void> _stop() async {
    try {
      if (camera.value.isRunning) await camera.stop();
    } catch (_) {
      /* Already released by the platform lifecycle. */
    }
  }

  Future<void> _start() async {
    if (!supported ||
        !widget.enabled ||
        !active ||
        starting ||
        importing ||
        captured ||
        model.preview != null ||
        widget.transfers.saved != null ||
        widget.transfers.review != null) {
      return;
    }
    starting = true;
    try {
      await camera.start();
      if (!active || importing || captured) await _stop();
    } on MobileScannerException catch (error) {
      if (active) {
        setState(
          () => inputError =
              error.errorCode == MobileScannerErrorCode.permissionDenied
              ? 'Camera access is denied. Enable it in device settings, or choose a QR image.'
              : 'Camera is unavailable. Retry or choose a QR image.',
        );
      }
    } catch (_) {
      if (active) {
        setState(
          () =>
              inputError = 'Camera is unavailable. Retry or choose a QR image.',
        );
      }
    } finally {
      starting = false;
    }
  }

  Completer<void>? _resume;
  Future<void> _resumed() async {
    if (foreground || !mounted) return;
    _resume ??= Completer<void>();
    await _resume!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && _resume != null) {
      _resume!.complete();
      _resume = null;
    }
    if (!foreground) {
      unawaited(_stop());
    } else {
      unawaited(_start());
    }
  }

  Future<void> _capture(BarcodeCapture capture) async {
    if (!active || captured || importing) return;
    final values = capture.barcodes
        .where((b) => b.format == BarcodeFormat.qrCode)
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .toSet();
    if (values.length != 1) {
      setState(
        () => inputError = 'No QR code was found. Choose another image.',
      );
      return;
    }
    captured = true;
    await _stop();
    if (!active) return;
    if (await model.scan(values.single) && active) {
      final preview = model.preview!;
      final handOff = widget.onScanned;
      // An already-paid fixed request stays here so the panel can explain it.
      if (handOff != null && !preview.paid) {
        handOff(preview);
        return;
      }
      setState(() {
        amount.text = preview.amount?.decimal ?? '';
        source = widget.accounts.accounts
            .where(
              (a) =>
                  a.currency == preview.currency &&
                  a.status == 'ACTIVE' &&
                  a.number != preview.destination,
            )
            .firstOrNull
            ?.number;
        inputError = null;
      });
    }
  }

  Future<void> _import() async {
    if (!supported || !widget.enabled || !active || importing || model.busy) {
      return;
    }
    setState(() {
      importing = true;
      inputError = null;
    });
    await _stop();
    if (!active) return;
    widget.session.beginTrustedImageSelection();
    try {
      final file = await (widget.chooseImage?.call() ?? pickImageFile());
      widget.session.endTrustedImageSelection();
      // The picker result can arrive just before Android resumes the app.
      await _resumed();
      if (file == null || !active) return;
      if (await file.length() > 5 * 1024 * 1024) throw const FormatException();
      final bytes = await file.readAsBytes();
      if (bytes.length < 8 ||
          !(bytes[0] == 0xff && bytes[1] == 0xd8 ||
              bytes[0] == 0x89 &&
                  bytes[1] == 0x50 &&
                  bytes[2] == 0x4e &&
                  bytes[3] == 0x47)) {
        throw const FormatException();
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (descriptor.width * descriptor.height > 16000000) {
            throw const FormatException();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
      if (!active) return;
      final capture = await camera.analyzeImage(
        file.path,
        formats: const [BarcodeFormat.qrCode],
      );
      if (!active) return;
      if (capture == null || capture.barcodes.isEmpty) {
        setState(
          () => inputError = 'No QR code was found. Choose another image.',
        );
        return;
      }
      importing = false;
      captured = false;
      await _capture(capture);
    } on FormatException {
      if (active) {
        setState(
          () => inputError =
              'Choose a JPG or PNG containing one QR code, up to 5 MB.',
        );
      }
    } catch (_) {
      if (active) {
        setState(
          () => inputError = 'No QR code was found. Choose another image.',
        );
      }
    } finally {
      widget.session.endTrustedImageSelection();
      if (mounted) {
        setState(() => importing = false);
        if (active && !captured && model.preview == null) unawaited(_start());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.dispose();
    unawaited(camera.dispose());
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, widget.transfers, widget.accounts]),
    builder: (context, _) {
      if (widget.transfers.saved != null || widget.transfers.review != null) {
        return TransferPanel(
          controller: widget.transfers,
          accounts: widget.accounts,
          enabled: widget.enabled,
          onDone: () {
            model.clearPreview();
            setState(() {
              captured = false;
              inputError = null;
              amount.clear();
              source = null;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _start();
            });
          },
        );
      }
      final preview = model.preview;
      final eligible = widget.accounts.accounts
          .where(
            (a) =>
                a.currency == preview?.currency &&
                a.status == 'ACTIVE' &&
                a.number != preview?.destination,
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (model.busy || importing) const LinearProgressIndicator(),
          if (model.error != null)
            NoticePanel(tx(context, model.error!.message), error: true),
          if (inputError != null)
            NoticePanel(tx(context, inputError!), error: true),
          if (preview == null) ...[
            if (!supported)
              NoticePanel(
                tx(
                  context,
                  'Camera and image scanning are available in the Android and iOS app.',
                ),
              )
            else if (!widget.enabled)
              NoticePanel(tx(context, 'QR features require the API app.'))
            else ...[
              Text(tx(context, 'Point your camera at a Kesor account QR.')),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 280,
                  child: MobileScanner(
                    controller: camera,
                    onDetect: _capture,
                    errorBuilder: (context, error) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: SingleChildScrollView(
                          child: Text(
                            tx(
                              context,
                              error.errorCode ==
                                      MobileScannerErrorCode.permissionDenied
                                  ? 'Camera access is denied. Enable it in device settings, or choose a QR image.'
                                  : 'Camera is unavailable. Retry or choose a QR image.',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: importing || model.busy ? null : _import,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(tx(context, 'Choose QR image')),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        await camera.toggleTorch();
                      } catch (_) {
                        /* Torch is optional on devices without one. */
                      }
                    },
                    icon: const Icon(Icons.flashlight_on_outlined),
                    label: Text(tx(context, 'Torch')),
                  ),
                ],
              ),
            ],
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tx(context, 'Recipient'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      preview.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(preview.destination),
                    Text(preview.currency),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (eligible.isEmpty)
              NoticePanel(
                tx(context, 'No active source account matches this currency.'),
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey('qr-source-$source'),
                initialValue: eligible.any((a) => a.number == source)
                    ? source
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tx(context, 'Source account'),
                ),
                items: eligible
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.number,
                        child: Text(
                          '${a.currency} · ${a.number}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => source = value),
              ),
            if (source != null && eligible.any((a) => a.number == source))
              Text(
                eligible
                    .firstWhere((a) => a.number == source)
                    .balance
                    .formatted,
              ),
            if (widget.accounts.detailError != null)
              NoticePanel(
                tx(context, widget.accounts.detailError!.message),
                error: true,
              ),
            if (widget.accounts.hasMore)
              TextButton(
                onPressed: widget.accounts.loadingMore
                    ? null
                    : widget.accounts.loadMore,
                child: Text(tx(context, 'Load more accounts')),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('qr-transfer-amount'),
              controller: amount,
              readOnly: preview.dynamic,
              decoration: InputDecoration(
                labelText: '${tx(context, 'Amount')} (${preview.currency})',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 24),
            if (widget.transfers.error != null)
              NoticePanel(
                tx(context, widget.transfers.error!.message),
                error: true,
              ),
            BusyButton(
              label: tx(context, 'Review transfer'),
              busy: widget.transfers.busy,
              onPressed:
                  !widget.enabled ||
                      source == null ||
                      !widget.transfers.ready ||
                      widget.transfers.storageError != null
                  ? null
                  : () async {
                      final account = eligible
                          .where((a) => a.number == source)
                          .firstOrNull;
                      if (account == null) return;
                      await widget.accounts.select(account);
                      if (!active) return;
                      final fresh = widget.accounts.selected;
                      if (fresh == null ||
                          fresh.number != account.number ||
                          widget.accounts.detailError != null) {
                        return;
                      }
                      widget.transfers.prepare(
                        fresh,
                        preview.destination,
                        amount.text,
                        preview.remark ?? '',
                        qrString: preview.payload,
                        destinationName: preview.name,
                      );
                    },
            ),
          ],
          const SizedBox(height: 16),
          if (supported && widget.enabled)
            TextButton(
              onPressed: model.busy || importing
                  ? null
                  : () async {
                      model.clearPreview();
                      widget.transfers.edit();
                      setState(() {
                        captured = false;
                        inputError = null;
                        amount.clear();
                        source = null;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _start();
                      });
                    },
              child: Text(tx(context, 'Scan again')),
            ),
        ],
      );
    },
  );
}
