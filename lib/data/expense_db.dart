import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/expense.dart';
import '../utils/format.dart';

/// Database SQLite trên máy: nơi lưu chính của app, chạy hoàn toàn offline.
/// Mọi phép tính tổng đều làm bằng SQL (SUM / GROUP BY).
class ExpenseDb {
  ExpenseDb._();

  static final instance = ExpenseDb._();

  /// Tăng mỗi khi dữ liệu thay đổi để các màn hình tự tải lại.
  final changes = ValueNotifier<int>(0);

  Future<Database>? _db;

  Future<Database> get db => _db ??= _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'sochitieu.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount INTEGER NOT NULL,
            category TEXT NOT NULL,
            date TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_expenses_date ON expenses(date)');
      },
    );
  }

  void _notify() => changes.value++;

  Future<void> insert(Expense e) async {
    await (await db).insert('expenses', e.toMap()..remove('id'));
    _notify();
  }

  Future<void> update(Expense e) async {
    await (await db).update('expenses', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
    _notify();
  }

  Future<void> delete(int id) async {
    await (await db).delete('expenses', where: 'id = ?', whereArgs: [id]);
    _notify();
  }

  Future<List<Expense>> byDay(DateTime day) async {
    final rows = await (await db).query(
      'expenses',
      where: 'date = ?',
      whereArgs: [dateKey(day)],
      orderBy: 'created_at DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  /// Khoảng [start, end) của tháng chứa [month], dạng khoá ngày.
  List<String> _monthRange(DateTime month) => [
        dateKey(DateTime(month.year, month.month, 1)),
        dateKey(DateTime(month.year, month.month + 1, 1)),
      ];

  Future<int> monthTotal(DateTime month) async {
    final rows = await (await db).rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM expenses WHERE date >= ? AND date < ?',
      _monthRange(month),
    );
    return (rows.first['total'] as num).toInt();
  }

  Future<List<DayTotal>> dayTotals(DateTime month) async {
    final rows = await (await db).rawQuery(
      'SELECT date, SUM(amount) AS total, COUNT(*) AS cnt FROM expenses '
      'WHERE date >= ? AND date < ? GROUP BY date ORDER BY date DESC',
      _monthRange(month),
    );
    return rows
        .map((r) => DayTotal(
              date: parseDateKey(r['date'] as String),
              total: (r['total'] as num).toInt(),
              count: (r['cnt'] as num).toInt(),
            ))
        .toList();
  }

  Future<Map<String, int>> categoryTotals(DateTime month) async {
    final rows = await (await db).rawQuery(
      'SELECT category, SUM(amount) AS total FROM expenses '
      'WHERE date >= ? AND date < ? GROUP BY category',
      _monthRange(month),
    );
    return {for (final r in rows) r['category'] as String: (r['total'] as num).toInt()};
  }

  Future<List<Expense>> all() async {
    final rows = await (await db).query('expenses', orderBy: 'date, created_at');
    return rows.map(Expense.fromMap).toList();
  }

  /// Thay toàn bộ dữ liệu (dùng khi khôi phục từ bản sao lưu).
  Future<void> replaceAll(List<Expense> expenses) async {
    await (await db).transaction((txn) async {
      await txn.delete('expenses');
      final batch = txn.batch();
      for (final e in expenses) {
        batch.insert('expenses', e.toMap()..remove('id'));
      }
      await batch.commit(noResult: true);
    });
    _notify();
  }
}
