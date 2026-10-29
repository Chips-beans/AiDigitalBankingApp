import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/app_preferences.dart';
import '../../../app/design_system/design_system.dart';
import '../data/profile_photo.dart';
import '../session_controller.dart';

class ProfilePhotoCard extends StatefulWidget {
  const ProfilePhotoCard(this.session, {super.key});
  final SessionController session;
  @override
  State<ProfilePhotoCard> createState() => _ProfilePhotoCardState();
}

class _ProfilePhotoCardState extends State<ProfilePhotoCard> {
  String? error;
  bool picking = false;
  @override
  void initState() {
    super.initState();
    // Do not notify the enclosing session builder during its build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.session.loadProfilePhoto());
    });
  }

  Future<void> choose() async {
    final session = widget.session;
    if (picking || session.busy || session.photoBusy) return;
    final user = session.identity?.userId;
    setState(() {
      picking = true;
      error = null;
    });
    try {
      session.beginPhotoSelection();
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'JPG or PNG',
            extensions: ['jpg', 'jpeg', 'png'],
            mimeTypes: ['image/jpeg', 'image/png'],
            uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
          ),
        ],
      );
      session.endPhotoSelection();
      if (file == null ||
          !mounted ||
          session.identity?.userId != user ||
          session.phase != SessionPhase.signedIn) {
        return;
      }
      if (await file.length() > maxProfilePhotoBytes) {
        if (mounted) {
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
      if (!mounted || session.identity?.userId != user) return;
      await session.saveProfilePhoto(bytes);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = tr(
            context,
            'The photo could not be opened. Please try again.',
            'មិនអាចបើករូបថតបានទេ។ សូមព្យាយាមម្ដងទៀត។',
          ),
        );
      }
    } finally {
      session.endPhotoSelection();
      if (mounted) setState(() => picking = false);
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
      final action = tr(
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
        child: session.profilePhoto != null
            ? Image.memory(
                session.profilePhoto!.bytes,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                semanticLabel: tr(
                  context,
                  'Your profile photo',
                  'រូបថតប្រវត្តិរូបរបស់អ្នក',
                ),
                errorBuilder: (_, error, stack) =>
                    const Icon(Icons.person_outline, size: 36),
              )
            : SvgPicture.asset(
                'assets/auth/email-profile-user.svg',
                width: 36,
                height: 36,
                excludeFromSemantics: true,
              ),
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
