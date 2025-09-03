import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import 'package:outings_app/services/socket_service.dart';
import 'package:outings_app/services/upload_service.dart';
import 'package:outings_app/utils/debouncer.dart';
import 'package:outings_app/models/message.dart';
import 'package:outings_app/features/messages/messages_repository.dart';
import 'package:outings_app/config/app_config.dart';
import 'messages_repository.dart';
import 'chat_state.dart';
import 'widgets/message_bubble.dart';
import 'widgets/date_divider.dart';
import 'widgets/new_messages_divider.dart';

// History base URL now comes from repository via AppConfig.

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

  StreamSubscription<bool>? _connSub;
  bool _offline = false;

  bool _canSend = false;
  bool _peerOnline = false;
  bool _showJumpDown = false;

  String? _newMarkerId;
  bool _initialLoaded = false;

  // ---- socket event handlers ----
  void _onReceive(dynamic data) {
    final chat = context.read<ChatState>();
    final map = Map<String, dynamic>.from(data as Map);
    final msg = Message.fromMap(map, chat.currentUserId);

    final atBottom = _scroll.hasClients &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 12;

    if (!atBottom && _newMarkerId == null) {
      _newMarkerId = msg.id;
    }

    chat.addIncoming(msg);
    if (atBottom) _scheduleScrollToBottom();
  }

  void _onTyping(dynamic data) {
    final chat = context.read<ChatState>();
    final map = Map<String, dynamic>.from(data as Map);
    final isTyping = (map['isTyping'] ?? false) as bool;
    chat.setTyping(isTyping);
  }

  void _onMessageRead(dynamic data) {
    final chat = context.read<ChatState>();
    final map = Map<String, dynamic>.from(data as Map);
    final messageId = (map['messageId'] ?? '').toString();
    if (messageId.isNotEmpty) chat.markRead(messageId);
  }

  void _onPresence(dynamic data) {
    final map = Map<String, dynamic>.from(data as Map);
    final isOnline = (map['online'] ?? false) as bool;
    setState(() => _peerOnline = isOnline);
  }

  @override
  void initState() {
    super.initState();
    _socket.initSocket();

    _socket.on('receive_message', _onReceive);
    _socket.on('typing', _onTyping);
    _socket.on('message_read', _onMessageRead);
    _socket.on('presence', _onPresence);

    _controller.addListener(() {
      final next = _controller.text.trim().isNotEmpty;
      if (next != _canSend) setState(() => _canSend = next);
    });

    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final atBottom = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 12;
      setState(() {
        _showJumpDown = !atBottom;
        if (atBottom) _newMarkerId = null;
      });

      if (_scroll.position.pixels <= 80) {
        _loadMoreHistory();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadInitialHistory();
    });
  }

  @override
  void dispose() {
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

  // ---- history & pagination ----

  Future<void> _loadInitialHistory() async {
    if (!mounted) return;
    final chat = context.read<ChatState>();
    if (_initialLoaded) return;
    _initialLoaded = true;

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

  // ---- UI helpers ----
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
      id: DateTime.now().millisecondsSinceEpoch.toString(),
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

    _controller.clear();
    setState(() => _canSend = false);
    _scheduleScrollToBottom();

    _socket.sendTyping(
      isTyping: false,
      recipientId: chat.peerUserId,
      groupId: chat.groupId,
    );
  }

  Future<void> _pickAndSendAttachment() async {
    final chat = context.read<ChatState>();

    // 1) Pick (allow images and files)
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      withData: false,
    );
    if (res == null || res.files.isEmpty) return;

    final picked = res.files.first;
    final path = picked.path;
    if (path == null) return;

    final file = File(path);
    final isImage = _isImageExtension(picked.extension);

    // 2) Optimistic bubble (with temporary "uploading" text)
    final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Message(
      id: tempId,
      text: isImage ? '[image]' : (picked.name ?? '[file]'),
      senderId: chat.currentUserId,
      recipientId: chat.peerUserId,
      groupId: chat.groupId,
      createdAt: DateTime.now(),
      isRead: false,
      isMine: true,
      messageType: isImage ? 'image' : 'file',
      mediaUrl: null, // to be filled after upload
      fileName: picked.name,
      fileSize: picked.size,
    );
    chat.addOutgoing(optimistic);
    _scheduleScrollToBottom();

    try {
      // 3) Upload
      final up = await _uploader.uploadFile(file);

      // 4) Send via socket
      _socket.sendMessage(
        text: isImage ? '' : (picked.name ?? ''),
        senderId: chat.currentUserId,
        recipientId: chat.peerUserId,
        groupId: chat.groupId,
        messageType: isImage ? 'image' : 'file',
        mediaUrl: up.url,
        fileName: up.fileName ?? picked.name,
        fileSize: up.fileSize ?? picked.size,
      );

      // (Optional) You could replace the optimistic message with a final one if you had server id
      // For now, the "official" message will arrive via socket from backend and show up naturally.
    } catch (e) {
      debugPrint('Upload failed: $e');
      // (Optional) show a snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload failed')),
        );
      }
    }
  }

  bool _isImageExtension(String? ext) {
    final e = (ext ?? '').toLowerCase();
    return e == 'png' || e == 'jpg' || e == 'jpeg' || e == 'gif' || e == 'webp' || e == 'bmp' || e == 'heic';
    // Render side uses messageType anyway; this is just for optimistic label.
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

  DateTime _dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  String _labelForDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _initialsFromId(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (clean.length >= 2) return clean.substring(0, 2).toUpperCase();
    if (clean.isNotEmpty) return clean[0].toUpperCase();
    return '🙂';
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    final messages = chat.messages;

    WidgetsBinding.instance.addPostFrameCallback((_) => _sendReadForVisible());

    final peerName = chat.peerUserId ?? chat.groupId ?? 'Chat';
    final avatarLabel = _initialsFromId(chat.peerUserId ?? '🙂');
    final unread = _unreadCount(messages);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.circle, size: 10, color: _peerOnline ? Colors.green : Colors.grey),
            const SizedBox(width: 6),
            Text(peerName, overflow: TextOverflow.ellipsis),
            const SizedBox(width: 8),
            if (chat.typingPeer) const Text('• typing...', style: TextStyle(fontSize: 12)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
                        ),
                        constraints: const BoxConstraints(minWidth: 22, minHeight: 18),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            )
          : null,

      body: Column(
        children: [
          // Pull-to-refresh + sticky headers
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];

                // day header logic
                bool showHeader = false;
                String? headerLabel;
                if (index == 0) {
                  showHeader = true;
                } else {
                  final prev = messages[index - 1];
                  final a = DateTime(msg.createdAt.year, msg.createdAt.month, msg.createdAt.day);
                  final b = DateTime(prev.createdAt.year, prev.createdAt.month, prev.createdAt.day);
                  if (a.difference(b).inDays != 0) showHeader = true;
                }
                if (showHeader) {
                  headerLabel = _labelForDate(msg.createdAt);
                }

                final showNew = _newMarkerId != null && _newMarkerId == msg.id;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showHeader) DateDivider(headerLabel!),
                    if (showNew) const NewMessagesDivider(),
                    MessageBubble(
                      message: msg,
                      avatarLabel: msg.isMine ? null : _initialsFromId(msg.senderId),
                    ),
                  ],
                );
              },
            ),
          ),


          // history loader indicator
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

          // typing row
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: context.watch<ChatState>().typingPeer
                ? Padding(
                    key: const ValueKey('typing'),
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
                    child: Row(
                      children: const [
                        SizedBox(width: 4),
                        Text('typing…', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('not_typing')),
          ),

          // sticky input bar
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
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // paperclip
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _pickAndSendAttachment,
                    tooltip: 'Attach file/image',
                  ),
                  Expanded(
                    child: TextField(
                      focusNode: _inputFocus,
                      controller: _controller,
                      onChanged: _maybeEmitTyping,
                      decoration: const InputDecoration(hintText: 'Type a message...'),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _canSend ? _sendMessage : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
