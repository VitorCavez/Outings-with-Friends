// lib/features/outings/widgets/outing_image_uploader.dart
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/outing_image.dart';
import '../../../services/api_client.dart';
import '../../../services/images_service.dart';
import 'unsplash_picker_sheet.dart';

class OutingImageUploader extends StatefulWidget {
  const OutingImageUploader({
    super.key,
    required this.outingId,
    required this.api,
  });

  final String outingId;
  final ApiClient api;

  @override
  State<OutingImageUploader> createState() => _OutingImageUploaderState();
}

class _OutingImageUploaderState extends State<OutingImageUploader> {
  final _picker = ImagePicker();
  late final ImagesService _imagesSvc;

  bool _loading = false;
  final Set<String> _deleting = <String>{};
  List<OutingImage> _images = [];

  @override
  void initState() {
    super.initState();
    _imagesSvc = ImagesService(widget.api);
    _fetchImages();
  }

  Future<void> _fetchImages() async {
    setState(() => _loading = true);
    try {
      final list = await _imagesSvc.listOutingImages(widget.outingId);
      if (!mounted) return;
      setState(() => _images = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Load images failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 2400,
      imageQuality: 90,
    );
    if (picked == null) return;

    setState(() => _loading = true);
    try {
      await _imagesSvc.uploadOutingImage(
        widget.outingId,
        file: File(picked.path),
        filename: picked.name,
      );
      await _fetchImages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.camera ? 'Photo captured' : 'Image uploaded',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addFromUnsplash(String imageUrl) async {
    setState(() => _loading = true);
    try {
      await _imagesSvc.addFromUrl(
        widget.outingId,
        imageUrl: imageUrl,
        imageSource: 'unsplash',
      );
      await _fetchImages();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unsplash image added')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Add from Unsplash failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openUnsplashSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.9,
        child: UnsplashPickerSheet(
          api: widget.api,
          onPicked: (url) => _addFromUnsplash(url),
        ),
      ),
    );
  }

  void _showPickSheet() {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              runSpacing: 8,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take a photo'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUpload(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from gallery'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUpload(ImageSource.gallery);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: scheme.error),
                  title: const Text('Cancel'),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmAndDelete(OutingImage img) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            runSpacing: 8,
            children: [
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: const Text('Delete photo'),
                subtitle: const Text('This removes the photo from the outing.'),
                onTap: () => Navigator.pop(ctx, true),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting.add(img.id));
    try {
      final ok = await _imagesSvc.deleteImage(img.id);
      if (!mounted) return;

      if (ok) {
        setState(() => _images.removeWhere((e) => e.id == img.id));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo deleted')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Delete failed')));
        await _fetchImages();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete error: $e')));
    } finally {
      if (mounted) setState(() => _deleting.remove(img.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtle = scheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Buttons row
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _loading ? null : _showPickSheet,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add photo'),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _openUnsplashSheet,
              icon: const Icon(Icons.image_search_outlined),
              label: const Text('Add from Unsplash'),
            ),
            if (_loading)
              const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),

        const SizedBox(height: 12),

        if (_images.isEmpty && !_loading)
          Text(
            'No images yet. Be the first to add one!',
            style: theme.textTheme.bodyMedium?.copyWith(color: subtle),
          ),

        if (_images.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _images.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemBuilder: (ctx, i) {
              final img = _images[i];
              final deleting = _deleting.contains(img.id);

              return GestureDetector(
                onLongPress: deleting ? null : () => _confirmAndDelete(img),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: img.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (c, _) =>
                            ColoredBox(color: scheme.surfaceVariant),
                        errorWidget: (c, _, __) => ColoredBox(
                          color: scheme.surfaceVariant.withOpacity(0.6),
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),

                    // Top-right delete icon (more discoverable than long-press)
                    if (!deleting)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black45,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _confirmAndDelete(img),
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Deleting overlay
                    if (deleting)
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.scrim.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
