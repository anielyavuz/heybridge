class WorkspaceModel {
  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final List<String> memberIds;
  final List<String> channelIds;
  final DateTime createdAt;
  final String? inviteCode;
  final String? password;

  WorkspaceModel({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    this.memberIds = const [],
    this.channelIds = const [],
    required this.createdAt,
    this.inviteCode,
    this.password,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'ownerId': ownerId,
      'memberIds': memberIds,
      'channelIds': channelIds,
      'createdAt': createdAt.toIso8601String(),
      'inviteCode': inviteCode,
      'password': password,
    };
  }

  factory WorkspaceModel.fromMap(Map<String, dynamic> map) {
    return WorkspaceModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'],
      ownerId: map['ownerId'] ?? '',
      memberIds: List<String>.from(map['memberIds'] ?? []),
      channelIds: List<String>.from(map['channelIds'] ?? []),
      createdAt: DateTime.parse(map['createdAt']),
      inviteCode: map['inviteCode'],
      password: map['password'],
    );
  }

  WorkspaceModel copyWith({
    String? id,
    String? name,
    String? description,
    String? ownerId,
    List<String>? memberIds,
    List<String>? channelIds,
    DateTime? createdAt,
    String? inviteCode,
    String? password,
  }) {
    return WorkspaceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ownerId: ownerId ?? this.ownerId,
      memberIds: memberIds ?? this.memberIds,
      channelIds: channelIds ?? this.channelIds,
      createdAt: createdAt ?? this.createdAt,
      inviteCode: inviteCode ?? this.inviteCode,
      password: password ?? this.password,
    );
  }
}
