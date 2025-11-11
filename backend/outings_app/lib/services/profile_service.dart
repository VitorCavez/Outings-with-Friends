// lib/services/profile_service.dart
import 'dart:convert';
import 'package:intl/intl.dart';
import '../models/user_profile.dart';
import 'api_client.dart';

class ProfileService {
  ProfileService(this.api);
  final ApiClient api;

  // -----------------------------
  // Public profile (existing)
  // -----------------------------
  /// GET /api/users/:userId/profile
  Future<UserProfile> getPublicProfile(String userId) async {
    final r = await api.get('/api/users/$userId/profile');
    if (r.statusCode == 403) {
      throw Exception('PROFILE_PRIVATE');
    }
    if (r.statusCode != 200) {
      throw Exception('Get profile failed (${r.statusCode})');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    return UserProfile.fromJson(map['data'] as Map<String, dynamic>);
  }

  /// PUT /api/users/me/profile
  Future<UserProfile> updateMyProfile({
    String? fullName,
    String? bio,
    String? homeLocation,
    bool? isProfilePublic,
    List<String>? preferredOutingTypes,
    String? profilePhotoUrl,
    List<String>? badges,
  }) async {
    final body = <String, dynamic>{
      if (fullName != null) 'fullName': fullName,
      if (bio != null) 'bio': bio,
      if (homeLocation != null) 'homeLocation': homeLocation,
      if (isProfilePublic != null) 'isProfilePublic': isProfilePublic,
      if (preferredOutingTypes != null) 'preferredOutingTypes': preferredOutingTypes,
      if (profilePhotoUrl != null) 'profilePhotoUrl': profilePhotoUrl,
      if (badges != null) 'badges': badges,
    };
    final r = await api.putJson('/api/users/me/profile', body);
    if (r.statusCode != 200) {
      throw Exception('Update profile failed (${r.statusCode})');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    return UserProfile.fromJson(map['data'] as Map<String, dynamic>);
  }

  // -----------------------------
  // Favorites (existing)
  // -----------------------------
  /// GET /api/users/me/favorites
  /// Note: This returns a raw list (kept as-is for backward compat with your UI).
  Future<List<Map<String, dynamic>>> listMyFavorites() async {
    final r = await api.get('/api/users/me/favorites');
    if (r.statusCode != 200) {
      throw Exception('Get favorites failed (${r.statusCode})');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    return (map['data'] as List).cast<Map<String, dynamic>>();
  }

  // -----------------------------
  // NEW (Phase 6): History + Timeline
  // -----------------------------

  /// GET /api/users/:userId/history?role=all|host|guest&limit=&offset=
  Future<ProfileHistoryResponse> fetchHistory(
    String userId, {
    String role = 'all',
    int limit = 25,
    int offset = 0,
  }) async {
    final r = await api.get(
      '/api/users/$userId/history',
      query: {
        'role': role,
        'limit': limit,
        'offset': offset,
      },
    );
    if (r.statusCode != 200) {
      throw Exception('History failed (${r.statusCode})');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    return ProfileHistoryResponse.fromJson(map);
  }

  /// GET /api/users/:userId/timeline?from=&to=&limit=&offset=
  ///
  /// Tip: pass ISO strings like:
  ///   DateFormat("yyyy-MM-ddTHH:mm:ss.SSS'Z'").format(date.toUtc())
  Future<ProfileTimelineResponse> fetchTimeline(
    String userId, {
    String? fromIso,
    String? toIso,
    int limit = 50,
    int offset = 0,
  }) async {
    final r = await api.get(
      '/api/users/$userId/timeline',
      query: {
        if (fromIso != null) 'from': fromIso,
        if (toIso != null) 'to': toIso,
        'limit': limit,
        'offset': offset,
      },
    );
    if (r.statusCode != 200) {
      throw Exception('Timeline failed (${r.statusCode})');
    }
    final map = jsonDecode(r.body) as Map<String, dynamic>;
    return ProfileTimelineResponse.fromJson(map);
  }
}

// =============================
// DTOs for History
// =============================
class ProfileHistoryItem {
  ProfileHistoryItem({
    required this.id,
    required this.title,
    required this.outingType,
    this.locationName,
    this.address,
    this.dateTimeStart,
    this.dateTimeEnd,
    required this.createdById,
    this.groupId,
    this.role,
    this.rsvpStatus,
  });

  final String id;
  final String title;
  final String outingType;
  final String? locationName;
  final String? address;
  final DateTime? dateTimeStart;
  final DateTime? dateTimeEnd;
  final String createdById;
  final String? groupId;
  final String? role;        // host | guest
  final String? rsvpStatus;  // going | maybe | etc.

  factory ProfileHistoryItem.fromJson(Map<String, dynamic> j) {
    DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v.toString());
    return ProfileHistoryItem(
      id: j['id'] as String,
      title: j['title'] as String,
      outingType: j['outingType'] as String,
      locationName: j['locationName'] as String?,
      address: j['address'] as String?,
      dateTimeStart: _dt(j['dateTimeStart']),
      dateTimeEnd: _dt(j['dateTimeEnd']),
      createdById: j['createdById'] as String,
      groupId: j['groupId'] as String?,
      role: j['role'] as String?,
      rsvpStatus: j['rsvpStatus'] as String?,
    );
  }
}

class ProfileHistoryResponse {
  ProfileHistoryResponse({
    required this.ok,
    required this.total,
    required this.limit,
    required this.offset,
    required this.items,
  });

  final bool ok;
  final int total;
  final int limit;
  final int offset;
  final List<ProfileHistoryItem> items;

  factory ProfileHistoryResponse.fromJson(Map<String, dynamic> j) {
    final items = (j['data'] as List)
        .map((e) => ProfileHistoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return ProfileHistoryResponse(
      ok: j['ok'] == true,
      total: (j['total'] as int?) ?? items.length,
      limit: (j['limit'] as int?) ?? items.length,
      offset: (j['offset'] as int?) ?? 0,
      items: items,
    );
  }
}

// =============================
// DTOs for Timeline
// =============================
class LinkedOutingSnapshot {
  LinkedOutingSnapshot({
    required this.id,
    required this.title,
    required this.outingType,
    this.locationName,
    this.address,
    this.dateTimeStart,
    this.dateTimeEnd,
  });

  final String id;
  final String title;
  final String outingType;
  final String? locationName;
  final String? address;
  final DateTime? dateTimeStart;
  final DateTime? dateTimeEnd;

  factory LinkedOutingSnapshot.fromJson(Map<String, dynamic> j) {
    DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v.toString());
    return LinkedOutingSnapshot(
      id: j['id'] as String,
      title: j['title'] as String,
      outingType: j['outingType'] as String,
      locationName: j['locationName'] as String?,
      address: j['address'] as String?,
      dateTimeStart: _dt(j['dateTimeStart']),
      dateTimeEnd: _dt(j['dateTimeEnd']),
    );
  }
}

class TimelineEntry {
  TimelineEntry({
    required this.id,
    required this.title,
    this.description,
    required this.dateTimeStart,
    required this.dateTimeEnd,
    required this.isAllDay,
    required this.isReminder,
    this.linkedOutingId,
    this.groupId,
    this.createdAt,
    this.linkedOuting,
  });

  final String id;
  final String title;
  final String? description;
  final DateTime dateTimeStart;
  final DateTime dateTimeEnd;
  final bool isAllDay;
  final bool isReminder;
  final String? linkedOutingId;
  final String? groupId;
  final DateTime? createdAt;
  final LinkedOutingSnapshot? linkedOuting;

  factory TimelineEntry.fromJson(Map<String, dynamic> j) {
    DateTime _dt(dynamic v) => DateTime.parse(v.toString());
    return TimelineEntry(
      id: j['id'] as String,
      title: j['title'] as String,
      description: j['description'] as String?,
      dateTimeStart: _dt(j['dateTimeStart']),
      dateTimeEnd: _dt(j['dateTimeEnd']),
      isAllDay: j['isAllDay'] == true,
      isReminder: j['isReminder'] == true,
      linkedOutingId: j['linkedOutingId'] as String?,
      groupId: j['groupId'] as String?,
      createdAt: j['createdAt'] != null ? DateTime.parse(j['createdAt'].toString()) : null,
      linkedOuting: (j['linkedOuting'] == null)
          ? null
          : LinkedOutingSnapshot.fromJson(j['linkedOuting'] as Map<String, dynamic>),
    );
  }
}

class ProfileTimelineResponse {
  ProfileTimelineResponse({
    required this.ok,
    required this.total,
    required this.limit,
    required this.offset,
    required this.items,
  });

  final bool ok;
  final int total;
  final int limit;
  final int offset;
  final List<TimelineEntry> items;

  factory ProfileTimelineResponse.fromJson(Map<String, dynamic> j) {
    final items = (j['data'] as List)
        .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return ProfileTimelineResponse(
      ok: j['ok'] == true,
      total: (j['total'] as int?) ?? items.length,
      limit: (j['limit'] as int?) ?? items.length,
      offset: (j['offset'] as int?) ?? 0,
      items: items,
    );
  }
}

// (Optional helper) If you need quick UTC ISO formatting for 'from'/'to' params
String toUtcIso(DateTime dt) =>
    DateFormat("yyyy-MM-ddTHH:mm:ss.SSS'Z'").format(dt.toUtc());
