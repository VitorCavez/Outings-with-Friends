// lib/features/messages/chat_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import 'package:outings_app/services/socket_service.dart';
import 'package:outings_app/services/upload_service.dart';
import 'package:outings_app/utils/debouncer.dart';
import 'package:outings_app/models/message.dart';
import 'package:outings_app/features/messages/messages_repository.dart';

// Friendly names from ContactsProvider cache
import 'package:outings_app/features/contacts/display_name.dart';

import 'chat_state.dart';
// Hide Container to avoid name clash with Flutter's Container.
import 'widgets/message_bubble.dart' hide Container;
import 'widgets/date_divider.dart';
import 'widgets/new_messages_divider.dart';

// Group title
import 'package:outings_app/services/group_service.dart';
import 'package:outings_app/services/api_client.dart';
import 'package:outings_app/config/app_config.dart';
import 'package:outings_app/features/auth/auth_provider.dart';

// Brand tokens (ThemeExtension)
import 'package:outings_app/theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scroll = ScrollController();

  final SocketService _socket = SocketService();
  final UploadService _uploader = UploadService();
  final Debouncer _debouncer = Debouncer(ms: 400);
  final Set<String> _readSent = {};

  late final MessagesRepository _repo = MessagesRepository();

  bool _canSend = false;
  bool _peerOnline = false;
  bool _showJumpDown = false;

  String? _newMarkerId;
  bool _initialLoaded = false;

  // group title (for app bar)
  String? _groupTitle;

  ApiClient _api() {
    String? token;
    try {
      final auth = context.read<AuthProvider>();
      final dyn = auth as dynamic;
      token = (dyn.authToken ?? dyn.token) as String?;
    } catch (_) {}
    return ApiClient(baseUrl: AppConfig.apiBaseUrl, authToken: token);
  }

  Future<void> _loadGroupTitleIfNeeded() async {
    final chat = context.read<ChatState>();
    final gid = chat.groupId;
    if (gid == null) return;
    try {
      final svc = GroupService(_api());
      final raw = await svc.getGroup(gid); // tolerates {ok,data} or raw

      Map<String, dynamic> map;
      if (raw is Map<String, dynamic>) {
        final inner =
            (raw['group'] ?? raw['data'] ?? raw) as Map<String, dynamic>? ??
            <String, dynamic>{};
        map = inner;
      } else {
        map = <String, dynamic>{};
      }

      final title = _firstNonEmpty([
        map['name'],
        map['title'],
        map['displayName'],
        map['outingTitle'],
      ]);

      setState(() {
        _groupTitle = (title != null && title.trim().isNotEmpty)
            ? title.trim()
            : 'Group chat';
      });
    } catch (_) {
      setState(() => _groupTitle = 'Group chat');
    }
  }

  // ---- socket handlers ------------------------------------------------------

  void _onReceive(dynamic data) {
    if (!mounted) return;
    final chat = context.read<ChatState>();
    final map = Map<String, dynamic>.from(data as Map);
    final msg = Message.fromMap(map, chat.currentUserId);

    final atBottom = _isAtBottom(threshold: 80);

    if (!atBottom && _newMarkerId == null) {
      _newMarkerId = msg.id;
    }

    chat.addIncoming(msg);

    if (chat.groupId != null && msg.groupId == chat.groupId) {
      _repo.upsertGroupOne(chat.groupId!, msg);
    }

    if (chat.peerUserId != null) {
      final peer = chat.peerUserId!;

      if (!msg.isMine) {
        _repo.markThreadSeen(peer);
        if (!_readSent.contains(msg.id)) {
          _socket.sendRead(msg.id);
          _readSent.add(msg.id);
        }
      }
      _repo.upsertOne(peer, msg);
    }

    if (atBottom || msg.isMine) _scheduleScrollToBottom();
  }

  void _onTyping(dynamic data) {
    if (!mounted) return;
    final chat = context.read<ChatState>();
    final map = Map<String, dynamic>.from(data as Map);
    final isTyping = (map['isTyping'] ?? false) as bool;
    chat.setTyping(isTyping);
  }

  void _onMessageRead(dynamic data) {
    if (!mounted) return;
    final chat = context.read<ChatState>();
    final map = Map<String, dynamic>.from(data as Map);
    final messageId = (map['messageId'] ?? '').toString();
    if (messageId.isNotEmpty) chat.markRead(messageId);
  }

  void _onPresence(dynamic data) {
    if (!mounted) return;
    final chat = context.read<ChatState>();
    final map = Map<String, dynamic>.from(data as Map);
    final userId = (map['userId'] ?? '').toString();
    final isOnline = (map['online'] ?? false) as bool;
    if (chat.peerUserId != null && userId == chat.peerUserId) {
      setState(() => _peerOnline = isOnline);
    }
  }

  @override
  void initState() {
    super.initState();

    final chat = context.read<ChatState>();
    _socket.initSocket(userId: chat.currentUserId);

    _socket.on('receive_message', _onReceive);
    _socket.on('typing', _onTyping);
    _socket.on('message_read', _onMessageRead);
    _socket.on('presence', _onPresence);

    if (chat.groupId != null && chat.groupId!.isNotEmpty) {
      _socket.joinGroup(chat.groupId!);
      _repo.setActiveGroup(chat.groupId);
    } else {
      _repo.setActiveGroup(null);
    }

    if (chat.peerUserId != null) {
      _repo.setActivePeer(chat.peerUserId);
      _repo.markThreadSeen(chat.peerUserId!);
    } else {
      _repo.setActivePeer(null);
    }

    _loadGroupTitleIfNeeded();

    _controller.addListener(() {
      final next = _controller.text.trim().isNotEmpty;
      if (next != _canSend) setState(() => _canSend = next);
    });

    _scroll.addListener(() {
      final atBottom = _isAtBottom(threshold: 80);
      setState(() {
        _showJumpDown = !atBottom;
        if (atBottom) _newMarkerId = null;
      });

      if (_scroll.position.pixels <= 80) {
        _loadMoreHistory();
      }
    });

    if (chat.peerUserId != null) {
      _socket.queryPresence(chat.peerUserId!);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chat2 = context.read<ChatState>();

      final cached = _repo.getCachedDm(chat2.peerUserId ?? '');
      if (cached.isNotEmpty) {
        chat2.addHistory(cached, prepend: true);
        _scheduleScrollToBottom();
      }

      if (chat2.peerUserId != null) {
        _repo.markThreadSeen(chat2.peerUserId!);
      }
      _sendReadForVisible();

      _loadInitialHistory();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chat = context.read<ChatState>();
    if (chat.peerUserId != null) {
      _repo.setActivePeer(chat.peerUserId);
      _repo.markThreadSeen(chat.peerUserId!);
      _socket.queryPresence(chat.peerUserId!);
    }
    if (chat.groupId != null) {
      _repo.setActiveGroup(chat.groupId);
    }
  }

  @override
  void dispose() {
    final chat = context.read<ChatState>();
    if (chat.peerUserId != null) {
      _repo.markThreadSeen(chat.peerUserId!);
    }
    _repo.setActivePeer(null);

    if (chat.groupId != null && chat.groupId!.isNotEmpty) {
      _socket.leaveGroup(chat.groupId!);
    }
    _repo.setActiveGroup(null);

    _socket.off('receive_message', _onReceive);
    _socket.off('typing', _onTyping);
    _socket.off('message_read', _onMessageRead);
    _socket.off('presence', _onPresence);

    _debouncer.dispose();
    _controller.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- history & pagination -------------------------------------------------

  Future<void> _loadInitialHistory() async {
    if (!mounted || _initialLoaded) return;
    _initialLoaded = true;
    final chat = context.read<ChatState>();

    try {
      chat.setFetchingHistory(true);
      final page = await _repo.history(
        currentUserId: chat.currentUserId,
        peerUserId: chat.peerUserId,
        groupId: chat.groupId,
        cursor: null,
        limit: 25,
      );
      chat.addHistory(page.items, prepend: true);

      if (chat.peerUserId != null) {
        _repo.putDmMessages(chat.peerUserId!, page.items, prepend: true);
        _repo.markThreadSeen(chat.peerUserId!);
      }
      if (chat.groupId != null) {
        _repo.putGroupMessages(chat.groupId!, page.items, prepend: true);
      }

      chat.setNextCursor(page.nextCursor);
      _scheduleScrollToBottom();
    } catch (e) {
      debugPrint('Initial history load failed: $e');
    } finally {
      chat.setFetchingHistory(false);
    }
  }

  Future<void> _loadMoreHistory() async {
    if (!mounted) return;
    final chat = context.read<ChatState>();
    if (chat.isFetchingHistory || !chat.hasMoreHistory) return;

    try {
      chat.setFetchingHistory(true);
      final double oldPixels = _scroll.hasClients ? _scroll.position.pixels : 0;

      final page = await _repo.history(
        currentUserId: chat.currentUserId,
        peerUserId: chat.peerUserId,
        groupId: chat.groupId,
        cursor: chat.nextCursorIso,
        limit: 25,
      );

      final added = chat.addHistory(page.items, prepend: true);

      if (chat.peerUserId != null) {
        _repo.putDmMessages(chat.peerUserId!, page.items, prepend: true);
      }
      if (chat.groupId != null) {
        _repo.putGroupMessages(chat.groupId!, page.items, prepend: true);
      }

      chat.setNextCursor(page.nextCursor);

      if (added > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(oldPixels + 1);
        });
      }
    } catch (e) {
      debugPrint('Load more history failed: $e');
    } finally {
      chat.setFetchingHistory(false);
    }
  }

  // ---- sending / typing -----------------------------------------------------

  void _sendMessage() {
    final chat = context.read<ChatState>();
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _socket.sendMessage(
      text: text,
      senderId: chat.currentUserId,
      recipientId: chat.peerUserId,
      groupId: chat.groupId,
      messageType: 'text',
    );

    final optimistic = Message(
      id: 'tmp_${DateTime.now().microsecondsSinceEpoch}!',
      text: text,
      senderId: chat.currentUserId,
      recipientId: chat.peerUserId,
      groupId: chat.groupId,
      createdAt: DateTime.now(),
      isRead: false,
      isMine: true,
      messageType: 'text',
    );
    chat.addOutgoing(optimistic);

    if (chat.groupId != null) {
      _repo.upsertGroupOne(chat.groupId!, optimistic);
    } else if (chat.peerUserId != null) {
      _repo.upsertOne(chat.peerUserId!, optimistic);
    }

    _controller.clear();
    setState(() => _canSend = false);
    _scheduleScrollToBottom();

    _socket.sendTyping(
      isTyping: false,
      recipientId: chat.peerUserId,
      groupId: chat.groupId,
    );
  }

  String _prettyMB(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(2)}MB';
  }

  Future<File> _compressChatImage(File original) async {
    // Strict-ish for chat images (still readable)
    const int maxDim = 1440;
    const int quality = 75;

    final tmpDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final base = 'chat_$ts';

    // Try WebP first
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
    } catch (_) {
      // fallback below
    }

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

  Future<void> _pickAndSendAttachment() async {
    final chat = context.read<ChatState>();

    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      withData: false,
    );
    if (res == null || res.files.isEmpty) return;

    final picked = res.files.first;
    final path = picked.path;
    if (path == null) return;

    final originalFile = File(path);
    final isImage = _isImageExtension(picked.extension);

    final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Message(
      id: tempId,
      text: isImage ? '[image]' : (picked.name),
      senderId: chat.currentUserId,
      recipientId: chat.peerUserId,
      groupId: chat.groupId,
      createdAt: DateTime.now(),
      isRead: false,
      isMine: true,
      messageType: isImage ? 'image' : 'file',
      mediaUrl: null,
      fileName: picked.name,
      fileSize: picked.size,
    );
    chat.addOutgoing(optimistic);

    if (chat.groupId != null) {
      _repo.upsertGroupOne(chat.groupId!, optimistic);
    } else if (chat.peerUserId != null) {
      _repo.upsertOne(chat.peerUserId!, optimistic);
    }

    _scheduleScrollToBottom();

    File fileToUpload = originalFile;
    bool deleteTempAfter = false;

    try {
      // ✅ If it’s an image, compress before upload (STRICT COST CONTROL)
      if (isImage) {
        final before = await originalFile.length();
        final compressed = await _compressChatImage(originalFile);
        final after = await compressed.length();

        fileToUpload = compressed;
        deleteTempAfter = (compressed.path != originalFile.path);

        if (mounted && deleteTempAfter) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Image optimized ${_prettyMB(before)} → ${_prettyMB(after)}',
              ),
            ),
          );
        }
      }

      final up = await _uploader.uploadFile(fileToUpload);
      if (!mounted) return;

      _socket.sendMessage(
        text: isImage ? '' : (picked.name),
        senderId: chat.currentUserId,
        recipientId: chat.peerUserId,
        groupId: chat.groupId,
        messageType: isImage ? 'image' : 'file',
        mediaUrl: up.url,
        fileName: up.fileName ?? picked.name,
        fileSize: up.fileSize ?? picked.size,
      );
    } catch (e) {
      debugPrint('Upload failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Upload failed',
            style: TextStyle(color: Theme.of(context).colorScheme.onError),
          ),
        ),
      );
    } finally {
      // Clean up compressed temp file (never delete the original)
      if (deleteTempAfter) {
        try {
          if (await fileToUpload.exists()) await fileToUpload.delete();
        } catch (_) {}
      }
    }
  }

  bool _isImageExtension(String? ext) {
    final e = (ext ?? '').toLowerCase();
    return e == 'png' ||
        e == 'jpg' ||
        e == 'jpeg' ||
        e == 'gif' ||
        e == 'webp' ||
        e == 'bmp' ||
        e == 'heic';
  }

  void _maybeEmitTyping(String value) {
    final chat = context.read<ChatState>();
    _debouncer.run(() {
      _socket.sendTyping(
        isTyping: value.trim().isNotEmpty,
        recipientId: chat.peerUserId,
        groupId: chat.groupId,
      );
    });
  }

  void _sendReadForVisible() {
    final chat = context.read<ChatState>();
    for (final m in chat.messages) {
      if (!m.isMine && !m.isRead && !_readSent.contains(m.id)) {
        _socket.sendRead(m.id);
        _readSent.add(m.id);
      }
    }
    if (chat.peerUserId != null) {
      _repo.markThreadSeen(chat.peerUserId!);
    }
  }

  // ---- scrolling helpers ----------------------------------------------------

  bool _isAtBottom({double threshold = 12}) {
    if (!_scroll.hasClients) return true;
    final pos = _scroll.position;
    return pos.pixels >= (pos.maxScrollExtent - threshold);
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent + 100,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  int _unreadCount(List<Message> messages) {
    if (_newMarkerId == null) return 0;
    final idx = messages.indexWhere((m) => m.id == _newMarkerId);
    if (idx < 0) return 0;
    int count = 0;
    for (var i = idx; i < messages.length; i++) {
      final m = messages[i];
      if (!m.isMine) count++;
    }
    return count;
  }

  String _initialsFromId(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (clean.length >= 2) return clean.substring(0, 2).toUpperCase();
    if (clean.isNotEmpty) return clean[0].toUpperCase();
    return '🙂';
  }

  String _labelForDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    final messages = chat.messages;

    final c = Theme.of(context).colorScheme;
    final brand = Theme.of(context).extension<BrandColors>();

    WidgetsBinding.instance.addPostFrameCallback((_) => _sendReadForVisible());

    final resolver = DisplayNameResolver.of(context);
    String title;
    if (chat.peerUserId != null) {
      title = resolver.forUserId(chat.peerUserId!, fallback: 'Conversation');
    } else if (chat.groupId != null) {
      title = _groupTitle ?? 'Group chat';
    } else {
      title = 'Chat';
    }

    final unread = _unreadCount(messages);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final showPresenceDot = chat.peerUserId != null;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (showPresenceDot)
              Icon(
                Icons.circle,
                size: 10,
                color: _peerOnline
                    ? (brand?.success ?? c.secondary)
                    : c.outlineVariant,
              ),
            if (showPresenceDot) const SizedBox(width: 6),
            Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            if (chat.typingPeer)
              Text(
                '• typing...',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: c.onSurfaceVariant),
              ),
          ],
        ),
      ),
      floatingActionButton: _showJumpDown
          ? SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: FloatingActionButton(
                      onPressed: _scrollToBottom,
                      child: const Icon(Icons.arrow_downward),
                    ),
                  ),
                  if (unread > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: c.primary,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 2,
                              color: Theme.of(
                                context,
                              ).shadowColor.withValues(alpha: 0.15),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 18,
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: c.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            )
          : null,
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];

                bool showHeader = false;
                String? headerLabel;
                if (index == 0) {
                  showHeader = true;
                } else {
                  final prev = messages[index - 1];
                  final a = DateTime(
                    msg.createdAt.year,
                    msg.createdAt.month,
                    msg.createdAt.day,
                  );
                  final b = DateTime(
                    prev.createdAt.year,
                    prev.createdAt.month,
                    prev.createdAt.day,
                  );
                  if (a.difference(b).inDays != 0) showHeader = true;
                }
                if (showHeader) headerLabel = _labelForDate(msg.createdAt);

                final showNew = _newMarkerId != null && _newMarkerId == msg.id;

                final incomingLabel = !msg.isMine
                    ? (chat.peerUserId != null
                          ? resolver.initialsFor(chat.peerUserId!)
                          : _initialsFromId(msg.senderId))
                    : null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showHeader) DateDivider(headerLabel!),
                    if (showNew) const NewMessagesDivider(),
                    MessageBubble(message: msg, avatarLabel: incomingLabel),
                  ],
                );
              },
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: context.watch<ChatState>().isFetchingHistory
                ? const Padding(
                    key: ValueKey('loading_history'),
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('idle_history')),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: context.watch<ChatState>().typingPeer
                ? Padding(
                    key: const ValueKey('typing'),
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 6,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 4),
                        Text(
                          'typing…',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: c.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('not_typing')),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: bottomInset > 0 ? bottomInset : 12,
              top: 8,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _pickAndSendAttachment,
                    tooltip: 'Attach file/image',
                    color: c.onSurfaceVariant,
                  ),
                  Expanded(
                    child: TextField(
                      focusNode: _inputFocus,
                      controller: _controller,
                      onChanged: _maybeEmitTyping,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _canSend ? _sendMessage : null,
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String? _firstNonEmpty(List<dynamic> xs) {
    for (final x in xs) {
      if (x == null) continue;
      final s = x.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }
}
