import 'dart:async';
import 'package:flutter/widgets.dart';
import 'firestore_service.dart';
import 'auth_service.dart';
import 'logger_service.dart';

/// Service that manages user online/offline presence status.
/// Updates presence every 30 seconds while the app is active.
/// A user is considered online if lastSeen is within 1 minute.
class PresenceService with WidgetsBindingObserver {
  static final PresenceService _instance = PresenceService._internal();
  factory PresenceService() => _instance;
  PresenceService._internal();

  final _firestoreService = FirestoreService();
  final _authService = AuthService();
  final _logger = LoggerService();

  Timer? _presenceTimer;
  bool _isInitialized = false;

  /// Initialize the presence service
  /// Should be called once when the app starts (after login)
  void init() {
    if (_isInitialized) return;

    _isInitialized = true;
    WidgetsBinding.instance.addObserver(this);

    // Start presence updates
    _startPresenceUpdates();

    _logger.log('PresenceService initialized',
      category: 'PRESENCE',
      level: LogLevel.info
    );
  }

  /// Dispose the presence service
  /// Should be called when user logs out
  void dispose() {
    _stopPresenceUpdates();
    WidgetsBinding.instance.removeObserver(this);
    _isInitialized = false;

    _logger.log('PresenceService disposed',
      category: 'PRESENCE',
      level: LogLevel.info
    );
  }

  /// Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final userId = _authService.currentUser?.uid;
    if (userId == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        // App is in foreground - set online and start timer
        _setOnline();
        _startPresenceUpdates();
        _logger.log('App resumed - setting online',
          category: 'PRESENCE',
          level: LogLevel.info
        );
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App is in background or closed - set offline and stop timer
        _setOffline();
        _stopPresenceUpdates();
        _logger.log('App paused/inactive - setting offline',
          category: 'PRESENCE',
          level: LogLevel.info
        );
        break;
    }
  }

  /// Start the presence update timer (every 30 seconds)
  void _startPresenceUpdates() {
    _presenceTimer?.cancel();

    // Update immediately
    _setOnline();

    // Then update every 30 seconds
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _setOnline();
    });
  }

  /// Stop the presence update timer
  void _stopPresenceUpdates() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  /// Set user as online
  Future<void> _setOnline() async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      _logger.log('Cannot set online - no user logged in',
        category: 'PRESENCE',
        level: LogLevel.warning
      );
      return;
    }

    try {
      _logger.log('Setting user online',
        category: 'PRESENCE',
        level: LogLevel.debug,
        data: {'userId': userId}
      );
      await _firestoreService.updatePresence(userId, true);
      _logger.log('User set online successfully',
        category: 'PRESENCE',
        level: LogLevel.info,
        data: {'userId': userId}
      );
    } catch (e) {
      _logger.log('Failed to set online',
        category: 'PRESENCE',
        level: LogLevel.error,
        data: {'userId': userId, 'error': e.toString()}
      );
    }
  }

  /// Set user as offline
  Future<void> _setOffline() async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) return;

    try {
      await _firestoreService.updatePresence(userId, false);
    } catch (e) {
      _logger.log('Failed to set offline',
        category: 'PRESENCE',
        level: LogLevel.error,
        data: {'error': e.toString()}
      );
    }
  }

  /// Manually set offline (e.g., on logout)
  Future<void> goOffline() async {
    await _setOffline();
    dispose();
  }

  /// Manually set online (e.g., on login)
  Future<void> goOnline() async {
    _logger.log('goOnline called',
      category: 'PRESENCE',
      level: LogLevel.info
    );
    init();
    // Always set online immediately when goOnline is called
    await _setOnline();
  }
}
