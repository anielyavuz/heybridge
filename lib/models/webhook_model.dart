class WebhookModel {
  final String id;
  final String name;
  final String channelId;
  final String workspaceId;
  final String createdBy;
  final DateTime createdAt;
  final bool isActive;

  WebhookModel({
    required this.id,
    required this.name,
    required this.channelId,
    required this.workspaceId,
    required this.createdBy,
    required this.createdAt,
    this.isActive = true,
  });

  /// Generate webhook URL
  String get webhookUrl =>
      'https://heybridgeservice-11767898554.europe-west1.run.app/api/webhook/$id';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'channelId': channelId,
      'workspaceId': workspaceId,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive,
    };
  }

  factory WebhookModel.fromMap(Map<String, dynamic> map) {
    return WebhookModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      channelId: map['channelId'] ?? '',
      workspaceId: map['workspaceId'] ?? '',
      createdBy: map['createdBy'] ?? '',
      createdAt: DateTime.parse(map['createdAt']),
      isActive: map['isActive'] ?? true,
    );
  }

  WebhookModel copyWith({
    String? id,
    String? name,
    String? channelId,
    String? workspaceId,
    String? createdBy,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return WebhookModel(
      id: id ?? this.id,
      name: name ?? this.name,
      channelId: channelId ?? this.channelId,
      workspaceId: workspaceId ?? this.workspaceId,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
