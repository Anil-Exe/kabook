import 'package:appwrite/models.dart';

class NotificationModel {
  final String id;
  final String toUserId;
  final String fromUserId;
  final String type;
  final String eventId;
  final String status;
  final String content;
  final bool isRead;
  final DateTime createdAt;
  final DateTime updatedAt;

  NotificationModel({
    required this.id,
    required this.toUserId,
    required this.fromUserId,
    required this.type,
    required this.eventId,
    required this.status,
    required this.content,
    required this.isRead,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory NotificationModel.fromDocument(Document doc) {
    final data = doc.data;
    return NotificationModel(
      id: doc.$id,
      toUserId: data['toUserId'] as String? ?? '',
      fromUserId: data['fromUserId'] as String? ?? '',
      type: data['type'] as String? ?? '',
      eventId: data['eventId'] as String? ?? '',
      status: data['status'] as String? ?? '',
      content: data['content'] as String? ?? '',
      isRead: data['isRead'] as bool? ?? false,
      createdAt: DateTime.parse(doc.$createdAt),
      updatedAt: DateTime.parse(doc.$updatedAt),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'toUserId': toUserId,
      'fromUserId': fromUserId,
      'type': type,
      'eventId': eventId,
      'status': status,
      'content': content,
      'isRead': isRead,
    };
  }

  NotificationModel copyWith({
    String? id,
    String? toUserId,
    String? fromUserId,
    String? type,
    String? eventId,
    String? status,
    String? content,
    bool? isRead,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      toUserId: toUserId ?? this.toUserId,
      fromUserId: fromUserId ?? this.fromUserId,
      type: type ?? this.type,
      eventId: eventId ?? this.eventId,
      status: status ?? this.status,
      content: content ?? this.content,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}