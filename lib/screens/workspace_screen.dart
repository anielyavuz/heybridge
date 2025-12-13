import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/workspace_service.dart';
import '../services/firestore_service.dart';
import '../services/logger_service.dart';
import 'login_screen.dart';
import 'workspace_list_screen.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _authService = AuthService();
  final _workspaceService = WorkspaceService();
  final _firestoreService = FirestoreService();
  final _logger = LoggerService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _logger.logUI('WorkspaceScreen', 'screen_opened');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1D21),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D3748),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.bubble_chart,
                        color: Color(0xFF4A9EFF),
                        size: 24,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () async {
                        _logger.logUI(
                          'WorkspaceScreen',
                          'logout_button_pressed',
                        );
                        await _authService.signOut();
                        if (context.mounted) {
                          _logger.logNavigation(
                            'WorkspaceScreen',
                            'LoginScreen',
                          );
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.logout, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 60),
                Container(
                  width: 120,
                  height: 100,
                  margin: const EdgeInsets.only(bottom: 32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF4A9EFF).withValues(alpha: 0.3),
                        const Color(0xFF2D5F8F).withValues(alpha: 0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: List.generate(
                      12,
                      (index) => Positioned(
                        left: (index % 4) * 30.0 + 10,
                        top: (index ~/ 4) * 30.0 + 10,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF4A9EFF,
                                ).withValues(alpha: 0.5),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Text(
                  'Where does your team\nlive?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Workspaces are where your team\ncommunicates. Create a new one or join an\nexisting team.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D3748),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: () {
                      _logger.logUI(
                        'WorkspaceScreen',
                        'create_workspace_button_pressed',
                      );
                      _showCreateWorkspaceDialog(context);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4A9EFF),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Create a Workspace',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Get your team together and start a new channel.',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.white60,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D3748),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: () {
                      _logger.logUI(
                        'WorkspaceScreen',
                        'join_workspace_button_pressed',
                      );
                      _showJoinWorkspaceDialog(context);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D3748),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(
                              Icons.tag,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Join a Workspace',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Enter an invite code or find your team URL.',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.white60,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateWorkspaceDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final passwordController = TextEditingController();
    bool hasPassword = false;

    _logger.logUI('WorkspaceScreen', 'create_workspace_dialog_opened');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2D3748),
          title: const Text(
            'Create a Workspace',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Workspace Name',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'e.g. My Team Workspace',
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
                  'Description (Optional)',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'What is this workspace about?',
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
                    Checkbox(
                      value: hasPassword,
                      onChanged: (value) {
                        setDialogState(() {
                          hasPassword = value ?? false;
                        });
                      },
                      fillColor: WidgetStateProperty.all(
                        const Color(0xFF4A9EFF),
                      ),
                    ),
                    const Text(
                      'Password protect this workspace',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
                if (hasPassword) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    style: const TextStyle(color: Colors.white),
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Enter password',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.lock, color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1A1D21),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
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
                  'WorkspaceScreen',
                  'create_workspace_dialog_cancelled',
                );
                Navigator.of(context).pop();
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white),
              ),
            ),
            ElevatedButton(
              onPressed: () => _handleCreateWorkspace(
                context,
                nameController.text,
                descriptionController.text.isEmpty
                    ? null
                    : descriptionController.text,
                hasPassword ? passwordController.text : null,
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

  Future<void> _handleCreateWorkspace(
    BuildContext context,
    String name,
    String? description,
    String? password,
  ) async {
    if (name.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workspace adı boş olamaz'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    _logger.logUI(
      'WorkspaceScreen',
      'create_workspace_confirmed',
      data: {'workspaceName': name, 'hasPassword': password != null},
    );

    // Capture context references before async operations
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) throw Exception('Kullanıcı oturumu bulunamadı');

      final workspace = await _workspaceService.createWorkspace(
        name: name,
        ownerId: userId,
        description: description,
        password: password,
      );

      // Add workspace ID to user's workspaceIds
      await _firestoreService.addUserToWorkspace(userId, workspace.id);

      if (mounted && context.mounted) {
        final inviteCode = workspace.inviteCode ?? '';

        navigator.pop(); // Close dialog

        // Show success with invite code
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF2D3748),
            title: const Text(
              'Workspace Created!',
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Share this invite code with your team:',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D21),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    inviteCode,
                    style: const TextStyle(
                      color: Color(0xFF4A9EFF),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  navigator.pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const WorkspaceListScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A9EFF),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showJoinWorkspaceDialog(BuildContext context) {
    final codeController = TextEditingController();
    final passwordController = TextEditingController();
    bool needsPassword = false;

    _logger.logUI('WorkspaceScreen', 'join_workspace_dialog_opened');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2D3748),
          title: const Text(
            'Join a Workspace',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Invite Code',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: codeController,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'XXXXXX',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.tag, color: Colors.white60),
                    filled: true,
                    fillColor: const Color(0xFF1A1D21),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    // Auto-check if this workspace needs password
                    // In a real app, you might want to check this with the server
                  },
                ),
                if (needsPassword) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Password',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    style: const TextStyle(color: Colors.white),
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Enter workspace password',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.lock, color: Colors.white60),
                      filled: true,
                      fillColor: const Color(0xFF1A1D21),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
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
                  'WorkspaceScreen',
                  'join_workspace_dialog_cancelled',
                );
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _handleJoinWorkspace(
                context,
                codeController.text,
                passwordController.text.isEmpty
                    ? null
                    : passwordController.text,
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
                  : const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleJoinWorkspace(
    BuildContext context,
    String inviteCode,
    String? password,
  ) async {
    if (inviteCode.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Davet kodu boş olamaz'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    _logger.logUI(
      'WorkspaceScreen',
      'join_workspace_confirmed',
      data: {'inviteCode': inviteCode},
    );

    // Capture context references before any async operations
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) throw Exception('Kullanıcı oturumu bulunamadı');

      final workspace = await _workspaceService.joinWorkspace(
        inviteCode: inviteCode.toUpperCase().trim(),
        userId: userId,
        password: password,
      );

      if (workspace != null) {
        final workspaceName = workspace.name;

        // Add workspace ID to user's workspaceIds
        await _firestoreService.addUserToWorkspace(userId, workspace.id);

        if (mounted) {
          navigator.pop(); // Close dialog

          // Navigate to workspace list immediately
          navigator.pushReplacement(
            MaterialPageRoute(builder: (_) => const WorkspaceListScreen()),
          );

          // Show success message after navigation
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text('$workspaceName workspace\'ine katıldınız!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
