import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/expense.dart';
import '../models/money_move.dart';
import '../models/money_source.dart';
import '../utils/format.dart';

/// Lỗi nghiệp vụ có câu báo tiếng Việt để hiện cho người dùng.
class DataException implements Exception {
  const DataException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Database SQLite trên máy: nơi lưu chính của app, chạy hoàn toàn offline.
/// Mọi phép tính tổng và số dư đều làm bằng SQL (SUM / GROUP BY).
///
/// Số dư nguồn tiền không được lưu: luôn tính từ sổ cái [_ledgerSql], gồm một dòng có dấu
/// cho mỗi ảnh hưởng lên một nguồn (chi tiêu −, tiền vào +, chuyển tiền −/+, điều chỉnh ±).
class ExpenseDb {
  ExpenseDb._() : _factory = null, _path = null;

  /// Database riêng cho test (ví dụ `databaseFactoryFfi` + file tạm).
  @visibleForTesting
  ExpenseDb.forTesting(DatabaseFactory factory, String path) : _factory = factory, _path = path;

  static ExpenseDb _instance = ExpenseDb._();

  static ExpenseDb get instance => _instance;

  /// Thay database dùng chung bằng database của test (nhớ trả lại bản cũ khi xong).
  @visibleForTesting
  static set instance(ExpenseDb db) => _instance = db;

  static const _version = 3;
  static const defaultSourceName = 'Tiền mặt';
  static const openingNote = 'Số dư ban đầu';
  static const realBalanceNote = 'Số dư thực tế';

  final DatabaseFactory? _factory;
  final String? _path;

  /// Tăng mỗi khi dữ liệu thay đổi để các màn hình tự tải lại.
  final changes = ValueNotifier<int>(0);

  Future<Database>? _db;

  Future<Database> get db => _db ??= _open();

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final path = _path ?? p.join(await factory.getDatabasesPath(), 'sochitieu.db');
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE expenses(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              amount INTEGER NOT NULL,
              category TEXT NOT NULL,
              date TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT '',
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              source_id INTEGER
            )
          ''');
          await db.execute('CREATE INDEX idx_expenses_date ON expenses(date)');
          await _createMoneyTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            // Khoản chi cũ giữ source_id = NULL: không tự gán vào nguồn nào.
            await db.execute('ALTER TABLE expenses ADD COLUMN source_id INTEGER');
            await _createMoneyTables(db); // đã có sẵn cột credit_limit
          } else if (oldVersion < 3) {
            // v3: tổng hạn mức thẻ tín dụng. Thẻ cũ giữ NULL (chưa nhập hạn mức).
            await db.execute('ALTER TABLE sources ADD COLUMN credit_limit INTEGER');
          }
        },
      ),
    );
  }

  static Future<void> _createMoneyTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE sources(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        in_total INTEGER NOT NULL DEFAULT 1,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        credit_limit INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE moves(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        amount INTEGER NOT NULL,
        from_id INTEGER,
        to_id INTEGER,
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_moves_date ON moves(date)');
    await db.execute('CREATE INDEX idx_expenses_source ON expenses(source_id)');
    await _insertDefaultSource(db);
  }

  static Future<void> _insertDefaultSource(DatabaseExecutor db) => db.insert(
        'sources',
        MoneySource(
          name: defaultSourceName,
          type: 'cash',
          isDefault: true,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ).toMap(),
      );

  /// Đóng database (dùng trong test).
  @visibleForTesting
  Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null) await (await d).close();
  }

  void _notify() => changes.value++;

  // ---------------------------------------------------------------- Chi tiêu

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

  Future<Expense?> expenseById(int id) async {
    final rows = await (await db).query('expenses', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Expense.fromMap(rows.first);
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

  // ------------------------------------------------------------------ Sổ cái

  /// Một dòng có dấu cho mỗi ảnh hưởng lên một nguồn tiền.
  static const _ledgerSql = '''
    SELECT source_id AS sid, -amount AS amt, date, 'expense' AS kind, id AS ref_id,
           category, note, created_at, NULL AS other_id
      FROM expenses WHERE source_id IS NOT NULL
    UNION ALL
    SELECT to_id AS sid, amount AS amt, date, kind, id AS ref_id,
           NULL AS category, note, created_at, from_id AS other_id
      FROM moves WHERE to_id IS NOT NULL
    UNION ALL
    SELECT from_id AS sid, -amount AS amt, date, kind, id AS ref_id,
           NULL AS category, note, created_at, to_id AS other_id
      FROM moves WHERE from_id IS NOT NULL
  ''';

  static const _sourcesWithBalanceSql = '''
    SELECT s.*, COALESCE(b.balance, 0) AS balance
      FROM sources s
      LEFT JOIN (SELECT sid, SUM(amt) AS balance FROM ($_ledgerSql) GROUP BY sid) b ON b.sid = s.id
  ''';

  // ------------------------------------------------------------- Nguồn tiền

  /// Các nguồn tiền kèm số dư. Mặc định chỉ lấy nguồn chưa xoá.
  Future<List<MoneySource>> sourcesWithBalance({bool includeArchived = false}) async {
    final rows = await (await db).rawQuery(
      '$_sourcesWithBalanceSql ${includeArchived ? '' : 'WHERE s.archived = 0'} ORDER BY s.id',
    );
    return rows.map(MoneySource.fromMap).toList();
  }

  Future<MoneySource?> sourceById(int id) async {
    final rows = await (await db).rawQuery('$_sourcesWithBalanceSql WHERE s.id = ?', [id]);
    return rows.isEmpty ? null : MoneySource.fromMap(rows.first);
  }

  /// Tên của mọi nguồn (kể cả đã xoá) để hiện trong danh sách chi tiêu.
  Future<Map<int, String>> sourceNames() async {
    final rows = await (await db).query('sources', columns: ['id', 'name']);
    return {for (final r in rows) (r['id'] as num).toInt(): r['name'] as String};
  }

  /// "Tổng tiền hiện có": tổng số dư các nguồn chưa xoá và được tính vào tổng.
  Future<int> totalBalance() async {
    final rows = await (await db).rawQuery(
      'SELECT COALESCE(SUM(l.amt), 0) AS total FROM ($_ledgerSql) l '
      'JOIN sources s ON s.id = l.sid WHERE s.archived = 0 AND s.in_total = 1',
    );
    return (rows.first['total'] as num).toInt();
  }

  /// Tiền vào (dương) và tiền ra (âm) của một nguồn trong tháng chứa [month].
  /// Không tính dòng điều chỉnh (số dư ban đầu, sửa số dư); chuyển tiền thì có tính.
  Future<({int inflow, int outflow})> sourceMonthFlow(int sourceId, DateTime month) async {
    final rows = await (await db).rawQuery(
      'SELECT COALESCE(SUM(CASE WHEN amt > 0 THEN amt ELSE 0 END), 0) AS inflow, '
      'COALESCE(SUM(CASE WHEN amt < 0 THEN amt ELSE 0 END), 0) AS outflow '
      "FROM ($_ledgerSql) WHERE sid = ? AND kind != 'adjust' AND date >= ? AND date < ?",
      [sourceId, ..._monthRange(month)],
    );
    return (
      inflow: (rows.first['inflow'] as num).toInt(),
      outflow: (rows.first['outflow'] as num).toInt(),
    );
  }

  /// Lịch sử của một nguồn, mới nhất trước.
  Future<List<LedgerEntry>> sourceHistory(int sourceId) async {
    final rows = await (await db).rawQuery(
      'SELECT * FROM ($_ledgerSql) WHERE sid = ? ORDER BY date DESC, created_at DESC, ref_id DESC',
      [sourceId],
    );
    return rows.map(LedgerEntry.fromMap).toList();
  }

  static Future<int> _balanceOf(DatabaseExecutor txn, int id) async {
    final rows = await txn.rawQuery('SELECT COALESCE(SUM(amt), 0) AS b FROM ($_ledgerSql) WHERE sid = ?', [id]);
    return (rows.first['b'] as num).toInt();
  }

  /// Giữ đúng một nguồn mặc định trong các nguồn chưa xoá: ưu tiên [prefer], rồi nguồn
  /// mặc định cũ có id nhỏ nhất, nếu không có thì nguồn đầu tiên. Nguồn đã xoá không là mặc định.
  static Future<void> _normalizeDefault(DatabaseExecutor txn, {int? prefer}) async {
    final active = await txn.query(
      'sources',
      columns: ['id', 'is_default'],
      where: 'archived = 0',
      orderBy: 'id',
    );
    int? keep;
    if (prefer != null && active.any((r) => r['id'] == prefer)) keep = prefer;
    keep ??= active.where((r) => (r['is_default'] as num) != 0).map((r) => r['id'] as int).firstOrNull;
    keep ??= active.map((r) => r['id'] as int).firstOrNull;
    await txn.rawUpdate(
      'UPDATE sources SET is_default = CASE WHEN id = ? AND archived = 0 THEN 1 ELSE 0 END',
      [keep ?? -1],
    );
  }

  MoneyMove _adjust(int sourceId, int delta, String note) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return MoneyMove(
      kind: MoveKind.adjust,
      amount: delta,
      toId: sourceId,
      date: dateOnly(DateTime.now()),
      note: note,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Thêm nguồn tiền. [openingBalance] khác 0 thì ghi một dòng điều chỉnh "Số dư ban đầu"
  /// (thẻ tín dụng: truyền số âm của số nợ, tức −(hạn mức − hạn mức còn lại)). Tổng hạn mức của thẻ
  /// nằm trong `s.creditLimit`. Trả về id của nguồn mới.
  Future<int> insertSource(MoneySource s, {int openingBalance = 0}) async {
    final id = await (await db).transaction((txn) async {
      final id = await txn.insert('sources', s.toMap()..remove('id'));
      await _normalizeDefault(txn, prefer: s.isDefault ? id : null);
      if (openingBalance != 0) {
        await txn.insert('moves', _adjust(id, openingBalance, openingNote).toMap()..remove('id'));
      }
      return id;
    });
    _notify();
    return id;
  }

  /// Sửa nguồn tiền (kể cả tổng hạn mức `s.creditLimit`; đổi hạn mức không ghi dòng sổ cái nào).
  /// [newBalance] khác số dư hiện tại thì ghi một dòng điều chỉnh
  /// "Số dư thực tế" cho phần chênh lệch, đề ngày hôm nay.
  /// Luôn còn đúng một nguồn mặc định: tắt mặc định của nguồn mặc định duy nhất thì
  /// nguồn đầu tiên (có thể chính nó) được chọn lại.
  Future<void> updateSource(MoneySource s, {int? newBalance}) async {
    await (await db).transaction((txn) async {
      final current = await _balanceOf(txn, s.id!);
      await txn.update('sources', s.toMap(), where: 'id = ?', whereArgs: [s.id]);
      await _normalizeDefault(txn, prefer: s.isDefault ? s.id : null);
      final delta = newBalance == null ? 0 : newBalance - current;
      if (delta != 0) {
        await txn.insert('moves', _adjust(s.id!, delta, realBalanceNote).toMap()..remove('id'));
      }
    });
    _notify();
  }

  /// "Xoá" nguồn tiền: ẩn đi nhưng giữ lịch sử và các khoản chi đã ghi.
  /// Không cho xoá nguồn cuối cùng; nếu xoá nguồn mặc định thì nguồn đầu tiên còn lại thành mặc định.
  Future<void> archiveSource(int id) async {
    await (await db).transaction((txn) async {
      final others = await txn.query('sources', columns: ['id'], where: 'archived = 0 AND id != ?', whereArgs: [id]);
      if (others.isEmpty) throw const DataException('Cần giữ ít nhất một nguồn tiền');
      await txn.update('sources', {'archived': 1, 'is_default': 0}, where: 'id = ?', whereArgs: [id]);
      await _normalizeDefault(txn);
    });
    _notify();
  }

  // ---------------------------------------------- Thêm tiền / chuyển tiền

  Future<int> insertMove(MoneyMove m) async {
    _checkMove(m);
    final id = await (await db).insert('moves', m.toMap()..remove('id'));
    _notify();
    return id;
  }

  Future<void> updateMove(MoneyMove m) async {
    _checkMove(m);
    await (await db).update('moves', m.toMap(), where: 'id = ?', whereArgs: [m.id]);
    _notify();
  }

  Future<void> deleteMove(int id) async {
    await (await db).delete('moves', where: 'id = ?', whereArgs: [id]);
    _notify();
  }

  Future<MoneyMove?> moveById(int id) async {
    final rows = await (await db).query('moves', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : MoneyMove.fromMap(rows.first);
  }

  Future<List<MoneyMove>> allMoves() async {
    final rows = await (await db).query('moves', orderBy: 'id');
    return rows.map(MoneyMove.fromMap).toList();
  }

  void _checkMove(MoneyMove m) {
    if (m.kind == MoveKind.move && (m.fromId == null || m.toId == null || m.fromId == m.toId)) {
      throw const DataException('Chọn hai nguồn khác nhau để chuyển tiền');
    }
    if (m.kind != MoveKind.move && m.toId == null) {
      throw const DataException('Chọn nguồn nhận tiền');
    }
  }

  // ------------------------------------------------------ Sao lưu / khôi phục

  /// Đọc toàn bộ dữ liệu trong một transaction, để bản sao lưu không lẫn dữ liệu cũ và mới.
  Future<({List<Expense> expenses, List<MoneySource> sources, List<MoneyMove> moves})> snapshot() async {
    return (await db).transaction((txn) async {
      final expenses = await txn.query('expenses', orderBy: 'date, created_at');
      final sources = await txn.query('sources', orderBy: 'id');
      final moves = await txn.query('moves', orderBy: 'id');
      return (
        expenses: expenses.map(Expense.fromMap).toList(),
        sources: sources.map(MoneySource.fromMap).toList(),
        moves: moves.map(MoneyMove.fromMap).toList(),
      );
    });
  }

  /// Thay toàn bộ dữ liệu (dùng khi khôi phục từ bản sao lưu).
  /// Không còn nguồn nào chưa xoá (ví dụ bản sao lưu cũ) thì tạo lại "Tiền mặt" mặc định;
  /// sau đó luôn còn đúng một nguồn mặc định.
  Future<void> replaceAll(
    List<Expense> expenses, {
    List<MoneySource> sources = const [],
    List<MoneyMove> moves = const [],
  }) async {
    await (await db).transaction((txn) async {
      await txn.delete('expenses');
      await txn.delete('moves');
      await txn.delete('sources');
      final batch = txn.batch();
      for (final s in sources) {
        batch.insert('sources', s.toMap());
      }
      for (final m in moves) {
        batch.insert('moves', m.toMap());
      }
      for (final e in expenses) {
        batch.insert('expenses', e.toMap()..remove('id'));
      }
      await batch.commit(noResult: true);
      if (!sources.any((s) => !s.archived)) await _insertDefaultSource(txn);
      await _normalizeDefault(txn);
    });
    _notify();
  }
}
