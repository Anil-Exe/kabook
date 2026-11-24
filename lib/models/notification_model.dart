class NotificationModel {
  final String id;
  final String toUserId;
  final String fromUserId;
  final String type;
  final String eventId;
  final String status;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.toUserId,
    required this.fromUserId,
    required this.type,
    required this.eventId,
    required this.status,
    required this.createdAt,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['\$id'],
      toUserId: map['toUserId'],
      fromUserId: map['fromUserId'],
      type: map['type'],
      eventId: map['eventId'],
      status: map['status'],
      createdAt: DateTime.parse(map['\$createdAt']),
    );
  }
}
