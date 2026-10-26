import '../utils/format.dart';

/// Loại giao dịch tiền không phải chi tiêu. Giá trị được lưu trong database, không được đổi.
class MoveKind {
  /// Thêm tiền vào một nguồn (lương, được cho...): `to_id`, số tiền dương.
  static const income = 'in';

  /// Chuyển tiền giữa hai nguồn: `from_id` → `to_id`, số tiền dương.
  static const move = 'move';

  /// Điều chỉnh số dư: `to_id`, số tiền có dấu (âm = giảm).
  static const adjust = 'adjust';
}

class MoneyMove {
  const MoneyMove({
    this.id,
    required this.kind,
    required this.amount,
    this.fromId,
    this.toId,
    required this.date,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String kind;
  final int amount;
  final int? fromId;
  final int? toId;
  final DateTime date;
  final String note;
  final int createdAt;
  final int updatedAt;

  /// Ảnh hưởng của giao dịch này lên số dư của nguồn [sourceId].
  int effectOn(int sourceId) {
    var d = 0;
    if (toId == sourceId) d += amount;
    if (fromId == sourceId) d -= amount;
    return d;
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'kind': kind,
        'amount': amount,
        'from_id': fromId,
        'to_id': toId,
        'date': dateKey(date),
        'note': note,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory MoneyMove.fromMap(Map<String, Object?> m) => MoneyMove(
        id: (m['id'] as num?)?.toInt(),
        kind: m['kind'] as String,
        amount: (m['amount'] as num).toInt(),
        fromId: (m['from_id'] as num?)?.toInt(),
        toId: (m['to_id'] as num?)?.toInt(),
        date: parseDateKey(m['date'] as String),
        note: (m['note'] as String?) ?? '',
        createdAt: (m['created_at'] as num).toInt(),
        updatedAt: (m['updated_at'] as num).toInt(),
      );
}

/// Một dòng trong sổ cái của một nguồn: chi tiêu, tiền vào, chuyển tiền hoặc điều chỉnh.
class LedgerEntry {
  const LedgerEntry({
    required this.kind,
    required this.refId,
    required this.sourceId,
    required this.amount,
    required this.date,
    required this.note,
    this.category,
    this.otherId,
    required this.createdAt,
  });

  static const expense = 'expense';

  /// `expense`, `in`, `move` hoặc `adjust`.
  final String kind;

  /// id của dòng gốc trong bảng `expenses` hoặc `moves`.
  final int refId;
  final int sourceId;

  /// Số tiền có dấu: dương = tiền vào nguồn, âm = tiền ra.
  final int amount;
  final DateTime date;
  final String note;
  final String? category;

  /// Nguồn bên kia của một lần chuyển tiền.
  final int? otherId;
  final int createdAt;

  factory LedgerEntry.fromMap(Map<String, Object?> m) => LedgerEntry(
        kind: m['kind'] as String,
        refId: (m['ref_id'] as num).toInt(),
        sourceId: (m['sid'] as num).toInt(),
        amount: (m['amt'] as num).toInt(),
        date: parseDateKey(m['date'] as String),
        note: (m['note'] as String?) ?? '',
        category: m['category'] as String?,
        otherId: (m['other_id'] as num?)?.toInt(),
        createdAt: (m['created_at'] as num).toInt(),
      );
}
