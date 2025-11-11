// lib/features/profile/my_profile_page.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'profile_provider.dart';

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final profile = context.read<ProfileProvider>();
    _nameCtrl = TextEditingController(text: profile.displayName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
      allowMultiple: false,
    );
    if (res != null && res.files.single.path != null) {
      await context.read<ProfileProvider>().setAvatarPath(res.files.single.path);
    }
  }

  Future<void> _removeImage() async {
    await context.read<ProfileProvider>().setAvatarPath(null);
  }

  Future<void> _saveName() async {
    await context.read<ProfileProvider>().setDisplayName(_nameCtrl.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>();
    final avatar = profile.avatarImageProvider();

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundImage: avatar,
                  child: avatar == null
                      ? Text(
                          (profile.displayName.isNotEmpty ? profile.displayName[0] : 'Y').toUpperCase(),
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: IconButton.filledTonal(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.edit),
                    tooltip: 'Change photo',
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Display name',
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _saveName,
                icon: const Icon(Icons.check),
                label: const Text('Save'),
              ),
              const SizedBox(width: 12),
              if (avatar != null)
                OutlinedButton.icon(
                  onPressed: _removeImage,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove photo'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
