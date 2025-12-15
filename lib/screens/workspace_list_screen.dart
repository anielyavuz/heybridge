import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/workspace_service.dart';
import '../services/presence_service.dart';
import '../services/logger_service.dart';
import '../services/preferences_service.dart';
import '../models/workspace_model.dart';
import 'login_screen.dart';
import 'channel_list_screen.dart';

class WorkspaceListScreen extends StatefulWidget {
  const WorkspaceListScreen({super.key});

  @override
  State<WorkspaceListScreen> createState() => _WorkspaceListScreenState();
}

class _WorkspaceListScreenState extends State<WorkspaceListScreen> {
  final _authService = AuthService();
  final _workspaceService = WorkspaceService();
  final _presenceService = PresenceService();
  final _logger = LoggerService();
  final _preferencesService = PreferencesService();
  List<WorkspaceModel> _workspaces = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _logger.logUI('WorkspaceListScreen', 'screen_opened');
    _loadWorkspaces();
  }

  Future<void> _loadWorkspaces() async {
    try {
      final userId = _authService.currentUser?.uid;
      if (userId != null) {
        final workspaces = await _workspaceService.getUserWorkspaces(userId);
        setState(() {
          _workspaces = workspaces;
          _isLoading = false;
        });
        _logger.log(
          'Workspaces loaded',
          category: 'UI',
          data: {'count': workspaces.length},
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _logger.log(
        'Failed to load workspaces',
        level: LogLevel.error,
        category: 'UI',
        data: {'error': e.toString()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Workspace\'ler yüklenemedi: $e'),
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
        title: const Text('Workspaces', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            onPressed: () async {
              _logger.logUI('WorkspaceListScreen', 'logout_button_pressed');
              // Set offline before signing out
              await _presenceService.goOffline();
              await _authService.signOut();
              if (context.mounted) {
                _logger.logNavigation('WorkspaceListScreen', 'LoginScreen');
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
            icon: const Icon(Icons.logout, color: Colors.white70),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _workspaces.isEmpty
          ? _buildEmptyState()
          : _buildWorkspaceList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.workspaces_outline,
            size: 80,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          const Text(
            'No workspaces yet',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create or join a workspace to get started',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _workspaces.length,
      itemBuilder: (context, index) {
        final workspace = _workspaces[index];
        return Card(
          color: const Color(0xFF2D3748),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF4A9EFF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  workspace.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
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
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: workspace.description != null
                ? Text(
                    workspace.description!,
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    '${workspace.memberIds.length} member${workspace.memberIds.length > 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
            trailing: workspace.password != null
                ? const Icon(Icons.lock, color: Colors.white60, size: 20)
                : null,
            onTap: () async {
              _logger.logUI(
                'WorkspaceListScreen',
                'workspace_selected',
                data: {
                  'workspaceId': workspace.id,
                  'workspaceName': workspace.name,
                },
              );

              // Save last workspace
              await _preferencesService.saveLastWorkspaceId(workspace.id);

              _logger.logNavigation('WorkspaceListScreen', 'ChannelListScreen');
              if (mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChannelListScreen(workspace: workspace),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }
}
