import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:outings_app/services/api_client.dart';

class DirectMessagesService {
  DirectMessagesService(this.api);
  final ApiClient api;

  /// POST /api/dm/send  body: { recipientId, text }
  Future<void> sendDirectMessage({
    required String recipientId,
    required String text,
  }) async {
    final r = await api.postJson('/api/dm/send', {
      'recipientId': recipientId,
      'text': text,
    });
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('HTTP ${r.statusCode}: ${r.body}');
    }
    // optionally parse: final j = jsonDecode(r.body);
  }
}
