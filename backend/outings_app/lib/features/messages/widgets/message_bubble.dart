// lib/features/messages/widgets/message_bubble.dart
import 'package:flutter/material.dart';
import 'package:characters/characters.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:outings_app/models/message.dart';

// Access the BrandColors extension from your theme
import 'package:outings_app/theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.avatarLabel,
    this.avatarImageUrl,
  });

  final Message message;

  /// If provided, a tiny avatar (initials or emoji) is shown for **incoming** messages.
  final String? avatarLabel;

  /// If you later have user photos, you can pass a URL here.
  final String? avatarImageUrl;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final c = Theme.of(context).colorScheme;

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        // keep bubbles readable on large screens
        maxWidth: MediaQuery.of(context).size.width * 0.68,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: message.isImage || message.isFile ? 8 : 10,
          horizontal: message.isImage || message.isFile ? 8 : 14,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: _bubbleColor(c, isMine),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildContent(context, isMine),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fmtTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 10,
                    color: isMine
                        ? c.onPrimary.withValues(alpha: 0.72)
                        : c.onSurfaceVariant,
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 6),
                  Icon(
                    message.isRead ? Icons.done_all : Icons.done,
                    size: 14,
                    color: message.isRead
                        ? c.onPrimary
                        : c.onPrimary.withValues(alpha: 0.72),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    // Avatars only for incoming messages; align left with avatar + bubble row.
    if (!isMine) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _AvatarCircle(label: avatarLabel, imageUrl: avatarImageUrl),
          const SizedBox(width: 8),
          Flexible(child: bubble),
          const Spacer(),
        ],
      );
    }

    // Outgoing: align right
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Spacer(),
        Flexible(child: bubble),
      ],
    );
  }

  // ---- content variants -----------------------------------------------------

  Widget _buildContent(BuildContext context, bool isMine) {
    final c = Theme.of(context).colorScheme;

    if (message.isImage && (message.mediaUrl?.isNotEmpty ?? false)) {
      return _ImageAttachment(url: message.mediaUrl!);
    }

    if (message.isFile && (message.mediaUrl?.isNotEmpty ?? false)) {
      return _FileAttachment(
        url: message.mediaUrl!,
        fileName: message.fileName ?? 'attachment',
        isMine: isMine,
      );
    }

    // Default: text bubble
    return Text(
      message.text,
      style: TextStyle(color: isMine ? c.onPrimary : c.onSurface),
    );
  }

  static Color _bubbleColor(ColorScheme c, bool isMine) {
    // Mine = brand primary; Others = elevated surface per M3 containers
    return isMine ? c.primary : c.surfaceContainerHighest;
  }

  static String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

// ---- Thumbnail helpers (strict-cost) ----------------------------------------
// We ONLY request small images in list/chat contexts.
// Full image loads only when user taps to view.
String _thumbUrl(String raw, {int w = 480, int q = 70}) {
  if (raw.trim().isEmpty) return raw;

  Uri? uri;
  try {
    uri = Uri.parse(raw);
  } catch (_) {
    return raw;
  }

  final host = (uri.host).toLowerCase();

  // Unsplash thumbnails
  if (host.contains('images.unsplash.com')) {
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['w'] = '$w';
    qp['q'] = '$q';
    qp['auto'] = qp['auto'] ?? 'format';
    qp['fit'] = qp['fit'] ?? 'crop';
    return uri.replace(queryParameters: qp).toString();
  }

  // Cloudinary thumbnails (insert transformation after /upload/)
  if (host.contains('res.cloudinary.com') && raw.contains('/upload/')) {
    final idx = raw.indexOf('/upload/');
    final prefix = raw.substring(0, idx + '/upload/'.length);
    final rest = raw.substring(idx + '/upload/'.length);

    // If a transformation segment already exists, don't double-transform.
    final firstSeg = rest.split('/').first;
    final looksLikeTransform =
        firstSeg.contains('w_') ||
        firstSeg.contains('q_') ||
        firstSeg.contains('c_') ||
        firstSeg.contains('f_');

    if (looksLikeTransform) return raw;

    final transform = 'c_fill,w_$w,q_$q,f_auto';
    return '$prefix$transform/$rest';
  }

  // Default: leave untouched (unknown provider)
  return raw;
}

// ---- Image attachment -------------------------------------------------------

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.url});
  final String url;

  void _openViewer(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: url, // full-size on demand
                    fit: BoxFit.contain,
                    placeholder: (_, __) => Container(
                      height: 360,
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: const SizedBox(
                        height: 28,
                        width: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: 360,
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 34,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    // thumbnail for bubble view
    final thumb = _thumbUrl(url, w: 480, q: 70);

    return GestureDetector(
      onTap: () => _openViewer(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: thumb,
          fit: BoxFit.cover,
          // keep a reasonable image size in memory for chat scrolling
          memCacheHeight: 600,
          memCacheWidth: 600,
          placeholder: (context, _) => Container(
            height: 180,
            width: 220,
            color: c.surface, // avoids harsh white
            alignment: Alignment.center,
            child: const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (context, _, __) => Container(
            height: 180,
            width: 220,
            color: c.surfaceVariant,
            alignment: Alignment.center,
            child: Icon(
              Icons.broken_image,
              size: 28,
              color: c.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ---- File attachment --------------------------------------------------------

class _FileAttachment extends StatelessWidget {
  const _FileAttachment({
    required this.url,
    required this.fileName,
    required this.isMine,
  });

  final String url;
  final String fileName;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final brand = Theme.of(context).extension<BrandColors>();

    final fg = isMine ? c.onPrimary : c.onSurface;
    final borderColor = isMine
        ? c.onPrimary.withValues(alpha: 0.30)
        : c.outlineVariant;
    final bgColor = isMine ? c.onPrimary.withValues(alpha: 0.08) : c.surface;

    return InkWell(
      onTap: () => _openUrl(url),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  decoration: TextDecoration.underline,
                  decorationColor: isMine
                      ? c.onPrimary
                      : (brand?.info ?? c.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String raw) async {
    final uri = Uri.parse(raw);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ---- Avatar ---------------------------------------------------------------

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({this.label, this.imageUrl});
  final String? label;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    // Also thumbnail avatars if they are remote.
    final thumb = (imageUrl != null && imageUrl!.trim().isNotEmpty)
        ? _thumbUrl(imageUrl!, w: 120, q: 70)
        : null;

    return CircleAvatar(
      radius: 14,
      backgroundImage: thumb != null ? NetworkImage(thumb) : null,
      backgroundColor: thumb == null ? c.secondaryContainer : null,
      child: thumb == null
          ? Text(
              (label ?? '🙂').characters.take(2).toString().toUpperCase(),
              style: TextStyle(fontSize: 11, color: c.onSecondaryContainer),
            )
          : null,
    );
  }
}
