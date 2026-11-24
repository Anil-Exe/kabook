class Event {
  final String id;
  final String title;
  final String description;
  final DateTime eventDate;
  final String location;
  final DateTime createdAt;

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.eventDate,
    required this.location,
    required this.createdAt,
  });

  factory Event.fromMap(Map<String, dynamic> map) {
    return Event(
      id: map['\$id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      eventDate: DateTime.tryParse(map['eventDate'] ?? '') ?? DateTime.now(),
      location: map['location'] ?? '',
      createdAt: DateTime.tryParse(map['\$createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}