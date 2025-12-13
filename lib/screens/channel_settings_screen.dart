import 'package:flutter/material.dart';
import '../models/workspace_model.dart';
import '../models/channel_model.dart';
import '../services/channel_service.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';

class ChannelSettingsScreen extends StatefulWidget {
  final WorkspaceModel workspace;
  final ChannelModel channel;

  const ChannelSettingsScreen({
    super.key,
    required this.workspace,
    required this.channel,
  });

  @override
  State<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
  final _channelService = ChannelService();
  final _authService = AuthService();
  final _logger = LoggerService();

  @override
  void initState() {
    super.initState();
    _logger.logUI('ChannelSettingsScreen', 'screen_opened',
      data: {
        'workspaceId': widget.workspace.id,
        'channelId': widget.channel.id,
        'channelName': widget.channel.name,
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = _authService.currentUser?.uid;
    final isCreator = userId == widget.channel.createdBy;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1D21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D3748),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Channel Settings',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Channel Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: const Color(0xFF2D3748),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.channel.isPrivate ? Icons.lock : Icons.tag,
                        color: Colors.white70,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.channel.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.channel.isPrivate ? 'Private Channel' : 'Public Channel',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (widget.channel.description != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      widget.channel.description!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Settings Options
            _buildSettingsSection([
              if (isCreator)
                _buildSettingItem(
                  icon: Icons.edit,
                  title: 'Edit Channel Name',
                  subtitle: 'Change the channel name',
                  onTap: () => _showEditNameDialog(),
                ),
              if (isCreator)
                _buildSettingItem(
                  icon: Icons.description,
                  title: 'Edit Description',
                  subtitle: 'Change the channel description',
                  onTap: () => _showEditDescriptionDialog(),
                ),
              _buildSettingItem(
                icon: Icons.people,
                title: 'Channel Members',
                subtitle: '${widget.channel.memberIds.length} members',
                onTap: () {
                  // TODO: Show members list
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Members list coming soon!')),
                  );
                },
              ),
              _buildSettingItem(
                icon: Icons.notifications,
                title: 'Notifications',
                subtitle: 'Manage notification preferences',
                onTap: () {
                  // TODO: Show notification settings
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notification settings coming soon!')),
                  );
                },
              ),
            ]),

            const SizedBox(height: 8),

            // Danger Zone
            _buildSettingsSection([
              _buildSettingItem(
                icon: Icons.exit_to_app,
                title: 'Leave Channel',
                subtitle: 'You will no longer have access to this channel',
                onTap: () => _showLeaveChannelDialog(),
                isDestructive: true,
              ),
              if (isCreator)
                _buildSettingItem(
                  icon: Icons.delete,
                  title: 'Delete Channel',
                  subtitle: 'Permanently delete this channel',
                  onTap: () => _showDeleteChannelDialog(),
                  isDestructive: true,
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection(List<Widget> items) {
    return Container(
      color: const Color(0xFF2D3748),
      child: Column(
        children: items,
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(
                icon,
                color: isDestructive ? Colors.red : Colors.white70,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDestructive ? Colors.red : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isDestructive ? Colors.red.withValues(alpha: 0.7) : Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: isDestructive ? Colors.red.withValues(alpha: 0.5) : Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditNameDialog() {
    final nameController = TextEditingController(text: widget.channel.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D3748),
        title: const Text(
          'Edit Channel Name',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () => _handleUpdateChannelName(nameController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditDescriptionDialog() {
    final descriptionController = TextEditingController(
      text: widget.channel.description ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D3748),
        title: const Text(
          'Edit Channel Description',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: descriptionController,
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () => _handleUpdateChannelDescription(
              descriptionController.text.isEmpty ? null : descriptionController.text,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUpdateChannelName(String newName) async {
    // Validate channel name
    final cleanName = newName.trim().toLowerCase().replaceAll(' ', '-');
    if (cleanName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kanal adı boş olamaz'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(cleanName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kanal adı sadece küçük harf, rakam ve tire içerebilir'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await _channelService.updateChannel(
        workspaceId: widget.workspace.id,
        channelId: widget.channel.id,
        name: cleanName,
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        Navigator.of(context).pop(); // Close settings
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kanal adı güncellendi'),
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
    }
  }

  Future<void> _handleUpdateChannelDescription(String? newDescription) async {
    try {
      await _channelService.updateChannel(
        workspaceId: widget.workspace.id,
        channelId: widget.channel.id,
        description: newDescription,
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        Navigator.of(context).pop(); // Close settings
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kanal açıklaması güncellendi'),
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
    }
  }

  void _showLeaveChannelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D3748),
        title: const Text(
          'Leave Channel',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to leave #${widget.channel.name}? You will need to be re-invited to join again.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () => _handleLeaveChannel(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Leave', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDeleteChannelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D3748),
        title: const Text(
          'Delete Channel',
          style: TextStyle(color: Colors.red),
        ),
        content: Text(
          'Are you sure you want to delete #${widget.channel.name}? This action cannot be undone and all messages will be lost.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () => _handleDeleteChannel(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLeaveChannel() async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) return;

    try {
      await _channelService.leaveChannel(
        workspaceId: widget.workspace.id,
        channelId: widget.channel.id,
        userId: userId,
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        Navigator.of(context).pop(); // Close settings
        Navigator.of(context).pop(); // Close chat
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Left #${widget.channel.name}'),
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
    }
  }

  Future<void> _handleDeleteChannel() async {
    try {
      await _channelService.deleteChannel(
        workspaceId: widget.workspace.id,
        channelId: widget.channel.id,
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        Navigator.of(context).pop(); // Close settings
        Navigator.of(context).pop(); // Close chat
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('#${widget.channel.name} deleted'),
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
    }
  }
}
