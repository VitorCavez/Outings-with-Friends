// lib/models/itinerary_item.dart
class ItineraryItem {
  final String id;
  final String title;
  final String? notes;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final DateTime? startTime;
  final DateTime? endTime;
  final int orderIndex;

  ItineraryItem({
    required this.id,
    required this.title,
    this.notes,
    this.locationName,
    this.latitude,
    this.longitude,
    this.startTime,
    this.endTime,
    required this.orderIndex,
  });

  factory ItineraryItem.fromJson(Map<String, dynamic> j) {
    return ItineraryItem(
      id: j['id'],
      title: j['title'],
      notes: j['notes'],
      locationName: j['locationName'],
      latitude: j['latitude'] != null ? (j['latitude'] as num).toDouble() : null,
      longitude: j['longitude'] != null ? (j['longitude'] as num).toDouble() : null,
      startTime: j['startTime'] != null ? DateTime.parse(j['startTime']) : null,
      endTime: j['endTime'] != null ? DateTime.parse(j['endTime']) : null,
      orderIndex: j['orderIndex'] ?? 0,
    );
  }
}
