import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/workspace_service.dart';
import 'services/preferences_service.dart';
import 'services/notification_service.dart';
import 'screens/login_screen.dart';
import 'screens/workspace_screen.dart';
import 'screens/workspace_list_screen.dart';
import 'screens/channel_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize notification service (skip background handler on web)
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  await NotificationService.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HeyBridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A9EFF)),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _authService = AuthService();
  final _workspaceService = WorkspaceService();
  final _preferencesService = PreferencesService();

  String? _lastUserId;

  /// Initialize notifications for the logged-in user
  Future<void> _initializeNotificationsForUser(String userId) async {
    final notificationService = NotificationService.instance;
    await notificationService.saveTokenToFirestore(userId);
    notificationService.setupTokenRefreshListener(userId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _authService.authStateChanges,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1A1D21),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF4A9EFF)),
            ),
          );
        }

        // If user is not logged in, show login screen
        if (!authSnapshot.hasData) {
          _lastUserId = null;
          return const LoginScreen();
        }

        // User is logged in, check if they have workspaces
        final userId = authSnapshot.data!.uid;

        // Save FCM token when user logs in (only once per session)
        if (_lastUserId != userId) {
          _lastUserId = userId;
          _initializeNotificationsForUser(userId);
        }

        return StreamBuilder(
          stream: _workspaceService.getUserWorkspacesStream(userId),
          builder: (context, workspaceSnapshot) {
            if (workspaceSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFF1A1D21),
                body: Center(
                  child: CircularProgressIndicator(color: Color(0xFF4A9EFF)),
                ),
              );
            }

            final workspaces = workspaceSnapshot.data ?? [];

            // If user has no workspaces, show workspace creation/join screen
            if (workspaces.isEmpty) {
              return const WorkspaceScreen();
            }

            // If user has workspaces, try to load last workspace
            return FutureBuilder<String?>(
              future: _preferencesService.getLastWorkspaceId(),
              builder: (context, lastWorkspaceSnapshot) {
                if (lastWorkspaceSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Scaffold(
                    backgroundColor: Color(0xFF1A1D21),
                    body: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF4A9EFF),
                      ),
                    ),
                  );
                }

                final lastWorkspaceId = lastWorkspaceSnapshot.data;

                // Check if last workspace still exists in user's workspaces
                if (lastWorkspaceId != null) {
                  final lastWorkspace = workspaces.firstWhere(
                    (w) => w.id == lastWorkspaceId,
                    orElse: () => workspaces.first,
                  );

                  // Navigate directly to the last workspace
                  return ChannelListScreen(workspace: lastWorkspace);
                }

                // No last workspace saved, show workspace list
                return const WorkspaceListScreen();
              },
            );
          },
        );
      },
    );
  }
}
