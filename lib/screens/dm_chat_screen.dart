import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../models/workspace_model.dart';
import '../models/direct_message_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/logger_service.dart';
import '../services/dm_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/fcm_api_service.dart';
import '../services/navigation_service.dart';
import '../providers/voice_channel_provider.dart';
import '../providers/current_user_provider.dart';
import '../widgets/voice_channel_button.dart';
import '../widgets/voice_channel_controls.dart';
import '../widgets/webrtc_monitor_panel.dart';
import '../widgets/linkified_text.dart';
import '../services/preferences_service.dart';

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
  final _dmService = DMService();
  final _authService = AuthService();
  final _firestoreService = FirestoreService();
  final _fcmService = FcmApiService.instance;
  final _prefsService = PreferencesService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _messageFocusNode = FocusNode();
  bool _showEmojiPicker = false;
  MessageModel? _replyingTo;
  MessageModel? _editingMessage;
  late final Stream<List<MessageModel>> _messagesStream;
  Stream<UserModel?>? _otherUserStream;
  UserModel? _otherUserData;
  String? _otherUserId;
  String _quickEmoji = '❤️';

  @override
  void initState() {
    super.initState();
    _otherUserData = widget.otherUser;
    _initOtherUserStream();
    _loadQuickEmoji();

    // Set active DM to suppress notifications from this user while viewing
    NavigationService.instance.setActiveDM(widget.dm.id);
    _logger.info('Active DM set', category: 'DM', data: {'dmId': widget.dm.id});

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

  Future<void> _loadQuickEmoji() async {
    final emoji = await _prefsService.getQuickEmoji();
    if (mounted) {
      setState(() => _quickEmoji = emoji);
    }
  }

  Stream<List<MessageModel>> _getMessagesStream() {
    final currentUserId = _authService.currentUser?.uid;
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
      final messages = snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();

      // Auto mark as read when new messages arrive while viewing this DM
      if (currentUserId != null && messages.isNotEmpty) {
        // Check if there are messages from others (not from current user)
        final hasNewFromOthers = messages.any((m) => m.senderId != currentUserId);
        if (hasNewFromOthers) {
          _dmService.markAsRead(
            workspaceId: widget.workspace.id,
            dmId: widget.dm.id,
            userId: currentUserId,
          );
        }
      }

      return messages;
    });
  }

  void _initOtherUserStream() {
    final currentUserId = _authService.currentUser?.uid;
    _otherUserId = widget.dm.participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => widget.dm.participantIds.first,
    );

    // Set up real-time listener for other user's data (including online status)
    _otherUserStream = _firestoreService.getUserStream(_otherUserId!);
  }

  // Format last seen time as relative string
  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'son görülme: şimdi';
    } else if (difference.inMinutes < 60) {
      return 'son görülme: ${difference.inMinutes} dk önce';
    } else if (difference.inHours < 24) {
      return 'son görülme: ${difference.inHours} saat önce';
    } else if (difference.inDays < 7) {
      return 'son görülme: ${difference.inDays} gün önce';
    } else {
      return 'son görülme: ${DateFormat('dd MMM').format(lastSeen)}';
    }
  }

  @override
  void dispose() {
    // Clear active DM when leaving the screen
    NavigationService.instance.setActiveDM(null);
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final userId = _authService.currentUser?.uid;
    if (userId == null) return;

    try {
      final messageText = _messageController.text.trim();
      _messageController.clear();

      // Check for @notion command
      if (messageText.toLowerCase().startsWith('@notion ')) {
        final taskText = messageText.substring(8).trim(); // Remove "@notion " prefix
        if (taskText.isNotEmpty) {
          await _sendNotionTask(taskText, userId);
          return;
        }
      }

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
        // Send new message - use CurrentUserProvider (cached)
        final userProvider = context.read<CurrentUserProvider>();
        String userName = userProvider.displayName;
        String? userPhotoURL = userProvider.photoURL;

        // Fallback to Firebase Auth if provider not initialized
        if (userName.isEmpty) {
          userName = _authService.currentUser?.displayName ?? '';
          userPhotoURL = _authService.currentUser?.photoURL;
        }

        // Last resort: use email prefix
        if (userName.isEmpty) {
          userName = _authService.currentUser?.email?.split('@')[0] ?? 'User';
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

        // Send push notification to other user
        _fcmService.notifyDMMessage(
          workspaceId: widget.workspace.id,
          dmId: widget.dm.id,
          senderId: userId,
          senderName: userName,
          message: messageText,
          messageId: message.id,
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
    }
  }

  /// Send task to Notion via backend API
  Future<void> _sendNotionTask(String taskText, String userId) async {
    try {
      _logger.log(
        'Sending Notion task from DM',
        category: 'NOTION',
        data: {'taskText': taskText, 'dmId': widget.dm.id},
      );

      // Get user name from CurrentUserProvider (cached)
      final userProvider = context.read<CurrentUserProvider>();
      String userName = userProvider.displayName;
      if (userName.isEmpty) {
        userName = _authService.currentUser?.displayName ??
            _authService.currentUser?.email?.split('@')[0] ??
            'User';
      }

      final response = await http.post(
        Uri.parse('https://heybridgeservice-11767898554.europe-west1.run.app/api/notion/dm'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'workspaceId': widget.workspace.id,
          'dmId': widget.dm.id,
          'senderId': userId,
          'senderName': userName,
          'task_text': taskText,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        _logger.log(
          'Notion task created successfully from DM',
          level: LogLevel.success,
          category: 'NOTION',
          data: {'shortId': result['shortId'], 'taskName': result['taskName']},
        );
      } else {
        throw Exception('Failed to create Notion task: ${response.body}');
      }

      // Scroll to bottom to see the confirmation message
      if (_scrollController.hasClients) {
        await Future.delayed(const Duration(milliseconds: 500));
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      _logger.log(
        'Failed to send Notion task from DM',
        level: LogLevel.error,
        category: 'NOTION',
        data: {'error': e.toString()},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notion task gönderilemedi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

    // Get message data before transaction for notification
    String? messageText;
    String? messageSenderId;
    final messageSnapshot = await messageRef.get();
    if (messageSnapshot.exists) {
      final msgData = messageSnapshot.data()!;
      messageText = msgData['text'] as String?;
      messageSenderId = msgData['senderId'] as String?;
    }

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

    // Send notification to message owner (if not self)
    if (messageSenderId != null && messageSenderId != userId && messageText != null) {
      final currentUser = _authService.currentUser;
      final senderName = currentUser?.displayName ??
          currentUser?.email?.split('@')[0] ??
          'Birisi';

      // Truncate message if too long
      final truncatedMessage = messageText.length > 30
          ? '${messageText.substring(0, 30)}...'
          : messageText;

      _fcmService.notifyDMMessage(
        workspaceId: widget.workspace.id,
        dmId: widget.dm.id,
        senderId: userId,
        senderName: senderName,
        message: '$emoji "$truncatedMessage" mesajına tepki verdi',
        messageId: messageId,
      );
    }
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
    return Scaffold(
      backgroundColor: const Color(0xFF1A1D21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D21),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: StreamBuilder<UserModel?>(
          stream: _otherUserStream,
          initialData: _otherUserData,
          builder: (context, snapshot) {
            final user = snapshot.data ?? _otherUserData;
            final otherUserName = user?.displayName ?? 'User';

            final photoURL = user?.photoURL;
            final hasValidPhoto = photoURL != null && photoURL.isNotEmpty &&
                (photoURL.startsWith('http://') || photoURL.startsWith('https://'));
            return Row(
              children: [
                // Online indicator on avatar
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFF4A9EFF),
                      backgroundImage: hasValidPhoto
                          ? NetworkImage(photoURL)
                          : null,
                      child: !hasValidPhoto
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
                    // Online indicator dot
                    if (user?.isOnline == true)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E), // Green for online
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF1A1D21),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
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
                      // Online status text
                      if (user != null)
                        Text(
                          user.isOnline
                              ? 'Çevrimiçi'
                              : _formatLastSeen(user.lastSeen),
                          style: TextStyle(
                            color: user.isOnline
                                ? const Color(0xFF22C55E)
                                : Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          // Voice channel button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: VoiceChannelButton(
              workspaceId: widget.workspace.id,
              dmId: widget.dm.id,
              currentUserId: _authService.currentUser?.uid ?? '',
              otherUserId: _otherUserId ?? '',
              otherUserName: _otherUserData?.displayName ?? 'User',
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            Column(
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
                  return _buildEmptyState();
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

            // Voice channel controls overlay
            Consumer<VoiceChannelProvider>(
              builder: (context, voiceProvider, child) {
                if (voiceProvider.currentDmId == widget.dm.id &&
                    voiceProvider.isInVoiceChannel) {
                  return Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: VoiceChannelControls(
                      otherUserName: _otherUserData?.displayName ?? 'User',
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            // WebRTC Monitor Panel
            const WebRTCMonitorPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return StreamBuilder<UserModel?>(
      stream: _otherUserStream,
      initialData: _otherUserData,
      builder: (context, snapshot) {
        final user = snapshot.data ?? _otherUserData;
        final otherUserName = user?.displayName ?? 'User';
        final userPhoto = user?.photoURL;
        final hasPhoto = userPhoto != null && userPhoto.isNotEmpty &&
            (userPhoto.startsWith('http://') || userPhoto.startsWith('https://'));

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: const Color(0xFF4A9EFF),
                backgroundImage: hasPhoto
                    ? NetworkImage(userPhoto)
                    : null,
                child: !hasPhoto
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
                'Bu konuşmanın başlangıcı',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
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
              Builder(builder: (context) {
                final senderPhoto = message.senderPhotoURL;
                final hasSenderPhoto = senderPhoto != null && senderPhoto.isNotEmpty &&
                    (senderPhoto.startsWith('http://') || senderPhoto.startsWith('https://'));
                return CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF4A9EFF),
                  backgroundImage: hasSenderPhoto
                      ? NetworkImage(senderPhoto)
                      : null,
                  child: !hasSenderPhoto
                      ? Text(
                          message.senderName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                );
              }),
              const SizedBox(width: 8),
            ],

            // Message bubble
            Flexible(
              child: GestureDetector(
                onLongPress: () => _showMessageOptions(message),
                onDoubleTap: () => _onDoubleTapMessage(message),
                child: Column(
                  crossAxisAlignment: isOwnMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Container(
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

                          // Message text with clickable links
                          LinkifiedText(
                            text: message.text,
                            textAlign: TextAlign.start,
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
                                DateFormat('HH:mm').format(message.createdAt),
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
                              // Message status indicator (WhatsApp-style ticks) for own messages
                              if (isOwnMessage) ...[
                                const SizedBox(width: 4),
                                _buildMessageStatusIcon(message.status),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Reactions row
                    if (message.reactions != null && message.reactions!.isNotEmpty)
                      _buildReactionsRow(message, isOwnMessage),
                  ],
                ),
              ),
            ),

            if (isOwnMessage) const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  // Build WhatsApp-style message status icon
  Widget _buildMessageStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return Icon(
          Icons.access_time,
          size: 14,
          color: Colors.white.withValues(alpha: 0.6),
        );
      case MessageStatus.sent:
        return Icon(
          Icons.check,
          size: 14,
          color: Colors.white.withValues(alpha: 0.8),
        );
      case MessageStatus.delivered:
        return Icon(
          Icons.done_all,
          size: 14,
          color: Colors.white.withValues(alpha: 0.8),
        );
      case MessageStatus.read:
        return Icon(
          Icons.done_all,
          size: 14,
          color: const Color(0xFF34B7F1), // WhatsApp blue tick color
        );
    }
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
                leading: const Icon(Icons.add_reaction_outlined, color: Colors.white70),
                title: const Text('Add Reaction', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showReactionPicker(message);
                },
              ),
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
              ListTile(
                leading: Text(_quickEmoji, style: const TextStyle(fontSize: 24)),
                title: const Text('Quick Emoji', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Çift tıklama için emoji seç', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _showQuickEmojiPicker();
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

  /// Handle double-tap on message to add quick emoji reaction
  void _onDoubleTapMessage(MessageModel message) {
    final userId = _authService.currentUser?.uid;
    if (userId == null) return;

    _addReaction(message.id, _quickEmoji, userId);

    // Show brief feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$_quickEmoji tepkisi eklendi'),
        backgroundColor: const Color(0xFF4A9EFF),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 100, left: 20, right: 20),
      ),
    );
  }

  /// Show picker to select quick emoji for double-tap
  void _showQuickEmojiPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1D21),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Çift Tıklama Emojisi Seç',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Mesaja çift tıkladığınızda bu emoji tepkisi eklenecek',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              // Quick selection row
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: ['❤️', '👍', '😂', '😮', '😢', '🔥', '👏', '🎉']
                      .map((emoji) => GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              _setQuickEmoji(emoji);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _quickEmoji == emoji
                                    ? const Color(0xFF4A9EFF).withValues(alpha: 0.3)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: _quickEmoji == emoji
                                    ? Border.all(color: const Color(0xFF4A9EFF), width: 2)
                                    : null,
                              ),
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 28),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const Divider(color: Color(0xFF2D3748), height: 1),
              // Full emoji picker
              Flexible(
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    Navigator.pop(context);
                    _setQuickEmoji(emoji.emoji);
                  },
                  config: Config(
                    height: 200,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: const Color(0xFF1A1D21),
                      columns: 8,
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
          ),
        );
      },
    );
  }

  /// Set and save quick emoji
  Future<void> _setQuickEmoji(String emoji) async {
    setState(() => _quickEmoji = emoji);
    await _prefsService.saveQuickEmoji(emoji);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$emoji çift tıklama emojisi olarak ayarlandı'),
          backgroundColor: const Color(0xFF22C55E),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildReactionsRow(MessageModel message, bool isOwnMessage) {
    final currentUserId = _authService.currentUser?.uid;
    final reactions = message.reactions!;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: reactions.entries.map((entry) {
          final emoji = entry.key;
          final userIds = List<String>.from(entry.value);
          final hasReacted = currentUserId != null && userIds.contains(currentUserId);

          return GestureDetector(
            onTap: () {
              if (currentUserId == null) return;
              if (hasReacted) {
                _removeReaction(message.id, emoji, currentUserId);
              } else {
                _addReaction(message.id, emoji, currentUserId);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasReacted
                    ? const Color(0xFF4A9EFF).withValues(alpha: 0.3)
                    : const Color(0xFF2D3748),
                borderRadius: BorderRadius.circular(12),
                border: hasReacted
                    ? Border.all(color: const Color(0xFF4A9EFF), width: 1)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 14)),
                  if (userIds.length > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${userIds.length}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showReactionPicker(MessageModel message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1D21),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quick reactions row
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['👍', '❤️', '😂', '😮', '😢', '🔥', '👏', '🎉']
                      .map((emoji) => GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              final userId = _authService.currentUser?.uid;
                              if (userId != null) {
                                _addReaction(message.id, emoji, userId);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 28),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const Divider(color: Color(0xFF2D3748), height: 1),
              // Full emoji picker
              SizedBox(
                height: 300,
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    Navigator.pop(context);
                    final userId = _authService.currentUser?.uid;
                    if (userId != null) {
                      _addReaction(message.id, emoji.emoji, userId);
                    }
                  },
                  config: Config(
                    height: 300,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: const Color(0xFF1A1D21),
                      columns: 8,
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
                  child: KeyboardListener(
                    focusNode: FocusNode(),
                    onKeyEvent: (event) {
                      // Handle Enter key press (without Ctrl/Shift)
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
                        final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

                        if (!isCtrlPressed && !isShiftPressed) {
                          // Enter only: send message
                          _sendMessage();
                        }
                        // Ctrl+Enter or Shift+Enter: let it add newline naturally
                      }
                    },
                    child: TextField(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      style: const TextStyle(color: Colors.white),
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      textCapitalization: TextCapitalization.sentences,
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
                  icon: const Icon(Icons.send, color: Color(0xFF4A9EFF)),
                  onPressed: _sendMessage,
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
