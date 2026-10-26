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

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late ExpenseDb db;
  final today = dateOnly(DateTime.now());
  final now = DateTime.now().millisecondsSinceEpoch;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sochitieu_test');
    db = ExpenseDb.forTesting(databaseFactoryFfi, p.join(dir.path, 'test.db'));
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Expense expense(int amount, {int? sourceId, DateTime? date, String category = 'food'}) => Expense(
        amount: amount,
        category: category,
        date: date ?? today,
        sourceId: sourceId,
        createdAt: now,
        updatedAt: now,
      );

  MoneyMove move(String kind, int amount, {int? from, int? to, DateTime? date, String note = ''}) => MoneyMove(
        kind: kind,
        amount: amount,
        fromId: from,
        toId: to,
        date: date ?? today,
        note: note,
        createdAt: now,
        updatedAt: now,
      );

  MoneySource source(String name, String type, {bool isDefault = false, bool inTotal = true}) =>
      MoneySource(name: name, type: type, isDefault: isDefault, inTotal: inTotal, createdAt: now);

  Future<int> balance(int id) async => (await db.sourceById(id))!.balance;

  Future<int> cashId() async => (await db.sourcesWithBalance()).single.id!;

  test('cài mới: có sẵn một nguồn "Tiền mặt" mặc định, số dư 0', () async {
    final sources = await db.sourcesWithBalance();
    expect(sources, hasLength(1));
    expect(sources.single.name, 'Tiền mặt');
    expect(sources.single.type, 'cash');
    expect(sources.single.isDefault, isTrue);
    expect(sources.single.balance, 0);
  });

  test('nâng cấp từ database v1: thêm bảng, khoản chi cũ không thuộc nguồn nào', () async {
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
    final sources = await upgraded.sourcesWithBalance();
    expect(sources.map((s) => (s.name, s.type, s.isDefault, s.balance)), [('Tiền mặt', 'cash', true, 0)]);
    final all = await upgraded.all();
    expect(all.single.amount, 45000);
    expect(all.single.sourceId, isNull);
    expect(await upgraded.totalBalance(), 0);
    expect(await upgraded.monthTotal(today), 45000);
    expect(await upgraded.sourceHistory(sources.single.id!), isEmpty);
    await upgraded.close();
  });

  test('chi tiêu trừ vào nguồn đã chọn', () async {
    final cash = await cashId();
    await db.updateSource((await db.sourceById(cash))!, newBalance: 1250000);
    expect(await balance(cash), 1250000);

    await db.insert(expense(45000, sourceId: cash));
    expect(await balance(cash), 1205000);
    expect(formatBalance(await balance(cash)), '1.205.000 đ');

    // Khoản chi không có nguồn không ảnh hưởng số dư.
    await db.insert(expense(30000));
    expect(await balance(cash), 1205000);
  });

  test('thẻ tín dụng: số nợ ban đầu là số dư âm, chi bằng thẻ làm âm thêm', () async {
    final card = await db.insertSource(source('Thẻ tín dụng VIB', 'credit'), openingBalance: -2350000);
    expect(await balance(card), -2350000);
    expect(formatBalance(await balance(card)), '−2.350.000 đ');

    final history = await db.sourceHistory(card);
    expect(history.single.kind, MoveKind.adjust);
    expect(history.single.note, 'Số dư ban đầu');

    await db.insert(expense(120000, sourceId: card, category: 'fun'));
    expect(await balance(card), -2470000);
  });

  test('chuyển tiền: hai nguồn đổi số dư, tổng không đổi, không tính là chi tiêu', () async {
    final cash = await cashId();
    await db.updateSource((await db.sourceById(cash))!, newBalance: 1250000);
    final vcb = await db.insertSource(source('Vietcombank', 'bank'), openingBalance: 18400000);
    final totalBefore = await db.totalBalance();

    await db.insertMove(move(MoveKind.move, 1000000, from: vcb, to: cash, note: 'Rút tiền'));
    expect(await balance(vcb), 17400000);
    expect(await balance(cash), 2250000);
    expect(await db.totalBalance(), totalBefore);
    expect(await db.monthTotal(today), 0);

    expect(
      () => db.insertMove(move(MoveKind.move, 1000, from: vcb, to: vcb)),
      throwsA(isA<DataException>()),
    );
  });

  test('sửa và xoá giao dịch tính lại số dư', () async {
    final cash = await cashId();
    final id = await db.insertMove(move(MoveKind.income, 500000, to: cash));
    expect(await balance(cash), 500000);

    final m = (await db.moveById(id))!;
    await db.updateMove(MoneyMove(
      id: m.id,
      kind: m.kind,
      amount: 700000,
      toId: cash,
      date: m.date,
      createdAt: m.createdAt,
      updatedAt: now,
    ));
    expect(await balance(cash), 700000);

    await db.deleteMove(id);
    expect(await balance(cash), 0);
  });

  test('sửa số dư: chỉ ghi dòng "Số dư thực tế" khi có chênh lệch', () async {
    final cash = await cashId();
    await db.insertMove(move(MoveKind.income, 1000000, to: cash));
    final s = (await db.sourceById(cash))!;

    await db.updateSource(s.copyWith(name: 'Ví'));
    await db.updateSource(s, newBalance: 1000000);
    expect((await db.sourceHistory(cash)).where((e) => e.kind == MoveKind.adjust), isEmpty);

    await db.updateSource(s, newBalance: 968000);
    final adjust = (await db.sourceHistory(cash)).firstWhere((e) => e.kind == MoveKind.adjust);
    expect(adjust.amount, -32000);
    expect(adjust.note, 'Số dư thực tế');
    expect(adjust.date, today);
    expect(await balance(cash), 968000);
  });

  test('xoá nguồn: ẩn đi, giữ lịch sử, chuyển mặc định, không xoá nguồn cuối', () async {
    final cash = await cashId();
    final vcb = await db.insertSource(source('Vietcombank', 'bank'), openingBalance: 5000000);
    await db.insert(expense(45000, sourceId: cash));
    await db.insertMove(move(MoveKind.income, 100000, to: cash));

    await db.archiveSource(cash);
    final active = await db.sourcesWithBalance();
    expect(active.map((s) => s.id), [vcb]);
    expect(active.single.isDefault, isTrue);
    expect(await db.totalBalance(), 5000000);
    // Lịch sử và khoản chi vẫn còn.
    expect(await db.sourceHistory(cash), hasLength(2));
    expect((await db.all()).single.sourceId, cash);
    expect((await db.sourceNames())[cash], 'Tiền mặt');

    await expectLater(
      db.archiveSource(vcb),
      throwsA(isA<DataException>().having((e) => e.message, 'message', 'Cần giữ ít nhất một nguồn tiền')),
    );
  });

  test('nguồn không tính vào tổng và nguồn mặc định duy nhất', () async {
    await db.insertSource(source('Sổ tiết kiệm', 'saving', inTotal: false), openingBalance: 50000000);
    final momo = await db.insertSource(source('MoMo', 'ewallet', isDefault: true), openingBalance: 845000);
    expect(await db.totalBalance(), 845000);
    final defaults = (await db.sourcesWithBalance()).where((s) => s.isDefault);
    expect(defaults.map((s) => s.id), [momo]);
  });

  test('vào/ra tháng này và lịch sử mới nhất trước', () async {
    final cash = await cashId();
    final lastMonth = DateTime(today.year, today.month - 1, 15);
    await db.insertMove(move(MoveKind.income, 300000, to: cash, date: lastMonth));
    await db.insertMove(move(MoveKind.income, 15000000, to: cash));
    await db.insert(expense(55000, sourceId: cash));

    final flow = await db.sourceMonthFlow(cash, today);
    expect(flow.inflow, 15000000);
    expect(flow.outflow, -55000);

    final history = await db.sourceHistory(cash);
    expect(history.map((e) => e.date), [today, today, lastMonth]);
    expect(history.last.amount, 300000);
    expect(history.firstWhere((e) => e.kind == LedgerEntry.expense).category, 'food');
  });

  test('khôi phục bản sao lưu v1: thay khoản chi, nguồn về "Tiền mặt", xoá giao dịch', () async {
    final vcb = await db.insertSource(source('Vietcombank', 'bank'), openingBalance: 100);
    await db.insert(expense(1000, sourceId: vcb));

    final count = await DriveBackup.importJson(db, {
      'app': 'sochitieu',
      'version': 1,
      'expenses': [
        {'amount': 45000, 'category': 'food', 'date': '2026-10-01', 'note': 'Phở', 'created_at': 1, 'updated_at': 1},
      ],
    });
    expect(count, 1);
    final all = await db.all();
    expect(all.single.amount, 45000);
    expect(all.single.sourceId, isNull);
    final sources = await db.sourcesWithBalance(includeArchived: true);
    expect(sources.map((s) => (s.name, s.isDefault, s.balance)), [('Tiền mặt', true, 0)]);
    expect(await db.allMoves(), isEmpty);
  });

  test('sao lưu v2 rồi khôi phục giữ nguyên nguồn, giao dịch và số dư', () async {
    final cash = await cashId();
    final vcb = await db.insertSource(source('Vietcombank', 'bank'), openingBalance: 18400000);
    await db.insertMove(move(MoveKind.move, 1000000, from: vcb, to: cash));
    await db.insert(expense(45000, sourceId: cash));
    await db.insert(expense(10000));
    final card = await db.insertSource(source('Thẻ', 'credit'), openingBalance: -200000);
    await db.archiveSource(card);

    final json = await DriveBackup.exportJson(db, DateTime(2026, 10, 26));
    expect(json['version'], 2);

    final dir2 = await Directory.systemTemp.createTemp('sochitieu_restore');
    final other = ExpenseDb.forTesting(databaseFactoryFfi, p.join(dir2.path, 'r.db'));
    await DriveBackup.importJson(other, Map<String, dynamic>.from(json));
    expect(await other.sourceById(cash).then((s) => s!.balance), 955000);
    expect(await other.sourceById(vcb).then((s) => s!.balance), 17400000);
    expect(await other.sourceById(card).then((s) => s!.archived), isTrue);
    expect(await other.totalBalance(), await db.totalBalance());
    expect((await other.all()).map((e) => e.sourceId), unorderedEquals([cash, null]));
    await other.close();
    await dir2.delete(recursive: true);
  });

  test('vào/ra tháng này không tính số dư ban đầu và dòng sửa số dư, có tính chuyển tiền', () async {
    final cash = await cashId();
    final vcb = await db.insertSource(source('Vietcombank', 'bank'), openingBalance: 18400000);
    await db.updateSource((await db.sourceById(vcb))!, newBalance: 18432000);
    await db.insertMove(move(MoveKind.move, 1000000, from: vcb, to: cash));
    await db.insertMove(move(MoveKind.income, 15000000, to: vcb));

    final flow = await db.sourceMonthFlow(vcb, today);
    expect(flow.inflow, 15000000);
    expect(flow.outflow, -1000000);
    expect(await balance(vcb), 32432000);

    final cashFlow = await db.sourceMonthFlow(cash, today);
    expect(cashFlow.inflow, 1000000);
    expect(cashFlow.outflow, 0);
  });

  test('chọn nguồn mặc định: chỉ còn đúng một nguồn mặc định', () async {
    final cash = await cashId();
    final b = await db.insertSource(source('B', 'bank'));
    await db.updateSource((await db.sourceById(b))!.copyWith(isDefault: true));
    var defaults = (await db.sourcesWithBalance()).where((s) => s.isDefault).map((s) => s.id);
    expect(defaults, [b]);

    // Tắt mặc định của nguồn mặc định duy nhất: nguồn đầu tiên trở thành mặc định.
    await db.updateSource((await db.sourceById(b))!.copyWith(isDefault: false));
    defaults = (await db.sourcesWithBalance()).where((s) => s.isDefault).map((s) => s.id);
    expect(defaults, [cash]);

    await db.updateSource((await db.sourceById(cash))!.copyWith(isDefault: false));
    expect((await db.sourcesWithBalance()).where((s) => s.isDefault), hasLength(1));
  });

  group('khôi phục bản sao lưu không chuẩn', () {
    Map<String, Object?> src(int id, String name, {bool isDefault = false, bool archived = false}) => {
          'id': id,
          'name': name,
          'type': 'bank',
          'is_default': isDefault ? 1 : 0,
          'in_total': 1,
          'archived': archived ? 1 : 0,
          'created_at': 1,
        };
    Map<String, Object?> mv(int id, String kind, int amount, {int? from, int? to}) => {
          'id': id,
          'kind': kind,
          'amount': amount,
          'from_id': from,
          'to_id': to,
          'date': '2026-10-01',
          'note': '',
          'created_at': 1,
          'updated_at': 1,
        };
    Map<String, Object?> exp(int amount, int? sourceId) => {
          'amount': amount,
          'category': 'food',
          'date': '2026-10-01',
          'note': '',
          'source_id': sourceId,
          'created_at': 1,
          'updated_at': 1,
        };

    test('bản từ app mới hơn bị từ chối, dữ liệu trên máy giữ nguyên', () async {
      await db.insert(expense(45000, sourceId: await cashId()));
      await expectLater(
        DriveBackup.importJson(db, {'version': 3, 'expenses': [], 'sources': [], 'moves': []}),
        throwsA(isA<BackupException>().having((e) => e.message, 'message',
            'Bản sao lưu được tạo từ phiên bản app mới hơn. Hãy cập nhật app rồi thử lại.')),
      );
      expect((await db.all()).single.amount, 45000);
      expect(await db.sourcesWithBalance(), hasLength(1));
    });

    test('bỏ nguồn trỏ sai ở khoản chi, bỏ giao dịch sai dạng, giữ một nguồn mặc định', () async {
      await DriveBackup.importJson(db, {
        'version': 2,
        'sources': [src(10, 'A', isDefault: true), src(11, 'B', isDefault: true), src(12, 'C', archived: true)],
        'expenses': [exp(1000, 10), exp(2000, 99)],
        'moves': [
          mv(1, MoveKind.income, 500, to: 10), // hợp lệ
          mv(2, MoveKind.move, 300, from: 10, to: 11), // hợp lệ
          mv(3, MoveKind.adjust, -50, to: 11), // hợp lệ
          mv(4, MoveKind.income, 500, to: 99), // nguồn không có
          mv(5, MoveKind.move, 300, from: 10, to: 10), // chuyển cho chính nó
          mv(6, MoveKind.move, 300, to: 11), // thiếu nguồn chuyển
          mv(7, MoveKind.income, 500, from: 11, to: 10), // tiền vào lại có nguồn chuyển
          mv(8, MoveKind.adjust, 100), // điều chỉnh không có nguồn
          mv(9, 'gift', 100, to: 10), // loại lạ
          mv(10, MoveKind.income, -5, to: 10), // tiền vào âm
        ],
      });
      expect((await db.allMoves()).map((m) => m.id), [1, 2, 3]);
      expect((await db.all()).map((e) => e.sourceId), unorderedEquals([10, null]));
      final active = await db.sourcesWithBalance();
      expect(active.map((s) => s.id), [10, 11]);
      expect(active.where((s) => s.isDefault).map((s) => s.id), [10]);
      expect(await balance(10), -1000 + 500 - 300);
      expect(await balance(11), 300 - 50);
    });

    test('không còn nguồn nào đang dùng thì thêm "Tiền mặt" mặc định', () async {
      await DriveBackup.importJson(db, {
        'version': 2,
        'sources': [src(10, 'A', isDefault: true, archived: true)],
        'expenses': [exp(1000, 10)],
        'moves': [],
      });
      final all = await db.sourcesWithBalance(includeArchived: true);
      expect(all.firstWhere((s) => s.id == 10).isDefault, isFalse);
      final active = await db.sourcesWithBalance();
      expect(active.map((s) => (s.name, s.type, s.isDefault)), [('Tiền mặt', 'cash', true)]);
      // Khoản chi vẫn giữ nguồn đã xoá (có trong file).
      expect((await db.all()).single.sourceId, 10);
    });
  });
}
