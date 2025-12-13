class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? photoURL;
  final DateTime createdAt;
  final DateTime lastSeen;
  final bool isOnline;
  final List<String> workspaceIds;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoURL,
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
      'createdAt': createdAt.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
      'isOnline': isOnline,
      'workspaceIds': workspaceIds,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      displayName: map['displayName'] ?? '',
      photoURL: map['photoURL'],
      createdAt: DateTime.parse(map['createdAt']),
      lastSeen: DateTime.parse(map['lastSeen']),
      isOnline: map['isOnline'] ?? false,
      workspaceIds: List<String>.from(map['workspaceIds'] ?? []),
    );
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoURL,
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
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
      workspaceIds: workspaceIds ?? this.workspaceIds,
    );
  }
}
