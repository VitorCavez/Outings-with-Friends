// lib/features/messages/widgets/message_bubble.dart
import 'package:flutter/material.dart';
import 'package:characters/characters.dart'; // <-- needed for .characters
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:outings_app/models/message.dart';

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
          color: _bubbleColor(context, isMine),
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
                    color: isMine ? Colors.white70 : Colors.black54,
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 6),
                  Icon(
                    message.isRead ? Icons.done_all : Icons.done,
                    size: 14,
                    color: message.isRead
                        ? (isMine ? Colors.white : Colors.black54)
                        : (isMine ? Colors.white70 : Colors.black45),
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
      style: TextStyle(color: isMine ? Colors.white : Colors.black),
    );
  }

  static Color _bubbleColor(BuildContext context, bool isMine) {
    return isMine
        ? Colors.blue
        : (Theme.of(context).brightness == Brightness.dark
            ? Colors.grey.shade800
            : Colors.grey[300]!);
  }

  static String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

// ---- Image attachment -------------------------------------------------------

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        // keep a reasonable image size
        memCacheHeight: 1200,
        memCacheWidth: 1200,
        placeholder: (context, _) => Container(
          height: 180,
          width: 220,
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
          color: Colors.black12,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, size: 28),
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
    final foreground = isMine ? Colors.white : Colors.black87;

    return InkWell(
      onTap: () => _openUrl(url),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMine ? Colors.white12 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isMine ? Colors.white38 : Colors.black12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, color: foreground),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  decoration: TextDecoration.underline,
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
    return CircleAvatar(
      radius: 14,
      backgroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
      backgroundColor: imageUrl == null ? Colors.grey.shade400 : null,
      child: imageUrl == null
          ? Text(
              (label ?? '🙂').characters.take(2).toString().toUpperCase(),
              style: const TextStyle(fontSize: 11, color: Colors.white),
            )
          : null,
    );
  }
}
