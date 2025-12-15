import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/channel_model.dart';
import 'logger_service.dart';

class ChannelService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _logger = LoggerService();

  // Generate unique channel ID
  String _generateChannelId() {
    return _firestore.collection('channels').doc().id;
  }

  // Create channel
  Future<ChannelModel> createChannel({
    required String workspaceId,
    required String name,
    required String createdBy,
    String? description,
    bool isPrivate = false,
    List<String>? initialMemberIds,
  }) async {
    try {
      _logger.log('Creating channel',
        category: 'FIRESTORE',
        phase: 'Phase 3',
        feature: 'Channel Creation',
        data: {
          'workspaceId': workspaceId,
          'name': name,
          'isPrivate': isPrivate,
          'createdBy': createdBy,
        }
      );

      final channelId = _generateChannelId();
      final now = DateTime.now();

      // Ensure creator is in member list
      final memberIds = initialMemberIds ?? [createdBy];
      if (!memberIds.contains(createdBy)) {
        memberIds.add(createdBy);
      }

      final channel = ChannelModel(
        id: channelId,
        name: name.toLowerCase().trim(),
        workspaceId: workspaceId,
        description: description,
        isPrivate: isPrivate,
        memberIds: memberIds,
        createdAt: now,
        createdBy: createdBy,
      );

      // Create channel in Firestore
      await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('channels')
        .doc(channelId)
        .set(channel.toMap());

      // Update workspace channelIds
      await _firestore.collection('workspaces').doc(workspaceId).update({
        'channelIds': FieldValue.arrayUnion([channelId]),
      });

      _logger.logFirestore('create_channel', success: true, collection: 'channels');
      _logger.log('Channel created successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        phase: 'Phase 3',
        data: {'channelId': channelId, 'workspaceId': workspaceId}
      );

      return channel;
    } catch (e) {
      _logger.logFirestore('create_channel', success: false, collection: 'channels', error: e.toString());
      _logger.log('Failed to create channel',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'error': e.toString()}
      );
      throw Exception('Kanal oluşturulamadı: $e');
    }
  }

  // Get workspace channels
  Future<List<ChannelModel>> getWorkspaceChannels({
    required String workspaceId,
    String? userId,
  }) async {
    try {
      _logger.log('Fetching workspace channels',
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'userId': userId}
      );

      Query query = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('channels')
        .orderBy('createdAt');

      // If userId provided, filter by member access
      if (userId != null) {
        // Get all channels where user is a member or channel is public
        final allChannelsSnapshot = await query.get();
        final channels = allChannelsSnapshot.docs
          .map((doc) => ChannelModel.fromMap(doc.data() as Map<String, dynamic>))
          .where((channel) => !channel.isPrivate || channel.memberIds.contains(userId))
          .toList();

        _logger.log('Workspace channels fetched successfully',
          level: LogLevel.success,
          category: 'FIRESTORE',
          data: {'workspaceId': workspaceId, 'count': channels.length}
        );

        return channels;
      }

      final querySnapshot = await query.get();
      final channels = querySnapshot.docs
        .map((doc) => ChannelModel.fromMap(doc.data() as Map<String, dynamic>))
        .toList();

      _logger.log('Workspace channels fetched successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'count': channels.length}
      );

      return channels;
    } catch (e) {
      _logger.log('Failed to fetch workspace channels',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'error': e.toString()}
      );
      throw Exception('Kanallar getirilemedi: $e');
    }
  }

  // Stream workspace channels (real-time updates)
  Stream<List<ChannelModel>> getWorkspaceChannelsStream({
    required String workspaceId,
    String? userId,
  }) {
    return _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .orderBy('createdAt')
      .snapshots()
      .map((snapshot) {
        final channels = snapshot.docs
          .map((doc) => ChannelModel.fromMap(doc.data()))
          .toList();

        // Filter by user access if userId provided
        if (userId != null) {
          return channels
            .where((channel) => !channel.isPrivate || channel.memberIds.contains(userId))
            .toList();
        }

        return channels;
      });
  }

  // Get channel by ID
  Future<ChannelModel?> getChannel({
    required String workspaceId,
    required String channelId,
  }) async {
    try {
      final doc = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('channels')
        .doc(channelId)
        .get();

      if (doc.exists) {
        return ChannelModel.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      _logger.log('Failed to fetch channel',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'channelId': channelId, 'error': e.toString()}
      );
      throw Exception('Kanal getirilemedi: $e');
    }
  }

  // Join channel (for private channels)
  Future<void> joinChannel({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    try {
      _logger.log('Joining channel',
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'channelId': channelId, 'userId': userId}
      );

      await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('channels')
        .doc(channelId)
        .update({
          'memberIds': FieldValue.arrayUnion([userId]),
        });

      _logger.log('User joined channel successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'channelId': channelId, 'userId': userId}
      );
    } catch (e) {
      _logger.log('Failed to join channel',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'channelId': channelId, 'userId': userId, 'error': e.toString()}
      );
      throw Exception('Kanala katılınamadı: $e');
    }
  }

  // Leave channel
  Future<void> leaveChannel({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    try {
      _logger.log('Leaving channel',
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'channelId': channelId, 'userId': userId}
      );

      await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('channels')
        .doc(channelId)
        .update({
          'memberIds': FieldValue.arrayRemove([userId]),
        });

      _logger.log('User left channel successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'channelId': channelId, 'userId': userId}
      );
    } catch (e) {
      _logger.log('Failed to leave channel',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'channelId': channelId, 'userId': userId, 'error': e.toString()}
      );
      throw Exception('Kanaldan çıkılamadı: $e');
    }
  }

  // Update channel
  Future<void> updateChannel({
    required String workspaceId,
    required String channelId,
    String? name,
    String? description,
  }) async {
    try {
      _logger.log('Updating channel',
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'channelId': channelId}
      );

      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name.toLowerCase().trim();
      if (description != null) updates['description'] = description;

      if (updates.isNotEmpty) {
        await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('channels')
          .doc(channelId)
          .update(updates);

        _logger.log('Channel updated successfully',
          level: LogLevel.success,
          category: 'FIRESTORE',
          data: {'workspaceId': workspaceId, 'channelId': channelId}
        );
      }
    } catch (e) {
      _logger.log('Failed to update channel',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'channelId': channelId, 'error': e.toString()}
      );
      throw Exception('Kanal güncellenemedi: $e');
    }
  }

  // Delete channel
  Future<void> deleteChannel({
    required String workspaceId,
    required String channelId,
  }) async {
    try {
      _logger.log('Deleting channel',
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'channelId': channelId}
      );

      // Delete channel document
      await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('channels')
        .doc(channelId)
        .delete();

      // Remove from workspace channelIds
      await _firestore.collection('workspaces').doc(workspaceId).update({
        'channelIds': FieldValue.arrayRemove([channelId]),
      });

      _logger.log('Channel deleted successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'channelId': channelId}
      );
    } catch (e) {
      _logger.log('Failed to delete channel',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'channelId': channelId, 'error': e.toString()}
      );
      throw Exception('Kanal silinemedi: $e');
    }
  }

  // Increment unread count for all members except sender
  Future<void> incrementUnreadCount({
    required String workspaceId,
    required String channelId,
    required String senderId,
    required List<String> memberIds,
  }) async {
    try {
      final updates = <String, dynamic>{};
      for (final memberId in memberIds) {
        if (memberId != senderId) {
          updates['unreadCounts.$memberId'] = FieldValue.increment(1);
        }
      }

      if (updates.isNotEmpty) {
        await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('channels')
          .doc(channelId)
          .update(updates);
      }
    } catch (e) {
      _logger.log('Failed to increment unread count',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'channelId': channelId, 'error': e.toString()}
      );
    }
  }

  // Mark channel as read for a user
  Future<void> markChannelAsRead({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    try {
      await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('channels')
        .doc(channelId)
        .update({
          'unreadCounts.$userId': 0,
        });
    } catch (e) {
      _logger.log('Failed to mark channel as read',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'channelId': channelId, 'userId': userId, 'error': e.toString()}
      );
    }
  }
}
