// lib/features/profile/my_profile_page.dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import 'profile_provider.dart';
import '../auth/auth_provider.dart';

import '../../config/app_config.dart';
import '../../services/api_client.dart';
import '../../services/profile_service.dart';
import '../../services/upload_service.dart';

ApiClient _apiFromContext(BuildContext context) {
  String? token;
  try {
    final auth = context.read<AuthProvider>();
    final dyn = auth as dynamic;
    token = (dyn.authToken ?? dyn.token) as String?;
  } catch (_) {
    token = null;
  }
  return ApiClient(baseUrl: AppConfig.apiBaseUrl, authToken: token);
}

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  late TextEditingController _nameCtrl;

  final UploadService _uploader = UploadService();

  bool _savingPhoto = false;

  // Keep track of temp avatar files we create so we can clean them up.
  String? _lastTempAvatarPath;

  @override
  void initState() {
    super.initState();
    final profile = context.read<ProfileProvider>();
    _nameCtrl = TextEditingController(text: profile.displayName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cleanupTempAvatar();
    super.dispose();
  }

  void _cleanupTempAvatar() {
    final p = _lastTempAvatarPath;
    if (p == null) return;
    try {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    _lastTempAvatarPath = null;
  }

  String _prettyMB(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(2)}MB';
  }

  Future<File> _compressAvatar(File original) async {
    // Avatars can be small and still look great.
    const int maxDim = 512;
    const int quality = 75;

    final tmpDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final base = 'avatar_$ts';

    // Try WebP first (smaller), fallback to JPEG.
    try {
      final outPath = '${tmpDir.path}/$base.webp';
      final result = await FlutterImageCompress.compressAndGetFile(
        original.absolute.path,
        outPath,
        quality: quality,
        minWidth: maxDim,
        minHeight: maxDim,
        format: CompressFormat.webp,
        keepExif: false,
      );
      if (result != null) return File(result.path);
    } catch (_) {}

    final outPath = '${tmpDir.path}/$base.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      original.absolute.path,
      outPath,
      quality: quality,
      minWidth: maxDim,
      minHeight: maxDim,
      format: CompressFormat.jpeg,
      keepExif: false,
    );

    return result != null ? File(result.path) : original;
  }

  Future<void> _pickImage() async {
    if (_savingPhoto) return;

    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
      allowMultiple: false,
    );
    if (res == null || res.files.isEmpty) return;

    final path = res.files.single.path;
    if (path == null) return;

    final original = File(path);

    setState(() => _savingPhoto = true);

    File? compressed;
    bool deleteTempAfter = false;

    try {
      final before = await original.length();

      compressed = await _compressAvatar(original);
      final after = await compressed.length();

      // Remember temp file so we can clean it later (UI needs it).
      if (compressed.path != original.path) {
        _cleanupTempAvatar();
        _lastTempAvatarPath = compressed.path;
        deleteTempAfter = false; // keep it for avatar preview
      }

      // 1) Update local preview immediately (compressed path)
      final profileProv = context.read<ProfileProvider>();
      await profileProv.setAvatarPath(compressed.path);

      // 2) Upload the COMPRESSED file (critical cost control)
      final upload = await _uploader.uploadFile(compressed);

      // 3) Save URL to backend profile
      final api = _apiFromContext(context);
      final svc = ProfileService(api);
      await svc.updateMyProfile(profilePhotoUrl: upload.url);

      // 4) Save URL locally so other screens can show it even without local file
      await profileProv.setAvatarUrl(upload.url);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo optimized ${_prettyMB(before)} → ${_prettyMB(after)} and saved online',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update photo: $e')));
    } finally {
      // We keep the temp avatar file for preview, so we do NOT delete it here.
      // If you ever want to delete it later, we already clean it on dispose.
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  Future<void> _removeImage() async {
    if (_savingPhoto) return;

    setState(() => _savingPhoto = true);

    try {
      final profileProv = context.read<ProfileProvider>();

      // Clear local display first
      await profileProv.setAvatarPath(null);
      await profileProv.setAvatarUrl(null);
      _cleanupTempAvatar();

      // Clear online
      final api = _apiFromContext(context);
      final svc = ProfileService(api);
      await svc.updateMyProfile(clearProfilePhotoUrl: true);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo removed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed locally, but failed online: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  Future<void> _saveName() async {
    final newName = _nameCtrl.text.trim();

    await context.read<ProfileProvider>().setDisplayName(newName);

    try {
      final api = _apiFromContext(context);
      final svc = ProfileService(api);

      if (newName.isNotEmpty) {
        await svc.updateMyProfile(fullName: newName);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile saved locally, but failed to update online: $e',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>();
    final avatar = profile.avatarImageProvider();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'view_public') {
                final uid = context.read<AuthProvider?>()?.currentUserId;
                if (uid == null || uid.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Not logged in')),
                  );
                  return;
                }
                context.push('/profile/$uid');
              } else if (v == 'logout') {
                final auth = context.read<AuthProvider>();
                await auth.signOut(context);
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'view_public',
                child: ListTile(
                  leading: Icon(Icons.person_search_outlined),
                  title: Text('View public profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Log out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
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
                          (profile.displayName.isNotEmpty
                                  ? profile.displayName[0]
                                  : 'Y')
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: IconButton.filledTonal(
                    onPressed: _savingPhoto ? null : _pickImage,
                    icon: _savingPhoto
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit),
                    tooltip: 'Change photo',
                  ),
                ),
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
              FilledButton.icon(
                onPressed: _saveName,
                icon: const Icon(Icons.check),
                label: const Text('Save'),
              ),
              const SizedBox(width: 12),
              if (avatar != null)
                OutlinedButton.icon(
                  onPressed: _savingPhoto ? null : _removeImage,
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
