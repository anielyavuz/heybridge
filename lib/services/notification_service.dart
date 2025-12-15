import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'navigation_service.dart';
import 'logger_service.dart';

// Conditional import for Platform
import 'platform_stub.dart' if (dart.library.io) 'dart:io';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background message
  await NotificationService.instance.showLocalNotification(message);
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LoggerService _logger = LoggerService();

  bool _isInitialized = false;
  String? _currentToken;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Web'de sadece temel FCM işlevleri çalışır
    if (kIsWeb) {
      _isInitialized = true;
      return;
    }

    // Request permission
    await _requestPermission();

    // Initialize local notifications
    await _initializeLocalNotifications();

    // Setup message handlers
    _setupMessageHandlers();

    // Get initial token
    _currentToken = await getToken();

    _isInitialized = true;
  }

  /// Request notification permissions
  Future<void> _requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
  }

  /// Initialize local notifications for foreground display
  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Skip local notifications initialization on web
    if (kIsWeb) return;

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel for Android
    if (!kIsWeb && Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'heybridge_messages',
        'HeyBridge Messages',
        description: 'Notifications for new messages in HeyBridge',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    _handleNotificationNavigation(response.payload);
  }

  /// Parse payload and navigate to appropriate screen
  void _handleNotificationNavigation(String? payload) {
    if (payload == null || payload.isEmpty) return;

    try {
      final data = _parsePayloadString(payload);
      if (data == null) return;

      final type = data['type'];

      if (type == 'channel_message') {
        NavigationService.instance.setPendingNavigation({
          'type': 'channel_message',
          'workspaceId': data['workspaceId'],
          'channelId': data['channelId'],
          'channelName': data['channelName'],
          'messageId': data['messageId'],
        });
      } else if (type == 'dm_message') {
        NavigationService.instance.setPendingNavigation({
          'type': 'dm_message',
          'dmId': data['dmId'],
          'messageId': data['messageId'],
        });
      }
    } catch (e) {
      // Error parsing payload
    }
  }

  /// Parse string payload to Map
  Map<String, dynamic>? _parsePayloadString(String payload) {
    try {
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      try {
        final cleaned = payload.replaceAll('{', '').replaceAll('}', '');
        final pairs = cleaned.split(', ');
        final map = <String, dynamic>{};
        for (final pair in pairs) {
          final kv = pair.split(': ');
          if (kv.length == 2) {
            map[kv[0].trim()] = kv[1].trim();
          }
        }
        return map.isNotEmpty ? map : null;
      } catch (_) {
        return null;
      }
    }
  }

  /// Setup FCM message handlers
  void _setupMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle when app is opened from a notification (background state)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Check if app was opened from a terminated state notification
    _checkInitialMessage();
  }

  /// Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    await showLocalNotification(message);
  }

  /// Handle when app is opened from notification
  void _handleMessageOpenedApp(RemoteMessage message) {
    _handleRemoteMessageNavigation(message.data);
  }

  /// Check if app was launched from a notification
  Future<void> _checkInitialMessage() async {
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleRemoteMessageNavigation(initialMessage.data);
    }
  }

  /// Handle navigation from RemoteMessage data
  void _handleRemoteMessageNavigation(Map<String, dynamic> data) {
    if (data.isEmpty) return;

    final type = data['type'];

    if (type == 'channel_message') {
      NavigationService.instance.setPendingNavigation({
        'type': 'channel_message',
        'workspaceId': data['workspaceId'],
        'channelId': data['channelId'],
        'channelName': data['channelName'],
        'messageId': data['messageId'],
      });
    } else if (type == 'dm_message') {
      NavigationService.instance.setPendingNavigation({
        'type': 'dm_message',
        'dmId': data['dmId'],
        'messageId': data['messageId'],
      });
    }
  }

  /// Show local notification
  Future<void> showLocalNotification(RemoteMessage message) async {
    // Skip on web - local notifications not supported
    if (kIsWeb) return;

    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'heybridge_messages',
      'HeyBridge Messages',
      channelDescription: 'Notifications for new messages in HeyBridge',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title ?? 'HeyBridge',
      notification.body ?? '',
      details,
      payload: message.data.toString(),
    );
  }

  /// Get FCM token for current device
  Future<String?> getToken() async {
    try {
      // iOS'ta önce APNS token'ın hazır olmasını bekle
      if (!kIsWeb && Platform.isIOS) {
        _logger.debug('iOS: Waiting for APNS token...', category: 'FCM');
        String? apnsToken = await _messaging.getAPNSToken();
        int attempts = 0;
        while (apnsToken == null && attempts < 5) {
          await Future.delayed(const Duration(seconds: 1));
          apnsToken = await _messaging.getAPNSToken();
          attempts++;
          _logger.debug('iOS: APNS attempt $attempts, token: ${apnsToken != null}', category: 'FCM');
        }
        if (apnsToken == null) {
          _logger.warning('iOS: APNS token is null after 5 attempts', category: 'FCM');
          return null;
        }
        _logger.success('iOS: APNS token obtained', category: 'FCM');
      }

      final token = await _messaging.getToken();
      _currentToken = token;
      _logger.info('Token obtained: ${token != null ? "${token.substring(0, 20)}..." : "null"}', category: 'FCM');
      return token;
    } catch (e) {
      _logger.error('Error getting token: $e', category: 'FCM');
      return null;
    }
  }

  /// Get unique device identifier
  String _getDeviceId() {
    final os = kIsWeb ? 'web' : Platform.operatingSystem;
    return '${os}_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Save FCM token to Firestore for a user (supports multiple devices)
  Future<void> saveTokenToFirestore(String userId) async {
    try {
      _logger.info('saveTokenToFirestore called', category: 'FCM', data: {'userId': userId});
      final token = await getToken();
      if (token == null) {
        _logger.warning('Token is null, cannot save', category: 'FCM');
        return;
      }

      final platform = kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android');
      final now = DateTime.now().toIso8601String();

      // Kullanıcının mevcut token'larını al
      final userDoc = await _firestore.collection('users').doc(userId).get();

      List<Map<String, dynamic>> existingTokens = [];
      if (userDoc.exists && userDoc.data()?['fcmTokens'] != null) {
        final rawTokens = userDoc.data()!['fcmTokens'] as List;
        existingTokens = rawTokens.map((t) => Map<String, dynamic>.from(t)).toList();
      }

      // Bu token zaten var mı kontrol et
      final existingIndex = existingTokens.indexWhere((t) => t['token'] == token);

      if (existingIndex >= 0) {
        // Token varsa lastUsedAt güncelle
        existingTokens[existingIndex]['lastUsedAt'] = now;
        _logger.debug('Token already exists, updating lastUsedAt', category: 'FCM');
      } else {
        // Yeni token ekle
        existingTokens.add({
          'token': token,
          'platform': platform,
          'deviceId': _getDeviceId(),
          'createdAt': now,
          'lastUsedAt': now,
        });
        _logger.info('New token added', category: 'FCM', data: {'platform': platform});
      }

      // 30 günden eski token'ları temizle
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      existingTokens.removeWhere((t) {
        try {
          final lastUsed = DateTime.parse(t['lastUsedAt']);
          return lastUsed.isBefore(thirtyDaysAgo);
        } catch (e) {
          return false;
        }
      });

      // Firestore'a kaydet
      await _firestore.collection('users').doc(userId).set({
        'fcmTokens': existingTokens,
      }, SetOptions(merge: true));
      _logger.success('Token saved to Firestore', category: 'FCM', data: {'totalTokens': existingTokens.length});
    } catch (e) {
      _logger.error('Error saving token: $e', category: 'FCM');
    }
  }

  /// Remove current device's FCM token from Firestore when user logs out
  Future<void> removeTokenFromFirestore(String userId) async {
    try {
      final token = _currentToken ?? await getToken();
      if (token == null) return;

      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists || userDoc.data()?['fcmTokens'] == null) return;

      List<Map<String, dynamic>> existingTokens =
          (userDoc.data()!['fcmTokens'] as List)
              .map((t) => Map<String, dynamic>.from(t))
              .toList();

      existingTokens.removeWhere((t) => t['token'] == token);

      await _firestore.collection('users').doc(userId).update({
        'fcmTokens': existingTokens,
      });
    } catch (e) {
      // Error removing token
    }
  }

  /// Setup token refresh listener
  void setupTokenRefreshListener(String userId) {
    _messaging.onTokenRefresh.listen((newToken) async {
      if (_currentToken != null && _currentToken != newToken) {
        await _removeSpecificToken(userId, _currentToken!);
      }

      _currentToken = newToken;
      await saveTokenToFirestore(userId);
    });
  }

  /// Remove a specific token from user's token list
  Future<void> _removeSpecificToken(String userId, String token) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists || userDoc.data()?['fcmTokens'] == null) return;

      List<Map<String, dynamic>> existingTokens =
          (userDoc.data()!['fcmTokens'] as List)
              .map((t) => Map<String, dynamic>.from(t))
              .toList();

      existingTokens.removeWhere((t) => t['token'] == token);

      await _firestore.collection('users').doc(userId).update({
        'fcmTokens': existingTokens,
      });
    } catch (e) {
      // Error removing specific token
    }
  }

  // ==================== Channel Notification Settings ====================

  /// Enable/disable notifications for a specific channel
  Future<void> setChannelNotification(
      String userId, String channelId, bool enabled) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'channelNotifications': {channelId: enabled},
      }, SetOptions(merge: true));
    } catch (e) {
      // Error setting channel notification
    }
  }

  /// Enable/disable notifications for a specific DM
  Future<void> setDMNotification(
      String userId, String dmId, bool enabled) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'dmNotifications': {dmId: enabled},
      }, SetOptions(merge: true));
    } catch (e) {
      // Error setting DM notification
    }
  }

  /// Enable/disable all notifications globally
  Future<void> setGlobalNotifications(String userId, bool enabled) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'globalNotificationsEnabled': enabled,
      });
    } catch (e) {
      // Error setting global notifications
    }
  }

  // ==================== Topic Subscriptions ====================

  /// Subscribe to a topic (e.g., workspace or channel)
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
    } catch (e) {
      // Error subscribing to topic
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
    } catch (e) {
      // Error unsubscribing from topic
    }
  }

  /// Subscribe user to workspace topics
  Future<void> subscribeToWorkspace(String workspaceId) async {
    await subscribeToTopic('workspace_$workspaceId');
  }

  /// Unsubscribe user from workspace topics
  Future<void> unsubscribeFromWorkspace(String workspaceId) async {
    await unsubscribeFromTopic('workspace_$workspaceId');
  }

  /// Subscribe user to channel topics
  Future<void> subscribeToChannel(String workspaceId, String channelId) async {
    await subscribeToTopic('channel_${workspaceId}_$channelId');
  }

  /// Unsubscribe user from channel topics
  Future<void> unsubscribeFromChannel(
      String workspaceId, String channelId) async {
    await unsubscribeFromTopic('channel_${workspaceId}_$channelId');
  }

  /// Subscribe to DM conversation
  Future<void> subscribeToDM(String dmId) async {
    await subscribeToTopic('dm_$dmId');
  }

  /// Unsubscribe from DM conversation
  Future<void> unsubscribeFromDM(String dmId) async {
    await unsubscribeFromTopic('dm_$dmId');
  }

  /// Subscribe to user's personal notification topic
  Future<void> subscribeToUserTopic(String userId) async {
    await subscribeToTopic('user_$userId');
  }

  /// Unsubscribe from user's personal notification topic
  Future<void> unsubscribeFromUserTopic(String userId) async {
    await unsubscribeFromTopic('user_$userId');
  }

  // ==================== Sync Subscriptions ====================

  /// Sync all channel subscriptions for a user based on their workspaces
  Future<void> syncAllSubscriptions(String userId, List<String> workspaceIds) async {
    try {
      // Subscribe to user's personal topic
      await subscribeToUserTopic(userId);

      // Subscribe to all workspaces
      for (final workspaceId in workspaceIds) {
        await subscribeToWorkspace(workspaceId);

        // Get all channels in workspace and subscribe
        final channelsSnapshot = await _firestore
            .collection('workspaces')
            .doc(workspaceId)
            .collection('channels')
            .get();

        for (final channelDoc in channelsSnapshot.docs) {
          await subscribeToChannel(workspaceId, channelDoc.id);
        }
      }

      // Subscribe to all DMs
      final dmsSnapshot = await _firestore
          .collection('directMessages')
          .where('participantIds', arrayContains: userId)
          .get();

      for (final dmDoc in dmsSnapshot.docs) {
        await subscribeToDM(dmDoc.id);
      }
    } catch (e) {
      // Error syncing subscriptions
    }
  }
}
