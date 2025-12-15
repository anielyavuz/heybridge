import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/workspace_model.dart';
import '../models/channel_model.dart';
import '../models/message_model.dart';
import '../services/logger_service.dart';
import '../services/message_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/channel_service.dart';
import 'channel_settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final WorkspaceModel workspace;
  final ChannelModel channel;

  const ChatScreen({
    super.key,
    required this.workspace,
    required this.channel,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _logger = LoggerService();
  final _messageService = MessageService();
  final _authService = AuthService();
  final _firestoreService = FirestoreService();
  final _channelService = ChannelService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _messageFocusNode = FocusNode();
  bool _showEmojiPicker = false;
  MessageModel? _replyingTo;
  MessageModel? _editingMessage;
  late final Stream<List<MessageModel>> _messagesStream;

  @override
  void initState() {
    super.initState();
    _logger.logUI('ChatScreen', 'screen_opened',
      data: {
        'workspaceId': widget.workspace.id,
        'channelId': widget.channel.id,
        'channelName': widget.channel.name,
      }
    );

    // Initialize the stream once in initState
    _messagesStream = _messageService.getChannelMessagesStream(
      workspaceId: widget.workspace.id,
      channelId: widget.channel.id,
    );

    // Mark channel as read when opening
    _markAsRead();
  }

  Future<void> _markAsRead() async {
    final userId = _authService.currentUser?.uid;
    if (userId != null) {
      await _channelService.markChannelAsRead(
        workspaceId: widget.workspace.id,
        channelId: widget.channel.id,
        userId: userId,
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<String> _getSenderDisplayName(String senderId, String currentName) async {
    // If the current name is not "Unknown User", return it
    if (currentName != 'Unknown User') {
      return currentName;
    }

    // Try to get from Firestore
    try {
      final userDoc = await _firestoreService.getUser(senderId);
      if (userDoc != null && userDoc.displayName.isNotEmpty) {
        return userDoc.displayName;
      }
    } catch (e) {
      _logger.log('Failed to fetch user display name',
        level: LogLevel.error,
        category: 'Chat',
        data: {'senderId': senderId, 'error': e.toString()}
      );
    }

    // Last resort: return current name or "User"
    return currentName;
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final userId = _authService.currentUser?.uid;
    if (userId == null) return;

    try {
      final messageText = _messageController.text.trim();
      _messageController.clear();

      // Check if we're editing or sending new message
      if (_editingMessage != null) {
        // Edit existing message
        final editingMessageId = _editingMessage!.id;

        await _messageService.updateMessage(
          workspaceId: widget.workspace.id,
          channelId: widget.channel.id,
          messageId: editingMessageId,
          newText: messageText,
        );

        setState(() => _editingMessage = null);

        _logger.logUI('ChatScreen', 'message_edited',
          data: {'channelId': widget.channel.id, 'messageId': editingMessageId}
        );
      } else {
        // Send new message
        // Get user name - first try Firebase Auth, then Firestore
        String userName = _authService.currentUser?.displayName ?? '';
        String? userPhotoURL = _authService.currentUser?.photoURL;

        if (userName.isEmpty) {
          final userDoc = await _firestoreService.getUser(userId);
          userName = userDoc?.displayName ?? _authService.currentUser?.email?.split('@')[0] ?? 'User';
          userPhotoURL = userDoc?.photoURL;
        }

        await _messageService.sendMessage(
          workspaceId: widget.workspace.id,
          channelId: widget.channel.id,
          senderId: userId,
          senderName: userName,
          senderPhotoURL: userPhotoURL,
          text: messageText,
          replyToId: _replyingTo?.id,
        );

        // Increment unread count for all workspace members (public channels)
        // Use workspace memberIds instead of channel memberIds
        await _channelService.incrementUnreadCount(
          workspaceId: widget.workspace.id,
          channelId: widget.channel.id,
          senderId: userId,
          memberIds: widget.workspace.memberIds,
        );

        _logger.logUI('ChatScreen', 'message_sent',
          data: {'channelId': widget.channel.id, 'hasReply': _replyingTo != null}
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
        category: 'Chat',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1D21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D3748),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(
              widget.channel.isPrivate ? Icons.lock : Icons.tag,
              color: Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.channel.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.channel.description != null)
                    Text(
                      widget.channel.description!,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white70),
            onPressed: () {
              _logger.logUI('ChatScreen', 'info_button_pressed',
                data: {'channelId': widget.channel.id}
              );
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChannelSettingsScreen(
                    workspace: widget.workspace,
                    channel: widget.channel,
                  ),
                ),
              );
            },
          ),
        ],
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
                      'Error loading messages: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
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
                        if (showDateHeader)
                          _buildDateHeader(message.createdAt),
                        _buildMessageItem(message),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Message Input Area
          Column(
            children: [
              // Edit Preview (if editing a message)
              if (_editingMessage != null)
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
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Editing message',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Press send to save changes',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () {
                          setState(() {
                            _editingMessage = null;
                            _messageController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),

              // Reply Preview (if replying to a message)
              if (_replyingTo != null && _editingMessage == null)
                FutureBuilder<String>(
                  future: _getSenderDisplayName(_replyingTo!.senderId, _replyingTo!.senderName),
                  builder: (context, snapshot) {
                    final displayName = snapshot.data ?? _replyingTo!.senderName;

                    return Container(
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
                              color: const Color(0xFF4A9EFF),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Replying to $displayName',
                                  style: const TextStyle(
                                    color: Color(0xFF4A9EFF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _replyingTo!.text,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                            onPressed: () {
                              setState(() => _replyingTo = null);
                            },
                          ),
                        ],
                      ),
                    );
                  },
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
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                        onPressed: () {
                          // TODO: Show attachment options
                        },
                      ),
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
                            hintText: 'Message #${widget.channel.name}',
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
                      skinToneConfig: const SkinToneConfig(
                        enabled: true,
                      ),
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
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: const Color(0xFF1A1D21),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.channel.isPrivate ? Icons.lock : Icons.tag,
              size: 60,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome to #${widget.channel.name}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.channel.description ?? 'This is the start of your conversation',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const Text(
              'No messages yet. Start the conversation!',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ],
        ),
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

  void _showEmojiReactionPicker(MessageModel message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D3748),
      builder: (context) {
        return SizedBox(
          height: 350,
          child: EmojiPicker(
            onEmojiSelected: (category, emoji) async {
              Navigator.pop(context);

              final userId = _authService.currentUser?.uid;
              if (userId == null) return;

              try {
                await _messageService.addReaction(
                  workspaceId: widget.workspace.id,
                  channelId: widget.channel.id,
                  messageId: message.id,
                  emoji: emoji.emoji,
                  userId: userId,
                );

                _logger.logUI('ChatScreen', 'reaction_added',
                  data: {'messageId': message.id, 'emoji': emoji.emoji}
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to add reaction: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            config: Config(
              height: 256,
              checkPlatformCompatibility: true,
              emojiViewConfig: EmojiViewConfig(
                backgroundColor: const Color(0xFF1A1D21),
                columns: 7,
                emojiSizeMax: 32,
              ),
              categoryViewConfig: const CategoryViewConfig(
                indicatorColor: Color(0xFF4A9EFF),
                iconColorSelected: Color(0xFF4A9EFF),
                backgroundColor: Color(0xFF2D3748),
                iconColor: Colors.white70,
              ),
              bottomActionBarConfig: const BottomActionBarConfig(
                backgroundColor: Color(0xFF2D3748),
                buttonColor: Color(0xFF2D3748),
                buttonIconColor: Colors.white70,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showMessageOptions(MessageModel message) {
    final currentUserId = _authService.currentUser?.uid;
    final isStarred = message.starredBy?.contains(currentUserId) ?? false;

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
                leading: const Icon(Icons.add_reaction_outlined, color: Colors.white70),
                title: const Text('Add Reaction', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showEmojiReactionPicker(message);
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
                  _logger.logUI('ChatScreen', 'message_copied',
                    data: {'messageId': message.id}
                  );
                },
              ),
              // Star/Unstar message
              ListTile(
                leading: Icon(
                  isStarred ? Icons.star : Icons.star_border,
                  color: isStarred ? Colors.amber : Colors.white70,
                ),
                title: Text(
                  isStarred ? 'Remove from Saved' : 'Save Message',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  if (currentUserId == null) return;

                  try {
                    if (isStarred) {
                      await _messageService.unstarMessage(
                        workspaceId: widget.workspace.id,
                        channelId: widget.channel.id,
                        messageId: message.id,
                        userId: currentUserId,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Message removed from saved'),
                            backgroundColor: Color(0xFF2D3748),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } else {
                      await _messageService.starMessage(
                        workspaceId: widget.workspace.id,
                        channelId: widget.channel.id,
                        messageId: message.id,
                        userId: currentUserId,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Message saved'),
                            backgroundColor: Color(0xFF4A9EFF),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                    _logger.logUI('ChatScreen', isStarred ? 'message_unstarred' : 'message_starred',
                      data: {'messageId': message.id}
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to ${isStarred ? 'unsave' : 'save'} message: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
              // Pin/Unpin message
              ListTile(
                leading: Icon(
                  message.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: message.isPinned ? const Color(0xFF4A9EFF) : Colors.white70,
                ),
                title: Text(
                  message.isPinned ? 'Unpin Message' : 'Pin Message',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  if (currentUserId == null) return;

                  try {
                    if (message.isPinned) {
                      await _messageService.unpinMessage(
                        workspaceId: widget.workspace.id,
                        channelId: widget.channel.id,
                        messageId: message.id,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Message unpinned'),
                            backgroundColor: Color(0xFF2D3748),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } else {
                      await _messageService.pinMessage(
                        workspaceId: widget.workspace.id,
                        channelId: widget.channel.id,
                        messageId: message.id,
                        userId: currentUserId,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Message pinned'),
                            backgroundColor: Color(0xFF4A9EFF),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                    _logger.logUI('ChatScreen', message.isPinned ? 'message_unpinned' : 'message_pinned',
                      data: {'messageId': message.id}
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to ${message.isPinned ? 'unpin' : 'pin'} message: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
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
                      try {
                        await _messageService.deleteMessage(
                          workspaceId: widget.workspace.id,
                          channelId: widget.channel.id,
                          messageId: message.id,
                        );

                        _logger.logUI('ChatScreen', 'message_deleted',
                          data: {'channelId': widget.channel.id, 'messageId': message.id}
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to delete message: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
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

  Widget _buildMessageItem(MessageModel message) {
    final currentUserId = _authService.currentUser?.uid;
    final isOwnMessage = message.senderId == currentUserId;

    // Create the action pane for reply
    final replyActionPane = ActionPane(
      motion: const StretchMotion(),
      extentRatio: 0.25,
      dismissible: DismissiblePane(
        dismissThreshold: 0.4, // Trigger at 40%
        closeOnCancel: true,
        onDismissed: () {
          // This won't be called because confirmDismiss returns false
        },
        confirmDismiss: () async {
          // Don't actually dismiss, just trigger the reply
          if (mounted) {
            setState(() {
              _replyingTo = message;
              _showEmojiPicker = false;
            });
            _messageFocusNode.requestFocus();
          }
          return false; // Return false to prevent actual dismissal
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
          // Avatar (only for other users' messages)
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

          // Message Bubble
          Flexible(
            child: Column(
              crossAxisAlignment: isOwnMessage
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
              children: [
                // Sender name (only for other users)
                if (!isOwnMessage)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                // Message Container with Long Press
                GestureDetector(
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Replied message preview (if this is a reply)
                        if (message.replyToId != null)
                          FutureBuilder<MessageModel?>(
                            future: _messageService.getMessage(
                              workspaceId: widget.workspace.id,
                              channelId: widget.channel.id,
                              messageId: message.replyToId!,
                            ),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData || snapshot.data == null) {
                                return const SizedBox.shrink();
                              }

                              final repliedMessage = snapshot.data!;

                              // Get sender name - if it's "Unknown User", try to fetch from Firestore
                              return FutureBuilder<String>(
                                future: _getSenderDisplayName(repliedMessage.senderId, repliedMessage.senderName),
                                builder: (context, nameSnapshot) {
                                  final displayName = nameSnapshot.data ?? repliedMessage.senderName;

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
                                          displayName,
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

                        // Timestamp, edited, pinned, and starred indicators
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Pinned indicator
                            if (message.isPinned) ...[
                              Icon(
                                Icons.push_pin,
                                size: 12,
                                color: isOwnMessage
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : const Color(0xFF4A9EFF),
                              ),
                              const SizedBox(width: 4),
                            ],
                            // Starred indicator
                            if (message.starredBy?.contains(currentUserId) ?? false) ...[
                              Icon(
                                Icons.star,
                                size: 12,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 4),
                            ],
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
                ),

                // Reactions (if any)
                if (message.reactions != null && message.reactions!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 12, right: 12),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: message.reactions!.entries.map((entry) {
                        final emoji = entry.key;
                        final userIds = entry.value;
                        final count = userIds.length;
                        final currentUserId = _authService.currentUser?.uid;
                        final hasReacted = currentUserId != null && userIds.contains(currentUserId);

                        return GestureDetector(
                          onTap: () async {
                            if (currentUserId == null) return;

                            try {
                              if (hasReacted) {
                                // Remove reaction
                                await _messageService.removeReaction(
                                  workspaceId: widget.workspace.id,
                                  channelId: widget.channel.id,
                                  messageId: message.id,
                                  emoji: emoji,
                                  userId: currentUserId,
                                );
                              } else {
                                // Add reaction
                                await _messageService.addReaction(
                                  workspaceId: widget.workspace.id,
                                  channelId: widget.channel.id,
                                  messageId: message.id,
                                  emoji: emoji,
                                  userId: currentUserId,
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to update reaction: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: hasReacted
                                ? const Color(0xFF4A9EFF).withValues(alpha: 0.3)
                                : const Color(0xFF1A1D21),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: hasReacted
                                  ? const Color(0xFF4A9EFF)
                                  : Colors.white.withValues(alpha: 0.2),
                                width: hasReacted ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(emoji, style: const TextStyle(fontSize: 12)),
                                const SizedBox(width: 3),
                                Text(
                                  count.toString(),
                                  style: TextStyle(
                                    color: hasReacted
                                      ? const Color(0xFF4A9EFF)
                                      : Colors.white.withValues(alpha: 0.8),
                                    fontSize: 11,
                                    fontWeight: hasReacted ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),

          // Spacing for own messages
          if (isOwnMessage) const SizedBox(width: 8),
        ],
      ),
      ),
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
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
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.done_all,
              size: 14,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ],
        );
      case MessageStatus.read:
        return Icon(
          Icons.done_all,
          size: 14,
          color: const Color(0xFF34B7F1), // WhatsApp blue tick color
        );
    }
  }
}
