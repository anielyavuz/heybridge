import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'logger_service.dart';

/// FCM Backend API Service
/// Cloud Run üzerinde çalışan FCM servisine istek gönderir
/// URL Firebase'den dinamik olarak okunur
class FcmApiService {
  static final FcmApiService instance = FcmApiService._();
  FcmApiService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LoggerService _logger = LoggerService();

  // Cached URL
  String? _cachedBaseUrl;
  DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 30);

  // Timeout süreleri
  static const Duration _timeout = Duration(seconds: 10);

  /// Firebase'den FCM URL'ini al (cached)
  Future<String?> _getBaseUrl() async {
    // Cache kontrolü
    if (_cachedBaseUrl != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        _logger.debug('Using cached URL', category: 'FCM_API', data: {'url': _cachedBaseUrl});
        return _cachedBaseUrl;
      }
    }

    try {
      _logger.info('Fetching FCM URL from Firestore...', category: 'FCM_API');
      final doc = await _firestore
          .collection('system')
          .doc('generalConfigs')
          .get();

      if (doc.exists) {
        final data = doc.data();
        _cachedBaseUrl = data?['fcmURL'] as String?;
        _cacheTime = DateTime.now();
        _logger.success('FCM URL loaded', category: 'FCM_API', data: {'url': _cachedBaseUrl});
        return _cachedBaseUrl;
      }
      _logger.warning('FCM URL not found in Firestore', category: 'FCM_API');
      return null;
    } catch (e) {
      _logger.error('Error fetching FCM URL: $e', category: 'FCM_API');
      return _cachedBaseUrl; // Return cached value on error
    }
  }

  /// Cache'i temizle (URL değiştiğinde kullanılabilir)
  void clearCache() {
    _cachedBaseUrl = null;
    _cacheTime = null;
  }

  /// Channel mesajı bildirimi gönder
  Future<bool> notifyChannelMessage({
    required String workspaceId,
    required String channelId,
    required String channelName,
    required String senderId,
    required String senderName,
    required String message,
    required String messageId,
  }) async {
    _logger.info('Sending channel notification', category: 'FCM_API', data: {'channelName': channelName});
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        _logger.error('FCM URL is null or empty', category: 'FCM_API');
        return false;
      }

      final url = '$baseUrl/api/notify/channel';
      _logger.debug('POST request', category: 'FCM_API', data: {'url': url});

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'workspaceId': workspaceId,
              'channelId': channelId,
              'channelName': channelName,
              'senderId': senderId,
              'senderName': senderName,
              'message': message,
              'messageId': messageId,
            }),
          )
          .timeout(_timeout);

      _logger.info('Channel notification response', category: 'FCM_API', data: {
        'statusCode': response.statusCode,
        'body': response.body,
      });
      return response.statusCode == 200;
    } catch (e) {
      _logger.error('Error sending channel notification: $e', category: 'FCM_API');
      return false;
    }
  }

  /// DM bildirimi gönder
  Future<bool> notifyDMMessage({
    required String workspaceId,
    required String dmId,
    required String senderId,
    required String senderName,
    required String message,
    required String messageId,
  }) async {
    _logger.info('Sending DM notification', category: 'FCM_API', data: {'senderName': senderName, 'workspaceId': workspaceId});
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        _logger.error('FCM URL is null or empty', category: 'FCM_API');
        return false;
      }

      final url = '$baseUrl/api/notify/dm';
      _logger.debug('POST request', category: 'FCM_API', data: {'url': url});

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'workspaceId': workspaceId,
              'dmId': dmId,
              'senderId': senderId,
              'senderName': senderName,
              'message': message,
              'messageId': messageId,
            }),
          )
          .timeout(_timeout);

      _logger.info('DM notification response', category: 'FCM_API', data: {
        'statusCode': response.statusCode,
        'body': response.body,
      });
      return response.statusCode == 200;
    } catch (e) {
      _logger.error('Error sending DM notification: $e', category: 'FCM_API');
      return false;
    }
  }

  /// Tek bir kullanıcıya bildirim gönder
  Future<bool> notifyUser({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    _logger.info('Sending user notification', category: 'FCM_API', data: {
      'userId': userId,
      'title': title,
    });
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        _logger.error('FCM URL is null or empty', category: 'FCM_API');
        return false;
      }

      final url = '$baseUrl/api/notify/user';
      _logger.debug('POST request', category: 'FCM_API', data: {'url': url});

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'title': title,
              'body': body,
              'data': data ?? {},
            }),
          )
          .timeout(_timeout);

      _logger.info('User notification response', category: 'FCM_API', data: {
        'statusCode': response.statusCode,
        'body': response.body,
      });
      return response.statusCode == 200;
    } catch (e) {
      _logger.error('Error sending user notification: $e', category: 'FCM_API');
      return false;
    }
  }

  /// Topic'e bildirim gönder
  Future<bool> notifyTopic({
    required String topic,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    _logger.info('Sending topic notification', category: 'FCM_API', data: {
      'topic': topic,
      'title': title,
    });
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        _logger.error('FCM URL is null or empty', category: 'FCM_API');
        return false;
      }

      final url = '$baseUrl/api/notify/topic';
      _logger.debug('POST request', category: 'FCM_API', data: {'url': url});

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'topic': topic,
              'title': title,
              'body': body,
              'data': data ?? {},
            }),
          )
          .timeout(_timeout);

      _logger.info('Topic notification response', category: 'FCM_API', data: {
        'statusCode': response.statusCode,
        'body': response.body,
      });
      return response.statusCode == 200;
    } catch (e) {
      _logger.error('Error sending topic notification: $e', category: 'FCM_API');
      return false;
    }
  }

  /// Sağlık kontrolü
  Future<bool> healthCheck() async {
    _logger.info('Performing FCM API health check', category: 'FCM_API');
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        _logger.error('FCM URL is null or empty for health check', category: 'FCM_API');
        return false;
      }

      final url = '$baseUrl/health';
      _logger.debug('GET request', category: 'FCM_API', data: {'url': url});

      final response = await http
          .get(Uri.parse(url))
          .timeout(_timeout);

      final isHealthy = response.statusCode == 200;
      if (isHealthy) {
        _logger.success('FCM API health check passed', category: 'FCM_API', data: {
          'statusCode': response.statusCode,
        });
      } else {
        _logger.warning('FCM API health check failed', category: 'FCM_API', data: {
          'statusCode': response.statusCode,
          'body': response.body,
        });
      }
      return isHealthy;
    } catch (e) {
      _logger.error('Health check failed: $e', category: 'FCM_API');
      return false;
    }
  }
}
