import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/direct_message_model.dart';
import 'logger_service.dart';

class DMService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LoggerService _logger = LoggerService();

  // Get or create a DM between two users
  Future<DirectMessageModel> getOrCreateDM({
    required String workspaceId,
    required String userId1,
    required String userId2,
  }) async {
    _logger.info('Getting or creating DM', category: 'DM', data: {
      'workspaceId': workspaceId,
      'userId1': userId1,
      'userId2': userId2,
    });

    // Sort user IDs to ensure consistent ordering
    final participantIds = [userId1, userId2]..sort();

    // Check if DM already exists
    final existingDMs = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('directMessages')
        .where('participantIds', isEqualTo: participantIds)
        .limit(1)
        .get();

    if (existingDMs.docs.isNotEmpty) {
      _logger.debug('Existing DM found', category: 'DM', data: {
        'dmId': existingDMs.docs.first.id,
      });
      return DirectMessageModel.fromMap(
        existingDMs.docs.first.data(),
        existingDMs.docs.first.id,
      );
    }

    // Create new DM
    final dmRef = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('directMessages')
        .doc();

    final newDM = DirectMessageModel(
      id: dmRef.id,
      workspaceId: workspaceId,
      participantIds: participantIds,
      lastMessage: '',
      lastMessageAt: DateTime.now(),
      unreadCounts: {userId1: 0, userId2: 0},
    );

    await dmRef.set(newDM.toMap());
    _logger.success('New DM created', category: 'DM', data: {'dmId': newDM.id});
    return newDM;
  }

  // Get user's DMs stream
  Stream<List<DirectMessageModel>> getUserDMsStream({
    required String workspaceId,
    required String userId,
  }) {
    return _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('directMessages')
        .where('participantIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      // Filter out archived DMs and sort by lastMessageAt on client side
      final dms = snapshot.docs
          .map((doc) => DirectMessageModel.fromMap(doc.data(), doc.id))
          .where((dm) => !dm.isArchived)
          .toList();

      // Sort by lastMessageAt descending (most recent first)
      dms.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

      return dms;
    });
  }

  // Update DM metadata (last message, timestamp, unread counts)
  Future<void> updateDMMetadata({
    required String workspaceId,
    required String dmId,
    required String lastMessage,
    required String senderId,
  }) async {
    final dmRef = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('directMessages')
        .doc(dmId);

    final dmDoc = await dmRef.get();
    if (!dmDoc.exists) return;

    final dm = DirectMessageModel.fromMap(dmDoc.data()!, dmDoc.id);
    final unreadCounts = Map<String, int>.from(dm.unreadCounts);

    // Increment unread count for other participant
    for (final participantId in dm.participantIds) {
      if (participantId != senderId) {
        unreadCounts[participantId] = (unreadCounts[participantId] ?? 0) + 1;
      }
    }

    await dmRef.update({
      'lastMessage': lastMessage,
      'lastMessageAt': Timestamp.now(),
      'unreadCounts': unreadCounts,
    });
  }

  // Mark DM as read for a user
  Future<void> markAsRead({
    required String workspaceId,
    required String dmId,
    required String userId,
  }) async {
    final dmRef = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('directMessages')
        .doc(dmId);

    final dmDoc = await dmRef.get();
    if (!dmDoc.exists) return;

    final dm = DirectMessageModel.fromMap(dmDoc.data()!, dmDoc.id);
    final unreadCounts = Map<String, int>.from(dm.unreadCounts);
    unreadCounts[userId] = 0;

    await dmRef.update({'unreadCounts': unreadCounts});
  }

  // Archive DM
  Future<void> archiveDM({
    required String workspaceId,
    required String dmId,
  }) async {
    await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('directMessages')
        .doc(dmId)
        .update({'isArchived': true});
  }

  // Unarchive DM
  Future<void> unarchiveDM({
    required String workspaceId,
    required String dmId,
  }) async {
    await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('directMessages')
        .doc(dmId)
        .update({'isArchived': false});
  }

  // Get single DM
  Future<DirectMessageModel?> getDM({
    required String workspaceId,
    required String dmId,
  }) async {
    final doc = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('directMessages')
        .doc(dmId)
        .get();

    if (!doc.exists) return null;
    return DirectMessageModel.fromMap(doc.data()!, doc.id);
  }
}
