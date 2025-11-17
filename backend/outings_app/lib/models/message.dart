// lib/models/message.dart
class Message {
  final String id;
  final String text;
  final String senderId;
  final String? recipientId;
  final String? groupId;
  final DateTime createdAt;
  final bool isRead;
  final bool isMine;

  /// 'text' | 'image' | 'file'
  final String messageType;

  /// Remote URL to the uploaded file/image
  final String? mediaUrl;

  /// Optional metadata for files
  final String? fileName;
  final int? fileSize; // bytes

  /// When the message was marked read (server time), if ever
  final DateTime? readAt;

  Message({
    required this.id,
    required this.text,
    required this.senderId,
    this.recipientId,
    this.groupId,
    required this.createdAt,
    required this.isRead,
    required this.isMine,
    this.messageType = 'text',
    this.mediaUrl,
    this.fileName,
    this.fileSize,
    this.readAt,
  });

  bool get isImage => messageType == 'image';
  bool get isFile => messageType == 'file';

  static DateTime _toLocal(DateTime dt) => dt.isUtc ? dt.toLocal() : dt;

  static DateTime _parseCreated(dynamic created) {
    if (created is String) {
      final parsed = DateTime.tryParse(created);
      if (parsed != null) return _toLocal(parsed);
      return DateTime.now();
    }
    if (created is int) {
      final ms = created > 1000000000000 ? created : created * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    return DateTime.now();
  }

  static DateTime? _parseOptionalDate(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final parsed = DateTime.tryParse(v);
      return parsed == null ? null : _toLocal(parsed);
    }
    if (v is int) {
      final ms = v > 1000000000000 ? v : v * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    return null;
  }

  static bool _looksLikeImageUrl(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.png') ||
        u.endsWith('.jpg') ||
        u.endsWith('.jpeg') ||
        u.endsWith('.gif') ||
        u.endsWith('.webp') ||
        u.endsWith('.bmp') ||
        u.contains('image/upload');
  }

  factory Message.fromMap(Map<String, dynamic> j, String currentUserId) {
    final idVal =
        (j['id'] ?? j['messageId'] ?? DateTime.now().millisecondsSinceEpoch)
            .toString();
    final sender = (j['senderId'] ?? '').toString();

    final String? rawMediaUrl =
        (j['mediaUrl'] ?? j['attachmentUrl'] ?? j['url'])?.toString();
    final String? rawType = (j['messageType'] ?? j['type'])?.toString();

    String computedType;
    if (rawType != null && rawType.isNotEmpty) {
      computedType = rawType;
    } else if (rawMediaUrl != null && rawMediaUrl.isNotEmpty) {
      computedType = _looksLikeImageUrl(rawMediaUrl) ? 'image' : 'file';
    } else {
      computedType = 'text';
    }

    return Message(
      id: idVal,
      text: (j['text'] ?? '').toString(),
      senderId: sender,
      recipientId: j['recipientId'] as String?,
      groupId: j['groupId'] as String?,
      createdAt: _parseCreated(j['createdAt']),
      isRead: (j['isRead'] ?? false) as bool,
      isMine: sender == currentUserId,
      messageType: computedType,
      mediaUrl: rawMediaUrl,
      fileName: (j['fileName'] ?? j['name'])?.toString(),
      fileSize: (j['fileSize'] is int) ? j['fileSize'] as int : null,
      readAt: _parseOptionalDate(j['readAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'senderId': senderId,
      'recipientId': recipientId,
      'groupId': groupId,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
      'messageType': messageType,
      'mediaUrl': mediaUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'readAt': readAt?.toIso8601String(),
    };
  }

  Message copyWith({
    String? id,
    String? text,
    String? senderId,
    String? recipientId,
    String? groupId,
    DateTime? createdAt,
    bool? isRead,
    bool? isMine,
    String? messageType,
    String? mediaUrl,
    String? fileName,
    int? fileSize,
    DateTime? readAt,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      groupId: groupId ?? this.groupId,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      isMine: isMine ?? this.isMine,
      messageType: messageType ?? this.messageType,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      readAt: readAt ?? this.readAt,
    );
  }

  Message merge(Message other) {
    final mergedText = other.text.trim().isNotEmpty ? other.text : text;
    final mergedCreated = other.createdAt.isAfter(createdAt)
        ? other.createdAt
        : createdAt;

    String mergedType = messageType;
    String? mergedMedia = mediaUrl;
    if (other.messageType != 'text' || messageType == 'text') {
      mergedType = other.messageType;
      mergedMedia = other.mediaUrl ?? mergedMedia;
    }

    return copyWith(
      text: mergedText,
      senderId: other.senderId.isNotEmpty ? other.senderId : senderId,
      recipientId: other.recipientId ?? recipientId,
      groupId: other.groupId ?? groupId,
      createdAt: mergedCreated,
      isRead: isRead || other.isRead,
      isMine: other.isMine,
      messageType: mergedType,
      mediaUrl: mergedMedia,
      fileName: other.fileName ?? fileName,
      fileSize: other.fileSize ?? fileSize,
      readAt: other.readAt ?? readAt,
    );
  }
}
