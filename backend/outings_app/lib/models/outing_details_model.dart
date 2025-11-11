class OutingDetails {
  final String id;
  final String title;
  final String type; // maps from backend 'outingType'
  final double lat;  // maps from backend 'latitude'
  final double lng;  // maps from backend 'longitude'
  final String? subtitle;
  final String? description;
  final String? address;
  final String? imageUrl;
  final DateTime? startsAt;

  // Phase 5 - Piggy Bank
  final bool piggyBankEnabled;
  final int? piggyBankTargetCents;

  OutingDetails({
    required this.id,
    required this.title,
    required this.type,
    required this.lat,
    required this.lng,
    this.subtitle,
    this.description,
    this.address,
    this.imageUrl,
    this.startsAt,
    required this.piggyBankEnabled,
    required this.piggyBankTargetCents,
  });

  factory OutingDetails.fromJson(Map<String, dynamic> j) {
    // Handle both legacy and backend field names safely
    final type = (j['type'] ?? j['outingType'] ?? 'other').toString();
    final latRaw = j['lat'] ?? j['latitude'] ?? 0.0;
    final lngRaw = j['lng'] ?? j['longitude'] ?? 0.0;
    final startsRaw = j['startsAt'] ?? j['dateTimeStart'];

    // Piggy Bank target: prefer cents; fallback from legacy float if present
    int? targetCents;
    if (j['piggyBankTargetCents'] != null) {
      targetCents = (j['piggyBankTargetCents'] as num).toInt();
    } else if (j['piggyBankTarget'] != null) {
      targetCents = ((j['piggyBankTarget'] as num) * 100).round();
    }

    return OutingDetails(
      id: j['id'] as String,
      title: j['title'] as String,
      type: type,
      lat: (latRaw as num).toDouble(),
      lng: (lngRaw as num).toDouble(),
      subtitle: j['subtitle'] as String?,
      description: j['description'] as String?,
      address: j['address'] as String?,
      imageUrl: j['imageUrl'] as String?,
      startsAt: startsRaw != null ? DateTime.tryParse(startsRaw as String) : null,
      piggyBankEnabled: (j['piggyBankEnabled'] ?? false) == true,
      piggyBankTargetCents: targetCents,
    );
  }

  String? get piggyBankTargetEuro =>
      piggyBankTargetCents != null ? (piggyBankTargetCents! / 100.0).toStringAsFixed(2) : null;
}
