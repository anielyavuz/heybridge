import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'navigation_service.dart';
import 'logger_service.dart';
import '../widgets/in_app_notification.dart';

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
    if (_isInitialized) {
      _logger.debug('NotificationService already initialized', category: 'FCM');
      return;
    }

    _logger.info('Initializing NotificationService...', category: 'FCM');

    // Web'de sadece temel FCM işlevleri çalışır
    if (kIsWeb) {
      _logger.info('Web platform detected, skipping native FCM setup', category: 'FCM');
      _isInitialized = true;
      return;
    }

    // Request permission
    _logger.debug('Requesting notification permissions...', category: 'FCM');
    await _requestPermission();

    // Initialize local notifications
    _logger.debug('Initializing local notifications...', category: 'FCM');
    await _initializeLocalNotifications();

    // Disable iOS system notifications in foreground - we handle them with in-app banners
    // This allows us to suppress notifications (e.g., when user is viewing the DM)
    _logger.debug('Configuring foreground notification options...', category: 'FCM');
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,  // Don't show system alert - we use InAppNotification
      badge: true,   // Keep badge updates
      sound: false,  // Don't play system sound - we control this
    );

    // Setup message handlers
    _logger.debug('Setting up message handlers...', category: 'FCM');
    _setupMessageHandlers();

    // Get initial token
    _logger.debug('Getting initial FCM token...', category: 'FCM');
    _currentToken = await getToken();

    // Clear badge on app launch
    await clearBadge();

    _isInitialized = true;
    _logger.success('NotificationService initialized successfully', category: 'FCM');
  }

  /// Clear app badge count
  Future<void> clearBadge() async {
    if (kIsWeb) return;

    try {
      // iOS: Clear badge by showing a notification with badge 0, then canceling
      if (Platform.isIOS) {
        final iosPlugin = _localNotifications
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

        if (iosPlugin != null) {
          // Cancel all notifications first
          await _localNotifications.cancelAll();

          // Show a silent notification with badge 0 to reset the badge
          const iosDetails = DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: true,
            presentSound: false,
            badgeNumber: 0,
          );

          await _localNotifications.show(
            999999, // Special ID for badge reset
            '',
            '',
            const NotificationDetails(iOS: iosDetails),
          );

          // Immediately cancel it
          await _localNotifications.cancel(999999);
        }
      }

      // Android: Cancel all notifications
      if (Platform.isAndroid) {
        await _localNotifications.cancelAll();
      }

      _logger.debug('Badge cleared', category: 'FCM');
    } catch (e) {
      _logger.error('Error clearing badge: $e', category: 'FCM');
    }
  }

  /// Request notification permissions
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    _logger.info('Permission status: ${settings.authorizationStatus}', category: 'FCM', data: {
      'alert': settings.alert.name,
      'badge': settings.badge.name,
      'sound': settings.sound.name,
    });
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
    _logger.info('Notification tapped', category: 'FCM', data: {
      'payload': response.payload,
      'actionId': response.actionId,
    });
    _handleNotificationNavigation(response.payload);
  }

  /// Parse payload and navigate to appropriate screen
  void _handleNotificationNavigation(String? payload) {
    if (payload == null || payload.isEmpty) {
      _logger.debug('No payload to navigate', category: 'FCM');
      return;
    }

    try {
      final data = _parsePayloadString(payload);
      if (data == null) {
        _logger.warning('Could not parse payload', category: 'FCM', data: {'payload': payload});
        return;
      }

      final type = data['type'];
      _logger.info('Navigating from notification', category: 'FCM', data: {'type': type});

      if (type == 'channel_message') {
        NavigationService.instance.setPendingNavigation({
          'type': 'channel_message',
          'workspaceId': data['workspaceId'],
          'channelId': data['channelId'],
          'channelName': data['channelName'],
          'messageId': data['messageId'],
        });
        _logger.debug('Set pending navigation to channel', category: 'FCM', data: {
          'channelId': data['channelId'],
          'channelName': data['channelName'],
        });
      } else if (type == 'dm_message') {
        NavigationService.instance.setPendingNavigation({
          'type': 'dm_message',
          'workspaceId': data['workspaceId'],
          'dmId': data['dmId'],
          'messageId': data['messageId'],
        });
        _logger.debug('Set pending navigation to DM', category: 'FCM', data: {
          'workspaceId': data['workspaceId'],
          'dmId': data['dmId'],
        });
      }
    } catch (e) {
      _logger.error('Error parsing notification payload: $e', category: 'FCM');
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
    _logger.info('Foreground message received', category: 'FCM', data: {
      'title': message.notification?.title,
      'body': message.notification?.body,
      'data': message.data,
    });

    // Show in-app notification banner (WhatsApp style)
    _showInAppNotification(message);
  }

  /// Show in-app notification banner when app is in foreground
  void _showInAppNotification(RemoteMessage message) {
    final context = NavigationService.instance.navigatorKey.currentContext;
    if (context == null) {
      _logger.warning('No context available for in-app notification', category: 'FCM');
      return;
    }

    final notification = message.notification;
    final data = message.data;

    // Suppress DM notifications if user is currently viewing that DM
    // Check for dmId in data - if present and matches active DM, suppress notification
    final dmId = data['dmId'];
    final activeDmId = NavigationService.instance.activeDmId;

    if (dmId != null && activeDmId != null && dmId == activeDmId) {
      _logger.debug('Suppressing DM notification - user is viewing this DM',
        category: 'FCM',
        data: {'dmId': dmId}
      );
      return;
    }

    final title = notification?.title ?? 'HeyBridge';
    final body = notification?.body ?? '';

    InAppNotification.show(
      context: context,
      title: title,
      body: body,
      onTap: () {
        _logger.info('In-app notification tapped', category: 'FCM');
        _handleRemoteMessageNavigation(data);

        // Navigate immediately if we have context
        _navigateFromNotification(data);
      },
    );
  }

  /// Navigate to the appropriate screen from notification data
  void _navigateFromNotification(Map<String, dynamic> data) {
    final type = data['type'];
    final workspaceId = data['workspaceId'];

    if (type == null || workspaceId == null) return;

    final navigatorState = NavigationService.instance.navigatorKey.currentState;
    if (navigatorState == null) return;

    // For now, just set pending navigation and let the current screen handle it
    // A more sophisticated implementation would navigate directly
    NavigationService.instance.setPendingNavigation({
      'type': type,
      'workspaceId': workspaceId,
      'channelId': data['channelId'],
      'channelName': data['channelName'],
      'dmId': data['dmId'],
      'messageId': data['messageId'],
    });

    // Pop to root and rebuild to trigger navigation check
    navigatorState.popUntil((route) => route.isFirst);
  }

  /// Handle when app is opened from notification
  void _handleMessageOpenedApp(RemoteMessage message) {
    _logger.info('App opened from notification (background)', category: 'FCM', data: {
      'title': message.notification?.title,
      'data': message.data,
    });

    // Clear badge when notification is tapped
    clearBadge();

    _handleRemoteMessageNavigation(message.data);

    // Trigger navigation after a short delay to ensure context is ready
    Future.delayed(const Duration(milliseconds: 500), () {
      _triggerPendingNavigation();
    });
  }

  /// Trigger pending navigation if navigator is ready
  void _triggerPendingNavigation({int retryCount = 0}) {
    // Notify listeners (ChannelListScreen) to check for pending navigation
    NavigationService.instance.notifyNavigationListeners();

    // If pending navigation still exists after notification, retry
    // This handles the case where ChannelListScreen hasn't mounted yet
    if (retryCount < 5) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (NavigationService.instance.peekPendingNavigation() != null) {
          _logger.debug('Retrying navigation trigger (attempt ${retryCount + 1})', category: 'FCM');
          _triggerPendingNavigation(retryCount: retryCount + 1);
        }
      });
    }
  }

  /// Check if app was launched from a notification
  Future<void> _checkInitialMessage() async {
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _logger.info('App launched from notification (terminated)', category: 'FCM', data: {
        'title': initialMessage.notification?.title,
        'data': initialMessage.data,
      });

      // Clear badge
      clearBadge();

      _handleRemoteMessageNavigation(initialMessage.data);

      // Trigger navigation after app is fully loaded
      Future.delayed(const Duration(milliseconds: 1000), () {
        _triggerPendingNavigation();
      });
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
        'workspaceId': data['workspaceId'],
        'dmId': data['dmId'],
        'messageId': data['messageId'],
      });
    }
  }

  /// Show local notification
  Future<void> showLocalNotification(RemoteMessage message) async {
    // Skip on web - local notifications not supported
    if (kIsWeb) {
      _logger.debug('Skipping local notification on web', category: 'FCM');
      return;
    }

    final notification = message.notification;
    if (notification == null) {
      _logger.warning('No notification content in message', category: 'FCM');
      return;
    }

    _logger.info('Showing local notification', category: 'FCM', data: {
      'title': notification.title,
      'body': notification.body,
    });

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
    _logger.success('Local notification displayed', category: 'FCM');
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
    _logger.info('Removing token from Firestore', category: 'FCM', data: {'userId': userId});
    try {
      final token = _currentToken ?? await getToken();
      if (token == null) {
        _logger.warning('No token to remove', category: 'FCM');
        return;
      }

      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists || userDoc.data()?['fcmTokens'] == null) {
        _logger.debug('No existing tokens to remove from', category: 'FCM');
        return;
      }

      List<Map<String, dynamic>> existingTokens =
          (userDoc.data()!['fcmTokens'] as List)
              .map((t) => Map<String, dynamic>.from(t))
              .toList();

      final beforeCount = existingTokens.length;
      existingTokens.removeWhere((t) => t['token'] == token);
      final afterCount = existingTokens.length;

      await _firestore.collection('users').doc(userId).update({
        'fcmTokens': existingTokens,
      });
      _logger.success('Token removed from Firestore', category: 'FCM', data: {
        'tokensRemoved': beforeCount - afterCount,
        'remainingTokens': afterCount,
      });
    } catch (e) {
      _logger.error('Error removing token: $e', category: 'FCM');
    }
  }

  /// Setup token refresh listener
  void setupTokenRefreshListener(String userId) {
    _logger.info('Setting up token refresh listener', category: 'FCM', data: {'userId': userId});
    _messaging.onTokenRefresh.listen((newToken) async {
      _logger.info('Token refresh detected', category: 'FCM', data: {
        'hasOldToken': _currentToken != null,
        'newTokenPrefix': newToken.substring(0, 20),
      });
      if (_currentToken != null && _currentToken != newToken) {
        _logger.debug('Removing old token before saving new one', category: 'FCM');
        await _removeSpecificToken(userId, _currentToken!);
      }

      _currentToken = newToken;
      await saveTokenToFirestore(userId);
    });
  }

  /// Remove a specific token from user's token list
  Future<void> _removeSpecificToken(String userId, String token) async {
    _logger.debug('Removing specific token', category: 'FCM', data: {
      'userId': userId,
      'tokenPrefix': token.length > 20 ? token.substring(0, 20) : token,
    });
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists || userDoc.data()?['fcmTokens'] == null) {
        _logger.debug('No tokens found to remove', category: 'FCM');
        return;
      }

      List<Map<String, dynamic>> existingTokens =
          (userDoc.data()!['fcmTokens'] as List)
              .map((t) => Map<String, dynamic>.from(t))
              .toList();

      existingTokens.removeWhere((t) => t['token'] == token);

      await _firestore.collection('users').doc(userId).update({
        'fcmTokens': existingTokens,
      });
      _logger.success('Specific token removed', category: 'FCM');
    } catch (e) {
      _logger.error('Error removing specific token: $e', category: 'FCM');
    }
  }

  // ==================== Channel Notification Settings ====================

  /// Enable/disable notifications for a specific channel
  Future<void> setChannelNotification(
      String userId, String channelId, bool enabled) async {
    _logger.debug('Setting channel notification', category: 'FCM', data: {
      'channelId': channelId,
      'enabled': enabled,
    });
    try {
      await _firestore.collection('users').doc(userId).set({
        'channelNotifications': {channelId: enabled},
      }, SetOptions(merge: true));
      _logger.success('Channel notification setting saved', category: 'FCM');
    } catch (e) {
      _logger.error('Error setting channel notification: $e', category: 'FCM');
    }
  }

  /// Enable/disable notifications for a specific DM
  Future<void> setDMNotification(
      String userId, String dmId, bool enabled) async {
    _logger.debug('Setting DM notification', category: 'FCM', data: {
      'dmId': dmId,
      'enabled': enabled,
    });
    try {
      await _firestore.collection('users').doc(userId).set({
        'dmNotifications': {dmId: enabled},
      }, SetOptions(merge: true));
      _logger.success('DM notification setting saved', category: 'FCM');
    } catch (e) {
      _logger.error('Error setting DM notification: $e', category: 'FCM');
    }
  }

  /// Enable/disable all notifications globally
  Future<void> setGlobalNotifications(String userId, bool enabled) async {
    _logger.info('Setting global notifications', category: 'FCM', data: {'enabled': enabled});
    try {
      await _firestore.collection('users').doc(userId).update({
        'globalNotificationsEnabled': enabled,
      });
      _logger.success('Global notification setting saved', category: 'FCM');
    } catch (e) {
      _logger.error('Error setting global notifications: $e', category: 'FCM');
    }
  }

  // ==================== Topic Subscriptions ====================

  /// Subscribe to a topic (e.g., workspace or channel)
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      _logger.debug('Subscribed to topic: $topic', category: 'FCM');
    } catch (e) {
      _logger.error('Error subscribing to topic $topic: $e', category: 'FCM');
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      _logger.debug('Unsubscribed from topic: $topic', category: 'FCM');
    } catch (e) {
      _logger.error('Error unsubscribing from topic $topic: $e', category: 'FCM');
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
    _logger.info('Syncing all subscriptions', category: 'FCM', data: {
      'userId': userId,
      'workspaceCount': workspaceIds.length,
    });
    try {
      // Subscribe to user's personal topic
      await subscribeToUserTopic(userId);

      int channelCount = 0;
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
          channelCount++;
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

      _logger.success('All subscriptions synced', category: 'FCM', data: {
        'workspaces': workspaceIds.length,
        'channels': channelCount,
        'dms': dmsSnapshot.docs.length,
      });
    } catch (e) {
      _logger.error('Error syncing subscriptions: $e', category: 'FCM');
    }
  }
}
