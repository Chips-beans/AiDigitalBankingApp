import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../../../core/platform/image_picker.dart';
import '../data/profile_photo.dart';
import '../session_controller.dart';

class ProfilePhotoCard extends StatefulWidget {
  const ProfilePhotoCard(
    this.session, {
    this.displayName,
    this.chooseImage,
    super.key,
  });
  final SessionController session;
  final String? displayName;
  final Future<XFile?> Function()? chooseImage;
  @override
  State<ProfilePhotoCard> createState() => _ProfilePhotoCardState();
}

class _ProfilePhotoCardState extends State<ProfilePhotoCard> {
  String? error;
  bool picking = false;
  Uint8List? preview;
  int selectionRevision = 0;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(clearPrivatePreview);
    // Do not notify the enclosing session builder during its build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.session.loadProfilePhoto());
    });
  }

  void clearPrivatePreview() {
    // Opening the gallery makes the app inactive and raises the privacy cover; that
    // must not cancel the trusted selection in progress (the cover still hides it).
    if (widget.session.phase != SessionPhase.signedIn ||
        (widget.session.privacyCovered &&
            !widget.session.trustedImageSelection)) {
      selectionRevision++;
      preview = null;
      error = null;
      picking = false;
    }
  }

  @override
  void didUpdateWidget(covariant ProfilePhotoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(clearPrivatePreview);
      widget.session.addListener(clearPrivatePreview);
      selectionRevision++;
      preview = null;
      error = null;
      picking = false;
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(clearPrivatePreview);
    super.dispose();
  }

  Future<void> choose() async {
    final session = widget.session;
    if (picking ||
        session.busy ||
        session.photoBusy ||
        session.privacyCovered) {
      return;
    }
    final user = session.identity?.userId;
    final revision = ++selectionRevision;
    bool current() =>
        mounted &&
        widget.session == session &&
        revision == selectionRevision &&
        session.identity?.userId == user &&
        // The privacy cover may still be up while the picker result arrives (before
        // resume). A slow (>60 s) selection locks the app and fails this phase check.
        session.phase == SessionPhase.signedIn;
    setState(() {
      picking = true;
      error = null;
    });
    try {
      session.beginPhotoSelection();
      final file = await (widget.chooseImage?.call() ?? pickImageFile());
      session.endPhotoSelection();
      if (file == null || !current()) return;
      if (await file.length() > maxProfilePhotoBytes) {
        if (current()) {
          setState(
            () => error = tr(
              context,
              'Choose a JPG or PNG up to 5 MB.',
              'សូមជ្រើសរើស JPG ឬ PNG មិនលើស 5 MB។',
            ),
          );
        }
        return;
      }
      final bytes = await file.readAsBytes();
      if (!current()) return;
      // Preview locally while the existing authenticated upload confirms saving.
      setState(() => preview = bytes);
      await session.saveProfilePhoto(bytes);
    } catch (_) {
      if (current()) {
        setState(
          () => error = tr(
            context,
            'The photo could not be opened. Please try again.',
            'មិនអាចបើករូបថតបានទេ។ សូមព្យាយាមម្ដងទៀត។',
          ),
        );
      }
    } finally {
      if (revision == selectionRevision && widget.session == session) {
        session.endPhotoSelection();
        if (mounted) {
          setState(() {
            picking = false;
            preview = null;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      final colors = AppColors.of(context);
      final text = AppTextStyles.of(context);
      final dark = Theme.of(context).brightness == Brightness.dark;
      final name = (widget.displayName ?? session.identity?.displayName ?? '')
          .trim();
      final bytes = preview ?? session.profilePhoto?.bytes;
      final fallback = name.isEmpty
          ? SvgPicture.asset(
              'assets/auth/email-profile-user.svg',
              width: 36,
              height: 36,
              excludeFromSemantics: true,
            )
          : Text(
              name.characters.first.toUpperCase(),
              key: const ValueKey('profile-photo-initial'),
              style: text.titleXL.copyWith(
                color: colors.accent500,
                fontSize: 32,
                height: 1,
              ),
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              semanticsLabel: tr(
                context,
                'Default profile picture for $name',
                'រូបភាពប្រវត្តិរូបលំនាំដើមសម្រាប់ $name',
              ),
            );
      final action = preview != null
          ? tr(context, 'Uploading photo…', 'កំពុងបញ្ចូលរូបថត…')
          : tr(
              context,
              session.profilePhoto == null ? 'Upload photo' : 'Change photo',
              session.profilePhoto == null ? 'បញ្ចូលរូបថត' : 'ប្ដូររូបថត',
            );
      final photo = Container(
        key: const ValueKey('profile-photo-avatar'),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: colors.primary100,
          shape: BoxShape.circle,
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: bytes != null
            ? Image.memory(
                bytes,
                width: 80,
                height: 80,
                cacheWidth: (80 * MediaQuery.devicePixelRatioOf(context))
                    .ceil(),
                fit: BoxFit.cover,
                semanticLabel: tr(
                  context,
                  'Your profile photo',
                  'រូបថតប្រវត្តិរូបរបស់អ្នក',
                ),
                errorBuilder: (_, error, stack) => fallback,
              )
            : fallback,
      );
      final uploadVisual = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (session.photoBusy || picking)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            SvgPicture.asset(
              'assets/auth/email-profile-camera.svg',
              width: 16,
              height: 16,
              excludeFromSemantics: true,
              colorFilter: dark
                  ? ColorFilter.mode(colors.primary400, BlendMode.srcIn)
                  : null,
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              action,
              style: text.button.copyWith(
                color: dark ? colors.primary400 : colors.primary700,
              ),
            ),
          ),
        ],
      );
      final details = Stack(
        children: [
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(context, 'Profile photo', 'រូបថតប្រវត្តិរូប'),
                  style: text.button.copyWith(
                    color: dark ? colors.foreground : colors.accent500,
                  ),
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 28),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: uploadVisual,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    context,
                    'Optional · JPG or PNG, up to 5 MB',
                    'ជាជម្រើស · JPG ឬ PNG មិនលើស 5 MB',
                  ),
                  style: text.caption.copyWith(
                    color: colors.disabledBackground,
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: TextButton(
              key: const ValueKey('upload-profile-photo'),
              onPressed: session.busy || session.photoBusy || picking
                  ? null
                  : choose,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: Semantics(label: action, child: const SizedBox.expand()),
            ),
          ),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('profile-photo-card'),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth < 250 ||
                    MediaQuery.textScalerOf(context).scale(14) > 24) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [photo, const SizedBox(height: 16), details],
                  );
                }
                // The 48px upload target overlaps the gaps around its 28px visual row.
                return Row(
                  children: [
                    photo,
                    const SizedBox(width: 16),
                    Expanded(child: details),
                  ],
                );
              },
            ),
          ),
          if (error != null || session.photoFailure != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error ?? session.photoFailure!.message,
                  style: text.caption.copyWith(color: colors.error),
                ),
              ),
            ),
          if (session.photoFailure != null && !session.photoLoaded)
            TextButton(
              onPressed: session.photoBusy ? null : session.loadProfilePhoto,
              child: Text(
                tr(context, 'Retry loading photo', 'ព្យាយាមផ្ទុករូបថតម្ដងទៀត'),
              ),
            ),
        ],
      );
    },
  );
}
