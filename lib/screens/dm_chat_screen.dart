import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/workspace_model.dart';
import '../models/direct_message_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/logger_service.dart';
import '../services/message_service.dart';
import '../services/dm_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class DMChatScreen extends StatefulWidget {
  final WorkspaceModel workspace;
  final DirectMessageModel dm;
  final UserModel? otherUser;

  const DMChatScreen({
    super.key,
    required this.workspace,
    required this.dm,
    this.otherUser,
  });

  @override
  State<DMChatScreen> createState() => _DMChatScreenState();
}

class _DMChatScreenState extends State<DMChatScreen> {
  final _logger = LoggerService();
  final _messageService = MessageService();
  final _dmService = DMService();
  final _authService = AuthService();
  final _firestoreService = FirestoreService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _messageFocusNode = FocusNode();
  bool _isLoading = false;
  bool _showEmojiPicker = false;
  MessageModel? _replyingTo;
  MessageModel? _editingMessage;
  late final Stream<List<MessageModel>> _messagesStream;
  UserModel? _otherUserData;

  @override
  void initState() {
    super.initState();
    _otherUserData = widget.otherUser;
    _loadOtherUser();

    _logger.logUI('DMChatScreen', 'screen_opened',
      data: {
        'workspaceId': widget.workspace.id,
        'dmId': widget.dm.id,
      }
    );

    // Initialize messages stream for this DM
    // We'll use the same message structure but in a different collection path
    _messagesStream = _getMessagesStream();

    // Mark as read when opening
    final currentUserId = _authService.currentUser?.uid;
    if (currentUserId != null) {
      _dmService.markAsRead(
        workspaceId: widget.workspace.id,
        dmId: widget.dm.id,
        userId: currentUserId,
      );
    }
  }

  Stream<List<MessageModel>> _getMessagesStream() {
    return _firestoreService.firestore
        .collection('workspaces')
        .doc(widget.workspace.id)
        .collection('directMessages')
        .doc(widget.dm.id)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> _loadOtherUser() async {
    if (_otherUserData != null) return;

    final currentUserId = _authService.currentUser?.uid;
    final otherUserId = widget.dm.participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => widget.dm.participantIds.first,
    );

    final user = await _firestoreService.getUser(otherUserId);
    if (mounted) {
      setState(() => _otherUserData = user);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final userId = _authService.currentUser?.uid;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      final messageText = _messageController.text.trim();
      _messageController.clear();

      if (_editingMessage != null) {
        // Edit existing message
        final editingMessageId = _editingMessage!.id;

        await _firestoreService.firestore
            .collection('workspaces')
            .doc(widget.workspace.id)
            .collection('directMessages')
            .doc(widget.dm.id)
            .collection('messages')
            .doc(editingMessageId)
            .update({
          'text': messageText,
          'updatedAt': DateTime.now(),
          'isEdited': true,
        });

        setState(() => _editingMessage = null);

        _logger.logUI('DMChatScreen', 'message_edited',
          data: {'dmId': widget.dm.id, 'messageId': editingMessageId}
        );
      } else {
        // Send new message
        String userName = _authService.currentUser?.displayName ?? '';
        String? userPhotoURL = _authService.currentUser?.photoURL;

        if (userName.isEmpty) {
          final userDoc = await _firestoreService.getUser(userId);
          userName = userDoc?.displayName ?? _authService.currentUser?.email?.split('@')[0] ?? 'User';
          userPhotoURL = userDoc?.photoURL;
        }

        final messageRef = _firestoreService.firestore
            .collection('workspaces')
            .doc(widget.workspace.id)
            .collection('directMessages')
            .doc(widget.dm.id)
            .collection('messages')
            .doc();

        final message = MessageModel(
          id: messageRef.id,
          channelId: widget.dm.id, // Using dmId as channelId for compatibility
          senderId: userId,
          senderName: userName,
          senderPhotoURL: userPhotoURL,
          text: messageText,
          replyToId: _replyingTo?.id,
          createdAt: DateTime.now(),
        );

        await messageRef.set(message.toMap());

        // Update DM metadata
        await _dmService.updateDMMetadata(
          workspaceId: widget.workspace.id,
          dmId: widget.dm.id,
          lastMessage: messageText,
          senderId: userId,
        );

        _logger.logUI('DMChatScreen', 'message_sent',
          data: {'dmId': widget.dm.id, 'hasReply': _replyingTo != null}
        );
      }

      // Clear reply after sending
      if (_replyingTo != null) {
        setState(() => _replyingTo = null);
      }

      // Scroll to bottom
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      _logger.log('Failed to send message',
        level: LogLevel.error,
        category: 'DMChatScreen',
        data: {'error': e.toString()}
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    await _firestoreService.firestore
        .collection('workspaces')
        .doc(widget.workspace.id)
        .collection('directMessages')
        .doc(widget.dm.id)
        .collection('messages')
        .doc(messageId)
        .update({
      'text': 'This message was deleted',
      'isDeleted': true,
      'updatedAt': DateTime.now(),
    });
  }

  Future<void> _addReaction(String messageId, String emoji, String userId) async {
    final messageRef = _firestoreService.firestore
        .collection('workspaces')
        .doc(widget.workspace.id)
        .collection('directMessages')
        .doc(widget.dm.id)
        .collection('messages')
        .doc(messageId);

    await _firestoreService.firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(messageRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});

      if (reactions.containsKey(emoji)) {
        final users = List<String>.from(reactions[emoji]);
        if (!users.contains(userId)) {
          users.add(userId);
          reactions[emoji] = users;
        }
      } else {
        reactions[emoji] = [userId];
      }

      transaction.update(messageRef, {'reactions': reactions});
    });
  }

  Future<void> _removeReaction(String messageId, String emoji, String userId) async {
    final messageRef = _firestoreService.firestore
        .collection('workspaces')
        .doc(widget.workspace.id)
        .collection('directMessages')
        .doc(widget.dm.id)
        .collection('messages')
        .doc(messageId);

    await _firestoreService.firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(messageRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});

      if (reactions.containsKey(emoji)) {
        final users = List<String>.from(reactions[emoji]);
        users.remove(userId);

        if (users.isEmpty) {
          reactions.remove(emoji);
        } else {
          reactions[emoji] = users;
        }

        transaction.update(messageRef, {'reactions': reactions});
      }
    });
  }

  Future<MessageModel?> _getMessage(String messageId) async {
    final doc = await _firestoreService.firestore
        .collection('workspaces')
        .doc(widget.workspace.id)
        .collection('directMessages')
        .doc(widget.dm.id)
        .collection('messages')
        .doc(messageId)
        .get();

    if (!doc.exists) return null;
    return MessageModel.fromMap(doc.data()!, doc.id);
  }

  @override
  Widget build(BuildContext context) {
    final otherUserName = _otherUserData?.displayName ?? 'User';

    return Scaffold(
      backgroundColor: const Color(0xFF1A1D21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D21),
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF4A9EFF),
              backgroundImage: _otherUserData?.photoURL != null
                  ? NetworkImage(_otherUserData!.photoURL!)
                  : null,
              child: _otherUserData?.photoURL == null
                  ? Text(
                      otherUserName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otherUserName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // Online status will be added in Phase 7
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages Area
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF4A9EFF)),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return _buildEmptyState(otherUserName);
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final showDateHeader = index == messages.length - 1 ||
                        !_isSameDay(message.createdAt, messages[index + 1].createdAt);

                    return Column(
                      children: [
                        if (showDateHeader) _buildDateHeader(message.createdAt),
                        _buildMessageItem(message),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Message Input Area (same as ChatScreen)
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String otherUserName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: const Color(0xFF4A9EFF),
            backgroundImage: _otherUserData?.photoURL != null
                ? NetworkImage(_otherUserData!.photoURL!)
                : null,
            child: _otherUserData?.photoURL == null
                ? Text(
                    otherUserName[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            otherUserName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This is the beginning of your conversation',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final messageDate = DateTime(date.year, date.month, date.day);

    String dateText;
    if (messageDate == DateTime(now.year, now.month, now.day)) {
      dateText = 'Today';
    } else if (messageDate == yesterday) {
      dateText = 'Yesterday';
    } else {
      dateText = DateFormat('MMMM d, y').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.white.withValues(alpha: 0.2),
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              dateText,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Colors.white.withValues(alpha: 0.2),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  // Rest of the message building code is similar to ChatScreen
  // For brevity, I'll include the key methods

  Widget _buildMessageItem(MessageModel message) {
    final currentUserId = _authService.currentUser?.uid;
    final isOwnMessage = message.senderId == currentUserId;

    // Create the action pane for reply
    final replyActionPane = ActionPane(
      motion: const StretchMotion(),
      extentRatio: 0.25,
      dismissible: DismissiblePane(
        dismissThreshold: 0.4,
        closeOnCancel: true,
        onDismissed: () {},
        confirmDismiss: () async {
          if (mounted) {
            setState(() {
              _replyingTo = message;
              _showEmojiPicker = false;
            });
            _messageFocusNode.requestFocus();
          }
          return false;
        },
      ),
      children: [
        SlidableAction(
          onPressed: (context) {
            setState(() {
              _replyingTo = message;
              _showEmojiPicker = false;
            });
            _messageFocusNode.requestFocus();
          },
          backgroundColor: const Color(0xFF4A9EFF),
          foregroundColor: Colors.white,
          icon: Icons.reply,
          label: 'Reply',
        ),
      ],
    );

    return Slidable(
      key: ValueKey(message.id),
      closeOnScroll: true,
      // Own messages: swipe right-to-left (endActionPane)
      // Other messages: swipe left-to-right (startActionPane)
      endActionPane: isOwnMessage ? replyActionPane : null,
      startActionPane: !isOwnMessage ? replyActionPane : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: isOwnMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar for other user
            if (!isOwnMessage) ...[
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF4A9EFF),
                backgroundImage: message.senderPhotoURL != null
                    ? NetworkImage(message.senderPhotoURL!)
                    : null,
                child: message.senderPhotoURL == null
                    ? Text(
                        message.senderName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
            ],

            // Message bubble
            Flexible(
              child: GestureDetector(
                onLongPress: () => _showMessageOptions(message),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isOwnMessage
                        ? const Color(0xFF4A9EFF)
                        : const Color(0xFF2D3748),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isOwnMessage ? 18 : 4),
                      bottomRight: Radius.circular(isOwnMessage ? 4 : 18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Reply preview if applicable
                      if (message.replyToId != null)
                        FutureBuilder<MessageModel?>(
                          future: _getMessage(message.replyToId!),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const SizedBox.shrink();
                            final repliedMessage = snapshot.data!;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border(
                                  left: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    repliedMessage.senderName,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    repliedMessage.text,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 12,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                      // Message text
                      Text(
                        message.text,
                        style: TextStyle(
                          color: message.isDeleted
                              ? Colors.white.withValues(alpha: 0.6)
                              : Colors.white,
                          fontSize: 15,
                          fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Timestamp
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('h:mm a').format(message.createdAt),
                            style: TextStyle(
                              color: isOwnMessage
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                          if (message.isEdited) ...[
                            const SizedBox(width: 4),
                            Text(
                              '(edited)',
                              style: TextStyle(
                                color: isOwnMessage
                                    ? Colors.white.withValues(alpha: 0.8)
                                    : Colors.white.withValues(alpha: 0.5),
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (isOwnMessage) const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  void _showMessageOptions(MessageModel message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D3748),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.white70),
                title: const Text('Reply', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _replyingTo = message;
                    _showEmojiPicker = false;
                  });
                  _messageFocusNode.requestFocus();
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.white70),
                title: const Text('Copy Text', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await Clipboard.setData(ClipboardData(text: message.text));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Message copied to clipboard'),
                        backgroundColor: Color(0xFF4A9EFF),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                  _logger.logUI('DMChatScreen', 'message_copied',
                    data: {'messageId': message.id}
                  );
                },
              ),
              if (message.senderId == _authService.currentUser?.uid) ...[
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.white70),
                  title: const Text('Edit', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _editingMessage = message;
                      _messageController.text = message.text;
                      _replyingTo = null;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Delete', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(context);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF2D3748),
                        title: const Text('Delete Message', style: TextStyle(color: Colors.white)),
                        content: const Text(
                          'Are you sure you want to delete this message?',
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      await _deleteMessage(message.id);
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Column(
      children: [
        // Edit/Reply Preview
        if (_editingMessage != null || _replyingTo != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF2D3748),
              border: Border(
                top: BorderSide(color: Color(0xFF1A1D21), width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _editingMessage != null
                        ? Colors.orange
                        : const Color(0xFF4A9EFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _editingMessage != null
                        ? 'Editing message'
                        : 'Replying to ${_replyingTo?.senderName}',
                    style: TextStyle(
                      color: _editingMessage != null
                          ? Colors.orange
                          : const Color(0xFF4A9EFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: () {
                    setState(() {
                      _editingMessage = null;
                      _replyingTo = null;
                      if (_editingMessage != null) {
                        _messageController.clear();
                      }
                    });
                  },
                ),
              ],
            ),
          ),

        // Input Field
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF2D3748),
            border: Border(
              top: BorderSide(color: Color(0xFF1A1D21), width: 1),
            ),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    style: const TextStyle(color: Colors.white),
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    onTap: () {
                      if (_showEmojiPicker) {
                        setState(() => _showEmojiPicker = false);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Message ${_otherUserData?.displayName ?? ""}',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1A1D21),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined,
                    color: Colors.white70,
                  ),
                  onPressed: () {
                    setState(() => _showEmojiPicker = !_showEmojiPicker);
                  },
                ),
                IconButton(
                  icon: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF4A9EFF),
                          ),
                        )
                      : const Icon(Icons.send, color: Color(0xFF4A9EFF)),
                  onPressed: _isLoading ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ),

        // Emoji Picker
        if (_showEmojiPicker)
          SizedBox(
            height: 250,
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) {
                _messageController.text += emoji.emoji;
              },
              config: Config(
                height: 256,
                checkPlatformCompatibility: true,
                emojiViewConfig: EmojiViewConfig(
                  backgroundColor: const Color(0xFF1A1D21),
                  columns: 7,
                  emojiSizeMax: 28,
                ),
                skinToneConfig: const SkinToneConfig(enabled: true),
                categoryViewConfig: const CategoryViewConfig(
                  indicatorColor: Color(0xFF4A9EFF),
                  iconColorSelected: Color(0xFF4A9EFF),
                  backspaceColor: Color(0xFF4A9EFF),
                  backgroundColor: Color(0xFF2D3748),
                  iconColor: Colors.white70,
                ),
                bottomActionBarConfig: const BottomActionBarConfig(
                  backgroundColor: Color(0xFF2D3748),
                  buttonColor: Color(0xFF2D3748),
                  buttonIconColor: Colors.white70,
                ),
                searchViewConfig: const SearchViewConfig(
                  backgroundColor: Color(0xFF1A1D21),
                  buttonIconColor: Colors.white70,
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }
}
