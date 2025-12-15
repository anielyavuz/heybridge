import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// FCM Backend API Service
/// Cloud Run üzerinde çalışan FCM servisine istek gönderir
/// URL Firebase'den dinamik olarak okunur
class FcmApiService {
  static final FcmApiService instance = FcmApiService._();
  FcmApiService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cached URL
  String? _cachedBaseUrl;
  DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 30);

  // Timeout süreleri
  static const Duration _timeout = Duration(seconds: 10);

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[FCM API] $message');
    }
  }

  /// Firebase'den FCM URL'ini al (cached)
  Future<String?> _getBaseUrl() async {
    // Cache kontrolü
    if (_cachedBaseUrl != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        _log('Using cached URL: $_cachedBaseUrl');
        return _cachedBaseUrl;
      }
    }

    try {
      _log('Fetching FCM URL from Firestore...');
      final doc = await _firestore
          .collection('system')
          .doc('generalConfigs')
          .get();

      if (doc.exists) {
        final data = doc.data();
        _cachedBaseUrl = data?['fcmURL'] as String?;
        _cacheTime = DateTime.now();
        _log('FCM URL loaded: $_cachedBaseUrl');
        return _cachedBaseUrl;
      }
      _log('FCM URL not found in Firestore (document does not exist)');
      return null;
    } catch (e) {
      _log('Error fetching FCM URL: $e');
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
    _log('Sending channel notification for #$channelName');
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        _log('ERROR: FCM URL is null or empty');
        return false;
      }

      final url = '$baseUrl/api/notify/channel';
      _log('POST $url');

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

      _log('Response: ${response.statusCode} - ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      _log('ERROR sending channel notification: $e');
      return false;
    }
  }

  /// DM bildirimi gönder
  Future<bool> notifyDMMessage({
    required String dmId,
    required String senderId,
    required String senderName,
    required String message,
    required String messageId,
  }) async {
    _log('Sending DM notification from $senderName');
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        _log('ERROR: FCM URL is null or empty');
        return false;
      }

      final url = '$baseUrl/api/notify/dm';
      _log('POST $url');

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'dmId': dmId,
              'senderId': senderId,
              'senderName': senderName,
              'message': message,
              'messageId': messageId,
            }),
          )
          .timeout(_timeout);

      _log('Response: ${response.statusCode} - ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      _log('ERROR sending DM notification: $e');
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
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        return false;
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/notify/user'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'title': title,
              'body': body,
              'data': data ?? {},
            }),
          )
          .timeout(_timeout);

      return response.statusCode == 200;
    } catch (e) {
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
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        return false;
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/notify/topic'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'topic': topic,
              'title': title,
              'body': body,
              'data': data ?? {},
            }),
          )
          .timeout(_timeout);

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Sağlık kontrolü
  Future<bool> healthCheck() async {
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        return false;
      }

      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(_timeout);

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
