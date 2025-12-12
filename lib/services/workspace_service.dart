import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import '../models/workspace_model.dart';
import '../models/channel_model.dart';
import 'logger_service.dart';

class WorkspaceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _logger = LoggerService();

  // Generate unique workspace ID
  String _generateWorkspaceId() {
    return _firestore.collection('workspaces').doc().id;
  }

  // Generate unique channel ID
  String _generateChannelId() {
    return _firestore.collection('channels').doc().id;
  }

  // Generate invite code (6 character alphanumeric)
  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  // Create workspace
  Future<WorkspaceModel> createWorkspace({
    required String name,
    required String ownerId,
    String? description,
    String? password,
  }) async {
    try {
      _logger.log('Creating workspace',
        category: 'FIRESTORE',
        phase: 'Phase 2',
        feature: 'Workspace Creation',
        data: {'name': name, 'ownerId': ownerId, 'hasPassword': password != null}
      );

      final workspaceId = _generateWorkspaceId();
      final inviteCode = _generateInviteCode();
      final now = DateTime.now();

      // Create workspace
      final workspace = WorkspaceModel(
        id: workspaceId,
        name: name,
        description: description,
        ownerId: ownerId,
        memberIds: [ownerId],
        channelIds: [],
        createdAt: now,
        inviteCode: inviteCode,
        password: password,
      );

      await _firestore.collection('workspaces').doc(workspaceId).set(workspace.toMap());

      // Create default #general channel
      final generalChannelId = _generateChannelId();
      final generalChannel = ChannelModel(
        id: generalChannelId,
        name: 'general',
        workspaceId: workspaceId,
        description: 'General discussion channel',
        isPrivate: false,
        memberIds: [ownerId],
        createdAt: now,
        createdBy: ownerId,
      );

      await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('channels')
        .doc(generalChannelId)
        .set(generalChannel.toMap());

      // Update workspace with channel ID
      await _firestore.collection('workspaces').doc(workspaceId).update({
        'channelIds': FieldValue.arrayUnion([generalChannelId]),
      });

      _logger.logFirestore('create_workspace', success: true, collection: 'workspaces');
      _logger.log('Workspace created successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        phase: 'Phase 2',
        data: {'workspaceId': workspaceId, 'inviteCode': inviteCode, 'channelId': generalChannelId}
      );

      return workspace.copyWith(channelIds: [generalChannelId]);
    } catch (e) {
      _logger.logFirestore('create_workspace', success: false, collection: 'workspaces', error: e.toString());
      _logger.log('Failed to create workspace',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'error': e.toString()}
      );
      throw Exception('Workspace oluşturulamadı: $e');
    }
  }

  // Join workspace by invite code
  Future<WorkspaceModel?> joinWorkspace({
    required String inviteCode,
    required String userId,
    String? password,
  }) async {
    try {
      _logger.log('Joining workspace',
        category: 'FIRESTORE',
        phase: 'Phase 2',
        feature: 'Workspace Join',
        data: {'inviteCode': inviteCode, 'userId': userId}
      );

      // Find workspace by invite code
      final querySnapshot = await _firestore
        .collection('workspaces')
        .where('inviteCode', isEqualTo: inviteCode)
        .limit(1)
        .get();

      if (querySnapshot.docs.isEmpty) {
        _logger.log('Workspace not found',
          level: LogLevel.warning,
          category: 'FIRESTORE',
          data: {'inviteCode': inviteCode}
        );
        throw Exception('Geçersiz davet kodu');
      }

      final workspaceDoc = querySnapshot.docs.first;
      final workspace = WorkspaceModel.fromMap(workspaceDoc.data());

      // Check password if workspace is protected
      if (workspace.password != null && workspace.password != password) {
        _logger.log('Invalid password',
          level: LogLevel.warning,
          category: 'FIRESTORE',
          data: {'workspaceId': workspace.id}
        );
        throw Exception('Yanlış şifre');
      }

      // Check if user is already a member
      if (workspace.memberIds.contains(userId)) {
        _logger.log('User already member',
          level: LogLevel.info,
          category: 'FIRESTORE',
          data: {'workspaceId': workspace.id, 'userId': userId}
        );
        return workspace;
      }

      // Add user to workspace members
      await _firestore.collection('workspaces').doc(workspace.id).update({
        'memberIds': FieldValue.arrayUnion([userId]),
      });

      // Add user to all public channels
      final channelsSnapshot = await _firestore
        .collection('workspaces')
        .doc(workspace.id)
        .collection('channels')
        .where('isPrivate', isEqualTo: false)
        .get();

      for (var channelDoc in channelsSnapshot.docs) {
        await _firestore
          .collection('workspaces')
          .doc(workspace.id)
          .collection('channels')
          .doc(channelDoc.id)
          .update({
            'memberIds': FieldValue.arrayUnion([userId]),
          });
      }

      _logger.logFirestore('join_workspace', success: true, collection: 'workspaces');
      _logger.log('User joined workspace successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        phase: 'Phase 2',
        data: {'workspaceId': workspace.id, 'userId': userId}
      );

      return workspace.copyWith(
        memberIds: [...workspace.memberIds, userId],
      );
    } catch (e) {
      _logger.logFirestore('join_workspace', success: false, collection: 'workspaces', error: e.toString());
      _logger.log('Failed to join workspace',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'error': e.toString()}
      );
      rethrow;
    }
  }

  // Get user's workspaces
  Future<List<WorkspaceModel>> getUserWorkspaces(String userId) async {
    try {
      _logger.log('Fetching user workspaces',
        category: 'FIRESTORE',
        data: {'userId': userId}
      );

      final querySnapshot = await _firestore
        .collection('workspaces')
        .where('memberIds', arrayContains: userId)
        .get();

      final workspaces = querySnapshot.docs
        .map((doc) => WorkspaceModel.fromMap(doc.data()))
        .toList();

      _logger.logFirestore('get_user_workspaces', success: true, collection: 'workspaces');
      _logger.log('User workspaces fetched successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        data: {'userId': userId, 'count': workspaces.length}
      );

      return workspaces;
    } catch (e) {
      _logger.logFirestore('get_user_workspaces', success: false, collection: 'workspaces', error: e.toString());
      _logger.log('Failed to fetch user workspaces',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'userId': userId, 'error': e.toString()}
      );
      throw Exception('Workspace\'ler getirilemedi: $e');
    }
  }

  // Get workspace by ID
  Future<WorkspaceModel?> getWorkspace(String workspaceId) async {
    try {
      final doc = await _firestore.collection('workspaces').doc(workspaceId).get();

      if (doc.exists) {
        return WorkspaceModel.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      _logger.log('Failed to fetch workspace',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'error': e.toString()}
      );
      throw Exception('Workspace getirilemedi: $e');
    }
  }

  // Stream user's workspaces
  Stream<List<WorkspaceModel>> getUserWorkspacesStream(String userId) {
    return _firestore
      .collection('workspaces')
      .where('memberIds', arrayContains: userId)
      .snapshots()
      .map((snapshot) => snapshot.docs
        .map((doc) => WorkspaceModel.fromMap(doc.data()))
        .toList());
  }

  // Get workspace channels
  Future<List<ChannelModel>> getWorkspaceChannels(String workspaceId) async {
    try {
      final querySnapshot = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('channels')
        .orderBy('createdAt')
        .get();

      final channels = querySnapshot.docs
        .map((doc) => ChannelModel.fromMap(doc.data()))
        .toList();

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

  // Leave workspace
  Future<void> leaveWorkspace(String workspaceId, String userId) async {
    try {
      _logger.log('Leaving workspace',
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'userId': userId}
      );

      // Remove user from workspace
      await _firestore.collection('workspaces').doc(workspaceId).update({
        'memberIds': FieldValue.arrayRemove([userId]),
      });

      // Remove user from all channels
      final channelsSnapshot = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('channels')
        .get();

      for (var channelDoc in channelsSnapshot.docs) {
        await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('channels')
          .doc(channelDoc.id)
          .update({
            'memberIds': FieldValue.arrayRemove([userId]),
          });
      }

      _logger.logFirestore('leave_workspace', success: true, collection: 'workspaces');
      _logger.log('User left workspace successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'userId': userId}
      );
    } catch (e) {
      _logger.logFirestore('leave_workspace', success: false, collection: 'workspaces', error: e.toString());
      _logger.log('Failed to leave workspace',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'workspaceId': workspaceId, 'userId': userId, 'error': e.toString()}
      );
      throw Exception('Workspace\'den çıkılamadı: $e');
    }
  }
}
