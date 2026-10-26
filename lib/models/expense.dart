import '../utils/format.dart';

class Expense {
  const Expense({
    this.id,
    required this.amount,
    required this.category,
    required this.date,
    this.note = '',
    this.sourceId,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;

  /// Số tiền VNĐ, lưu số nguyên để cộng không bị sai số.
  final int amount;
  final String category;
  final DateTime date;
  final String note;

  /// Nguồn tiền đã trả. NULL với các khoản chi cũ (trước khi có nguồn tiền): không trừ vào nguồn nào.
  final int? sourceId;
  final int createdAt;
  final int updatedAt;

  static const _keep = Object();

  /// [sourceId] để trống thì giữ nguyên; truyền `null` để bỏ nguồn tiền.
  Expense copyWith({
    int? amount,
    String? category,
    DateTime? date,
    String? note,
    Object? sourceId = _keep,
    int? updatedAt,
  }) =>
      Expense(
        id: id,
        amount: amount ?? this.amount,
        category: category ?? this.category,
        date: date ?? this.date,
        note: note ?? this.note,
        sourceId: identical(sourceId, _keep) ? this.sourceId : sourceId as int?,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'amount': amount,
        'category': category,
        'date': dateKey(date),
        'note': note,
        'source_id': sourceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as int?,
        amount: (m['amount'] as num).toInt(),
        category: m['category'] as String,
        date: parseDateKey(m['date'] as String),
        note: (m['note'] as String?) ?? '',
        sourceId: (m['source_id'] as num?)?.toInt(),
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
