// lib/models/expense_models.dart

class Expense {
  final String id;
  final String outingId;
  final String payerId;
  final int amountCents;
  final String? description;
  final String? category;
  final DateTime? createdAt;

  Expense({
    required this.id,
    required this.outingId,
    required this.payerId,
    required this.amountCents,
    this.description,
    this.category,
    this.createdAt,
  });

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as String,
        outingId: j['outingId'] as String,
        payerId: j['payerId'] as String,
        amountCents: (j['amountCents'] as num).toInt(),
        description: j['description'] as String?,
        category: j['category'] as String?,
        createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'] as String) : null,
      );

  String get amountEuro => _fmt(amountCents);

  static String _fmt(int cents) => (cents / 100.0).toStringAsFixed(2);
}

class ExpenseBalance {
  final String userId;
  final int paidCents;
  final int owesCents;
  final int balanceCents; // positive = others owe them

  ExpenseBalance({
    required this.userId,
    required this.paidCents,
    required this.owesCents,
    required this.balanceCents,
  });

  factory ExpenseBalance.fromJson(Map<String, dynamic> j) => ExpenseBalance(
        userId: j['userId'] as String,
        paidCents: (j['paidCents'] as num).toInt(),
        owesCents: (j['owesCents'] as num).toInt(),
        balanceCents: (j['balanceCents'] as num).toInt(),
      );

  String get paidEuro => _fmt(paidCents);
  String get owesEuro => _fmt(owesCents);
  String get balanceEuro => _fmt(balanceCents);

  static String _fmt(int cents) => (cents / 100.0).toStringAsFixed(2);
}

class ExpenseSummary {
  final int totalCents;
  final List<String> participants;
  final int perPersonCents;
  final List<ExpenseBalance> balances;
  final List<Expense> expenses;

  ExpenseSummary({
    required this.totalCents,
    required this.participants,
    required this.perPersonCents,
    required this.balances,
    required this.expenses,
  });

  factory ExpenseSummary.fromJson(Map<String, dynamic> j) {
    final bl = (j['balances'] as List<dynamic>? ?? [])
        .map((e) => ExpenseBalance.fromJson(e as Map<String, dynamic>))
        .toList();
    final ex = (j['expenses'] as List<dynamic>? ?? [])
        .map((e) => Expense.fromJson(e as Map<String, dynamic>))
        .toList();

    return ExpenseSummary(
      totalCents: (j['totalCents'] as num).toInt(),
      participants: (j['participants'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      perPersonCents: (j['perPersonCents'] as num).toInt(),
      balances: bl,
      expenses: ex,
    );
  }

  String get totalEuro => _fmt(totalCents);
  String get perPersonEuro => _fmt(perPersonCents);

  static String _fmt(int cents) => (cents / 100.0).toStringAsFixed(2);
}
