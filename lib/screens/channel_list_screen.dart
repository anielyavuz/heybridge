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
import '../models/workspace_model.dart';
import '../models/channel_model.dart';
import '../models/direct_message_model.dart';
import '../models/user_model.dart';
import 'chat_screen.dart';
import 'workspace_screen.dart';
import 'dm_list_screen.dart';
import 'dm_chat_screen.dart';
import 'new_dm_screen.dart';

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
  int _selectedIndex = 0; // 0: Home, 1: DMs, 2: Mentions, 3: You

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
                // Mentions tab (index 2)
                _buildMentionsContent(),
                // You tab (index 3)
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

        // Jump to search
        _buildJumpToSearch(),

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
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
                      widget.workspace.inviteCode,
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
                        ClipboardData(text: widget.workspace.inviteCode),
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
                    icon: const Icon(
                      Icons.copy,
                      color: Color(0xFF4A9EFF),
                    ),
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
            child: const Text(
              'Kapat',
              style: TextStyle(color: Colors.white70),
            ),
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
              Text(
                channel.name,
                style: const TextStyle(
                  color: Colors.white,
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

  void _showCreateChannelDialog({required bool isPrivate}) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    bool channelIsPrivate = isPrivate;

    _logger.logUI(
      'ChannelListScreen',
      'create_channel_dialog_opened',
      data: {'isPrivate': isPrivate},
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2D3748),
          title: Text(
            channelIsPrivate ? 'Create Private Channel' : 'Create Channel',
            style: const TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
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
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _logger.logUI(
                  'ChannelListScreen',
                  'create_channel_dialog_cancelled',
                );
                Navigator.of(context).pop();
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white),
              ),
            ),
            ElevatedButton(
              onPressed: () => _handleCreateChannel(
                context: context,
                name: nameController.text,
                description: descriptionController.text.isEmpty
                    ? null
                    : descriptionController.text,
                isPrivate: channelIsPrivate,
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
                  : const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCreateChannel({
    required BuildContext context,
    required String name,
    required String? description,
    required bool isPrivate,
  }) async {
    // Validate channel name
    final cleanName = name.trim().toLowerCase().replaceAll(' ', '-');
    if (cleanName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kanal adı boş olamaz'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate channel name format (alphanumeric and hyphens only)
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(cleanName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kanal adı sadece küçük harf, rakam ve tire içerebilir',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    _logger.logUI(
      'ChannelListScreen',
      'create_channel_confirmed',
      data: {'channelName': cleanName, 'isPrivate': isPrivate},
    );

    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) throw Exception('Kullanıcı oturumu bulunamadı');

      await _channelService.createChannel(
        workspaceId: widget.workspace.id,
        name: cleanName,
        createdBy: userId,
        description: description,
        isPrivate: isPrivate,
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
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

  // Jump to search bar
  Widget _buildJumpToSearch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1018), // Darker background for contrast
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search,
              color: Colors.white.withValues(alpha: 0.6),
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              'Jump to...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Slack-style channel list with sections
  Widget _buildSlackStyleChannelList(List<ChannelModel> channels) {
    final publicChannels = channels.where((c) => !c.isPrivate).toList();
    final userId = _authService.currentUser?.uid;
    // final privateChannels = channels.where((c) => c.isPrivate).toList(); // TODO: Use for DMs

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Threads section
        _buildMenuSection(
          icon: Icons.forum_outlined,
          label: 'Threads',
          onTap: () {},
        ),

        // Drafts & Sent section
        _buildMenuSection(
          icon: Icons.send_outlined,
          label: 'Drafts & Sent',
          onTap: () {},
        ),

        // Mentions & Reactions section
        _buildMenuSection(
          icon: Icons.alternate_email,
          label: 'Mentions & Reactions',
          onTap: () {},
        ),

        // CHANNELS section
        _buildSectionHeader('CHANNELS', Icons.expand_more),
        ...publicChannels.map((channel) => _buildChannelItem(channel)),
        _buildAddChannelButton(),

        const SizedBox(height: 16),

        // DIRECT MESSAGES section
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
      ],
    );
  }

  Widget _buildMenuSection({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 20),
              const SizedBox(width: 14),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.home, 'Home', index: 0),
            _buildNavItem(Icons.chat_bubble_outline, 'DMs', index: 1),
            _buildNavItem(Icons.alternate_email, 'Mentions', index: 2),
            _buildNavItem(Icons.person_outline, 'You', index: 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, {required int index}) {
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
              Icon(
                icon,
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.6),
                size: 26,
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

    return FutureBuilder<UserModel?>(
      future: _firestoreService.getUser(otherUserId),
      builder: (context, snapshot) {
        final otherUser = snapshot.data;
        final displayName =
            otherUser?.displayName ?? otherUser?.email ?? 'Unknown User';
        final unreadCount = dm.unreadCounts[currentUserId] ?? 0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              _logger.logUI(
                'ChannelListScreen',
                'dm_selected',
                data: {'dmId': dm.id, 'otherUserId': otherUserId},
              );
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DMChatScreen(
                    workspace: widget.workspace,
                    dm: dm,
                    otherUser: otherUser!,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 9,
                    backgroundColor: const Color(0xFF4A9EFF),
                    backgroundImage: otherUser?.photoURL != null
                        ? NetworkImage(otherUser!.photoURL!)
                        : null,
                    child: otherUser?.photoURL == null
                        ? Text(
                            displayName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
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
            ),
          ),
        );
      },
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
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Direct Messages',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
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

        // Jump to search
        _buildJumpToSearch(),

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

    return FutureBuilder<UserModel?>(
      future: _firestoreService.getUser(otherParticipantId),
      builder: (context, userSnapshot) {
        final otherUser = userSnapshot.data;
        final displayName = otherUser?.displayName ?? 'User';
        final photoURL = otherUser?.photoURL;

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar with online indicator
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFF4A9EFF),
                        backgroundImage:
                            photoURL != null ? NetworkImage(photoURL) : null,
                        child: photoURL == null
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
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: otherUser?.isOnline == true
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
                  const SizedBox(width: 12),
                  // Name and last message
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
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
                              ),
                            ),
                            if (dm.lastMessage.isNotEmpty)
                              Text(
                                _formatDMTime(dm.lastMessageAt),
                                style: TextStyle(
                                  color: unreadCount > 0
                                      ? const Color(0xFF4A9EFF)
                                      : Colors.white54,
                                  fontSize: 12,
                                  fontWeight: unreadCount > 0
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                          ],
                        ),
                        if (dm.lastMessage.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  dm.lastMessage,
                                  style: TextStyle(
                                    color: unreadCount > 0
                                        ? Colors.white70
                                        : Colors.white54,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (unreadCount > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4A9EFF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    unreadCount.toString(),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDMTime(DateTime dateTime) {
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

  // Mentions tab content
  Widget _buildMentionsContent() {
    return Column(
      children: [
        // Mentions Header
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
                  'Mentions & Reactions',
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

        // Empty state
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.alternate_email,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No mentions yet',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "When someone mentions you, you'll see it here",
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // You tab content
  Widget _buildYouContent() {
    final user = _authService.currentUser;

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
                  'You',
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
              // Profile card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D3748),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFF4A9EFF),
                      backgroundImage: user?.photoURL != null
                          ? NetworkImage(user!.photoURL!)
                          : null,
                      child: user?.photoURL == null
                          ? Text(
                              (user?.displayName ?? user?.email ?? 'U')[0]
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? 'User',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.email ?? '',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Menu items
              _buildProfileMenuItem(
                icon: Icons.person_outline,
                label: 'Edit Profile',
                onTap: () {},
              ),
              _buildProfileMenuItem(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                onTap: () {},
              ),
              _buildProfileMenuItem(
                icon: Icons.settings_outlined,
                label: 'Preferences',
                onTap: () {},
              ),

              const SizedBox(height: 24),

              // Logout button
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text(
                  'Sign Out',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 16,
                  ),
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
            ],
          ),
        ),
      ],
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: Colors.white54,
      ),
      onTap: onTap,
    );
  }
}
