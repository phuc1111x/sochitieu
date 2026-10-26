import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sochitieu/data/expense_db.dart';
import 'package:sochitieu/models/expense.dart';
import 'package:sochitieu/models/money_move.dart';
import 'package:sochitieu/models/money_source.dart';
import 'package:sochitieu/screens/day_screen.dart';
import 'package:sochitieu/screens/money_form_screen.dart';
import 'package:sochitieu/screens/source_form_screen.dart';
import 'package:sochitieu/utils/format.dart';

import 'test_helpers.dart';

void main() {
  late ExpenseDb db;
  final today = dateOnly(DateTime.now());
  final now = DateTime.now().millisecondsSinceEpoch;

  setUp(() async => db = await useFreshDb());

  Future<int> cashId(WidgetTester tester) =>
      dbRun(tester, () async => (await db.sourcesWithBalance()).single.id!);

  Future<int> balanceOf(WidgetTester tester, int id) => dbRun(tester, () async => (await db.sourceById(id))!.balance);

  testWidgets('sửa nguồn mà không chạm vào số dư: không ghi dòng điều chỉnh', (tester) async {
    usePhoneSize(tester);
    final cash = await cashId(tester);
    final source = await dbRun(tester, () async {
      await db.insertMove(MoneyMove(
          kind: MoveKind.income, amount: 1000000, toId: cash, date: today, createdAt: now, updatedAt: now));
      return (await db.sourceById(cash))!;
    });

    await openFromHost(tester, (c) => openSourceForm(c, source: source), SourceFormScreen);
    expect(find.text('1.000.000'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Ví');
    await saveAndWaitClosed(tester, 'Lưu thay đổi', SourceFormScreen);

    final after = await dbRun(tester, () => db.sourceById(cash));
    expect(after!.name, 'Ví');
    expect(after.balance, 1000000);
    final history = await dbRun(tester, () => db.sourceHistory(cash));
    expect(history.where((e) => e.kind == MoveKind.adjust), isEmpty);
  });

  testWidgets('chọn Chuyển tiền rồi quay lại Thêm tiền: chỉ nguồn nhận tăng, không có nguồn chuyển', (tester) async {
    usePhoneSize(tester);
    final cash = await cashId(tester);
    final vcb = await dbRun(tester, () async {
      await db.updateSource((await db.sourceById(cash))!, newBalance: 500000);
      return db.insertSource(MoneySource(name: 'Vietcombank', type: 'bank', createdAt: now), openingBalance: 3000000);
    });

    await openFromHost(tester, (c) => openMoneyForm(c, kind: MoveKind.income, toId: vcb), MoneyFormScreen);
    await pumpUntil(tester, () => shows(find.text('Vào nguồn')), reason: 'tải nguồn tiền');

    await tester.tap(find.text('Chuyển tiền'));
    await tester.pump();
    expect(find.text('Từ nguồn'), findsOneWidget);
    await tester.tap(find.text('Thêm tiền'));
    await tester.pump();
    expect(find.text('Từ nguồn'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '200000');
    await saveAndWaitClosed(tester, 'Lưu khoản tiền vào', MoneyFormScreen);

    final move = (await dbRun(tester, db.allMoves)).last;
    expect(move.kind, MoveKind.income);
    expect(move.fromId, isNull);
    expect(move.toId, vcb);
    expect(await balanceOf(tester, cash), 500000);
    expect(await balanceOf(tester, vcb), 3200000);
  });

  testWidgets('danh sách theo ngày: dòng phụ "Danh mục · Nguồn"', (tester) async {
    usePhoneSize(tester);
    final cash = await cashId(tester);
    Expense e(String category, {String note = '', int? sourceId}) => Expense(
        amount: 10000,
        category: category,
        date: today,
        note: note,
        sourceId: sourceId,
        createdAt: now,
        updatedAt: now);
    await dbRun(tester, () async {
      await db.insert(e('food', note: 'Phở bò', sourceId: cash));
      await db.insert(e('shopping', sourceId: cash));
      await db.insert(e('transport'));
    });

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DayScreen())));
    await pumpUntil(tester, () => shows(find.text('Phở bò')), reason: 'tải danh sách');

    // Có ghi chú: "Danh mục · Nguồn".
    expect(find.text('Ăn uống · Tiền mặt'), findsOneWidget);
    // Không ghi chú: tên danh mục ở dòng chính, dòng phụ chỉ có nguồn.
    expect(find.text('Mua sắm'), findsOneWidget);
    expect(find.text('Tiền mặt'), findsOneWidget);
    // Khoản chi cũ không có nguồn, không ghi chú: không có dòng phụ.
    expect(find.text('Đi lại'), findsOneWidget);
    expect(find.textContaining('Đi lại ·'), findsNothing);
  });
}
