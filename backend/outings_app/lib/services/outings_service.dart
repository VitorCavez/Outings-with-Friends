// lib/services/outings_service.dart
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

import '../services/api_client.dart';
import '../models/outing_details_model.dart';
import '../models/piggy_bank_models.dart';
import '../models/expense_models.dart';

class OutingsService {
  OutingsService(this.api);
  final ApiClient api;

  bool _ok(int s) => s >= 200 && s < 300;

  // ---- Outing details -------------------------------------------------
  Future<OutingDetails> fetchOutingDetails(String id) async {
    final uri = '/api/outings/$id';
    http.Response res;
    try {
      // Short, explicit timeout so the UI doesn’t hang indefinitely
      res = await api.get(uri).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw TimeoutException('GET $uri timed out');
    } catch (e) {
      rethrow; // let UI show the underlying socket/dns error
    }

    // Helpful diagnostics in logs
    // ignore: avoid_print
    print('GET $uri → ${res.statusCode} ${res.reasonPhrase}');

    if (_ok(res.statusCode)) {
      // some backends return {data: {...}}; others return the object directly
      final decoded = jsonDecode(res.body);
      final map = (decoded is Map<String, dynamic>)
          ? (decoded['data'] is Map<String, dynamic>
                ? decoded['data'] as Map<String, dynamic>
                : decoded as Map<String, dynamic>)
          : <String, dynamic>{};
      return OutingDetails.fromJson(map);
    }

    // bubble up body to the UI so you can see server errors quickly
    throw Exception('GET $uri failed (${res.statusCode}) ${res.body}');
  }

  // ---- Piggy Bank -----------------------------------------------------
  Future<PiggyBankSummary> getPiggyBankSummary(String outingId) async {
    final uri = '/api/outings/$outingId/piggybank';
    final res = await api.get(uri).timeout(const Duration(seconds: 10));
    if (_ok(res.statusCode)) {
      final decoded = jsonDecode(res.body);
      final map = (decoded is Map<String, dynamic>)
          ? (decoded['data'] is Map<String, dynamic>
                ? decoded['data'] as Map<String, dynamic>
                : decoded as Map<String, dynamic>)
          : <String, dynamic>{};
      return PiggyBankSummary.fromJson(map);
    }
    throw Exception('GET $uri failed (${res.statusCode}) ${res.body}');
  }

  Future<Contribution> addContribution({
    required String outingId,
    required String userId,
    required int amountCents,
    String? note,
  }) async {
    final uri = '/api/outings/$outingId/piggybank/contributions';
    final res = await api
        .postJson(uri, {
          'userId': userId,
          'amountCents': amountCents,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        })
        .timeout(const Duration(seconds: 10));

    if (_ok(res.statusCode)) {
      final decoded = jsonDecode(res.body);
      final map = (decoded is Map<String, dynamic>)
          ? decoded
          : <String, dynamic>{};
      final contrib = map['contribution'] is Map<String, dynamic>
          ? map['contribution'] as Map<String, dynamic>
          : map;
      return Contribution.fromJson(contrib);
    }
    throw Exception('POST $uri failed (${res.statusCode}) ${res.body}');
  }

  /// Delete a Piggy Bank contribution for an outing.
  /// Returns true on success, throws on non-2xx errors.
  Future<bool> deleteContribution({
    required String outingId,
    required String contributionId,
  }) async {
    final uri =
        '/api/outings/$outingId/piggybank/contributions/$contributionId';
    final res = await api.delete(uri).timeout(const Duration(seconds: 10));

    if (res.statusCode == 200 || res.statusCode == 204) {
      return true;
    }
    if (res.statusCode == 401) {
      throw Exception('DELETE $uri unauthorized (401) ${res.body}');
    }
    throw Exception('DELETE $uri failed (${res.statusCode}) ${res.body}');
  }

  // ---- Expenses -------------------------------------------------------
  Future<ExpenseSummary> getExpenseSummary(String outingId) async {
    final uri = '/api/outings/$outingId/expenses/summary';
    final res = await api.get(uri).timeout(const Duration(seconds: 10));
    if (_ok(res.statusCode)) {
      final decoded = jsonDecode(res.body);
      final map = (decoded is Map<String, dynamic>)
          ? (decoded['data'] is Map<String, dynamic>
                ? decoded['data'] as Map<String, dynamic>
                : decoded as Map<String, dynamic>)
          : <String, dynamic>{};
      return ExpenseSummary.fromJson(map);
    }
    throw Exception('GET $uri failed (${res.statusCode}) ${res.body}');
  }

  Future<Expense> addExpense({
    required String outingId,
    required String payerId,
    required int amountCents,
    String? description,
    String? category,
  }) async {
    final uri = '/api/outings/$outingId/expenses';
    final res = await api
        .postJson(uri, {
          'payerId': payerId,
          'amountCents': amountCents,
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
          if (category != null && category.trim().isNotEmpty)
            'category': category.trim(),
        })
        .timeout(const Duration(seconds: 10));

    if (_ok(res.statusCode)) {
      final decoded = jsonDecode(res.body);
      final map = (decoded is Map<String, dynamic>)
          ? (decoded['data'] is Map<String, dynamic>
                ? decoded['data'] as Map<String, dynamic>
                : decoded as Map<String, dynamic>)
          : <String, dynamic>{};
      return Expense.fromJson(map);
    }
    throw Exception('POST $uri failed (${res.statusCode}) ${res.body}');
  }
}
