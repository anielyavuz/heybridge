import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/workspace_service.dart';
import 'screens/login_screen.dart';
import 'screens/workspace_screen.dart';
import 'screens/workspace_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final workspaceService = WorkspaceService();

    return StreamBuilder(
      stream: authService.authStateChanges,
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
          return const LoginScreen();
        }

        // User is logged in, check if they have workspaces
        final userId = authSnapshot.data!.uid;

        return StreamBuilder(
          stream: workspaceService.getUserWorkspacesStream(userId),
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

            // If user has workspaces, show workspace list
            if (workspaces.isNotEmpty) {
              return const WorkspaceListScreen();
            }

            // If user has no workspaces, show workspace creation/join screen
            return const WorkspaceScreen();
          },
        );
      },
    );
  }
}
