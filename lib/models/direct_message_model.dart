import 'package:cloud_firestore/cloud_firestore.dart';

class DirectMessageModel {
  final String id;
  final String workspaceId;
  final List<String> participantIds;
  final String lastMessage;
  final DateTime lastMessageAt;
  final Map<String, int> unreadCounts; // userId -> unread count
  final bool isArchived;

  DirectMessageModel({
    required this.id,
    required this.workspaceId,
    required this.participantIds,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCounts,
    this.isArchived = false,
  });

  // Convert to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'workspaceId': workspaceId,
      'participantIds': participantIds,
      'lastMessage': lastMessage,
      'lastMessageAt': Timestamp.fromDate(lastMessageAt),
      'unreadCounts': unreadCounts,
      'isArchived': isArchived,
    };
  }

  // Create from Firestore document
  factory DirectMessageModel.fromMap(Map<String, dynamic> map, String id) {
    return DirectMessageModel(
      id: id,
      workspaceId: map['workspaceId'] ?? '',
      participantIds: List<String>.from(map['participantIds'] ?? []),
      lastMessage: map['lastMessage'] ?? '',
      lastMessageAt: (map['lastMessageAt'] as Timestamp).toDate(),
      unreadCounts: Map<String, int>.from(map['unreadCounts'] ?? {}),
      isArchived: map['isArchived'] ?? false,
    );
  }

  // Copy with method for updates
  DirectMessageModel copyWith({
    String? id,
    String? workspaceId,
    List<String>? participantIds,
    String? lastMessage,
    DateTime? lastMessageAt,
    Map<String, int>? unreadCounts,
    bool? isArchived,
  }) {
    return DirectMessageModel(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      participantIds: participantIds ?? this.participantIds,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}
