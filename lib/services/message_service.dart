import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';

class MessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get messages stream for a channel (real-time)
  Stream<List<MessageModel>> getChannelMessagesStream({
    required String workspaceId,
    required String channelId,
    int limit = 50,
  }) {
    return _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((snapshot) {
        return snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();
      });
  }

  // Send a new message
  Future<MessageModel> sendMessage({
    required String workspaceId,
    required String channelId,
    required String senderId,
    required String senderName,
    String? senderPhotoURL,
    required String text,
    List<String>? attachments,
    String? replyToId,
  }) async {
    final messageRef = _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .doc();

    final message = MessageModel(
      id: messageRef.id,
      channelId: channelId,
      senderId: senderId,
      senderName: senderName,
      senderPhotoURL: senderPhotoURL,
      text: text,
      attachments: attachments,
      replyToId: replyToId,
      createdAt: DateTime.now(),
    );

    await messageRef.set(message.toMap());

    // Update channel's last message timestamp
    await _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .update({
        'lastMessageAt': Timestamp.now(),
      });

    return message;
  }

  // Update a message (edit)
  Future<void> updateMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String newText,
  }) async {
    await _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .doc(messageId)
      .update({
        'text': newText,
        'updatedAt': Timestamp.now(),
        'isEdited': true,
      });
  }

  // Delete a message (soft delete)
  Future<void> deleteMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    await _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .doc(messageId)
      .update({
        'text': 'This message was deleted',
        'isDeleted': true,
        'updatedAt': Timestamp.now(),
      });
  }

  // Add reaction to a message
  Future<void> addReaction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
    required String userId,
  }) async {
    final messageRef = _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .doc(messageId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(messageRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});

      if (reactions.containsKey(emoji)) {
        final users = List<String>.from(reactions[emoji]);
        if (!users.contains(userId)) {
          users.add(userId);
          reactions[emoji] = users;
        }
      } else {
        reactions[emoji] = [userId];
      }

      transaction.update(messageRef, {'reactions': reactions});
    });
  }

  // Remove reaction from a message
  Future<void> removeReaction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
    required String userId,
  }) async {
    final messageRef = _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .doc(messageId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(messageRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});

      if (reactions.containsKey(emoji)) {
        final users = List<String>.from(reactions[emoji]);
        users.remove(userId);

        if (users.isEmpty) {
          reactions.remove(emoji);
        } else {
          reactions[emoji] = users;
        }

        transaction.update(messageRef, {'reactions': reactions});
      }
    });
  }

  // Get a single message
  Future<MessageModel?> getMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    final doc = await _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .doc(messageId)
      .get();

    if (!doc.exists) return null;
    return MessageModel.fromMap(doc.data()!, doc.id);
  }

  // Load older messages (pagination)
  Future<List<MessageModel>> loadOlderMessages({
    required String workspaceId,
    required String channelId,
    required DateTime before,
    int limit = 50,
  }) async {
    final snapshot = await _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .where('createdAt', isLessThan: Timestamp.fromDate(before))
      .limit(limit)
      .get();

    return snapshot.docs
      .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
      .toList();
  }

  // Pin a message
  Future<void> pinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String userId,
  }) async {
    await _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .doc(messageId)
      .update({
        'isPinned': true,
        'pinnedBy': userId,
        'pinnedAt': Timestamp.now(),
      });
  }

  // Unpin a message
  Future<void> unpinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    await _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .doc(messageId)
      .update({
        'isPinned': false,
        'pinnedBy': null,
        'pinnedAt': null,
      });
  }

  // Get pinned messages for a channel
  Stream<List<MessageModel>> getPinnedMessagesStream({
    required String workspaceId,
    required String channelId,
  }) {
    return _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .where('isPinned', isEqualTo: true)
      .orderBy('pinnedAt', descending: true)
      .snapshots()
      .map((snapshot) {
        return snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();
      });
  }

  // Star a message (add user to starredBy list)
  Future<void> starMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String userId,
  }) async {
    await _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .doc(messageId)
      .update({
        'starredBy': FieldValue.arrayUnion([userId]),
      });
  }

  // Unstar a message (remove user from starredBy list)
  Future<void> unstarMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String userId,
  }) async {
    await _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .doc(messageId)
      .update({
        'starredBy': FieldValue.arrayRemove([userId]),
      });
  }

  // Get starred messages for a user in a workspace
  Future<List<MessageModel>> getStarredMessages({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    final snapshot = await _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('channels')
      .doc(channelId)
      .collection('messages')
      .where('starredBy', arrayContains: userId)
      .orderBy('createdAt', descending: true)
      .get();

    return snapshot.docs
      .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
      .toList();
  }
}
