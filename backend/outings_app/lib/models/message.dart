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

  /// Attachments
  /// 'text' | 'image' | 'file'
  final String messageType;
  /// Remote URL to the uploaded file/image
  final String? mediaUrl;
  /// Optional metadata for files
  final String? fileName;
  final int? fileSize; // bytes

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
  });

  /// Convenience flags
  bool get isImage => messageType == 'image';
  bool get isFile  => messageType == 'file';

  /// Basic image extension detection (used if backend doesn't provide `messageType`)
  static bool _looksLikeImageUrl(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.png') ||
        u.endsWith('.jpg') ||
        u.endsWith('.jpeg') ||
        u.endsWith('.gif') ||
        u.endsWith('.webp') ||
        u.contains('image/upload'); // common on Cloudinary, etc.
  }

  factory Message.fromMap(Map<String, dynamic> j, String currentUserId) {
    // Robust createdAt parsing
    final created = j['createdAt'];
    DateTime ts;
    if (created is String) {
      ts = DateTime.tryParse(created) ?? DateTime.now();
    } else if (created is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(created);
    } else {
      ts = DateTime.now();
    }

    final idVal = (j['id'] ?? j['messageId'] ?? DateTime.now().millisecondsSinceEpoch).toString();
    final sender = (j['senderId'] ?? '').toString();

    // Attachment fields (all optional)
    final String? rawMediaUrl = (j['mediaUrl'] ?? j['attachmentUrl'] ?? j['url'])?.toString();
    final String? rawType = (j['messageType'] ?? j['type'])?.toString();

    // Infer type if not provided
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
      createdAt: ts,
      isRead: (j['isRead'] ?? false) as bool,
      isMine: sender == currentUserId,
      messageType: computedType,
      mediaUrl: rawMediaUrl,
      fileName: (j['fileName'] ?? j['name'])?.toString(),
      fileSize: (j['fileSize'] is int) ? j['fileSize'] as int : null,
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
    );
  }
}
