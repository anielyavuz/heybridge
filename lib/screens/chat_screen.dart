import 'package:flutter/material.dart';
import '../models/workspace_model.dart';
import '../models/channel_model.dart';
import '../services/logger_service.dart';

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
  final _messageController = TextEditingController();

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
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
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
              // TODO: Show channel info
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages Area
          Expanded(
            child: Container(
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
                      'No messages yet',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Message Input Area
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
                      style: const TextStyle(color: Colors.white),
                      maxLines: null,
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
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white70),
                    onPressed: () {
                      // TODO: Show emoji picker
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF4A9EFF)),
                    onPressed: () {
                      // TODO: Send message
                      if (_messageController.text.trim().isNotEmpty) {
                        _logger.logUI('ChatScreen', 'message_send_attempted',
                          data: {'channelId': widget.channel.id}
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Messaging coming in Phase 4!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        _messageController.clear();
                      }
                    },
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
