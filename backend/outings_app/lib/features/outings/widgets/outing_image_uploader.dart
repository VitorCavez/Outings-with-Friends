// lib/features/outings/widgets/outing_image_uploader.dart
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../models/outing_image.dart';
import '../../../services/api_client.dart';
import '../../../services/images_service.dart';
import '../../../services/app_config_service.dart';
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
  // Defaults (normal mode) – will be overridden by policy if Saver Mode is enabled
  int _maxPhotosPerOuting = 10;
  int _pickerMaxWidth = 1440;
  int _pickerMaxHeight = 1440;
  int _pickerQuality = 85;
  int _compressQuality = 75;

  bool _saverMode = false;

  final _picker = ImagePicker();
  late final ImagesService _imagesSvc;

  bool _loading = false;
  bool _policyLoading = true;

  final Set<String> _deleting = <String>{};
  List<OutingImage> _images = [];

  @override
  void initState() {
    super.initState();
    _imagesSvc = ImagesService(widget.api);
    _fetchPolicy();
    _fetchImages();
  }

  bool get _atLimit => _images.length >= _maxPhotosPerOuting;

  String _heroTag(OutingImage img) => 'outing-image:${img.id}';

  Future<void> _fetchPolicy() async {
    setState(() => _policyLoading = true);
    try {
      final svc = AppConfigService(widget.api);
      final policy = await svc.getImageUploadPolicy();

      if (!mounted) return;
      setState(() {
        _maxPhotosPerOuting = policy.maxPhotosPerOuting;
        _pickerMaxWidth = policy.pickerMaxWidth;
        _pickerMaxHeight = policy.pickerMaxHeight;
        _pickerQuality = policy.pickerQuality;
        _compressQuality = policy.compressQuality;
        _saverMode = policy.saverModeEnabled;
        _policyLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _policyLoading = false);
    }
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

  void _showLimitSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Photo limit reached ($_maxPhotosPerOuting). Delete one to add another.',
        ),
      ),
    );
  }

  Future<File> _compressForUpload(File original) async {
    final tmpDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final base = 'outing_${widget.outingId}_$ts';

    // Try WEBP first (best size), fallback to JPEG if unsupported.
    try {
      final outPath = '${tmpDir.path}/$base.webp';
      final result = await FlutterImageCompress.compressAndGetFile(
        original.absolute.path,
        outPath,
        quality: _compressQuality,
        format: CompressFormat.webp,
        keepExif: false,
      );
      if (result != null) return File(result.path);
    } on UnsupportedError {
      // fall back below
    } catch (_) {
      // fall back below
    }

    final outPath = '${tmpDir.path}/$base.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      original.absolute.path,
      outPath,
      quality: _compressQuality,
      format: CompressFormat.jpeg,
      keepExif: false,
    );

    // If compression fails for any reason, upload original (last resort).
    return result != null ? File(result.path) : original;
  }

  String _filenameFor(File f) {
    final path = f.path.toLowerCase();
    if (path.endsWith('.webp')) return 'upload.webp';
    if (path.endsWith('.png')) return 'upload.png';
    return 'upload.jpg';
  }

  String _prettyMB(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(2)}MB';
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    if (_loading) return;

    if (_atLimit) {
      _showLimitSnack();
      return;
    }

    final picked = await _picker.pickImage(
      source: source,
      maxWidth: _pickerMaxWidth.toDouble(),
      maxHeight: _pickerMaxHeight.toDouble(),
      imageQuality: _pickerQuality,
    );
    if (picked == null) return;

    setState(() => _loading = true);

    File? compressed;
    try {
      final original = File(picked.path);

      final before = await original.length();
      compressed = await _compressForUpload(original);
      final after = await compressed.length();

      await _imagesSvc.uploadOutingImage(
        widget.outingId,
        file: compressed,
        filename: _filenameFor(compressed),
      );

      await _fetchImages();
      if (!mounted) return;

      final msg = source == ImageSource.camera
          ? 'Photo captured'
          : 'Image uploaded';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$msg (optimized ${_prettyMB(before)} → ${_prettyMB(after)})',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    } finally {
      // Clean up temp compressed file if it’s not the original
      try {
        if (compressed != null && compressed.path != picked.path) {
          await compressed.delete();
        }
      } catch (_) {}
      if (mounted) setState(() => _loading = false);
    }
  }

  // -----------------------------
  // Image URL optimizer (thumb-only until tap)
  // Supports Cloudinary + Unsplash. Falls back to original URL.
  // -----------------------------
  String _optimizedImageUrl(
    String url, {
    required int w,
    int? h,
    int q = 70,
    bool crop = true,
  }) {
    final u = Uri.tryParse(url);
    if (u == null) return url;

    final host = u.host.toLowerCase();

    // Cloudinary: insert transforms after /upload/
    if (u.path.contains('/upload/')) {
      final parts = <String>[
        'f_auto',
        'q_auto:eco',
        'w_$w',
        if (h != null) 'h_$h',
        crop ? 'c_fill' : 'c_limit',
        'g_auto',
      ];
      final trans = parts.join(',');
      final newPath = u.path.replaceFirst('/upload/', '/upload/$trans/');
      return u.replace(path: newPath).toString();
    }

    // Unsplash: add w/h/q/auto/fit params
    if (host.contains('unsplash.com')) {
      final qp = Map<String, String>.from(u.queryParameters);
      qp['w'] = w.toString();
      if (h != null) qp['h'] = h.toString();
      qp['q'] = q.toString();
      qp.putIfAbsent('auto', () => 'format');
      if (crop) qp['fit'] = 'crop';
      return u.replace(queryParameters: qp).toString();
    }

    return url;
  }

  Future<void> _openGallery(int initialIndex) async {
    if (_images.isEmpty) return;

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _OutingGalleryViewer(
          images: List<OutingImage>.from(_images),
          initialIndex: initialIndex.clamp(0, _images.length - 1),
          heroTagFor: _heroTag,
          optimizedUrl:
              (url, {required int w, int? h, int q = 80, bool crop = false}) {
                return _optimizedImageUrl(url, w: w, h: h, q: q, crop: crop);
              },
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  Future<void> _addFromUnsplash(String imageUrl) async {
    if (_loading) return;

    if (_atLimit) {
      _showLimitSnack();
      return;
    }

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
    if (_atLimit) {
      _showLimitSnack();
      return;
    }

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
    if (_atLimit) {
      _showLimitSnack();
      return;
    }

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

    final canAdd = !_loading && !_atLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + counter + Saver badge
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Photos (${_images.length}/$_maxPhotosPerOuting)',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                if (_policyLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_saverMode)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Saver mode'),
                  ),
              ],
            ),
            if (_atLimit)
              Text(
                'Limit reached',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Buttons row
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: canAdd ? _showPickSheet : null,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add photo'),
            ),
            OutlinedButton.icon(
              onPressed: canAdd ? _openUnsplashSheet : null,
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

        const SizedBox(height: 8),

        if (_saverMode)
          Text(
            'Saver mode is active. Limits and compression are tighter to reduce costs.',
            style: theme.textTheme.bodySmall?.copyWith(color: subtle),
          ),

        if (_atLimit) ...[
          const SizedBox(height: 6),
          Text(
            'You can add up to $_maxPhotosPerOuting photos per outing for now. Delete one to add another.',
            style: theme.textTheme.bodySmall?.copyWith(color: subtle),
          ),
        ],

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

              final dpr = MediaQuery.of(context).devicePixelRatio;
              final screenW = MediaQuery.of(context).size.width;
              final tileLogical = (screenW - (8 * 2)) / 3.0;
              final thumbPx = (tileLogical * dpr).round().clamp(96, 512);

              final thumbUrl = _optimizedImageUrl(
                img.imageUrl,
                w: thumbPx,
                h: thumbPx,
                q: 55,
                crop: true,
              );

              final tag = _heroTag(img);

              return GestureDetector(
                onTap: deleting ? null : () => _openGallery(i),
                onLongPress: deleting ? null : () => _confirmAndDelete(img),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: tag,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: thumbUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: thumbPx,
                          memCacheHeight: thumbPx,
                          maxWidthDiskCache: thumbPx,
                          maxHeightDiskCache: thumbPx,
                          placeholder: (c, _) =>
                              ColoredBox(color: scheme.surfaceVariant),
                          errorWidget: (c, _, __) => ColoredBox(
                            color: scheme.surfaceVariant.withOpacity(0.6),
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
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

/* ------------------------------------------------------------------
   Viewer code below stays as-is (your existing PageView gallery viewer)
------------------------------------------------------------------- */

class _OutingGalleryViewer extends StatefulWidget {
  const _OutingGalleryViewer({
    required this.images,
    required this.initialIndex,
    required this.heroTagFor,
    required this.optimizedUrl,
  });

  final List<OutingImage> images;
  final int initialIndex;
  final String Function(OutingImage) heroTagFor;

  final String Function(String url, {required int w, int? h, int q, bool crop})
  optimizedUrl;

  @override
  State<_OutingGalleryViewer> createState() => _OutingGalleryViewerState();
}

class _OutingGalleryViewerState extends State<_OutingGalleryViewer> {
  late final PageController _controller;
  late int _index;

  bool _showChrome = true;

  bool _dragging = false;
  bool _currentZoomed = false;
  Offset _dragOffset = Offset.zero;
  double _backdropOpacity = 1.0;

  static const double _dismissDistance = 160.0;
  static const double _dismissVelocity = 900.0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _resetDragAnimated() {
    setState(() {
      _dragging = false;
      _dragOffset = Offset.zero;
      _backdropOpacity = 1.0;
      _showChrome = true;
    });
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    if (_currentZoomed) return;
    setState(() {
      _dragging = true;
      _showChrome = false;
    });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (!_dragging || _currentZoomed) return;

    final next = _dragOffset + Offset(0, details.delta.dy);
    final absDy = next.dy.abs();
    final opacity = (1.0 - (absDy / 320.0)).clamp(0.0, 1.0);

    setState(() {
      _dragOffset = next;
      _backdropOpacity = opacity;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (!_dragging) return;

    final absDy = _dragOffset.dy.abs();
    final v = (details.primaryVelocity ?? 0).abs();

    final shouldDismiss = absDy > _dismissDistance || v > _dismissVelocity;

    if (shouldDismiss) {
      Navigator.of(context).pop();
      return;
    }

    _resetDragAnimated();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final screenW = MediaQuery.of(context).size.width;

    final fullW = (screenW * dpr).round().clamp(320, 2048);

    final absDy = _dragOffset.dy.abs();
    final scale = (1.0 - (absDy / 900.0)).clamp(0.85, 1.0);

    final settleDuration = _dragging
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          AnimatedContainer(
            duration: settleDuration,
            curve: Curves.easeOut,
            color: Colors.black.withOpacity(_backdropOpacity),
          ),
          SafeArea(
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _showChrome = !_showChrome),
                  onVerticalDragStart: _handleVerticalDragStart,
                  onVerticalDragUpdate: _handleVerticalDragUpdate,
                  onVerticalDragEnd: _handleVerticalDragEnd,
                  child: AnimatedContainer(
                    duration: settleDuration,
                    curve: Curves.easeOut,
                    child: Transform.translate(
                      offset: _dragOffset,
                      child: Transform.scale(
                        scale: scale,
                        child: PageView.builder(
                          controller: _controller,
                          itemCount: widget.images.length,
                          onPageChanged: (i) {
                            setState(() {
                              _index = i;
                              _currentZoomed = false;
                              _dragging = false;
                              _dragOffset = Offset.zero;
                              _backdropOpacity = 1.0;
                            });
                          },
                          itemBuilder: (ctx, i) {
                            final img = widget.images[i];
                            final tag = widget.heroTagFor(img);

                            final fullUrl = widget.optimizedUrl(
                              img.imageUrl,
                              w: fullW,
                              q: 80,
                              crop: false,
                            );

                            return _ZoomableHeroImagePage(
                              key: ValueKey('zoom-${img.id}'),
                              heroTag: tag,
                              imageUrl: fullUrl,
                              errorColor: scheme.onSurface,
                              onZoomChanged: (z) {
                                if (i != _index) return;
                                if (_currentZoomed != z)
                                  setState(() => _currentZoomed = z);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _showChrome ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: IgnorePointer(
                    ignoring: !_showChrome,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Row(
                        children: [
                          Material(
                            color: Colors.black45,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => Navigator.of(context).pop(),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.close, color: Colors.white),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${_index + 1} / ${widget.images.length}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
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
  }
}

class _ZoomableHeroImagePage extends StatefulWidget {
  const _ZoomableHeroImagePage({
    super.key,
    required this.heroTag,
    required this.imageUrl,
    required this.errorColor,
    required this.onZoomChanged,
  });

  final String heroTag;
  final String imageUrl;
  final Color errorColor;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableHeroImagePage> createState() => _ZoomableHeroImagePageState();
}

class _ZoomableHeroImagePageState extends State<_ZoomableHeroImagePage>
    with SingleTickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  TapDownDetails? _doubleTapDetails;

  late final AnimationController _animCtrl;
  Animation<Matrix4>? _anim;

  static const double _doubleTapScale = 2.6;

  bool _zoomed = false;

  @override
  void initState() {
    super.initState();

    _tc.addListener(_onTransformChanged);

    _animCtrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
        )..addListener(() {
          final a = _anim;
          if (a != null) _tc.value = a.value;
        });
  }

  @override
  void dispose() {
    _tc.removeListener(_onTransformChanged);
    _animCtrl.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final nowZoomed = !matrixEquals(_tc.value, Matrix4.identity());
    if (nowZoomed != _zoomed) {
      _zoomed = nowZoomed;
      widget.onZoomChanged(_zoomed);
    }
  }

  void _animateTo(Matrix4 target) {
    _animCtrl.stop();
    _anim = Matrix4Tween(
      begin: _tc.value,
      end: target,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward(from: 0);
  }

  void _handleDoubleTap() {
    final current = _tc.value;
    final isZoomed = !matrixEquals(current, Matrix4.identity());

    if (isZoomed) {
      _animateTo(Matrix4.identity());
      return;
    }

    final tapPos = _doubleTapDetails?.localPosition;
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size;
    final focal =
        tapPos ?? (size != null ? size.center(Offset.zero) : Offset.zero);

    final scale = _doubleTapScale;
    final dx = -focal.dx * (scale - 1);
    final dy = -focal.dy * (scale - 1);

    final target = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);

    _animateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Hero(
        tag: widget.heroTag,
        child: Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            onDoubleTapDown: (d) => _doubleTapDetails = d,
            onDoubleTap: _handleDoubleTap,
            child: InteractiveViewer(
              transformationController: _tc,
              minScale: 1,
              maxScale: 4,
              child: CachedNetworkImage(
                imageUrl: widget.imageUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                errorWidget: (_, __, ___) => Icon(
                  Icons.broken_image_outlined,
                  color: widget.errorColor,
                  size: 36,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool matrixEquals(Matrix4 a, Matrix4 b) {
    const eps = 1e-10;
    for (var i = 0; i < 16; i++) {
      if ((a.storage[i] - b.storage[i]).abs() > eps) return false;
    }
    return true;
  }
}
