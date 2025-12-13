import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String channelId;
  final String senderId;
  final String senderName;
  final String? senderPhotoURL;
  final String text;
  final List<String>? attachments;
  final String? replyToId;
  final Map<String, List<String>>? reactions; // emoji -> list of userIds
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isEdited;
  final bool isDeleted;

  MessageModel({
    required this.id,
    required this.channelId,
    required this.senderId,
    required this.senderName,
    this.senderPhotoURL,
    required this.text,
    this.attachments,
    this.replyToId,
    this.reactions,
    required this.createdAt,
    this.updatedAt,
    this.isEdited = false,
    this.isDeleted = false,
  });

  // Convert MessageModel to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'channelId': channelId,
      'senderId': senderId,
      'senderName': senderName,
      'senderPhotoURL': senderPhotoURL,
      'text': text,
      'attachments': attachments,
      'replyToId': replyToId,
      'reactions': reactions,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
    };
  }

  // Create MessageModel from Firestore document
  factory MessageModel.fromMap(Map<String, dynamic> map, String documentId) {
    return MessageModel(
      id: documentId,
      channelId: map['channelId'] ?? '',
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? 'Unknown',
      senderPhotoURL: map['senderPhotoURL'],
      text: map['text'] ?? '',
      attachments: map['attachments'] != null
        ? List<String>.from(map['attachments'])
        : null,
      replyToId: map['replyToId'],
      reactions: map['reactions'] != null
        ? Map<String, List<String>>.from(
            (map['reactions'] as Map).map(
              (key, value) => MapEntry(
                key.toString(),
                List<String>.from(value),
              ),
            ),
          )
        : null,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: map['updatedAt'] != null
        ? (map['updatedAt'] as Timestamp).toDate()
        : null,
      isEdited: map['isEdited'] ?? false,
      isDeleted: map['isDeleted'] ?? false,
    );
  }

  // Create a copy with updated fields
  MessageModel copyWith({
    String? id,
    String? channelId,
    String? senderId,
    String? senderName,
    String? senderPhotoURL,
    String? text,
    List<String>? attachments,
    String? replyToId,
    Map<String, List<String>>? reactions,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isEdited,
    bool? isDeleted,
  }) {
    return MessageModel(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderPhotoURL: senderPhotoURL ?? this.senderPhotoURL,
      text: text ?? this.text,
      attachments: attachments ?? this.attachments,
      replyToId: replyToId ?? this.replyToId,
      reactions: reactions ?? this.reactions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
