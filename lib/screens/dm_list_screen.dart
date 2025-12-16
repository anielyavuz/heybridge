import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/workspace_model.dart';
import '../models/direct_message_model.dart';
import '../models/user_model.dart';
import '../services/dm_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/logger_service.dart';
import 'dm_chat_screen.dart';
import 'new_dm_screen.dart';

class DMListScreen extends StatefulWidget {
  final WorkspaceModel workspace;

  const DMListScreen({
    super.key,
    required this.workspace,
  });

  @override
  State<DMListScreen> createState() => _DMListScreenState();
}

class _DMListScreenState extends State<DMListScreen> {
  final _dmService = DMService();
  final _authService = AuthService();
  final _firestoreService = FirestoreService();
  final _logger = LoggerService();

  /// Check if user is online (isOnline flag OR lastSeen within 1 minute)
  bool _isUserOnline(UserModel? user) {
    if (user == null) return false;
    if (user.isOnline) return true;
    final now = DateTime.now();
    final difference = now.difference(user.lastSeen);
    return difference.inMinutes < 1;
  }

  @override
  void initState() {
    super.initState();
    _logger.logUI('DMListScreen', 'screen_opened',
      data: {'workspaceId': widget.workspace.id}
    );
  }

  String _getOtherParticipantId(List<String> participantIds) {
    final currentUserId = _authService.currentUser?.uid;
    return participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => participantIds.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1D21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D21),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Direct Messages',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.workspace.name,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NewDMScreen(workspace: widget.workspace),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<DirectMessageModel>>(
        stream: currentUserId != null
            ? _dmService.getUserDMsStream(
                workspaceId: widget.workspace.id,
                userId: currentUserId,
              )
            : null,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF4A9EFF)),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading DMs: ${snapshot.error}',
                style: const TextStyle(color: Colors.white70),
              ),
            );
          }

          final dms = snapshot.data ?? [];

          if (dms.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            itemCount: dms.length,
            itemBuilder: (context, index) {
              final dm = dms[index];
              return _buildDMItem(dm);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          const Text(
            'No direct messages yet',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start a conversation with your teammates',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NewDMScreen(workspace: widget.workspace),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Start New DM'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDMItem(DirectMessageModel dm) {
    final currentUserId = _authService.currentUser?.uid;
    final otherParticipantId = _getOtherParticipantId(dm.participantIds);
    final unreadCount = dm.unreadCounts[currentUserId] ?? 0;

    // Use StreamBuilder for real-time online status updates
    return StreamBuilder<UserModel?>(
      stream: _firestoreService.getUserStream(otherParticipantId),
      builder: (context, userSnapshot) {
        final otherUser = userSnapshot.data;
        final displayName = otherUser?.displayName ?? 'User';
        final photoURL = otherUser?.photoURL;
        final hasValidPhoto = photoURL != null && photoURL.isNotEmpty &&
            (photoURL.startsWith('http://') || photoURL.startsWith('https://'));
        final isOnline = _isUserOnline(otherUser);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF4A9EFF),
                backgroundImage: hasValidPhoto ? NetworkImage(photoURL) : null,
                child: !hasValidPhoto
                    ? Text(
                        displayName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              // Online status indicator
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF22C55E) : Colors.grey,
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
          title: Row(
            children: [
              Expanded(
                child: Text(
                  displayName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (dm.lastMessage.isNotEmpty)
                Text(
                  _formatTime(dm.lastMessageAt),
                  style: TextStyle(
                    color: unreadCount > 0
                        ? const Color(0xFF4A9EFF)
                        : Colors.white54,
                    fontSize: 12,
                    fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
            ],
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  dm.lastMessage.isEmpty ? 'No messages yet' : dm.lastMessage,
                  style: TextStyle(
                    color: dm.lastMessage.isEmpty
                        ? Colors.white38
                        : Colors.white70,
                    fontSize: 14,
                    fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unreadCount > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A9EFF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          onTap: () {
            // Mark as read
            if (currentUserId != null && unreadCount > 0) {
              _dmService.markAsRead(
                workspaceId: widget.workspace.id,
                dmId: dm.id,
                userId: currentUserId,
              );
            }

            // Navigate to DM chat screen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DMChatScreen(
                  workspace: widget.workspace,
                  dm: dm,
                  otherUser: otherUser,
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return DateFormat('h:mm a').format(dateTime);
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return DateFormat('EEE').format(dateTime);
    } else {
      return DateFormat('M/d/yy').format(dateTime);
    }
  }
}
