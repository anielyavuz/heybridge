import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? photoURL;
  final String? avatarId;
  final DateTime createdAt;
  final DateTime lastSeen;
  final bool isOnline;
  final List<String> workspaceIds;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoURL,
    this.avatarId,
    required this.createdAt,
    required this.lastSeen,
    this.isOnline = false,
    this.workspaceIds = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoURL': photoURL,
      'avatarId': avatarId,
      'createdAt': createdAt.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
      'isOnline': isOnline,
      'workspaceIds': workspaceIds,
    };
  }

  /// Parse DateTime from various formats (Timestamp, String, or null)
  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      displayName: map['displayName'] ?? '',
      photoURL: map['photoURL'],
      avatarId: map['avatarId'],
      createdAt: _parseDateTime(map['createdAt']),
      lastSeen: _parseDateTime(map['lastSeen']),
      isOnline: map['isOnline'] ?? false,
      workspaceIds: List<String>.from(map['workspaceIds'] ?? []),
    );
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoURL,
    String? avatarId,
    DateTime? createdAt,
    DateTime? lastSeen,
    bool? isOnline,
    List<String>? workspaceIds,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoURL: photoURL ?? this.photoURL,
      avatarId: avatarId ?? this.avatarId,
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
      workspaceIds: workspaceIds ?? this.workspaceIds,
    );
  }
}
