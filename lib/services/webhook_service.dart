import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/webhook_model.dart';
import 'logger_service.dart';

class WebhookService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _logger = LoggerService();

  // Generate unique webhook ID
  String _generateWebhookId() {
    return _firestore.collection('webhooks').doc().id;
  }

  // Create webhook for a channel
  Future<WebhookModel> createWebhook({
    required String name,
    required String channelId,
    required String workspaceId,
    required String createdBy,
  }) async {
    try {
      _logger.log('Creating webhook',
        category: 'WEBHOOK',
        data: {
          'name': name,
          'channelId': channelId,
          'workspaceId': workspaceId,
        }
      );

      final webhookId = _generateWebhookId();
      final now = DateTime.now();

      final webhook = WebhookModel(
        id: webhookId,
        name: name,
        channelId: channelId,
        workspaceId: workspaceId,
        createdBy: createdBy,
        createdAt: now,
        isActive: true,
      );

      // Store webhook in global webhooks collection for easy lookup by ID
      await _firestore
        .collection('webhooks')
        .doc(webhookId)
        .set(webhook.toMap());

      _logger.log('Webhook created successfully',
        level: LogLevel.success,
        category: 'WEBHOOK',
        data: {
          'webhookId': webhookId,
          'webhookUrl': webhook.webhookUrl,
        }
      );

      return webhook;
    } catch (e) {
      _logger.log('Failed to create webhook',
        level: LogLevel.error,
        category: 'WEBHOOK',
        data: {'error': e.toString()}
      );
      throw Exception('Webhook oluşturulamadı: $e');
    }
  }

  // Get webhooks for a channel
  Future<List<WebhookModel>> getChannelWebhooks({
    required String channelId,
  }) async {
    try {
      final querySnapshot = await _firestore
        .collection('webhooks')
        .where('channelId', isEqualTo: channelId)
        .get();

      final webhooks = querySnapshot.docs
        .map((doc) => WebhookModel.fromMap(doc.data()))
        .toList();
      // Sort client-side to avoid composite index requirement
      webhooks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return webhooks;
    } catch (e) {
      _logger.log('Failed to get channel webhooks',
        level: LogLevel.error,
        category: 'WEBHOOK',
        data: {'channelId': channelId, 'error': e.toString()}
      );
      throw Exception('Webhooklar getirilemedi: $e');
    }
  }

  // Stream webhooks for a channel
  Stream<List<WebhookModel>> getChannelWebhooksStream({
    required String channelId,
  }) {
    _logger.debug('Starting webhook stream for channel: $channelId', category: 'WEBHOOK');

    return _firestore
      .collection('webhooks')
      .where('channelId', isEqualTo: channelId)
      .snapshots()
      .map((snapshot) {
        _logger.debug('Webhook stream received ${snapshot.docs.length} docs', category: 'WEBHOOK');
        final webhooks = snapshot.docs
          .map((doc) => WebhookModel.fromMap(doc.data()))
          .toList();
        // Sort client-side to avoid composite index requirement
        webhooks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return webhooks;
      });
  }

  // Get webhook by ID
  Future<WebhookModel?> getWebhook(String webhookId) async {
    try {
      final doc = await _firestore
        .collection('webhooks')
        .doc(webhookId)
        .get();

      if (doc.exists) {
        return WebhookModel.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      _logger.log('Failed to get webhook',
        level: LogLevel.error,
        category: 'WEBHOOK',
        data: {'webhookId': webhookId, 'error': e.toString()}
      );
      return null;
    }
  }

  // Toggle webhook active status
  Future<void> toggleWebhookStatus({
    required String webhookId,
    required bool isActive,
  }) async {
    try {
      await _firestore
        .collection('webhooks')
        .doc(webhookId)
        .update({'isActive': isActive});

      _logger.log('Webhook status updated',
        level: LogLevel.success,
        category: 'WEBHOOK',
        data: {'webhookId': webhookId, 'isActive': isActive}
      );
    } catch (e) {
      _logger.log('Failed to update webhook status',
        level: LogLevel.error,
        category: 'WEBHOOK',
        data: {'webhookId': webhookId, 'error': e.toString()}
      );
      throw Exception('Webhook durumu güncellenemedi: $e');
    }
  }

  // Delete webhook
  Future<void> deleteWebhook(String webhookId) async {
    try {
      await _firestore
        .collection('webhooks')
        .doc(webhookId)
        .delete();

      _logger.log('Webhook deleted',
        level: LogLevel.success,
        category: 'WEBHOOK',
        data: {'webhookId': webhookId}
      );
    } catch (e) {
      _logger.log('Failed to delete webhook',
        level: LogLevel.error,
        category: 'WEBHOOK',
        data: {'webhookId': webhookId, 'error': e.toString()}
      );
      throw Exception('Webhook silinemedi: $e');
    }
  }

  // Update webhook name
  Future<void> updateWebhookName({
    required String webhookId,
    required String name,
  }) async {
    try {
      await _firestore
        .collection('webhooks')
        .doc(webhookId)
        .update({'name': name});

      _logger.log('Webhook name updated',
        level: LogLevel.success,
        category: 'WEBHOOK',
        data: {'webhookId': webhookId, 'name': name}
      );
    } catch (e) {
      _logger.log('Failed to update webhook name',
        level: LogLevel.error,
        category: 'WEBHOOK',
        data: {'webhookId': webhookId, 'error': e.toString()}
      );
      throw Exception('Webhook adı güncellenemedi: $e');
    }
  }
}
