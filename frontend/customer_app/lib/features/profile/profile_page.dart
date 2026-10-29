import 'package:flutter/material.dart';

import '../../shared/widgets/app_states.dart';
import '../auth/session_controller.dart';
import '../auth/presentation/profile_photo_card.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage(this.session, {super.key});
  final SessionController session;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'You’re signed in.',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 24),
      ProfilePhotoCard(session),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('NAME'),
              const SizedBox(height: 8),
              SelectableText(
                session.identity!.displayName.isEmpty
                    ? session.identity!.username
                    : session.identity!.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              const Text('EMAIL'),
              const SizedBox(height: 8),
              SelectableText(
                session.identity!.email ?? 'No recovery email connected',
              ),
              const SizedBox(height: 16),
              Text(
                session.identity!.telegramLinked
                    ? 'Telegram connected'
                    : 'Telegram not connected',
              ),
              if (!session.identity!.telegramLinked)
                TextButton(
                  onPressed: session.busy ? null : session.continueTelegram,
                  child: const Text('Connect Telegram'),
                ),
              if (session.identity!.email == null)
                TextButton(
                  onPressed: session.busy
                      ? null
                      : () => session.openEmail(link: true),
                  child: const Text('Add recovery email'),
                ),
              if (session.telegramPending)
                TextButton(
                  onPressed: session.cancelTelegram,
                  child: const Text('Cancel Telegram approval'),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      if (session.failure != null) ...[
        NoticePanel(session.failure!.message, error: true),
        const Text(
          'Profile refresh failed. Showing the last verified identity.',
        ),
      ],
      if (session.notice != null) NoticePanel(session.notice!),
      TextButton(
        onPressed: session.busy ? null : session.refreshProfile,
        child: const Text('Refresh identity'),
      ),
      const SizedBox(height: 16),
      // Sign-out remains available during pending reads/profile renewal.
      FilledButton(onPressed: session.signOut, child: const Text('Sign out')),
    ],
  );
}
