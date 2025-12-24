// lib/services/group_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class GroupService {
  GroupService(this.api);
  final ApiClient api;

  // ---------------------------------------------------------------------------
  // Helpers: accept {data: ...}, {ok: true, data: ...}, arrays, or raw payloads
  // ---------------------------------------------------------------------------
  List<dynamic> _asList(dynamic body) {
    final dynamic json = body is String ? jsonDecode(body) : body;
    if (json is List) return json;
    if (json is Map && json['data'] is List) return (json['data'] as List);
    if (json is Map && json['items'] is List) return (json['items'] as List);
    return const [];
  }

  Map<String, dynamic> _asMap(dynamic body) {
    final dynamic json = body is String ? jsonDecode(body) : body;
    if (json is Map<String, dynamic>) return json;
    if (json is Map) return Map<String, dynamic>.from(json);
    if (json is String) return jsonDecode(json) as Map<String, dynamic>;
    return <String, dynamic>{};
  }

  Map<String, String>? _authHeaderOrNull() {
    final t = api.authToken;
    if (t == null || t.isEmpty) return null;
    return {'Authorization': 'Bearer $t'};
  }

  // ---------------------------------------------------------------------------
  // Invites (aligned with /api/groups router)
  // ---------------------------------------------------------------------------

  /// POST /api/groups/:groupId/invites
  /// body: { emails: string[], message?: string }
  Future<Map<String, dynamic>> createInvite(
    String groupId, {
    required List<String> emails,
    String? message,
  }) async {
    final r = await api.postJson('/api/groups/$groupId/invites', {
      'emails': emails,
      if (message != null) 'message': message,
    });
    if (r.statusCode != 201 && r.statusCode != 200) {
      throw Exception('Create invite failed (${r.statusCode})');
    }
    return _asMap(r.body);
  }

  /// GET /api/groups/:groupId/invites
  Future<List<dynamic>> listGroupInvites(String groupId) async {
    final r = await api.get('/api/groups/$groupId/invites');
    if (r.statusCode != 200) {
      throw Exception('List invites failed (${r.statusCode})');
    }
    return _asList(r.body);
  }

  /// GET /api/groups/me/invites
  Future<List<dynamic>> listMyInvites() async {
    final r = await api.get('/api/groups/me/invites');
    if (r.statusCode != 200) {
      throw Exception('List my invites failed (${r.statusCode})');
    }
    return _asList(r.body);
  }

  /// POST /api/groups/invites/:inviteId/accept
  Future<void> acceptInvite(String inviteId) async {
    final r = await api.postJson('/api/groups/invites/$inviteId/accept', {});
    if (r.statusCode != 200) {
      throw Exception('Accept invite failed (${r.statusCode})');
    }
  }

  /// POST /api/groups/invites/:inviteId/decline
  Future<void> declineInvite(String inviteId) async {
    final r = await api.postJson('/api/groups/invites/$inviteId/decline', {});
    if (r.statusCode != 200) {
      throw Exception('Decline invite failed (${r.statusCode})');
    }
  }

  /// POST /api/groups/invites/:inviteId/cancel
  Future<void> cancelInvite(String inviteId) async {
    final r = await api.postJson('/api/groups/invites/$inviteId/cancel', {});
    if (r.statusCode != 200) {
      throw Exception('Cancel invite failed (${r.statusCode})');
    }
  }

  // ---------------------------------------------------------------------------
  // Group profile
  // ---------------------------------------------------------------------------

  /// GET /api/groups/:groupId/profile
  Future<Map<String, dynamic>> getGroupProfile(String groupId) async {
    final r = await api.get('/api/groups/$groupId/profile');
    if (r.statusCode != 200) {
      throw Exception('Get group profile failed (${r.statusCode})');
    }
    final m = _asMap(r.body);
    return (m['data'] as Map<String, dynamic>? ?? m);
  }

  /// PUT /api/groups/:groupId/profile
  Future<Map<String, dynamic>> updateGroupProfile(
    String groupId, {
    String? name,
    String? description,
    String? groupImageUrl, // legacy
    String? coverImageUrl, // new
    String? groupVisibility, // legacy string visibility
    String? visibility, // enum: 'private' | 'public' | 'invite_only'
    double? defaultBudgetMin,
    double? defaultBudgetMax,
    List<String>? preferredOutingTypes,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (groupImageUrl != null) 'groupImageUrl': groupImageUrl,
      if (coverImageUrl != null) 'coverImageUrl': coverImageUrl,
      if (groupVisibility != null) 'groupVisibility': groupVisibility,
      if (visibility != null) 'visibility': visibility,
      if (defaultBudgetMin != null) 'defaultBudgetMin': defaultBudgetMin,
      if (defaultBudgetMax != null) 'defaultBudgetMax': defaultBudgetMax,
      if (preferredOutingTypes != null)
        'preferredOutingTypes': preferredOutingTypes,
    };
    final r = await api.putJson('/api/groups/$groupId/profile', body);
    if (r.statusCode != 200) {
      throw Exception('Update group profile failed (${r.statusCode})');
    }
    final m = _asMap(r.body);
    return (m['data'] as Map<String, dynamic>? ?? m);
  }

  // ---------------------------------------------------------------------------
  // Members & Roles
  // ---------------------------------------------------------------------------

  /// GET /api/groups/:groupId/members
  Future<List<dynamic>> listMembers(String groupId) async {
    final r = await api.get('/api/groups/$groupId/members');
    if (r.statusCode != 200) {
      throw Exception('List members failed (${r.statusCode})');
    }
    return _asList(r.body);
  }

  /// POST /api/groups/:groupId/members/:userId/promote
  Future<void> promoteMember(String groupId, String userId) async {
    final r = await api.postJson(
      '/api/groups/$groupId/members/$userId/promote',
      {},
    );
    if (r.statusCode != 200) {
      throw Exception('Promote failed (${r.statusCode})');
    }
  }

  /// POST /api/groups/:groupId/members/:userId/demote
  Future<void> demoteMember(String groupId, String userId) async {
    final r = await api.postJson(
      '/api/groups/$groupId/members/$userId/demote',
      {},
    );
    if (r.statusCode != 200) {
      throw Exception('Demote failed (${r.statusCode})');
    }
  }

  /// Back-compat: PUT /api/groups/:groupId/members/:userId/role
  Future<void> updateMemberRole(
    String groupId,
    String userId,
    String role,
  ) async {
    try {
      final r = await api.putJson('/api/groups/$groupId/members/$userId/role', {
        'role': role,
      });
      if (r.statusCode != 200) {
        throw Exception('Update role failed (${r.statusCode})');
      }
    } catch (_) {
      if (role.toLowerCase() == 'admin') {
        await promoteMember(groupId, userId);
      } else {
        await demoteMember(groupId, userId);
      }
    }
  }

  /// DELETE /api/groups/:groupId/members/:userId
  Future<void> removeMember(String groupId, String userId) async {
    final r = await api.delete('/api/groups/$groupId/members/$userId');
    if (r.statusCode != 200) {
      throw Exception('Remove member failed (${r.statusCode})');
    }
  }

  /// POST /api/groups/:groupId/leave
  ///
  /// Lets the current user leave a group. The backend may respond with
  /// specific error codes such as `LAST_ADMIN_CANNOT_LEAVE`; we surface
  /// that in the thrown exception message so the UI can show something
  /// friendly.
  Future<void> leaveGroup(String groupId) async {
    final r = await api.postJson('/api/groups/$groupId/leave', {});
    if (r.statusCode != 200) {
      try {
        final body = jsonDecode(r.body);
        if (body is Map && body['error'] != null) {
          throw Exception('Leave group failed: ${body['error']}');
        }
      } catch (_) {
        // fall through to generic error
      }
      throw Exception('Leave group failed (${r.statusCode})');
    }
  }

  /// Optional: POST /api/groups/:groupId/members/:userId/pin { pinned: bool }
  Future<void> setMemberPinned(
    String groupId,
    String userId,
    bool pinned,
  ) async {
    final r = await api.postJson('/api/groups/$groupId/members/$userId/pin', {
      'pinned': pinned,
    });
    if (r.statusCode != 200) {
      throw Exception('Pin/unpin failed (${r.statusCode})');
    }
  }

  // ---------------------------------------------------------------------------
  // Groups CRUD + discovery + joining
  // ---------------------------------------------------------------------------

  /// POST /api/groups
  Future<Map<String, dynamic>> createGroup({
    required String name,
    String? description,
    String? coverImageUrl,
    String visibility = 'private', // 'private' | 'public' | 'invite_only'
  }) async {
    final r = await api.postJson('/api/groups', {
      'name': name,
      if (description != null) 'description': description,
      if (coverImageUrl != null) 'coverImageUrl': coverImageUrl,
      'visibility': visibility,
    });
    if (r.statusCode != 201) {
      throw Exception('Create group failed (${r.statusCode})');
    }
    final m = _asMap(r.body);
    return (m['data'] as Map<String, dynamic>? ?? m);
  }

  /// PATCH /api/groups/:groupId
  Future<Map<String, dynamic>> updateGroup(
    String groupId, {
    String? name,
    String? description,
    String? coverImageUrl,
    String? visibility,
  }) async {
    final r = await api.patchJson('/api/groups/$groupId', {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (coverImageUrl != null) 'coverImageUrl': coverImageUrl,
      if (visibility != null) 'visibility': visibility,
    });
    if (r.statusCode != 200) {
      throw Exception('Update group failed (${r.statusCode})');
    }
    final m = _asMap(r.body);
    return (m['data'] as Map<String, dynamic>? ?? m);
  }

  /// GET /api/groups/discover?q&visibility&limit&offset
  Future<Map<String, dynamic>> discover({
    String q = '',
    String visibility = 'public',
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse('${api.baseUrl}/api/groups/discover').replace(
      queryParameters: {
        if (q.isNotEmpty) 'q': q,
        'visibility': visibility,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final r = await http.get(uri, headers: _authHeaderOrNull());
    if (r.statusCode != 200) {
      throw Exception('Discover groups failed (${r.statusCode})');
    }
    return _asMap(r.body);
  }

  /// GET /api/groups/:id
  Future<Map<String, dynamic>> getGroup(String id) async {
    final r = await api.get('/api/groups/$id');
    if (r.statusCode != 200) {
      throw Exception('Get group failed (${r.statusCode})');
    }
    final m = _asMap(r.body);
    return (m['data'] as Map<String, dynamic>? ?? m);
  }

  /// GET /api/groups/mine
  Future<List<dynamic>> listMyGroups() async {
    final r = await api.get('/api/groups/mine');
    if (r.statusCode != 200) {
      throw Exception('List my groups failed (${r.statusCode})');
    }
    return _asList(r.body);
  }

  /// POST /api/groups/:groupId/join
  Future<void> joinGroup(String groupId, {String? userId}) async {
    final r = await api.postJson('/api/groups/$groupId/join', {
      if (userId != null) 'userId': userId,
    });
    // 201 = joined, 409 = already a member — treat both as success
    if (r.statusCode != 201 && r.statusCode != 409) {
      throw Exception('Join failed (${r.statusCode})');
    }
  }

  /// DELETE /api/groups/:id
  Future<void> deleteGroup(String id) async {
    final r = await api.delete('/api/groups/$id');
    if (r.statusCode != 200) {
      throw Exception('Delete group failed (${r.statusCode})');
    }
  }
}
