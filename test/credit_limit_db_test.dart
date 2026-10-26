import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sochitieu/data/drive_backup.dart';
import 'package:sochitieu/data/expense_db.dart';
import 'package:sochitieu/models/expense.dart';
import 'package:sochitieu/models/money_move.dart';
import 'package:sochitieu/models/money_source.dart';
import 'package:sochitieu/utils/format.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Hạn mức thẻ tín dụng: chỉ lưu tổng hạn mức, số nợ vẫn tính từ sổ cái.
void main() {
  sqfliteFfiInit();

  late Directory dir;
  late ExpenseDb db;
  final today = dateOnly(DateTime.now());
  final now = DateTime.now().millisecondsSinceEpoch;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sochitieu_credit');
    db = ExpenseDb.forTesting(databaseFactoryFfi, p.join(dir.path, 'test.db'));
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  MoneySource card(String name, {int? limit}) =>
      MoneySource(name: name, type: 'credit', createdAt: now, creditLimit: limit);

  Future<MoneySource> byId(int id) async => (await db.sourceById(id))!;

  Future<List<MoneyMove>> adjustsOf(int id) async =>
      (await db.allMoves()).where((m) => m.kind == MoveKind.adjust && m.toId == id).toList();

  test('thẻ mới: lưu hạn mức 10.000.000, nợ ban đầu −2.350.000, còn được tiêu 7.650.000, đã dùng 24%', () async {
    final id = await db.insertSource(card('Thẻ VIB', limit: 10000000), openingBalance: 7650000 - 10000000);
    final s = await byId(id);
    expect(s.creditLimit, 10000000);
    expect(s.balance, -2350000);
    expect(s.hasLimit, isTrue);
    expect(s.available, 7650000);
    expect(s.usedPercent, 24);
    final adj = await adjustsOf(id);
    expect(adj.single.amount, -2350000);
    expect(adj.single.note, ExpenseDb.openingNote);
  });

  test('sửa chỉ hạn mức: không ghi dòng sổ cái, còn được tiêu tăng theo', () async {
    final id = await db.insertSource(card('Thẻ', limit: 10000000), openingBalance: -2350000);
    await db.updateSource((await byId(id)).copyWith(creditLimit: 15000000));
    final s = await byId(id);
    expect(s.creditLimit, 15000000);
    expect(s.balance, -2350000);
    expect(s.available, 12650000);
    expect(await adjustsOf(id), hasLength(1));
  });

  test('sửa hạn mức còn lại 7.650.000 → 7.000.000: dòng "Số dư thực tế" −650.000', () async {
    final id = await db.insertSource(card('Thẻ', limit: 10000000), openingBalance: -2350000);
    await db.updateSource(await byId(id), newBalance: 7000000 - 10000000);
    final s = await byId(id);
    expect(s.available, 7000000);
    final last = (await adjustsOf(id)).last;
    expect(last.amount, -650000);
    expect(last.note, ExpenseDb.realBalanceNote);
  });

  test('chi bằng thẻ và trả thẻ thay đổi số còn được tiêu, hạn mức giữ nguyên', () async {
    final cash = (await db.sourcesWithBalance()).single.id!;
    final id = await db.insertSource(card('Thẻ', limit: 10000000), openingBalance: -2350000);
    await db.insert(Expense(
        amount: 50000, category: 'food', date: today, sourceId: id, createdAt: now, updatedAt: now));
    expect((await byId(id)).available, 7600000);
    await db.insertMove(MoneyMove(
        kind: MoveKind.move, amount: 3000000, fromId: cash, toId: id, date: today, createdAt: now, updatedAt: now));
    final s = await byId(id);
    expect(s.available, 10600000);
    expect(s.creditLimit, 10000000);
    expect(s.usedPercent, 0);
  });

  test('đổi loại từ thẻ sang ngân hàng: xoá hạn mức (NULL)', () async {
    final id = await db.insertSource(card('Thẻ', limit: 10000000), openingBalance: -2350000);
    await db.updateSource((await byId(id)).copyWith(type: 'bank'));
    final s = await byId(id);
    expect(s.creditLimit, isNull);
    expect(s.hasLimit, isFalse);
    final raw = await (await db.db).query('sources', columns: ['credit_limit'], where: 'id = ?', whereArgs: [id]);
    expect(raw.single['credit_limit'], isNull);
  });

  test('% đã dùng: làm tròn, giới hạn 0–100', () {
    expect(usedPercentOf(2350000, 10000000), 24);
    expect(usedPercentOf(9000000, 10000000), 90);
    expect(usedPercentOf(-500000, 10000000), 0);
    expect(usedPercentOf(12000000, 10000000), 100);
    expect(usedPercentOf(100, 0), 0);
    final over = MoneySource(name: 'T', type: 'credit', createdAt: 0, balance: -10350000, creditLimit: 10000000);
    expect(over.available, -350000);
    expect(over.usedPercent, 100);
    // Thẻ cũ chưa có hạn mức.
    expect(MoneySource(name: 'T', type: 'credit', createdAt: 0, balance: -1).hasLimit, isFalse);
  });

  test('nâng cấp từ database v2: giữ dữ liệu, thẻ cũ chưa có hạn mức, nhập hạn mức được', () async {
    final path = p.join(dir.path, 'v2.db');
    final v2 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (d, _) async {
            await d.execute('CREATE TABLE expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, amount INTEGER NOT NULL, '
                "category TEXT NOT NULL, date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', "
                'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, source_id INTEGER)');
            await d.execute('CREATE INDEX idx_expenses_date ON expenses(date)');
            await d.execute('CREATE TABLE sources(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, '
                'type TEXT NOT NULL, is_default INTEGER NOT NULL DEFAULT 0, in_total INTEGER NOT NULL DEFAULT 1, '
                'archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)');
            await d.execute('CREATE TABLE moves(id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, '
                'amount INTEGER NOT NULL, from_id INTEGER, to_id INTEGER, date TEXT NOT NULL, '
                "note TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)");
            await d.execute('CREATE INDEX idx_moves_date ON moves(date)');
            await d.execute('CREATE INDEX idx_expenses_source ON expenses(source_id)');
          },
        ));
    await v2.insert('sources', {'id': 1, 'name': 'Tiền mặt', 'type': 'cash', 'is_default': 1, 'created_at': now});
    await v2.insert('sources', {'id': 2, 'name': 'Thẻ VIB', 'type': 'credit', 'created_at': now});
    await v2.insert('moves', {
      'kind': 'adjust',
      'amount': -2350000,
      'to_id': 2,
      'date': dateKey(today),
      'note': 'Số dư ban đầu',
      'created_at': now,
      'updated_at': now,
    });
    await v2.insert('expenses', {
      'amount': 45000,
      'category': 'food',
      'date': dateKey(today),
      'source_id': 2,
      'created_at': now,
      'updated_at': now,
    });
    await v2.close();

    final upgraded = ExpenseDb.forTesting(databaseFactoryFfi, path);
    final sources = await upgraded.sourcesWithBalance();
    expect(sources.map((s) => (s.name, s.type, s.balance, s.creditLimit)), [
      ('Tiền mặt', 'cash', 0, null),
      ('Thẻ VIB', 'credit', -2395000, null),
    ]);
    expect(sources.last.hasLimit, isFalse);
    expect((await upgraded.all()).single.sourceId, 2);

    await upgraded.updateSource(sources.last.copyWith(creditLimit: 10000000));
    final s = (await upgraded.sourceById(2))!;
    expect(s.creditLimit, 10000000);
    expect(s.available, 7605000);
    await upgraded.close();
  });

  test('nâng cấp từ database v1 lên v3: bảng nguồn có credit_limit, có "Tiền mặt", giữ khoản chi', () async {
    final path = p.join(dir.path, 'v1.db');
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute('CREATE TABLE expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, amount INTEGER NOT NULL, '
                "category TEXT NOT NULL, date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', "
                'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)');
            await d.execute('CREATE INDEX idx_expenses_date ON expenses(date)');
          },
        ));
    await v1.insert('expenses', {
      'amount': 45000,
      'category': 'food',
      'date': dateKey(today),
      'note': 'Phở',
      'created_at': now,
      'updated_at': now,
    });
    await v1.close();

    final upgraded = ExpenseDb.forTesting(databaseFactoryFfi, path);
    final raw = await upgraded.db;
    expect(await raw.getVersion(), 3);
    final columns = (await raw.rawQuery('PRAGMA table_info(sources)')).map((r) => r['name']);
    expect(columns, contains('credit_limit'));
    final sources = await upgraded.sourcesWithBalance();
    expect(sources.map((s) => (s.name, s.type, s.isDefault, s.creditLimit)), [('Tiền mặt', 'cash', true, null)]);
    final all = await upgraded.all();
    expect((all.single.amount, all.single.note, all.single.sourceId), (45000, 'Phở', null));

    // Thẻ mới tạo sau khi nâng cấp lưu được hạn mức.
    final cardId = await upgraded.insertSource(card('Thẻ', limit: 10000000), openingBalance: -1000000);
    expect((await upgraded.sourceById(cardId))!.creditLimit, 10000000);
    await upgraded.close();
  });

  test('sao lưu rồi khôi phục giữ hạn mức (file vẫn version 2)', () async {
    final id = await db.insertSource(card('Thẻ VIB', limit: 10000000), openingBalance: -2350000);
    final json = await DriveBackup.exportJson(db, DateTime(2026, 10, 26));
    expect(json['version'], 2);
    final rows = (json['sources'] as List).cast<Map<String, Object?>>();
    expect(rows.firstWhere((r) => r['id'] == id)['credit_limit'], 10000000);
    expect(rows.firstWhere((r) => r['type'] == 'cash')['credit_limit'], isNull);

    final dir2 = await Directory.systemTemp.createTemp('sochitieu_credit_restore');
    final other = ExpenseDb.forTesting(databaseFactoryFfi, p.join(dir2.path, 'r.db'));
    await DriveBackup.importJson(other, Map<String, dynamic>.from(json));
    final s = (await other.sourceById(id))!;
    expect(s.creditLimit, 10000000);
    expect(s.available, 7650000);
    await other.close();
    await dir2.delete(recursive: true);
  });

  test('khôi phục file v2 cũ không có credit_limit: thẻ có hạn mức NULL', () async {
    await DriveBackup.importJson(db, {
      'app': 'sochitieu',
      'version': 2,
      'expenses': <Object>[],
      'sources': [
        {'id': 1, 'name': 'Tiền mặt', 'type': 'cash', 'is_default': 1, 'in_total': 1, 'archived': 0, 'created_at': 1},
        {'id': 2, 'name': 'Thẻ', 'type': 'credit', 'is_default': 0, 'in_total': 1, 'archived': 0, 'created_at': 1},
      ],
      'moves': [
        {
          'id': 1,
          'kind': 'adjust',
          'amount': -200000,
          'from_id': null,
          'to_id': 2,
          'date': '2026-10-01',
          'note': '',
          'created_at': 1,
          'updated_at': 1,
        },
      ],
    });
    final s = (await db.sourceById(2))!;
    expect(s.creditLimit, isNull);
    expect(s.balance, -200000);
    expect(s.hasLimit, isFalse);
  });
}
