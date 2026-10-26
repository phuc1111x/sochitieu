import '../utils/format.dart';

class Expense {
  const Expense({
    this.id,
    required this.amount,
    required this.category,
    required this.date,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;

  /// Số tiền VNĐ, lưu số nguyên để cộng không bị sai số.
  final int amount;
  final String category;
  final DateTime date;
  final String note;
  final int createdAt;
  final int updatedAt;

  Expense copyWith({int? amount, String? category, DateTime? date, String? note, int? updatedAt}) =>
      Expense(
        id: id,
        amount: amount ?? this.amount,
        category: category ?? this.category,
        date: date ?? this.date,
        note: note ?? this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'amount': amount,
        'category': category,
        'date': dateKey(date),
        'note': note,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as int?,
        amount: (m['amount'] as num).toInt(),
        category: m['category'] as String,
        date: parseDateKey(m['date'] as String),
        note: (m['note'] as String?) ?? '',
        createdAt: (m['created_at'] as num).toInt(),
        updatedAt: (m['updated_at'] as num).toInt(),
      );
}

class DayTotal {
  const DayTotal({required this.date, required this.total, required this.count});

  final DateTime date;
  final int total;
  final int count;
}
