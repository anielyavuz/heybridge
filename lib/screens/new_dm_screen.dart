import 'package:flutter/material.dart';
import '../models/workspace_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/dm_service.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';
import 'dm_chat_screen.dart';

class NewDMScreen extends StatefulWidget {
  final WorkspaceModel workspace;

  const NewDMScreen({
    super.key,
    required this.workspace,
  });

  @override
  State<NewDMScreen> createState() => _NewDMScreenState();
}

class _NewDMScreenState extends State<NewDMScreen> {
  final _firestoreService = FirestoreService();
  final _dmService = DMService();
  final _authService = AuthService();
  final _logger = LoggerService();
  final _searchController = TextEditingController();
  List<UserModel> _workspaceMembers = [];
  List<UserModel> _filteredMembers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkspaceMembers();
    _logger.logUI('NewDMScreen', 'screen_opened',
      data: {'workspaceId': widget.workspace.id}
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkspaceMembers() async {
    try {
      final currentUserId = _authService.currentUser?.uid;
      if (currentUserId == null) return;

      // Get all workspace members except current user
      final members = <UserModel>[];
      for (final memberId in widget.workspace.memberIds) {
        if (memberId != currentUserId) {
          final user = await _firestoreService.getUser(memberId);
          if (user != null) {
            members.add(user);
          }
        }
      }

      // Sort by display name
      members.sort((a, b) => a.displayName.compareTo(b.displayName));

      setState(() {
        _workspaceMembers = members;
        _filteredMembers = members;
        _isLoading = false;
      });
    } catch (e) {
      _logger.log('Failed to load workspace members',
        level: LogLevel.error,
        category: 'NewDMScreen',
        data: {'error': e.toString()}
      );
      setState(() => _isLoading = false);
    }
  }

  void _filterMembers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredMembers = _workspaceMembers;
      } else {
        _filteredMembers = _workspaceMembers
            .where((user) =>
                user.displayName.toLowerCase().contains(query.toLowerCase()) ||
                user.email.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _startDM(UserModel otherUser) async {
    final currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: Color(0xFF4A9EFF)),
          ),
        );
      }

      // Get or create DM
      final dm = await _dmService.getOrCreateDM(
        workspaceId: widget.workspace.id,
        userId1: currentUserId,
        userId2: otherUser.uid,
      );

      _logger.logUI('NewDMScreen', 'dm_created',
        data: {'dmId': dm.id, 'otherUserId': otherUser.uid}
      );

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);

        // Navigate to DM chat screen and remove NewDMScreen from stack
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DMChatScreen(
              workspace: widget.workspace,
              dm: dm,
              otherUser: otherUser,
            ),
          ),
        );
      }
    } catch (e) {
      _logger.log('Failed to start DM',
        level: LogLevel.error,
        category: 'NewDMScreen',
        data: {'error': e.toString()}
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start DM: $e'),
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
        backgroundColor: const Color(0xFF1A1D21),
        elevation: 0,
        title: const Text(
          'New Direct Message',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: _filterMembers,
              decoration: InputDecoration(
                hintText: 'Search members...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF2D3748),
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

          // Members list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF4A9EFF)),
                  )
                : _filteredMembers.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty
                              ? 'No other members in this workspace'
                              : 'No members found',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredMembers.length,
                        itemBuilder: (context, index) {
                          final user = _filteredMembers[index];
                          return _buildMemberItem(user);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberItem(UserModel user) {
    final hasValidPhoto = user.photoURL != null && user.photoURL!.isNotEmpty;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFF4A9EFF),
        backgroundImage: hasValidPhoto ? NetworkImage(user.photoURL!) : null,
        child: !hasValidPhoto
            ? Text(
                user.displayName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Text(
        user.displayName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        user.email,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 14,
        ),
      ),
      onTap: () => _startDM(user),
    );
  }
}
