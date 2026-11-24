import 'package:appwrite/models.dart';

class Event {
  final String id;
  final String title;
  final String description;
  final String location;
  final DateTime eventDate;
  final String creatorId;
  final String? imageId;
  final int maxParticipants;
  final int participantsCount;
  final int likesCount;
  final bool isActive;
  final DateTime? createdAt;
  final String category;

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.eventDate,
    required this.creatorId,
    this.imageId,
    required this.maxParticipants,
    required this.participantsCount,
    this.likesCount = 0,
    required this.isActive,
    this.createdAt,
    this.category = 'Diğer',
  });

  factory Event.fromDocument(Document doc) {
    final data = doc.data;
    return Event(
      id: doc.$id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      location: data['location'] ?? '',
      eventDate: DateTime.parse(data['eventDate']),
      creatorId: data['creatorId'] ?? data['ownerId'] ?? '',
      imageId: data['imageId'],
      maxParticipants: data['maxParticipants'] ?? 50,
      participantsCount: data['participantsCount'] ?? 0,
      likesCount: data['likesCount'] ?? 0,
      isActive: data['isActive'] ?? true,
      createdAt: DateTime.parse(doc.$createdAt),
      category: data['category'] ?? 'Diğer',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'location': location,
      'eventDate': eventDate.toIso8601String(),
      'creatorId': creatorId,
      'imageId': imageId,
      'maxParticipants': maxParticipants,
      'participantsCount': participantsCount,
      'likesCount': likesCount,
      'isActive': isActive,
      'category': category,
    };
  }

  factory Event.fromMap(Map<String, dynamic> map) {
    return Event(
      id: map['\$id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      location: map['location'] ?? '',
      eventDate: map['eventDate'] != null 
          ? DateTime.tryParse(map['eventDate'].toString()) ?? DateTime.now() 
          : DateTime.now(),
      creatorId: map['creatorId'] ?? map['ownerId'] ?? '',
      imageId: map['imageId'],
      maxParticipants: (map['maxParticipants'] as num?)?.toInt() ?? 50,
      participantsCount: (map['participantsCount'] as num?)?.toInt() ?? 0,
      likesCount: (map['likesCount'] as num?)?.toInt() ?? 0,
      isActive: map['isActive'] ?? true,
      createdAt: map['\$createdAt'] != null ? DateTime.tryParse(map['\$createdAt'].toString()) : null,
      category: map['category'] ?? 'Diğer',
    );
  }
}