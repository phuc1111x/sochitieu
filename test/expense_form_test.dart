import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sochitieu/data/expense_db.dart';
import 'package:sochitieu/models/expense.dart';
import 'package:sochitieu/models/money_source.dart';
import 'package:sochitieu/screens/expense_form_screen.dart';
import 'package:sochitieu/utils/format.dart';

import 'test_helpers.dart';

void main() {
  late ExpenseDb db;
  final today = dateOnly(DateTime.now());
  final now = DateTime.now().millisecondsSinceEpoch;

  setUp(() async => db = await useFreshDb());

  Expense expense(int amount, {int? sourceId, String note = ''}) => Expense(
        amount: amount,
        category: 'food',
        date: today,
        note: note,
        sourceId: sourceId,
        createdAt: now,
        updatedAt: now,
      );

  /// Nguồn "Tiền mặt" có sẵn, đặt số dư [balance]. Trả về id.
  Future<int> cashWith(WidgetTester tester, int balance) => dbRun(tester, () async {
        final cash = (await db.sourcesWithBalance()).single;
        await db.updateSource(cash, newBalance: balance);
        return cash.id!;
      });

  Future<int> balanceOf(WidgetTester tester, int id) => dbRun(tester, () async => (await db.sourceById(id))!.balance);

  Future<void> openForm(WidgetTester tester, {Expense? edit}) async {
    usePhoneSize(tester);
    await openFromHost(tester, (c) => openExpenseForm(c, expense: edit), ExpenseFormScreen);
    await pumpUntil(tester, () => shows(find.textContaining('Sau khi lưu')) || shows(find.text('Không trừ vào nguồn nào')),
        reason: 'tải nguồn tiền');
  }

  testWidgets('thêm mới: chọn sẵn nguồn mặc định, lưu thì trừ vào nguồn đó', (tester) async {
    final cash = await cashWith(tester, 1250000);
    await openForm(tester);
    expect(find.text('Tiền mặt'), findsOneWidget);
    expect(find.text('Sau khi lưu, Tiền mặt còn 1.250.000 đ'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '45000');
    await tester.pump();
    expect(find.text('Sau khi lưu, Tiền mặt còn 1.205.000 đ'), findsOneWidget);

    await saveAndWaitClosed(tester, 'Lưu chi tiêu', ExpenseFormScreen);
    final saved = await dbRun(tester, db.all);
    expect(saved.single.amount, 45000);
    expect(saved.single.sourceId, cash);
    expect(await balanceOf(tester, cash), 1205000);
  });

  testWidgets('sửa: không tính trùng khoản đang sửa, đổi nguồn từ A sang B', (tester) async {
    final cash = await cashWith(tester, 1000000);
    final vcb = await dbRun(tester, () async {
      final id = await db.insertSource(
          MoneySource(name: 'Vietcombank', type: 'bank', createdAt: now), openingBalance: 5000000);
      await db.insert(expense(100000, sourceId: cash, note: 'Đi chợ'));
      return id;
    });
    expect(await balanceOf(tester, cash), 900000);
    final e = (await dbRun(tester, db.all)).single;

    await openForm(tester, edit: e);
    // 900.000 hiện tại + 100.000 của chính khoản này − 100.000 = 900.000 (không phải 800.000).
    expect(find.text('Sau khi lưu, Tiền mặt còn 900.000 đ'), findsOneWidget);

    await tester.tap(find.text('Tiền mặt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vietcombank'));
    await tester.pumpAndSettle();
    expect(find.text('Sau khi lưu, Vietcombank còn 4.900.000 đ'), findsOneWidget);

    await saveAndWaitClosed(tester, 'Lưu thay đổi', ExpenseFormScreen);
    expect((await dbRun(tester, db.all)).single.sourceId, vcb);
    expect(await balanceOf(tester, cash), 1000000);
    expect(await balanceOf(tester, vcb), 4900000);
  });

  testWidgets('sửa khoản chi cũ (không có nguồn): giữ nguyên không nguồn, số dư không đổi', (tester) async {
    final cash = await cashWith(tester, 1000000);
    await dbRun(tester, () => db.insert(expense(30000, note: 'Bánh mì')));
    final e = (await dbRun(tester, db.all)).single;

    await openForm(tester, edit: e);
    expect(find.text('Không trừ vào nguồn nào'), findsOneWidget);
    expect(find.textContaining('Sau khi lưu'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'Bánh mì pate');
    await saveAndWaitClosed(tester, 'Lưu thay đổi', ExpenseFormScreen);
    final saved = (await dbRun(tester, db.all)).single;
    expect(saved.note, 'Bánh mì pate');
    expect(saved.sourceId, isNull);
    expect(await balanceOf(tester, cash), 1000000);
  });

  testWidgets('sửa khoản chi trỏ tới nguồn không còn trong máy: coi như không nguồn', (tester) async {
    await dbRun(tester, () => db.insert(expense(30000, sourceId: 999)));
    final e = (await dbRun(tester, db.all)).single;
    await openForm(tester, edit: e);
    expect(find.text('Không trừ vào nguồn nào'), findsOneWidget);
  });

  testWidgets('số tiền 0 thì nhắc nhập số tiền', (tester) async {
    await openForm(tester);
    await tester.tap(find.text('Lưu chi tiêu'));
    await tester.pump();
    // Host và form cùng dùng một ScaffoldMessenger nên SnackBar hiện ở cả hai Scaffold.
    expect(find.text('Vui lòng nhập số tiền'), findsWidgets);
    expect(await dbRun(tester, db.all), isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  test('câu "Sau khi lưu": còn / âm / nợ', () {
    MoneySource src(String name, String type) => MoneySource(name: name, type: type, createdAt: 0);
    final ok = afterSaveParts(src('Tiền mặt', 'cash'), 1205000);
    expect('${ok.text}${ok.amount}', 'Sau khi lưu, Tiền mặt còn 1.205.000 đ');
    expect(ok.negative, isFalse);

    final below = afterSaveParts(src('Tiền mặt', 'cash'), -500000);
    expect('${below.text}${below.amount}', 'Sau khi lưu, Tiền mặt âm 500.000 đ');
    expect(below.negative, isTrue);

    final debt = afterSaveParts(src('Thẻ VIB', 'credit'), -2350000);
    expect('${debt.text}${debt.amount}', 'Sau khi lưu, Thẻ VIB nợ 2.350.000 đ');
    expect(debt.negative, isTrue);
  });
}
