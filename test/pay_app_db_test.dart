import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sochitieu/data/drive_backup.dart';
import 'package:sochitieu/data/expense_db.dart';
import 'package:sochitieu/models/money_source.dart';
import 'package:sochitieu/utils/format.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ứng dụng thanh toán gắn với nguồn tiền: cột `sources.app_package` (DB v4).
void main() {
  sqfliteFfiInit();

  const momo = 'com.mservice.momotransfer';
  late Directory dir;
  late ExpenseDb db;
  final today = dateOnly(DateTime.now());
  final now = DateTime.now().millisecondsSinceEpoch;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sochitieu_payapp');
    db = ExpenseDb.forTesting(databaseFactoryFfi, p.join(dir.path, 'test.db'));
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  MoneySource wallet({String? app}) => MoneySource(name: 'Ví MoMo', type: 'ewallet', createdAt: now, appPackage: app);

  Future<Object?> rawApp(ExpenseDb d, int id) async =>
      (await (await d.db).query('sources', columns: ['app_package'], where: 'id = ?', whereArgs: [id]))
          .single['app_package'];

  test('gắn ứng dụng khi thêm nguồn, đổi và bỏ liên kết khi sửa', () async {
    final id = await db.insertSource(wallet(app: momo), openingBalance: 300000);
    expect((await db.sourceById(id))!.appPackage, momo);

    await db.updateSource((await db.sourceById(id))!.copyWith(name: 'MoMo'));
    expect((await db.sourceById(id))!.appPackage, momo, reason: 'copyWith không truyền thì giữ nguyên');

    await db.updateSource((await db.sourceById(id))!.copyWith(appPackage: null));
    expect((await db.sourceById(id))!.appPackage, isNull);
    expect(await rawApp(db, id), isNull);
    expect((await db.sourceById(id))!.balance, 300000, reason: 'đổi liên kết không ghi sổ cái');
  });

  test('tiền mặt không gắn ứng dụng: đổi loại sang tiền mặt thì xoá liên kết', () async {
    expect(wallet(app: momo).copyWith(type: 'cash').toMap()['app_package'], isNull);
    expect(wallet(app: momo).copyWith(type: 'bank').toMap()['app_package'], momo);

    final id = await db.insertSource(wallet(app: momo));
    await db.updateSource((await db.sourceById(id))!.copyWith(type: 'cash'));
    expect(await rawApp(db, id), isNull);
  });

  test('tên gói rỗng đọc ra là null', () {
    expect(MoneySource.fromMap({'name': 'A', 'type': 'bank', 'app_package': ''}).appPackage, isNull);
    expect(MoneySource.fromMap({'name': 'A', 'type': 'bank'}).appPackage, isNull);
  });

  test('nâng cấp từ database v3: giữ dữ liệu, nguồn cũ chưa gắn ứng dụng, gắn được sau đó', () async {
    final path = p.join(dir.path, 'v3.db');
    final v3 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (d, _) async {
            await d.execute('CREATE TABLE expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, amount INTEGER NOT NULL, '
                "category TEXT NOT NULL, date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', "
                'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, source_id INTEGER)');
            await d.execute('CREATE INDEX idx_expenses_date ON expenses(date)');
            await d.execute('CREATE TABLE sources(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, '
                'type TEXT NOT NULL, is_default INTEGER NOT NULL DEFAULT 0, in_total INTEGER NOT NULL DEFAULT 1, '
                'archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, credit_limit INTEGER)');
            await d.execute('CREATE TABLE moves(id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, '
                'amount INTEGER NOT NULL, from_id INTEGER, to_id INTEGER, date TEXT NOT NULL, '
                "note TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)");
            await d.execute('CREATE INDEX idx_moves_date ON moves(date)');
            await d.execute('CREATE INDEX idx_expenses_source ON expenses(source_id)');
          },
        ));
    await v3.insert('sources', {'id': 1, 'name': 'Tiền mặt', 'type': 'cash', 'is_default': 1, 'created_at': now});
    await v3.insert('sources',
        {'id': 2, 'name': 'Thẻ VIB', 'type': 'credit', 'created_at': now, 'credit_limit': 10000000});
    await v3.insert('sources', {'id': 3, 'name': 'Ví MoMo', 'type': 'ewallet', 'created_at': now});
    await v3.insert('moves', {
      'kind': 'adjust',
      'amount': 300000,
      'to_id': 3,
      'date': dateKey(today),
      'note': 'Số dư ban đầu',
      'created_at': now,
      'updated_at': now,
    });
    await v3.insert('expenses', {
      'amount': 45000,
      'category': 'food',
      'date': dateKey(today),
      'source_id': 3,
      'created_at': now,
      'updated_at': now,
    });
    await v3.close();

    final upgraded = ExpenseDb.forTesting(databaseFactoryFfi, path);
    final raw = await upgraded.db;
    expect(await raw.getVersion(), 4);
    final columns = (await raw.rawQuery('PRAGMA table_info(sources)')).map((r) => r['name']);
    expect(columns, containsAll(['credit_limit', 'app_package']));
    final sources = await upgraded.sourcesWithBalance();
    expect(sources.map((s) => (s.name, s.balance, s.creditLimit, s.appPackage)), [
      ('Tiền mặt', 0, null, null),
      ('Thẻ VIB', 0, 10000000, null),
      ('Ví MoMo', 255000, null, null),
    ]);
    expect((await upgraded.all()).single.sourceId, 3);

    await upgraded.updateSource(sources.last.copyWith(appPackage: momo));
    expect((await upgraded.sourceById(3))!.appPackage, momo);
    await upgraded.close();
  });

  test('nâng cấp từ database v2 lên v4: có cả credit_limit và app_package', () async {
    final path = p.join(dir.path, 'v2.db');
    final v2 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (d, _) async {
            await d.execute('CREATE TABLE expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, amount INTEGER NOT NULL, '
                "category TEXT NOT NULL, date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', "
                'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, source_id INTEGER)');
            await d.execute('CREATE TABLE sources(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, '
                'type TEXT NOT NULL, is_default INTEGER NOT NULL DEFAULT 0, in_total INTEGER NOT NULL DEFAULT 1, '
                'archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)');
            await d.execute('CREATE TABLE moves(id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, '
                'amount INTEGER NOT NULL, from_id INTEGER, to_id INTEGER, date TEXT NOT NULL, '
                "note TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)");
          },
        ));
    await v2.insert('sources', {'id': 1, 'name': 'Tiền mặt', 'type': 'cash', 'is_default': 1, 'created_at': now});
    await v2.close();

    final upgraded = ExpenseDb.forTesting(databaseFactoryFfi, path);
    final raw = await upgraded.db;
    expect(await raw.getVersion(), 4);
    final columns = (await raw.rawQuery('PRAGMA table_info(sources)')).map((r) => r['name']);
    expect(columns, containsAll(['credit_limit', 'app_package']));
    expect((await upgraded.sourcesWithBalance()).single.name, 'Tiền mặt');
    await upgraded.close();
  });

  test('sao lưu rồi khôi phục giữ ứng dụng thanh toán (file vẫn version 2)', () async {
    final id = await db.insertSource(wallet(app: momo), openingBalance: 300000);
    final json = await DriveBackup.exportJson(db, DateTime(2026, 10, 26));
    expect(json['version'], 2);
    final rows = (json['sources'] as List).cast<Map<String, Object?>>();
    expect(rows.firstWhere((r) => r['id'] == id)['app_package'], momo);
    expect(rows.firstWhere((r) => r['type'] == 'cash')['app_package'], isNull);

    final dir2 = await Directory.systemTemp.createTemp('sochitieu_payapp_restore');
    final other = ExpenseDb.forTesting(databaseFactoryFfi, p.join(dir2.path, 'r.db'));
    await DriveBackup.importJson(other, Map<String, dynamic>.from(json));
    final s = (await other.sourceById(id))!;
    expect(s.appPackage, momo);
    expect(s.balance, 300000);
    await other.close();
    await dir2.delete(recursive: true);
  });

  test('khôi phục file v2 cũ không có app_package: nguồn chưa gắn ứng dụng', () async {
    await DriveBackup.importJson(db, {
      'app': 'sochitieu',
      'version': 2,
      'expenses': <Object>[],
      'sources': [
        {'id': 1, 'name': 'Tiền mặt', 'type': 'cash', 'is_default': 1, 'in_total': 1, 'archived': 0, 'created_at': 1},
        {'id': 2, 'name': 'Ví MoMo', 'type': 'ewallet', 'is_default': 0, 'in_total': 1, 'archived': 0, 'created_at': 1},
      ],
      'moves': <Object>[],
    });
    expect((await db.sourceById(2))!.appPackage, isNull);
  });
}
