// lib/features/outings/widgets/outing_gallery_viewer.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/outing_image.dart';

typedef OptimizedUrlBuilder =
    String Function(String url, {required int w, int? h, int q, bool crop});

class OutingGalleryViewer extends StatefulWidget {
  const OutingGalleryViewer({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.heroTagFor,
    required this.optimizedUrl,
  });

  final List<OutingImage> images;
  final int initialIndex;
  final String Function(OutingImage) heroTagFor;

  /// url -> optimized url (cloudinary/unsplash aware)
  final OptimizedUrlBuilder optimizedUrl;

  @override
  State<OutingGalleryViewer> createState() => _OutingGalleryViewerState();
}

class _OutingGalleryViewerState extends State<OutingGalleryViewer> {
  late final PageController _controller;
  late int _index;

  bool _showChrome = true;

  // Drag-to-dismiss state
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

    // Preload current + neighbors for smooth swipe
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheAround(_index);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _precacheAround(int i) {
    if (!mounted) return;
    final ctx = context;

    final dpr = MediaQuery.of(ctx).devicePixelRatio;
    final screenW = MediaQuery.of(ctx).size.width;
    final fullW = (screenW * dpr).round().clamp(320, 2048);

    for (final idx in <int>[i - 1, i, i + 1]) {
      if (idx < 0 || idx >= widget.images.length) continue;
      final url = widget.optimizedUrl(
        widget.images[idx].imageUrl,
        w: fullW,
        q: 80,
        crop: false,
      );
      precacheImage(CachedNetworkImageProvider(url), ctx);
    }
  }

  Future<void> _jumpTo(int i) async {
    final target = i.clamp(0, widget.images.length - 1);
    if (target == _index) return;

    setState(() {
      _index = target;
      _currentZoomed = false; // new page should be "not zoomed"
      _dragging = false;
      _dragOffset = Offset.zero;
      _backdropOpacity = 1.0;
    });

    _precacheAround(target);

    // Smooth jump
    await _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _resetDrag() {
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

    _resetDrag();
  }

  Widget _buildThumbStrip(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;

    // Thumb sizing
    const thumbLogical = 64.0;
    final thumbPx = (thumbLogical * dpr).round().clamp(96, 220);

    final radius = BorderRadius.circular(10);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Container(
          height: 86,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.images.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              final img = widget.images[i];
              final isActive = i == _index;

              final thumbUrl = widget.optimizedUrl(
                img.imageUrl,
                w: thumbPx,
                h: thumbPx,
                q: 55,
                crop: true,
              );

              return Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: radius,
                  onTap: () => _jumpTo(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(
                        color: isActive ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: radius,
                      child: CachedNetworkImage(
                        imageUrl: thumbUrl,
                        fit: BoxFit.cover,
                        width: thumbLogical,
                        height: thumbLogical,
                        memCacheWidth: thumbPx,
                        memCacheHeight: thumbPx,
                        maxWidthDiskCache: thumbPx,
                        maxHeightDiskCache: thumbPx,
                        placeholder: (_, __) => Container(
                          width: thumbLogical,
                          height: thumbLogical,
                          color: Colors.white10,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: thumbLogical,
                          height: thumbLogical,
                          color: Colors.white10,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
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

                  // ✅ swipe-down (or swipe-up) to dismiss, with fade + scale
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
                            _precacheAround(i);
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
                                if (_currentZoomed != z) {
                                  setState(() => _currentZoomed = z);
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // Top chrome (close + counter)
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

                // Bottom thumbnail strip (hidden when chrome hidden)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedOpacity(
                    opacity: _showChrome ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: IgnorePointer(
                      ignoring: !_showChrome,
                      child: _buildThumbStrip(context),
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
    final nowZoomed = !_matrixEquals(_tc.value, Matrix4.identity());
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
    final isZoomed = !_matrixEquals(current, Matrix4.identity());

    if (isZoomed) {
      _animateTo(Matrix4.identity());
      return;
    }

    // Zoom in around tap position (best UX)
    final tapPos = _doubleTapDetails?.localPosition;
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size;

    // Fallback to center if we don't have tap info yet
    final focal =
        tapPos ?? (size != null ? size.center(Offset.zero) : Offset.zero);

    final scale = _doubleTapScale;

    // Translate so the tapped point stays under the finger after scaling.
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

  bool _matrixEquals(Matrix4 a, Matrix4 b) {
    const eps = 1e-10;
    for (var i = 0; i < 16; i++) {
      if ((a.storage[i] - b.storage[i]).abs() > eps) return false;
    }
    return true;
  }
}
