class ChannelModel {
  final String id;
  final String name;
  final String workspaceId;
  final String? description;
  final bool isPrivate;
  final List<String> memberIds;
  final DateTime createdAt;
  final String createdBy;
  final Map<String, int> unreadCounts; // userId -> unread message count

  ChannelModel({
    required this.id,
    required this.name,
    required this.workspaceId,
    this.description,
    this.isPrivate = false,
    this.memberIds = const [],
    required this.createdAt,
    required this.createdBy,
    this.unreadCounts = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'workspaceId': workspaceId,
      'description': description,
      'isPrivate': isPrivate,
      'memberIds': memberIds,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
      'unreadCounts': unreadCounts,
    };
  }

  factory ChannelModel.fromMap(Map<String, dynamic> map) {
    return ChannelModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      workspaceId: map['workspaceId'] ?? '',
      description: map['description'],
      isPrivate: map['isPrivate'] ?? false,
      memberIds: List<String>.from(map['memberIds'] ?? []),
      createdAt: DateTime.parse(map['createdAt']),
      createdBy: map['createdBy'] ?? '',
      unreadCounts: Map<String, int>.from(
        (map['unreadCounts'] as Map<String, dynamic>?)?.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        ) ?? {},
      ),
    );
  }

  ChannelModel copyWith({
    String? id,
    String? name,
    String? workspaceId,
    String? description,
    bool? isPrivate,
    List<String>? memberIds,
    DateTime? createdAt,
    String? createdBy,
    Map<String, int>? unreadCounts,
  }) {
    return ChannelModel(
      id: id ?? this.id,
      name: name ?? this.name,
      workspaceId: workspaceId ?? this.workspaceId,
      description: description ?? this.description,
      isPrivate: isPrivate ?? this.isPrivate,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      unreadCounts: unreadCounts ?? this.unreadCounts,
    );
  }
}
