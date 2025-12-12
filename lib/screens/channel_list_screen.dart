import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/channel_service.dart';
import '../services/logger_service.dart';
import '../models/workspace_model.dart';
import '../models/channel_model.dart';
import 'chat_screen.dart';

class ChannelListScreen extends StatefulWidget {
  final WorkspaceModel workspace;

  const ChannelListScreen({
    super.key,
    required this.workspace,
  });

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  final _authService = AuthService();
  final _channelService = ChannelService();
  final _logger = LoggerService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _logger.logUI('ChannelListScreen', 'screen_opened',
      data: {'workspaceId': widget.workspace.id, 'workspaceName': widget.workspace.name}
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = _authService.currentUser?.uid;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1D21),
      body: isMobile
        ? _buildMobileLayout(userId)
        : _buildDesktopLayout(userId),
    );
  }

  Widget _buildMobileLayout(String? userId) {
    return SafeArea(
      child: Container(
        color: const Color(0xFF3F0E40), // Slack purple
        child: Column(
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

            // Bottom Navigation
            _buildBottomNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(String? userId) {
    return Row(
      children: [
        // Left Sidebar - Channel List
        Container(
          width: 260,
          decoration: BoxDecoration(
            color: const Color(0xFF3F0E40), // Slack purple
            border: Border(
              right: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
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
      ],
    );
  }

  Widget _buildWorkspaceHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF1A1D21), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.workspace.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.workspace.memberIds.length} members',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white70),
                color: const Color(0xFF1A1D21),
                onSelected: (value) {
                  if (value == 'back') {
                    Navigator.of(context).pop();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'back',
                    child: Row(
                      children: [
                        Icon(Icons.arrow_back, color: Colors.white70, size: 20),
                        SizedBox(width: 12),
                        Text('Back to Workspaces', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
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
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
              ),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
          _logger.logUI('ChannelListScreen', 'channel_selected',
            data: {'channelId': channel.id, 'channelName': channel.name}
          );
          _logger.logNavigation('ChannelListScreen', 'ChatScreen');
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                workspace: widget.workspace,
                channel: channel,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                channel.isPrivate ? Icons.lock : Icons.tag,
                size: 18,
                color: Colors.white60,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  channel.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

    _logger.logUI('ChannelListScreen', 'create_channel_dialog_opened',
      data: {'isPrivate': isPrivate}
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D3748),
        title: Text(
          isPrivate ? 'Create Private Channel' : 'Create Channel',
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
              if (isPrivate) ...[
                const SizedBox(height: 16),
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
                          style: TextStyle(color: Colors.white70, fontSize: 12),
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
              _logger.logUI('ChannelListScreen', 'create_channel_dialog_cancelled');
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
              isPrivate: isPrivate,
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
          content: Text('Kanal adı sadece küçük harf, rakam ve tire içerebilir'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    _logger.logUI('ChannelListScreen', 'create_channel_confirmed',
      data: {'channelName': cleanName, 'isPrivate': isPrivate}
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1D), // Darker background for contrast
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: const Row(
          children: [
            Icon(Icons.search, color: Colors.white70, size: 18),
            SizedBox(width: 8),
            Text(
              'Jump to...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
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
    final privateChannels = channels.where((c) => c.isPrivate).toList();

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

        const SizedBox(height: 16),

        // STARRED section
        if (publicChannels.isNotEmpty) ...[
          _buildSectionHeader('STARRED', Icons.expand_more),
          // TODO: Add starred channels
        ],

        const SizedBox(height: 16),

        // CHANNELS section
        _buildSectionHeader('CHANNELS', Icons.expand_more),
        ...publicChannels.map((channel) => _buildChannelItem(channel)),
        _buildAddChannelButton(),

        const SizedBox(height: 16),

        // DIRECT MESSAGES section
        _buildSectionHeader('DIRECT MESSAGES', Icons.expand_more),
        // TODO: Add DM list
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white60, size: 16),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddChannelButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showCreateChannelDialog(isPrivate: false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.add, color: Colors.white60, size: 18),
              const SizedBox(width: 12),
              Text(
                'Add channel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
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
        color: const Color(0xFF350D36), // Darker purple for nav
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.home, 'Home', isActive: true),
            _buildNavItem(Icons.chat_bubble_outline, 'DMs', isActive: false),
            _buildNavItem(Icons.alternate_email, 'Mentions', isActive: false),
            _buildNavItem(Icons.person_outline, 'You', isActive: false),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, {required bool isActive}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? Colors.white : Colors.white60,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white60,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
