// lib/features/outings/outing_share_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../services/api_client.dart';

/// Mirror backend enums (string values) for safety
class OutingVisibility {
  static const String PUBLIC = 'PUBLIC';
  static const String CONTACTS = 'CONTACTS';
  static const String INVITED = 'INVITED';
  static const String GROUPS = 'GROUPS';
}

class ParticipantRole {
  static const String OWNER = 'OWNER';
  static const String PARTICIPANT = 'PARTICIPANT';
  static const String VIEWER = 'VIEWER';
}

class InviteStatus {
  static const String PENDING = 'PENDING';
  static const String ACCEPTED = 'ACCEPTED';
  static const String DECLINED = 'DECLINED';
  static const String EXPIRED = 'EXPIRED';
}

/// Minimal list item for Plan tab views
class OutingLite {
  final String id;
  final String title;
  final DateTime? dateTimeStart;
  final bool isPublished;
  final String visibility;
  final bool allowParticipantEdits;
  final String createdById;
  final bool? showOrganizer; // optional in case backend includes it

  OutingLite({
    required this.id,
    required this.title,
    required this.isPublished,
    required this.visibility,
    required this.allowParticipantEdits,
    required this.createdById,
    this.dateTimeStart,
    this.showOrganizer,
  });

  factory OutingLite.fromJson(Map<String, dynamic> j) => OutingLite(
    id: j['id'] as String,
    title: (j['title'] ?? '') as String,
    isPublished: (j['isPublished'] ?? false) as bool,
    visibility: (j['visibility'] ?? OutingVisibility.INVITED) as String,
    allowParticipantEdits: (j['allowParticipantEdits'] ?? false) as bool,
    createdById: (j['createdById'] ?? '') as String,
    dateTimeStart: j['dateTimeStart'] != null
        ? DateTime.tryParse(j['dateTimeStart'].toString())
        : null,
    showOrganizer: j['showOrganizer'] as bool?,
  );
}

/// Invite DTO (used for incoming AND sent invites)
class OutingInvite {
  final String id;
  final String outingId;
  final String inviterId;
  final String? inviteeUserId;
  final String? inviteeContact; // email or phone
  final String role; // PARTICIPANT / VIEWER
  final String status; // PENDING / ACCEPTED / DECLINED / EXPIRED
  final String code;
  final DateTime? expiresAt;
  final DateTime createdAt;

  /// ⭐ May be provided by backend inside an 'outing' object; helps UI
  final String? outingTitle;

  OutingInvite({
    required this.id,
    required this.outingId,
    required this.inviterId,
    required this.role,
    required this.status,
    required this.code,
    required this.createdAt,
    this.inviteeUserId,
    this.inviteeContact,
    this.expiresAt,
    this.outingTitle,
  });

  factory OutingInvite.fromJson(Map<String, dynamic> j) {
    String? embeddedTitle;
    final o = (j['outing'] ?? {}) as Map<String, dynamic>;
    if (o.isNotEmpty) {
      embeddedTitle = (o['title'] ?? '') as String?;
    }
    return OutingInvite(
      id: j['id'] as String,
      outingId: j['outingId'] as String,
      inviterId: j['inviterId'] as String,
      inviteeUserId: j['inviteeUserId'] as String?,
      inviteeContact: j['inviteeContact'] as String?,
      role: (j['role'] ?? ParticipantRole.PARTICIPANT) as String,
      status: (j['status'] ?? InviteStatus.PENDING) as String,
      code: j['code'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      expiresAt: j['expiresAt'] != null
          ? DateTime.tryParse(j['expiresAt'].toString())
          : null,
      outingTitle: embeddedTitle,
    );
  }
}

/// Service that talks to the backend “publish / invites / lists” endpoints.
/// Requires ApiClient(authToken: <jwt>) so it sends Authorization header.
class OutingShareService {
  OutingShareService(this.api);
  final ApiClient api;

  // ---------- PUBLISH / VISIBILITY ----------

  Future<OutingLite> publishOuting({
    required String outingId,
    required String visibility,
    bool allowParticipantEdits = false,
    bool showOrganizer = true,
  }) async {
    final r = await api.patchJson('/api/outings/$outingId/publish', {
      'visibility': visibility,
      'allowParticipantEdits': allowParticipantEdits,
      'showOrganizer': showOrganizer,
    });
    _throwIfNotOk(r, {200});
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final data = (j['outing'] ?? j['data'] ?? j) as Map<String, dynamic>;
    return OutingLite.fromJson(data);
  }

  Future<OutingLite> updateOutingSettings({
    required String outingId,
    bool? allowParticipantEdits,
    bool? showOrganizer,
    String? visibility,
  }) async {
    final body = <String, dynamic>{};
    if (allowParticipantEdits != null)
      body['allowParticipantEdits'] = allowParticipantEdits;
    if (showOrganizer != null) body['showOrganizer'] = showOrganizer;
    if (visibility != null) body['visibility'] = visibility;

    final r = await api.patchJson('/api/outings/$outingId/publish', body);
    _throwIfNotOk(r, {200});
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final data = (j['outing'] ?? j['data'] ?? j) as Map<String, dynamic>;
    return OutingLite.fromJson(data);
  }

  // ---------- INVITES ----------

  Future<List<OutingInvite>> createInvites({
    required String outingId,
    List<String>? userIds,
    List<String>? contacts,
    String role = ParticipantRole.PARTICIPANT,
  }) async {
    final payload = <String, dynamic>{'role': role};
    if (userIds != null && userIds.isNotEmpty) payload['userIds'] = userIds;
    if (contacts != null && contacts.isNotEmpty) payload['contacts'] = contacts;

    final r = await api.postJson('/api/outings/$outingId/invites', payload);
    _throwIfNotOk(r, {200, 201});
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (j['invites'] ?? j['data'] ?? []) as List;
    return list
        .map((e) => OutingInvite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Accept / Decline (server route to be added separately if needed)
  Future<OutingInvite> _updateInviteAction(
    String inviteId,
    String action,
  ) async {
    final r = await api.patchJson('/api/outings/invites/$inviteId', {
      'action': action,
    });
    _throwIfNotOk(r, {200});
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final data = (j['invite'] ?? j['data'] ?? j) as Map<String, dynamic>;
    return OutingInvite.fromJson(data);
  }

  Future<OutingInvite> acceptInvite(String inviteId) =>
      _updateInviteAction(inviteId, 'ACCEPT');

  Future<OutingInvite> declineInvite(String inviteId) =>
      _updateInviteAction(inviteId, 'DECLINE');

  // ---------- LISTS FOR PLAN TAB ----------

  Future<List<OutingLite>> listMyOutings() async {
    final r = await api.get('/api/outings/mine');
    _throwIfNotOk(r, {200});
    final j = jsonDecode(r.body);
    final list = (j is List) ? j : (j['data'] as List? ?? const []);
    return list
        .map((e) => OutingLite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<OutingLite>> listSharedWithMe() async {
    final r = await api.get('/api/outings/shared-with-me');
    _throwIfNotOk(r, {200});
    final j = jsonDecode(r.body);
    final list = (j is List) ? j : (j['data'] as List? ?? const []);
    return list.map((e) {
      final map = e as Map<String, dynamic>;
      final o = (map['outing'] ?? map) as Map<String, dynamic>;
      return OutingLite.fromJson(o);
    }).toList();
  }

  /// Incoming invites for me (defaults to PENDING)
  Future<List<OutingInvite>> listMyInvites({
    String status = InviteStatus.PENDING,
  }) async {
    final r = await api.get('/api/outings/invites', query: {'status': status});
    _throwIfNotOk(r, {200});
    final j = jsonDecode(r.body);
    final list = (j is List) ? j : (j['data'] as List? ?? const []);
    return list
        .map((e) => OutingInvite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Sent invites across my outings (optionally filter by status or outingId)
  Future<List<OutingInvite>> listSentInvites({
    String? status,
    String? outingId,
  }) async {
    final query = <String, dynamic>{};
    if (status != null) query['status'] = status;
    if (outingId != null) query['outingId'] = outingId;

    final r = await api.get(
      '/api/outings/sent-invites',
      query: query.isEmpty ? null : query,
    );
    _throwIfNotOk(r, {200});
    final j = jsonDecode(r.body);
    final list = (j is List) ? j : (j['data'] as List? ?? const []);
    return list
        .map((e) => OutingInvite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// ⭐ Helper: fetch a single outing (lite) for title lookups
  Future<OutingLite> getOutingLiteById(String outingId) async {
    final r = await api.get('/api/outings/$outingId');
    _throwIfNotOk(r, {200});
    final body = jsonDecode(r.body);
    final map = body is Map<String, dynamic>
        ? (body['outing'] ?? body['data'] ?? body) as Map<String, dynamic>
        : <String, dynamic>{};
    return OutingLite.fromJson(map);
  }

  // ---------- Helpers ----------
  void _throwIfNotOk(http.Response r, Set<int> ok) {
    if (!ok.contains(r.statusCode)) {
      throw Exception('HTTP ${r.statusCode}: ${r.body}');
    }
  }
}
