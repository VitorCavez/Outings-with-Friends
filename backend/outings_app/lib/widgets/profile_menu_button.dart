// lib/widgets/profile_menu_button.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../features/profile/profile_provider.dart';

class ProfileMenuButton extends StatelessWidget {
  const ProfileMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>();
    final avatar = profile.avatarImageProvider();

    return PopupMenuButton<String>(
      tooltip: 'Profile menu',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: CircleAvatar(
          radius: 16,
          backgroundImage: avatar,
          child: avatar == null
              ? Text(
                  (profile.displayName.isNotEmpty ? profile.displayName[0] : 'Y').toUpperCase(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                )
              : null,
        ),
      ),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'profile', child: Text('Profile')),
        PopupMenuItem(value: 'settings', child: Text('Settings')),
      ],
      onSelected: (value) {
        switch (value) {
          case 'profile':
            context.go('/home/profile');
            break;
          case 'settings':
            context.go('/home/settings');
            break;
        }
      },
    );
  }
}
