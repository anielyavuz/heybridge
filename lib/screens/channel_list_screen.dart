import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/channel_service.dart';
import '../services/logger_service.dart';
import '../services/workspace_service.dart';
import '../services/preferences_service.dart';
import '../services/presence_service.dart';
import '../services/dm_service.dart';
import '../services/firestore_service.dart';
import '../services/navigation_service.dart';
import '../services/gemini_service.dart';
import '../models/workspace_model.dart';
import '../models/channel_model.dart';
import '../models/direct_message_model.dart';
import '../models/user_model.dart';
// import '../widgets/avatar_picker_dialog.dart'; // TODO: Re-enable when Firebase Storage is ready
import 'chat_screen.dart';
import 'workspace_screen.dart';
import 'dm_chat_screen.dart';
import 'new_dm_screen.dart';
import 'agent_chat_screen.dart';
import '../models/message_model.dart';
import '../services/fcm_api_service.dart';
import 'package:provider/provider.dart';
import '../providers/current_user_provider.dart';

/// Model for storing suggestion with target info
class SuggestionItem {
  final String text;
  final String targetType; // 'dm' or 'channel'
  final String targetName;
  final String? dmId;
  final String? otherUserId;
  final String? channelId;

  SuggestionItem({
    required this.text,
    required this.targetType,
    required this.targetName,
    this.dmId,
    this.otherUserId,
    this.channelId,
  });
}

class ChannelListScreen extends StatefulWidget {
  final WorkspaceModel workspace;

  const ChannelListScreen({super.key, required this.workspace});

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  final _authService = AuthService();
  final _channelService = ChannelService();
  final _workspaceService = WorkspaceService();
  final _preferencesService = PreferencesService();
  final _presenceService = PresenceService();
  final _dmService = DMService();
  final _firestoreService = FirestoreService();
  final _logger = LoggerService();
  bool _isLoading = false;
  int _selectedIndex = 0; // 0: Home, 1: DMs, 2: Channels, 3: Profile

  // Timer for periodic refresh of online status
  Timer? _onlineStatusTimer;

  // Counter to force StreamBuilder rebuild for online status recalculation
  int _refreshCounter = 0;

  @override
  void initState() {
    super.initState();
    _logger.logUI(
      'ChannelListScreen',
      'screen_opened',
      data: {
        'workspaceId': widget.workspace.id,
        'workspaceName': widget.workspace.name,
      },
    );
    // Ensure presence is active when entering workspace
    _presenceService.goOnline();

    // Check for pending navigation from notification
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingNavigation();
    });

    // Listen for navigation events from notifications
    NavigationService.instance.addNavigationListener(_onNavigationRequested);

    // Refresh every 30 seconds to update online status based on lastSeen
    _onlineStatusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {
          _refreshCounter++;
        });
      }
    });
  }

  @override
  void dispose() {
    _onlineStatusTimer?.cancel();
    NavigationService.instance.removeNavigationListener(_onNavigationRequested);
    super.dispose();
  }

  void _onNavigationRequested() {
    if (mounted) {
      _checkPendingNavigation();
    }
  }

  Future<void> _checkPendingNavigation() async {
    final pendingNav = NavigationService.instance.consumePendingNavigation();
    if (pendingNav == null) return;

    _logger.info(
      'Processing pending navigation',
      category: 'NAVIGATION',
      data: pendingNav,
    );

    final type = pendingNav['type'];
    final workspaceId = pendingNav['workspaceId'];

    // Only process if this is the correct workspace
    if (workspaceId != null && workspaceId != widget.workspace.id) {
      _logger.debug(
        'Pending navigation is for different workspace',
        category: 'NAVIGATION',
      );
      return;
    }

    if (type == 'channel_message') {
      final channelId = pendingNav['channelId'];
      final channelName = pendingNav['channelName'];
      if (channelId != null) {
        // Navigate to channel
        final channel = ChannelModel(
          id: channelId,
          name: channelName ?? 'Channel',
          workspaceId: widget.workspace.id,
          createdBy: '',
          createdAt: DateTime.now(),
          memberIds: [],
        );
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ChatScreen(workspace: widget.workspace, channel: channel),
            ),
          );
        }
      }
    } else if (type == 'dm_message') {
      final dmId = pendingNav['dmId'];
      if (dmId != null) {
        // Fetch the DM and navigate
        try {
          final dm = await _dmService.getDM(
            workspaceId: widget.workspace.id,
            dmId: dmId,
          );
          if (dm != null && mounted) {
            final userId = _authService.currentUser?.uid;
            final otherUserId = dm.participantIds.firstWhere(
              (id) => id != userId,
              orElse: () => '',
            );
            UserModel? otherUser;
            if (otherUserId.isNotEmpty) {
              otherUser = await _firestoreService.getUser(otherUserId);
            }
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DMChatScreen(
                    workspace: widget.workspace,
                    dm: dm,
                    otherUser: otherUser,
                  ),
                ),
              );
            }
          }
        } catch (e) {
          _logger.error('Failed to navigate to DM: $e', category: 'NAVIGATION');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = _authService.currentUser?.uid;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1D21),
        body: isMobile
            ? _buildMobileLayout(userId)
            : _buildDesktopLayout(userId),
      ),
    );
  }

  Widget _buildMobileLayout(String? userId) {
    return Container(
      color: const Color(0xFF1A1D29), // Dark grayish navy blue
      child: Column(
        children: [
          // Content area with IndexedStack
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                // Home tab (index 0)
                _buildHomeContent(userId),
                // DMs tab (index 1)
                _buildDMsContent(userId),
                // Channels tab (index 2)
                _buildChannelsContent(userId),
                // Profile tab (index 3)
                _buildYouContent(),
              ],
            ),
          ),

          // Bottom Navigation
          _buildBottomNavigation(),
        ],
      ),
    );
  }

  Widget _buildHomeContent(String? userId) {
    return Column(
      children: [
        // Workspace Header
        _buildWorkspaceHeader(),

        // HeyBridge Agent
        _buildHeybridgeAgent(),

        // Channels List
        Expanded(
          child: userId == null
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<List<ChannelModel>>(
                  stream: _channelService.getWorkspaceChannelsStream(
                    workspaceId: widget.workspace.id,
                    userId: userId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Hata: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    }

                    final channels = snapshot.data ?? [];

                    if (channels.isEmpty) {
                      return _buildEmptyChannelList();
                    }

                    return _buildSlackStyleChannelList(channels);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(String? userId) {
    return Row(
      children: [
        // Left Sidebar - Channel List
        Container(
          width: 260,
          decoration: BoxDecoration(
            color: const Color(0xFF0B1A2F), // Dark navy blue
            border: Border(
              right: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // Workspace Header
              _buildWorkspaceHeader(),

              // Channels List
              Expanded(
                child: userId == null
                    ? const Center(child: CircularProgressIndicator())
                    : StreamBuilder<List<ChannelModel>>(
                        stream: _channelService.getWorkspaceChannelsStream(
                          workspaceId: widget.workspace.id,
                          userId: userId,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                'Hata: ${snapshot.error}',
                                style: const TextStyle(color: Colors.red),
                              ),
                            );
                          }

                          final channels = snapshot.data ?? [];

                          if (channels.isEmpty) {
                            return _buildEmptyChannelList();
                          }

                          return _buildSlackStyleChannelList(channels);
                        },
                      ),
              ),
            ],
          ),
        ),

        // Main Content Area
        Expanded(
          child: Container(
            color: const Color(0xFF1A1D21),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 80,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Select a channel to start messaging',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a channel from the sidebar',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 55, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Workspace Dropdown Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showWorkspaceSwitcher(),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.workspace.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.workspace.memberIds.length} members',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 24,
                    ),
                    const SizedBox(width: 4),
                    // Share workspace code button
                    GestureDetector(
                      onTap: () => _showWorkspaceCodeModal(),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.share,
                          color: Colors.white.withValues(alpha: 0.7),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showWorkspaceCodeModal() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D3748),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.group_add, color: Color(0xFF4A9EFF)),
            SizedBox(width: 12),
            Text(
              'Workspace Kodu',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Bu kodu paylaşarak başkalarını workspace\'e davet edebilirsiniz:',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D21),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF4A9EFF).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.workspace.inviteCode ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.workspace.inviteCode ?? ''),
                      );
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(
                          content: Text('Kod kopyalandı!'),
                          backgroundColor: Color(0xFF22C55E),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, color: Color(0xFF4A9EFF)),
                    tooltip: 'Kopyala',
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _showWorkspaceSwitcher() {
    final userId = _authService.currentUser?.uid;
    if (userId == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D3748),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StreamBuilder<List<WorkspaceModel>>(
        stream: _workspaceService.getUserWorkspacesStream(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final workspaces = snapshot.data ?? [];

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text(
                        'Switch Workspace',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF1A1D21), height: 1),

                // Workspace List
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: workspaces.length,
                    itemBuilder: (context, index) {
                      final workspace = workspaces[index];
                      final isCurrentWorkspace =
                          workspace.id == widget.workspace.id;

                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isCurrentWorkspace
                                ? const Color(0xFF4A9EFF)
                                : const Color(0xFF1A1D21),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              workspace.name[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          workspace.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${workspace.memberIds.length} members',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                        trailing: isCurrentWorkspace
                            ? const Icon(Icons.check, color: Color(0xFF4A9EFF))
                            : null,
                        onTap: isCurrentWorkspace
                            ? null
                            : () async {
                                // Save last workspace
                                await _preferencesService.saveLastWorkspaceId(
                                  workspace.id,
                                );

                                if (mounted) {
                                  Navigator.pop(context); // Close bottom sheet
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => ChannelListScreen(
                                        workspace: workspace,
                                      ),
                                    ),
                                  );
                                }
                              },
                      );
                    },
                  ),
                ),

                const Divider(color: Color(0xFF1A1D21), height: 1),

                // Add Workspace Options
                ListTile(
                  leading: const Icon(
                    Icons.add_circle_outline,
                    color: Color(0xFF4A9EFF),
                  ),
                  title: const Text(
                    'Create or Join Workspace',
                    style: TextStyle(
                      color: Color(0xFF4A9EFF),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context); // Close bottom sheet
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WorkspaceScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyChannelList() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.tag,
              size: 60,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'No channels yet',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a channel to start chatting',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showCreateChannelDialog(isPrivate: false),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Create Channel',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A9EFF),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelItem(ChannelModel channel) {
    final userId = _authService.currentUser?.uid;
    final unreadCount = userId != null
        ? (channel.unreadCounts[userId] ?? 0)
        : 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _logger.logUI(
            'ChannelListScreen',
            'channel_selected',
            data: {'channelId': channel.id, 'channelName': channel.name},
          );
          _logger.logNavigation('ChannelListScreen', 'ChatScreen');
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ChatScreen(workspace: widget.workspace, channel: channel),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(
                channel.isPrivate ? Icons.lock : Icons.tag,
                size: 18,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  channel.name,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: unreadCount > 0
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4004B),
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
        ),
      ),
    );
  }

  void _showCreateChannelDialog({required bool isPrivate}) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    bool channelIsPrivate = isPrivate;
    final currentUserId = _authService.currentUser?.uid;

    // For private channels: track selected members
    final Set<String> selectedMemberIds = {};
    List<UserModel> workspaceMembers = [];
    bool isLoadingMembers = false;

    _logger.logUI(
      'ChannelListScreen',
      'create_channel_dialog_opened',
      data: {'isPrivate': isPrivate},
    );

    // Load workspace members for private channel member selection
    Future<void> loadMembers(StateSetter setDialogState) async {
      if (workspaceMembers.isNotEmpty) return;
      setDialogState(() => isLoadingMembers = true);

      try {
        final memberIds = widget.workspace.memberIds
            .where((id) => id != currentUserId)
            .toList();

        if (memberIds.isNotEmpty) {
          final usersMap = await _firestoreService.getUsers(memberIds);
          workspaceMembers = usersMap.values.toList();
          workspaceMembers.sort(
            (a, b) => a.displayName.compareTo(b.displayName),
          );
        }
      } catch (e) {
        _logger.error('Failed to load workspace members: $e', category: 'UI');
      }

      setDialogState(() => isLoadingMembers = false);
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // Load members when private is enabled
          if (channelIsPrivate &&
              workspaceMembers.isEmpty &&
              !isLoadingMembers) {
            loadMembers(setDialogState);
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF2D3748),
            title: Text(
              channelIsPrivate ? 'Create Private Channel' : 'Create Channel',
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Channel Name',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      textCapitalization: TextCapitalization.none,
                      decoration: InputDecoration(
                        hintText: 'e.g. design-team',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixText: '# ',
                        prefixStyle: const TextStyle(color: Colors.white60),
                        filled: true,
                        fillColor: const Color(0xFF1A1D21),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Description (Optional)',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'What is this channel about?',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF1A1D21),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Switch(
                          value: channelIsPrivate,
                          onChanged: (value) {
                            setDialogState(() {
                              channelIsPrivate = value;
                            });
                          },
                          activeColor: const Color(0xFF4A9EFF),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Make channel private',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                    if (channelIsPrivate) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1D21),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lock, color: Colors.orange, size: 20),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Private channels are only visible to invited members',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Add Members',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      if (isLoadingMembers)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              color: Color(0xFF4A9EFF),
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      else if (workspaceMembers.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1D21),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'No other members in this workspace',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        )
                      else
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1D21),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: workspaceMembers.length,
                            itemBuilder: (context, index) {
                              final member = workspaceMembers[index];
                              final isSelected = selectedMemberIds.contains(
                                member.uid,
                              );
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(0xFF4A9EFF),
                                  backgroundImage:
                                      member.photoURL != null &&
                                          member.photoURL!.isNotEmpty
                                      ? NetworkImage(member.photoURL!)
                                      : null,
                                  child:
                                      member.photoURL == null ||
                                          member.photoURL!.isEmpty
                                      ? Text(
                                          member.displayName[0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        )
                                      : null,
                                ),
                                title: Text(
                                  member.displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                trailing: Checkbox(
                                  value: isSelected,
                                  onChanged: (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selectedMemberIds.add(member.uid);
                                      } else {
                                        selectedMemberIds.remove(member.uid);
                                      }
                                    });
                                  },
                                  activeColor: const Color(0xFF4A9EFF),
                                  checkColor: Colors.white,
                                ),
                                onTap: () {
                                  setDialogState(() {
                                    if (isSelected) {
                                      selectedMemberIds.remove(member.uid);
                                    } else {
                                      selectedMemberIds.add(member.uid);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      if (selectedMemberIds.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${selectedMemberIds.length} member${selectedMemberIds.length > 1 ? 's' : ''} selected',
                          style: const TextStyle(
                            color: Color(0xFF4A9EFF),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _logger.logUI(
                    'ChannelListScreen',
                    'create_channel_dialog_cancelled',
                  );
                  Navigator.of(dialogContext).pop();
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              ElevatedButton(
                onPressed: () => _handleCreateChannel(
                  dialogContext: dialogContext,
                  name: nameController.text,
                  description: descriptionController.text.isEmpty
                      ? null
                      : descriptionController.text,
                  isPrivate: channelIsPrivate,
                  selectedMemberIds: channelIsPrivate
                      ? selectedMemberIds.toList()
                      : null,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A9EFF),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Create',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleCreateChannel({
    required BuildContext dialogContext,
    required String name,
    required String? description,
    required bool isPrivate,
    List<String>? selectedMemberIds,
  }) async {
    // Validate channel name
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kanal adı boş olamaz'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    _logger.logUI(
      'ChannelListScreen',
      'create_channel_confirmed',
      data: {
        'channelName': cleanName,
        'isPrivate': isPrivate,
        'memberCount': selectedMemberIds?.length ?? 0,
      },
    );

    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) throw Exception('Kullanıcı oturumu bulunamadı');

      // For private channels, include selected members + creator
      List<String>? initialMemberIds;
      if (isPrivate && selectedMemberIds != null) {
        initialMemberIds = [...selectedMemberIds, userId];
      }

      await _channelService.createChannel(
        workspaceId: widget.workspace.id,
        name: cleanName,
        createdBy: userId,
        description: description,
        isPrivate: isPrivate,
        initialMemberIds: initialMemberIds,
      );

      if (mounted) {
        // Close dialog first, then show snackbar
        Navigator.of(dialogContext).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('#$cleanName kanalı oluşturuldu!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // HeyBridge Agent - AI summary for unread messages
  Widget _buildHeybridgeAgent() {
    return GestureDetector(
      onTap: () => _showAgentSummaryModal(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF1E3A5F), const Color(0xFF2D4A6F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF4A9EFF).withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A9EFF).withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Robot icon with glow effect
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4A9EFF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
                color: Color(0xFF4A9EFF),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'HeyBridge Agent',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to summarize unread messages',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Arrow icon
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white.withValues(alpha: 0.4),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // Show AI summary modal
  void _showAgentSummaryModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AgentSummaryModal(
        workspace: widget.workspace,
        userId: _authService.currentUser?.uid,
      ),
    );
  }

  // Slack-style channel list with sections (DMs first, then Channels)
  Widget _buildSlackStyleChannelList(List<ChannelModel> channels) {
    final publicChannels = channels.where((c) => !c.isPrivate).toList();
    final userId = _authService.currentUser?.uid;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // DIRECT MESSAGES section (first)
        _buildSectionHeader('DIRECT MESSAGES', Icons.expand_more),

        // DM List
        if (userId != null)
          StreamBuilder<List<DirectMessageModel>>(
            stream: _dmService.getUserDMsStream(
              workspaceId: widget.workspace.id,
              userId: userId,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final dms = snapshot.data ?? [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...dms.map((dm) => _buildDMItem(dm, userId)),
                    _buildAddDMButton(),
                  ],
                );
              }
              // While loading, show button
              return _buildAddDMButton();
            },
          ),

        const SizedBox(height: 8),

        // CHANNELS section (second)
        _buildSectionHeader('CHANNELS', Icons.expand_more),
        ...publicChannels.map((channel) => _buildChannelItem(channel)),
        _buildAddChannelButton(),
      ],
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.5), size: 14),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: content),
      );
    }

    return content;
  }

  Widget _buildAddChannelButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showCreateChannelDialog(isPrivate: false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.add,
                color: Colors.white.withValues(alpha: 0.6),
                size: 18,
              ),
              const SizedBox(width: 14),
              Text(
                'Add channel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Bottom navigation bar
  Widget _buildBottomNavigation() {
    final userId = _authService.currentUser?.uid;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D42), // Dark gray-blue matching reference
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: StreamBuilder<List<DirectMessageModel>>(
          stream: _dmService.getUserDMsStream(
            workspaceId: widget.workspace.id,
            userId: userId ?? '',
          ),
          builder: (context, dmSnapshot) {
            // Count DMs with unread messages (not total unread messages)
            int unreadDMCount = 0;
            if (dmSnapshot.hasData && userId != null) {
              for (final dm in dmSnapshot.data!) {
                final unread = dm.unreadCounts[userId] ?? 0;
                if (unread > 0) unreadDMCount++;
              }
            }

            return StreamBuilder<List<ChannelModel>>(
              stream: _channelService.getWorkspaceChannelsStream(
                workspaceId: widget.workspace.id,
                userId: userId,
              ),
              builder: (context, channelSnapshot) {
                // Count channels with unread messages
                int unreadChannelCount = 0;
                if (channelSnapshot.hasData && userId != null) {
                  for (final channel in channelSnapshot.data!) {
                    final unread = channel.unreadCounts[userId] ?? 0;
                    if (unread > 0) unreadChannelCount++;
                  }
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(Icons.home, 'Home', index: 0),
                    _buildNavItem(
                      Icons.chat_bubble_outline,
                      'DMs',
                      index: 1,
                      badgeCount: unreadDMCount,
                    ),
                    _buildNavItem(
                      Icons.tag,
                      'Channels',
                      index: 2,
                      badgeCount: unreadChannelCount,
                    ),
                    _buildNavItem(Icons.person_outline, 'Profil', index: 3),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    String label, {
    required int index,
    int badgeCount = 0,
  }) {
    final isActive = _selectedIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.6),
                    size: 26,
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE4004B),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : badgeCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDMItem(DirectMessageModel dm, String currentUserId) {
    final otherUserId = dm.participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => dm.participantIds.first,
    );
    final unreadCount = dm.unreadCounts[currentUserId] ?? 0;

    // Use StreamBuilder for real-time online status updates
    // Key includes refreshCounter to force rebuild when timer triggers
    return StreamBuilder<UserModel?>(
      key: ValueKey('dm_user_${otherUserId}_$_refreshCounter'),
      stream: _firestoreService.getUserStream(otherUserId),
      builder: (context, snapshot) {
        // While loading, show a minimal placeholder (same height, no text)
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SizedBox(height: 30); // Placeholder with same height
        }
        final otherUser = snapshot.data;
        return _buildDMItemContent(dm, otherUser, unreadCount);
      },
    );
  }

  Widget _buildDMItemContent(
    DirectMessageModel dm,
    UserModel? otherUser,
    int unreadCount,
  ) {
    final displayName = otherUser?.displayName ?? otherUser?.email ?? 'User';
    final isOnline = _isUserOnline(otherUser);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (otherUser == null) return;
          _logger.logUI(
            'ChannelListScreen',
            'dm_selected',
            data: {'dmId': dm.id, 'otherUserId': otherUser.uid},
          );
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DMChatScreen(
                workspace: widget.workspace,
                dm: dm,
                otherUser: otherUser,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // Avatar with online indicator
              Stack(
                children: [
                  Builder(
                    builder: (context) {
                      final photo = otherUser?.photoURL;
                      final hasValidPhoto =
                          photo != null &&
                          photo.isNotEmpty &&
                          (photo.startsWith('http://') ||
                              photo.startsWith('https://'));
                      return CircleAvatar(
                        radius: 9,
                        backgroundColor: const Color(0xFF4A9EFF),
                        backgroundImage: hasValidPhoto
                            ? NetworkImage(photo)
                            : null,
                        child: !hasValidPhoto
                            ? Text(
                                displayName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                  // Online indicator dot
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? const Color(0xFF22C55E) : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF1A1D21),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: unreadCount > 0
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  textAlign: TextAlign.start,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4004B),
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
        ),
      ),
    );
  }

  Widget _buildAddDMButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NewDMScreen(workspace: widget.workspace),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.add,
                color: Colors.white.withValues(alpha: 0.6),
                size: 18,
              ),
              const SizedBox(width: 14),
              Text(
                'New direct message',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // DMs tab content
  Widget _buildDMsContent(String? userId) {
    return Column(
      children: [
        // DMs Header
        SafeArea(
          bottom: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Direct Messages',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            NewDMScreen(workspace: widget.workspace),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // DMs List
        Expanded(
          child: userId == null
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<List<DirectMessageModel>>(
                  stream: _dmService.getUserDMsStream(
                    workspaceId: widget.workspace.id,
                    userId: userId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF4A9EFF),
                        ),
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
                      return _buildEmptyDMsState();
                    }

                    return ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: dms.length,
                      itemBuilder: (context, index) {
                        final dm = dms[index];
                        return _buildDMListItem(dm, userId);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyDMsState() {
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
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start a conversation with your teammates',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      NewDMScreen(workspace: widget.workspace),
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

  Widget _buildDMListItem(DirectMessageModel dm, String currentUserId) {
    final otherParticipantId = dm.participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => dm.participantIds.first,
    );
    final unreadCount = dm.unreadCounts[currentUserId] ?? 0;

    // Use StreamBuilder for real-time online status updates
    // Key includes refreshCounter to force rebuild when timer triggers
    return StreamBuilder<UserModel?>(
      key: ValueKey('dms_tab_user_${otherParticipantId}_$_refreshCounter'),
      stream: _firestoreService.getUserStream(otherParticipantId),
      builder: (context, userSnapshot) {
        // Show placeholder while loading
        if (userSnapshot.connectionState == ConnectionState.waiting &&
            !userSnapshot.hasData) {
          return _buildDMListItemContent(
            dm,
            null,
            unreadCount,
            isLoading: true,
          );
        }
        final otherUser = userSnapshot.data;
        return _buildDMListItemContent(dm, otherUser, unreadCount);
      },
    );
  }

  Widget _buildDMListItemContent(
    DirectMessageModel dm,
    UserModel? otherUser,
    int unreadCount, {
    bool isLoading = false,
  }) {
    final displayName = otherUser?.displayName ?? 'User';
    final photoURL = otherUser?.photoURL;
    final hasValidPhoto =
        photoURL != null &&
        photoURL.isNotEmpty &&
        (photoURL.startsWith('http://') || photoURL.startsWith('https://'));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DMChatScreen(
                workspace: widget.workspace,
                dm: dm,
                otherUser: otherUser,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar with online indicator - green border for online users
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isUserOnline(otherUser)
                        ? const Color(0xFF22C55E)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFF4A9EFF),
                      backgroundImage: hasValidPhoto
                          ? NetworkImage(photoURL)
                          : null,
                      child: !hasValidPhoto
                          ? Text(
                              displayName[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    // Small online dot indicator
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _isUserOnline(otherUser)
                              ? const Color(0xFF22C55E)
                              : Colors.grey,
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
              ),
              const SizedBox(width: 12),
              // Name and last message - aligned to left
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: unreadCount > 0
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                    ),
                    if (dm.lastMessage.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        dm.lastMessage,
                        style: TextStyle(
                          color: unreadCount > 0
                              ? Colors.white70
                              : Colors.white54,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Right side: time and unread badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (dm.lastMessage.isNotEmpty)
                    Text(
                      _formatDMTime(dm.lastMessageAt),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  if (unreadCount > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4004B),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDMTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return DateFormat('HH:mm').format(dateTime);
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return DateFormat('EEE').format(dateTime);
    } else {
      return DateFormat('M/d/yy').format(dateTime);
    }
  }

  // Channels tab content
  Widget _buildChannelsContent(String? userId) {
    return Column(
      children: [
        // Channels Header
        SafeArea(
          bottom: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Channels',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: () => _showCreateChannelDialog(isPrivate: false),
                ),
              ],
            ),
          ),
        ),

        // Channels List
        Expanded(
          child: userId == null
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<List<ChannelModel>>(
                  stream: _channelService.getWorkspaceChannelsStream(
                    workspaceId: widget.workspace.id,
                    userId: userId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF4A9EFF),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading channels: ${snapshot.error}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    final channels = snapshot.data ?? [];

                    if (channels.isEmpty) {
                      return _buildEmptyChannelList();
                    }

                    return ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: channels.length,
                      itemBuilder: (context, index) {
                        final channel = channels[index];
                        return _buildChannelListItem(channel);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildChannelListItem(ChannelModel channel) {
    final userId = _authService.currentUser?.uid;
    final unreadCount = userId != null
        ? (channel.unreadCounts[userId] ?? 0)
        : 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _logger.logUI(
            'ChannelListScreen',
            'channel_selected',
            data: {'channelId': channel.id, 'channelName': channel.name},
          );
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ChatScreen(workspace: widget.workspace, channel: channel),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                channel.isPrivate ? Icons.lock : Icons.tag,
                size: 20,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: unreadCount > 0
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (channel.description != null &&
                        channel.description!.isNotEmpty)
                      Text(
                        channel.description!,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4004B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // You tab content
  Widget _buildYouContent() {
    final userId = _authService.currentUser?.uid;

    if (userId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<UserModel?>(
      stream: _firestoreService.getUserStream(userId),
      builder: (context, snapshot) {
        final userData = snapshot.data;

        return Column(
          children: [
            // Profile Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 55, 16, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Profil',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Profile content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Profile card with avatar and online status
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D3748),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        // Avatar with online indicator
                        Stack(
                          children: [
                            _buildProfileAvatar(userData, 50),
                            // Online indicator
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: _isUserOnline(userData)
                                      ? const Color(0xFF22C55E)
                                      : Colors.grey,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF2D3748),
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Display name
                        Text(
                          userData?.displayName ?? 'Kullanıcı',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Email
                        Text(
                          userData?.email ?? '',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Online status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _isUserOnline(userData)
                                ? const Color(0xFF22C55E).withValues(alpha: 0.2)
                                : Colors.grey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _isUserOnline(userData)
                                      ? const Color(0xFF22C55E)
                                      : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isUserOnline(userData)
                                    ? 'Çevrimiçi'
                                    : 'Çevrimdışı',
                                style: TextStyle(
                                  color: _isUserOnline(userData)
                                      ? const Color(0xFF22C55E)
                                      : Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Profile details card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D3748),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildProfileDetailRow(
                          icon: Icons.calendar_today,
                          label: 'Üyelik Tarihi',
                          value: userData != null
                              ? _formatMemberSince(userData.createdAt)
                              : '-',
                        ),
                        const Divider(color: Color(0xFF1A1D21), height: 24),
                        _buildProfileDetailRow(
                          icon: Icons.access_time,
                          label: 'Son Görülme',
                          value: userData != null
                              ? (_isUserOnline(userData)
                                    ? 'Şu an aktif'
                                    : _formatLastSeenProfile(userData.lastSeen))
                              : '-',
                        ),
                        const Divider(color: Color(0xFF1A1D21), height: 24),
                        _buildProfileDetailRow(
                          icon: Icons.workspaces_outline,
                          label: 'Workspace Sayısı',
                          value:
                              userData?.workspaceIds.length.toString() ?? '0',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Menu items
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D3748),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildProfileMenuItem(
                          icon: Icons.edit,
                          label: 'Kullanıcı Adını Değiştir',
                          onTap: () => _showChangeUsernameDialog(userData),
                        ),
                        const Divider(color: Color(0xFF1A1D21), height: 1),
                        _buildProfileMenuItem(
                          icon: Icons.email_outlined,
                          label: 'E-posta Değiştir',
                          onTap: () => _showChangeEmailDialog(userData),
                        ),
                        const Divider(color: Color(0xFF1A1D21), height: 1),
                        _buildProfileMenuItem(
                          icon: Icons.lock_outline,
                          label: 'Şifre Değiştir',
                          onTap: () => _showChangePasswordDialog(),
                        ),
                        const Divider(color: Color(0xFF1A1D21), height: 1),
                        _buildProfileMenuItem(
                          icon: Icons.notifications_outlined,
                          label: 'Bildirimler',
                          onTap: () {},
                        ),
                        const Divider(color: Color(0xFF1A1D21), height: 1),
                        _buildProfileMenuItem(
                          icon: Icons.palette_outlined,
                          label: 'Tema',
                          onTap: () {},
                        ),
                        const Divider(color: Color(0xFF1A1D21), height: 1),
                        _buildProfileMenuItem(
                          icon: Icons.settings_outlined,
                          label: 'Ayarlar',
                          onTap: () {},
                        ),
                        const Divider(color: Color(0xFF1A1D21), height: 1),
                        _buildProfileMenuItem(
                          icon: Icons.bug_report_outlined,
                          label: 'Logları Görüntüle',
                          onTap: () => _showLogsDialog(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Logout button
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D3748),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.logout,
                        color: Colors.redAccent,
                      ),
                      title: const Text(
                        'Çıkış Yap',
                        style: TextStyle(color: Colors.redAccent, fontSize: 16),
                      ),
                      onTap: () async {
                        // Set offline before signing out
                        await _presenceService.goOffline();
                        await _authService.signOut();
                        if (mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const WorkspaceScreen(),
                            ),
                            (route) => false,
                          );
                        }
                      },
                    ),
                  ),

                  const SizedBox(height: 24),

                  // App version
                  Center(
                    child: Text(
                      'HeyBridge v1.0.7',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatMemberSince(DateTime date) {
    final months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatLastSeenProfile(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'Az önce';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} dk önce';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} saat önce';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} gün önce';
    } else {
      return _formatMemberSince(lastSeen);
    }
  }

  /// Check if user is online based on lastSeen (within last 1 minute)
  bool _isUserOnline(UserModel? user) {
    if (user == null) return false;
    // isOnline flag OR lastSeen within last 1 minute
    if (user.isOnline) return true;
    final now = DateTime.now();
    final difference = now.difference(user.lastSeen);
    return difference.inMinutes < 1;
  }

  Widget _buildProfileDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF4A9EFF), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _showChangeUsernameDialog(UserModel? userData) {
    final nameController = TextEditingController(
      text: userData?.displayName ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D3748),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit, color: Color(0xFF4A9EFF)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Kullanıcı Adını Değiştir',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Yeni Kullanıcı Adı',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Kullanıcı adınızı girin',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1A1D21),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty && userData != null) {
                try {
                  await _firestoreService.firestore
                      .collection('users')
                      .doc(userData.uid)
                      .update({'displayName': newName});

                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('Kullanıcı adı güncellendi!'),
                        backgroundColor: Color(0xFF22C55E),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Hata: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
            ),
            child: const Text('Kaydet', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showChangeEmailDialog(UserModel? userData) {
    final emailController = TextEditingController(text: userData?.email ?? '');
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D3748),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.email_outlined, color: Color(0xFF4A9EFF)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'E-posta Değiştir',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Yeni E-posta Adresi',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'yeni@email.com',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1A1D21),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Mevcut Şifre (doğrulama için)',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passwordController,
              style: const TextStyle(color: Colors.white),
              obscureText: true,
              decoration: InputDecoration(
                hintText: '••••••••',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1A1D21),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newEmail = emailController.text.trim();
              final password = passwordController.text;

              if (newEmail.isEmpty || password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Lütfen tüm alanları doldurun'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                // Re-authenticate user first
                final user = _authService.currentUser;
                if (user != null && user.email != null) {
                  final credential = await _authService.reauthenticate(
                    user.email!,
                    password,
                  );

                  if (credential != null) {
                    // Update email in Firebase Auth
                    await user.verifyBeforeUpdateEmail(newEmail);

                    // Update email in Firestore
                    await _firestoreService.firestore
                        .collection('users')
                        .doc(user.uid)
                        .update({'email': newEmail});

                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Doğrulama e-postası gönderildi. Lütfen yeni e-postanızı doğrulayın.',
                          ),
                          backgroundColor: Color(0xFF22C55E),
                        ),
                      );
                    }
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
            ),
            child: const Text(
              'Değiştir',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D3748),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Color(0xFF4A9EFF)),
            SizedBox(width: 12),
            Text(
              'Şifre Değiştir',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mevcut Şifre',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: currentPasswordController,
                style: const TextStyle(color: Colors.white),
                obscureText: true,
                decoration: InputDecoration(
                  hintText: '••••••••',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF1A1D21),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Yeni Şifre',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newPasswordController,
                style: const TextStyle(color: Colors.white),
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'En az 6 karakter',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF1A1D21),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Yeni Şifre (Tekrar)',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmPasswordController,
                style: const TextStyle(color: Colors.white),
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Şifreyi tekrar girin',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF1A1D21),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              final currentPassword = currentPasswordController.text;
              final newPassword = newPasswordController.text;
              final confirmPassword = confirmPasswordController.text;

              if (currentPassword.isEmpty ||
                  newPassword.isEmpty ||
                  confirmPassword.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Lütfen tüm alanları doldurun'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (newPassword.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Şifre en az 6 karakter olmalıdır'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (newPassword != confirmPassword) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Şifreler eşleşmiyor'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                final user = _authService.currentUser;
                if (user != null && user.email != null) {
                  // Re-authenticate user first
                  final credential = await _authService.reauthenticate(
                    user.email!,
                    currentPassword,
                  );

                  if (credential != null) {
                    // Update password
                    await user.updatePassword(newPassword);

                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(
                          content: Text('Şifre başarıyla güncellendi!'),
                          backgroundColor: Color(0xFF22C55E),
                        ),
                      );
                    }
                  }
                }
              } catch (e) {
                if (mounted) {
                  String errorMessage = 'Bir hata oluştu';
                  if (e.toString().contains('wrong-password')) {
                    errorMessage = 'Mevcut şifre yanlış';
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
            ),
            child: const Text(
              'Değiştir',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: onTap,
    );
  }

  // TODO: Re-enable avatar picker when Firebase Storage is ready
  // void _showAvatarPicker(UserModel? userData) { ... }

  /// Check if a URL is a valid network URL (http/https)
  bool _isValidNetworkUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// Build profile avatar widget
  Widget _buildProfileAvatar(UserModel? userData, double radius) {
    final displayName = userData?.displayName ?? userData?.email ?? 'U';

    // TODO: Re-enable avatarId support when Firebase Storage is ready
    // Currently disabled to avoid asset loading errors

    // If user has a valid photoURL (from Google/Apple sign-in)
    // Must be a valid http/https URL
    final photoURL = userData?.photoURL;
    if (_isValidNetworkUrl(photoURL)) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFF4A9EFF),
        backgroundImage: NetworkImage(photoURL!),
      );
    }

    // Default: show first letter of name
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF4A9EFF),
      child: Text(
        displayName[0].toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.72,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Show logs dialog
  void _showLogsDialog() {
    final logs = _logger.getLogs();
    final stats = _logger.getStatistics();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1A1D21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Uygulama Logları',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      // Clear logs button
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                        ),
                        onPressed: () {
                          _logger.clearLogs();
                          Navigator.of(context).pop();
                          _showLogsDialog(); // Refresh
                        },
                        tooltip: 'Logları Temizle',
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Statistics
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D3748),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildLogStatItem(
                      'Toplam',
                      '${stats['total_logs']}',
                      Colors.white,
                    ),
                    _buildLogStatItem(
                      'Hata',
                      '${(stats['by_level'] as Map)['error'] ?? 0}',
                      Colors.redAccent,
                    ),
                    _buildLogStatItem(
                      'Uyarı',
                      '${(stats['by_level'] as Map)['warning'] ?? 0}',
                      Colors.orange,
                    ),
                    _buildLogStatItem(
                      'Başarı',
                      '${(stats['by_level'] as Map)['success'] ?? 0}',
                      const Color(0xFF22C55E),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Logs list
              Expanded(
                child: logs.isEmpty
                    ? const Center(
                        child: Text(
                          'Henüz log kaydı yok',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: logs.length,
                        reverse: true, // Show newest first
                        itemBuilder: (context, index) {
                          final log = logs[logs.length - 1 - index];
                          return _buildLogItem(log);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final level = log['level'] as String;
    final message = log['message'] as String;
    final timestamp = log['timestamp'] as String;
    final category = log['category'] as String?;
    final data = log['data'] as Map<String, dynamic>?;

    Color levelColor;
    IconData levelIcon;
    switch (level) {
      case 'error':
        levelColor = Colors.redAccent;
        levelIcon = Icons.error_outline;
        break;
      case 'warning':
        levelColor = Colors.orange;
        levelIcon = Icons.warning_amber_outlined;
        break;
      case 'success':
        levelColor = const Color(0xFF22C55E);
        levelIcon = Icons.check_circle_outline;
        break;
      case 'debug':
        levelColor = Colors.grey;
        levelIcon = Icons.bug_report_outlined;
        break;
      default:
        levelColor = const Color(0xFF4A9EFF);
        levelIcon = Icons.info_outline;
    }

    // Parse timestamp
    final dateTime = DateTime.parse(timestamp);
    final formattedTime =
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
    final formattedDate = '${dateTime.day}/${dateTime.month}/${dateTime.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D3748),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: levelColor.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(levelIcon, color: levelColor, size: 16),
              const SizedBox(width: 6),
              if (category != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: levelColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      color: levelColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              Text(
                '$formattedDate $formattedTime',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Message
          Text(
            message,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          // Data
          if (data != null && data.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              data.toString(),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// HeyBridge Agent Summary Modal
class _AgentSummaryModal extends StatefulWidget {
  final WorkspaceModel workspace;
  final String? userId;

  const _AgentSummaryModal({required this.workspace, this.userId});

  @override
  State<_AgentSummaryModal> createState() => _AgentSummaryModalState();
}

class _AgentSummaryModalState extends State<_AgentSummaryModal> {
  final _geminiService = GeminiService();
  final _channelService = ChannelService();
  final _firestoreService = FirestoreService();
  final _dmService = DMService();
  final _fcmService = FcmApiService.instance;
  final _logger = LoggerService();

  bool _isLoading = false;
  bool _hasSummary = false;
  String _summaryText = '';

  // Store target info for DMs and channels
  final Map<String, Map<String, dynamic>> _dmTargets =
      {}; // name -> {dmId, otherUserId}
  final Map<String, String> _channelTargets = {}; // name -> channelId

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D21),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                // Robot icon with glow
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF4A9EFF).withValues(alpha: 0.3),
                        const Color(0xFF4A9EFF).withValues(alpha: 0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.smart_toy,
                    color: Color(0xFF4A9EFF),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'HeyBridge Agent',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'AI-powered message summary',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Divider
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),

          // Content
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _hasSummary
                ? _buildSummaryContent()
                : _buildInitialState(),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          // Illustration
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF2D3748),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4A9EFF).withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Color(0xFF4A9EFF),
              size: 64,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Catch up quickly',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Let HeyBridge Agent summarize your unread messages across all channels and DMs.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          // Generate Summary Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _generateSummary,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A9EFF),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Generate Summary',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Chat with Agent Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AgentChatScreen()),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Color(0xFF4A9EFF), width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_outlined, color: Color(0xFF4A9EFF), size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Chat with Agent',
                    style: TextStyle(
                      color: Color(0xFF4A9EFF),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Features list
          _buildFeatureItem(
            icon: Icons.message_outlined,
            title: 'Channels & DMs',
            description: 'Summarizes unread messages from all sources',
          ),
          _buildFeatureItem(
            icon: Icons.flash_on_outlined,
            title: 'Key Highlights',
            description: 'Identifies important discussions and decisions',
          ),
          _buildFeatureItem(
            icon: Icons.schedule_outlined,
            title: 'Action Items',
            description: 'Extracts tasks and mentions that need your attention',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return SizedBox();

    //  Padding(
    //   padding: const EdgeInsets.symmetric(vertical: 10),
    //   child: Row(
    //     crossAxisAlignment: CrossAxisAlignment.start,
    //     children: [
    //       Container(
    //         padding: const EdgeInsets.all(8),
    //         decoration: BoxDecoration(
    //           color: const Color(0xFF2D3748),
    //           borderRadius: BorderRadius.circular(8),
    //         ),
    //         child: Icon(icon, color: const Color(0xFF4A9EFF), size: 20),
    //       ),
    //       const SizedBox(width: 14),
    //       Expanded(
    //         child: Column(
    //           crossAxisAlignment: CrossAxisAlignment.start,
    //           children: [
    //             Text(
    //               title,
    //               style: const TextStyle(
    //                 color: Colors.white,
    //                 fontSize: 15,
    //                 fontWeight: FontWeight.w600,
    //               ),
    //             ),
    //             const SizedBox(height: 2),
    //             Text(
    //               description,
    //               style: TextStyle(
    //                 color: Colors.white.withValues(alpha: 0.6),
    //                 fontSize: 13,
    //               ),
    //             ),
    //           ],
    //         ),
    //       ),
    //     ],
    //   ),
    // );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated robot icon
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 1500),
            builder: (context, value, child) {
              return Transform.scale(
                scale:
                    0.9 + (0.1 * (0.5 + 0.5 * math.sin(value * 3.14159)).abs()),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D3748),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4A9EFF).withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.smart_toy,
                    color: Color(0xFF4A9EFF),
                    size: 48,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          const CircularProgressIndicator(
            color: Color(0xFF4A9EFF),
            strokeWidth: 2,
          ),
          const SizedBox(height: 24),
          const Text(
            'Analyzing messages...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a few moments',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryContent() {
    // Parse summary to extract action items
    final parsed = _parseSummary(_summaryText);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF2D3748),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF4A9EFF).withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.summarize,
                      color: Color(0xFF4A9EFF),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Özet',
                      style: TextStyle(
                        color: Color(0xFF4A9EFF),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Şimdi',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  parsed['summary'] ?? _summaryText,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),

          // Action items card (if any)
          if (parsed['actions'] != null &&
              (parsed['actions'] as List).isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFF9500).withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9500).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.flag_outlined,
                          color: Color(0xFFFF9500),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Aksiyonlar',
                        style: TextStyle(
                          color: Color(0xFFFF9500),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...(parsed['actions'] as List).map(
                    (action) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF9500),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              action.toString(),
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Suggestion buttons (from Gemini) - grouped by target
          if (parsed['suggestions'] != null &&
              (parsed['suggestions'] as List<SuggestionItem>).isNotEmpty) ...[
            const SizedBox(height: 24),
            ..._buildGroupedSuggestions(
              parsed['suggestions'] as List<SuggestionItem>,
            ),
          ],

          const SizedBox(height: 20),
          // Regenerate button
          Center(
            child: TextButton.icon(
              onPressed: _generateSummary,
              icon: const Icon(
                Icons.refresh,
                color: Color(0xFF4A9EFF),
                size: 18,
              ),
              label: const Text(
                'Yeniden oluştur',
                style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build grouped suggestions by target (DM/Channel)
  List<Widget> _buildGroupedSuggestions(List<SuggestionItem> suggestions) {
    final widgets = <Widget>[];

    // Group suggestions by target
    final grouped = <String, List<SuggestionItem>>{};
    for (final suggestion in suggestions) {
      final key = '${suggestion.targetType}:${suggestion.targetName}';
      grouped.putIfAbsent(key, () => []).add(suggestion);
    }

    for (final entry in grouped.entries) {
      final items = entry.value;
      if (items.isEmpty) continue;

      final first = items.first;
      final icon = first.targetType == 'dm' ? Icons.person : Icons.tag;
      final label = first.targetType == 'dm'
          ? first.targetName
          : '#${first.targetName}';

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 14, color: Colors.white54),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((s) => _buildSuggestionChip(s)).toList(),
          ),
        ),
      );
    }

    if (widgets.isEmpty) {
      return [];
    }

    return [
      const Text(
        'Önerilen Yanıtlar',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 12),
      ...widgets,
    ];
  }

  Widget _buildSuggestionChip(SuggestionItem suggestion) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _sendSuggestionReply(suggestion),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF2D3748),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: suggestion.targetType == 'dm'
                  ? const Color(0xFF4A9EFF).withValues(alpha: 0.3)
                  : const Color(0xFF10B981).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Text(
            suggestion.text,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ),
    );
  }

  /// Send a reply using the suggestion
  Future<void> _sendSuggestionReply(SuggestionItem suggestion) async {
    final userId = widget.userId;
    if (userId == null) return;

    try {
      // Get current user info
      final userProvider = context.read<CurrentUserProvider>();
      String userName = userProvider.displayName;
      String? userPhotoURL = userProvider.photoURL;

      // Fallback to auth service if provider not ready
      final authService = AuthService();
      if (userName.isEmpty) {
        userName = authService.currentUser?.displayName ?? '';
        userPhotoURL = authService.currentUser?.photoURL;
      }
      if (userName.isEmpty) {
        userName = authService.currentUser?.email?.split('@')[0] ?? 'User';
      }

      // Add Gemini attribution to the message
      final messageText = '${suggestion.text}\n\n_(Gemini Tarafından Yazıldı)_';

      if (suggestion.targetType == 'dm' && suggestion.dmId != null) {
        // Send DM message
        final messageRef = _firestoreService.firestore
            .collection('workspaces')
            .doc(widget.workspace.id)
            .collection('directMessages')
            .doc(suggestion.dmId)
            .collection('messages')
            .doc();

        final message = MessageModel(
          id: messageRef.id,
          channelId: suggestion.dmId!,
          senderId: userId,
          senderName: userName,
          senderPhotoURL: userPhotoURL,
          text: messageText,
          createdAt: DateTime.now(),
        );

        await messageRef.set(message.toMap());

        // Update DM metadata
        await _dmService.updateDMMetadata(
          workspaceId: widget.workspace.id,
          dmId: suggestion.dmId!,
          lastMessage: suggestion.text,
          senderId: userId,
        );

        // Send push notification
        _fcmService.notifyDMMessage(
          workspaceId: widget.workspace.id,
          dmId: suggestion.dmId!,
          senderId: userId,
          senderName: userName,
          message: suggestion.text,
          messageId: message.id,
        );

        _logger.success(
          'Sent suggestion reply to DM',
          category: 'AGENT',
          data: {'dmId': suggestion.dmId, 'targetName': suggestion.targetName},
        );

        if (mounted) {
          Navigator.of(context).pop(); // Close modal
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${suggestion.targetName} kişisine yanıt paylaşıldı ✓',
              ),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (suggestion.targetType == 'channel' &&
          suggestion.channelId != null) {
        // Send channel message
        final messageRef = _firestoreService.firestore
            .collection('workspaces')
            .doc(widget.workspace.id)
            .collection('channels')
            .doc(suggestion.channelId)
            .collection('messages')
            .doc();

        final message = MessageModel(
          id: messageRef.id,
          channelId: suggestion.channelId!,
          senderId: userId,
          senderName: userName,
          senderPhotoURL: userPhotoURL,
          text: messageText,
          createdAt: DateTime.now(),
        );

        await messageRef.set(message.toMap());

        // Update channel's last message timestamp
        await _firestoreService.firestore
            .collection('workspaces')
            .doc(widget.workspace.id)
            .collection('channels')
            .doc(suggestion.channelId)
            .update({'lastMessageAt': Timestamp.now()});

        // Send push notification
        _fcmService.notifyChannelMessage(
          workspaceId: widget.workspace.id,
          channelId: suggestion.channelId!,
          channelName: suggestion.targetName,
          senderId: userId,
          senderName: userName,
          message: suggestion.text,
          messageId: message.id,
        );

        _logger.success(
          'Sent suggestion reply to channel',
          category: 'AGENT',
          data: {
            'channelId': suggestion.channelId,
            'targetName': suggestion.targetName,
          },
        );

        if (mounted) {
          Navigator.of(context).pop(); // Close modal
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '#${suggestion.targetName} kanalına yanıt paylaşıldı ✓',
              ),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      _logger.error('Failed to send suggestion reply: $e', category: 'AGENT');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Yanıt gönderilemedi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Parse summary text to extract action items and per-user suggestions
  Map<String, dynamic> _parseSummary(String text) {
    final actions = <String>[];
    final suggestions = <SuggestionItem>[];
    final summaryLines = <String>[];

    final lines = text.split('\n');
    String currentSection = 'summary'; // summary, action, suggestion
    String? currentTargetType; // 'dm' or 'channel'
    String? currentTargetName;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (currentSection == 'summary' && summaryLines.isNotEmpty) {
          summaryLines.add('');
        }
        continue;
      }

      final lowerLine = trimmed.toLowerCase();

      // Check if this is a summary section header (skip it but stay in summary mode)
      if (lowerLine.contains('özet') &&
          !lowerLine.contains('aksiyon') &&
          !lowerLine.contains('öneri') &&
          trimmed.startsWith('**')) {
        // This is just a header like "**Özet:**", skip it
        continue;
      }

      // Check if this is an action section header
      if ((lowerLine.contains('aksiyon') ||
              lowerLine.contains('yapılacak') ||
              lowerLine.contains('action')) &&
          (trimmed.startsWith('**') || trimmed.startsWith('#'))) {
        currentSection = 'action';
        currentTargetType = null;
        currentTargetName = null;
        continue;
      }

      // Check if this is a suggestions section header
      if ((lowerLine.contains('öneri') || lowerLine.contains('suggestion')) &&
          (trimmed.startsWith('**') || trimmed.startsWith('#'))) {
        currentSection = 'suggestion';
        continue;
      }

      // Check for per-user/channel target markers
      // Format: [DM:UserName] or [KANAL:ChannelName]
      final dmMatch = RegExp(r'\[DM:([^\]]+)\]').firstMatch(trimmed);
      final channelMatch = RegExp(r'\[KANAL:([^\]]+)\]').firstMatch(trimmed);

      if (dmMatch != null) {
        currentTargetType = 'dm';
        currentTargetName = dmMatch.group(1)?.trim();
        continue;
      }

      if (channelMatch != null) {
        currentTargetType = 'channel';
        currentTargetName = channelMatch.group(1)?.trim();
        continue;
      }

      // Extract content based on current section
      String cleanText = trimmed
          .replaceAll(RegExp(r'^[\*\-\•\⚙️\📌\🔔\✅\➡️💡🔹📢💬]+\s*'), '')
          .replaceAll(RegExp(r'^\d+[\.\)]\s*'), '')
          .replaceAll('**', '')
          .trim();

      if (cleanText.isEmpty || cleanText.length < 2) continue;

      switch (currentSection) {
        case 'action':
          if (cleanText.length > 3) {
            actions.add(cleanText);
          }
          break;
        case 'suggestion':
          if (currentTargetType != null && currentTargetName != null) {
            // Create suggestion with target info
            if (currentTargetType == 'dm') {
              final dmInfo = _dmTargets[currentTargetName];
              suggestions.add(
                SuggestionItem(
                  text: cleanText,
                  targetType: 'dm',
                  targetName: currentTargetName,
                  dmId: dmInfo?['dmId'] as String?,
                  otherUserId: dmInfo?['otherUserId'] as String?,
                ),
              );
            } else if (currentTargetType == 'channel') {
              final channelId = _channelTargets[currentTargetName];
              suggestions.add(
                SuggestionItem(
                  text: cleanText,
                  targetType: 'channel',
                  targetName: currentTargetName,
                  channelId: channelId,
                ),
              );
            }
          }
          break;
        default:
          // Add to summary, preserving original formatting
          summaryLines.add(trimmed);
      }
    }

    // Clean up summary - remove leading/trailing empty lines
    while (summaryLines.isNotEmpty && summaryLines.first.isEmpty) {
      summaryLines.removeAt(0);
    }
    while (summaryLines.isNotEmpty && summaryLines.last.isEmpty) {
      summaryLines.removeLast();
    }

    return {
      'summary': summaryLines.join('\n').trim(),
      'actions': actions,
      'suggestions': suggestions,
    };
  }

  Future<void> _generateSummary() async {
    if (widget.userId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Initialize Gemini service
      await _geminiService.initialize();

      // Fetch unread channel messages
      final channelMessages = await _fetchUnreadChannelMessages();

      // Fetch unread DM messages
      final dmMessages = await _fetchUnreadDMMessages();

      _logger.info(
        'Fetched unread messages',
        category: 'AGENT',
        data: {
          'channelCount': channelMessages.length,
          'dmCount': dmMessages.length,
        },
      );

      // Generate summary with Gemini
      final summary = await _geminiService.generateSummary(
        channelMessages: channelMessages,
        dmMessages: dmMessages,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasSummary = true;
          _summaryText = summary;
        });
      }
    } catch (e) {
      _logger.error('Failed to generate summary: $e', category: 'AGENT');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _summaryText =
              '''❌ Özet oluşturulamadı

Hata: $e

Lütfen tekrar deneyin.''';
          _hasSummary = true;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUnreadChannelMessages() async {
    final result = <Map<String, dynamic>>[];
    final userId = widget.userId;
    if (userId == null) return result;

    // Clear previous targets
    _channelTargets.clear();

    try {
      // Get channels user is member of
      final channels = await _channelService.getWorkspaceChannels(
        workspaceId: widget.workspace.id,
        userId: userId,
      );

      for (final channel in channels) {
        // Check if channel has unread count for this user
        final channelDoc = await _firestoreService.firestore
            .collection('workspaces')
            .doc(widget.workspace.id)
            .collection('channels')
            .doc(channel.id)
            .get();

        if (!channelDoc.exists) continue;

        final data = channelDoc.data()!;
        final unreadCounts =
            data['unreadCounts'] as Map<String, dynamic>? ?? {};
        final unreadCount = unreadCounts[userId] as int? ?? 0;

        if (unreadCount > 0) {
          // Store target info for later use
          _channelTargets[channel.name] = channel.id;

          // Fetch recent messages (up to unread count, max 20)
          final messagesSnapshot = await _firestoreService.firestore
              .collection('workspaces')
              .doc(widget.workspace.id)
              .collection('channels')
              .doc(channel.id)
              .collection('messages')
              .orderBy('createdAt', descending: true)
              .limit(unreadCount > 20 ? 20 : unreadCount)
              .get();

          if (messagesSnapshot.docs.isNotEmpty) {
            final messages = messagesSnapshot.docs.map((doc) {
              final msgData = doc.data();
              return {
                'senderName': msgData['senderName'] ?? 'Unknown',
                'text': msgData['text'] ?? '',
              };
            }).toList();

            result.add({'channelName': channel.name, 'messages': messages});
          }
        }
      }
    } catch (e) {
      _logger.error('Failed to fetch channel messages: $e', category: 'AGENT');
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _fetchUnreadDMMessages() async {
    final result = <Map<String, dynamic>>[];
    final userId = widget.userId;
    if (userId == null) return result;

    // Clear previous targets
    _dmTargets.clear();

    try {
      // Get user's DMs
      final dmsSnapshot = await _firestoreService.firestore
          .collection('workspaces')
          .doc(widget.workspace.id)
          .collection('directMessages')
          .where('participantIds', arrayContains: userId)
          .get();

      for (final dmDoc in dmsSnapshot.docs) {
        final dm = DirectMessageModel.fromMap(dmDoc.data(), dmDoc.id);
        final unreadCount = dm.unreadCounts[userId] ?? 0;

        if (unreadCount > 0) {
          // Get other user's name
          final otherUserId = dm.participantIds.firstWhere(
            (id) => id != userId,
            orElse: () => '',
          );

          String otherUserName = 'Unknown';
          if (otherUserId.isNotEmpty) {
            final otherUser = await _firestoreService.getUser(otherUserId);
            otherUserName = otherUser?.displayName ?? 'Unknown';
          }

          // Store target info for later use
          _dmTargets[otherUserName] = {
            'dmId': dm.id,
            'otherUserId': otherUserId,
          };

          // Fetch recent messages
          final messagesSnapshot = await _firestoreService.firestore
              .collection('workspaces')
              .doc(widget.workspace.id)
              .collection('directMessages')
              .doc(dm.id)
              .collection('messages')
              .orderBy('createdAt', descending: true)
              .limit(unreadCount > 20 ? 20 : unreadCount)
              .get();

          if (messagesSnapshot.docs.isNotEmpty) {
            final messages = messagesSnapshot.docs.map((doc) {
              final msgData = doc.data();
              return {
                'senderName': msgData['senderName'] ?? 'Unknown',
                'text': msgData['text'] ?? '',
              };
            }).toList();

            result.add({'otherUserName': otherUserName, 'messages': messages});
          }
        }
      }
    } catch (e) {
      _logger.error('Failed to fetch DM messages: $e', category: 'AGENT');
    }

    return result;
  }
}
