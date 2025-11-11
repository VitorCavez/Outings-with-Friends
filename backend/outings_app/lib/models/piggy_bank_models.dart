// lib/models/piggy_bank_models.dart

class Contribution {
  final String id;
  final String userId;
  final String outingId;
  final int? amountCents; // new cents field
  final double? amount;   // legacy float, may be present
  final String? note;
  final DateTime? createdAt;

  Contribution({
    required this.id,
    required this.userId,
    required this.outingId,
    required this.amountCents,
    required this.amount,
    required this.note,
    required this.createdAt,
  });

  factory Contribution.fromJson(Map<String, dynamic> json) {
    return Contribution(
      id: json['id'] as String,
      userId: json['userId'] as String,
      outingId: json['outingId'] as String,
      amountCents: json['amountCents'] is int ? json['amountCents'] as int : null,
      amount: json['amount'] is num ? (json['amount'] as num).toDouble() : null,
      note: json['note'] as String?,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
    );
  }
}

class PiggyBankSummary {
  final int targetCents;
  final int raisedCents;
  final int progressPct; // 0..100
  final List<Contribution> contributions;

  PiggyBankSummary({
    required this.targetCents,
    required this.raisedCents,
    required this.progressPct,
    required this.contributions,
  });

  factory PiggyBankSummary.fromJson(Map<String, dynamic> json) {
    final list = (json['contributions'] as List<dynamic>? ?? [])
        .map((e) => Contribution.fromJson(e as Map<String, dynamic>))
        .toList();
    return PiggyBankSummary(
      targetCents: (json['targetCents'] as num).toInt(),
      raisedCents: (json['raisedCents'] as num).toInt(),
      progressPct: (json['progressPct'] as num).toInt(),
      contributions: list,
    );
  }

  String get targetEuro => _fmt(targetCents);
  String get raisedEuro => _fmt(raisedCents);

  static String _fmt(int cents) {
    final euros = cents / 100.0;
    return euros.toStringAsFixed(2);
  }
}
