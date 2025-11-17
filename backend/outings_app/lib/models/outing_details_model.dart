class OutingDetails {
  final String id;
  final String title;

  /// UI uses this directly in a Chip.
  /// Maps from backend 'outingType' as fallback.
  final String type;

  /// Location
  final double lat; // maps from backend 'latitude'
  final double lng; // maps from backend 'longitude'

  /// Optional details
  final String? subtitle;
  final String? description;
  final String? address;
  final String? imageUrl;
  final DateTime? startsAt;

  // ====== NEW fields expected by the screen ======
  /// Owner/creator of the outing.
  /// Accept common backend variants: createdById / organizerId / ownerId
  final String createdById;

  /// Visibility enum as a string (PUBLIC, CONTACTS, INVITED, GROUPS).
  /// Kept nullable so UI can default it if not present.
  final String? visibility;

  /// Whether participants (non-owner) can edit.
  final bool? allowParticipantEdits;

  /// Whether to show organizer in listing.
  final bool? showOrganizer;

  /// Whether organizer is hidden by privacy settings.
  final bool? organizerHidden;

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
    // new
    required this.createdById,
    this.visibility,
    this.allowParticipantEdits,
    this.showOrganizer,
    this.organizerHidden,
    // piggy bank
    required this.piggyBankEnabled,
    required this.piggyBankTargetCents,
  });

  factory OutingDetails.fromJson(Map<String, dynamic> j) {
    // ----- tolerant field mapping -----
    final type = (j['type'] ?? j['outingType'] ?? 'other').toString();

    final latRaw = j['lat'] ?? j['latitude'] ?? 0.0;
    final lngRaw = j['lng'] ?? j['longitude'] ?? 0.0;

    final startsRaw = j['startsAt'] ?? j['dateTimeStart'] ?? j['startAt'];

    // createdById can arrive under a few names
    final createdBy =
        j['createdById'] ?? j['organizerId'] ?? j['ownerId'] ?? j['userId'];

    // visibility is usually a string enum
    final visibility =
        (j['visibility'] ??
                j['publishVisibility'] ??
                j['privacy'] ??
                j['scope'])
            ?.toString();

    // allowParticipantEdits – accept several booleans that mean the same thing
    final allowEditsRaw =
        j['allowParticipantEdits'] ??
        j['participantsCanEdit'] ??
        j['participantEdits'] ??
        j['allowEdits'];
    final bool? allowEdits = (allowEditsRaw is bool)
        ? allowEditsRaw
        : _coerceBool(allowEditsRaw);

    // showOrganizer / organizerHidden
    final showOrganizerRaw = j['showOrganizer'];
    final bool? showOrganizer = (showOrganizerRaw is bool)
        ? showOrganizerRaw
        : _coerceBool(showOrganizerRaw);

    final organizerHiddenRaw = j['organizerHidden'];
    final bool? organizerHidden = (organizerHiddenRaw is bool)
        ? organizerHiddenRaw
        : _coerceBool(organizerHiddenRaw);

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
      startsAt: startsRaw != null
          ? DateTime.tryParse(startsRaw.toString())
          : null,
      // new fields
      createdById: (createdBy ?? '').toString(),
      visibility: visibility,
      allowParticipantEdits: allowEdits,
      showOrganizer: showOrganizer,
      organizerHidden: organizerHidden,
      // piggy bank
      piggyBankEnabled: (j['piggyBankEnabled'] ?? false) == true,
      piggyBankTargetCents: targetCents,
    );
  }

  String? get piggyBankTargetEuro => piggyBankTargetCents != null
      ? (piggyBankTargetCents! / 100.0).toStringAsFixed(2)
      : null;

  // small helper to coerce truthy/falsey strings or ints to bool?
  static bool? _coerceBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase().trim();
    if (s == 'true' || s == 'yes' || s == '1') return true;
    if (s == 'false' || s == 'no' || s == '0') return false;
    return null;
  }
}
