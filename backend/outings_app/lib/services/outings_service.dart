import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/outing_details_model.dart';
import '../models/piggy_bank_models.dart';
import '../models/expense_models.dart';

class OutingsService {
  // Use the platform/env-aware base URL from AppConfig
  final String _base = AppConfig.apiBaseUrl;

  // Default JSON headers shared across requests
  Map<String, String> get _headers => AppConfig.defaultHeaders;

  bool _ok(int status) => status >= 200 && status < 300;

  // ---------------------------
  // Outing details
  // ---------------------------
  Future<OutingDetails> fetchOutingDetails(String id) async {
    final uri = Uri.parse('$_base/api/outings/$id');
    final res = await http.get(uri, headers: _headers);

    if (_ok(res.statusCode)) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return OutingDetails.fromJson(data);
    }
    throw Exception('GET /outings/$id failed (${res.statusCode}) ${res.body}');
  }

  // ---------------------------
  // PHASE 5: Piggy Bank
  // ---------------------------
  Future<PiggyBankSummary> getPiggyBankSummary(String outingId) async {
    final uri = Uri.parse('$_base/api/outings/$outingId/piggybank');
    final res = await http.get(uri, headers: _headers);

    if (_ok(res.statusCode)) {
      return PiggyBankSummary.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
    }
    throw Exception(
        'GET /outings/$outingId/piggybank failed (${res.statusCode}) ${res.body}');
  }

  Future<Contribution> addContribution({
    required String outingId,
    required String userId,
    required int amountCents,
    String? note,
  }) async {
    final uri =
        Uri.parse('$_base/api/outings/$outingId/piggybank/contributions');

    final body = jsonEncode({
      'userId': userId,
      'amountCents': amountCents,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });

    final res = await http.post(
      uri,
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (_ok(res.statusCode)) {
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final contrib = map['contribution'] as Map<String, dynamic>? ?? map;
      return Contribution.fromJson(contrib);
    }
    throw Exception(
        'POST /outings/$outingId/piggybank/contributions failed (${res.statusCode}) ${res.body}');
  }

  // ---------------------------
  // PHASE 5: Expenses
  // ---------------------------
  Future<ExpenseSummary> getExpenseSummary(String outingId) async {
    final uri = Uri.parse('$_base/api/outings/$outingId/expenses/summary');
    final res = await http.get(uri, headers: _headers);

    if (_ok(res.statusCode)) {
      return ExpenseSummary.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
    }
    throw Exception(
        'GET /outings/$outingId/expenses/summary failed (${res.statusCode}) ${res.body}');
  }

  Future<Expense> addExpense({
    required String outingId,
    required String payerId,
    required int amountCents,
    String? description,
    String? category,
  }) async {
    final uri = Uri.parse('$_base/api/outings/$outingId/expenses');

    final body = jsonEncode({
      'payerId': payerId,
      'amountCents': amountCents,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (category != null && category.trim().isNotEmpty)
        'category': category.trim(),
    });

    final res = await http.post(
      uri,
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (_ok(res.statusCode)) {
      return Expense.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw Exception(
        'POST /outings/$outingId/expenses failed (${res.statusCode}) ${res.body}');
  }
}
