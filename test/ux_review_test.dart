import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sochitieu/data/expense_db.dart';
import 'package:sochitieu/models/expense.dart';
import 'package:sochitieu/models/money_source.dart';
import 'package:sochitieu/models/money_move.dart';
import 'package:sochitieu/screens/day_screen.dart';
import 'package:sochitieu/screens/expense_form_screen.dart';
import 'package:sochitieu/screens/money_form_screen.dart';
import 'package:sochitieu/screens/source_detail_screen.dart';
import 'package:sochitieu/widgets/form_fields.dart';
import 'package:sochitieu/screens/month_screen.dart';
import 'package:sochitieu/screens/source_form_screen.dart';
import 'package:sochitieu/screens/sources_screen.dart';
import 'package:sochitieu/utils/format.dart';
import 'package:sochitieu/widgets/common.dart';

import 'test_helpers.dart';

void main() {
  late ExpenseDb db;
  final today = dateOnly(DateTime.now());
  final now = DateTime.now().millisecondsSinceEpoch;

  setUp(() async {
    db = await useFreshDb();
    SharedPreferences.setMockInitialValues({});
    SwipeHint.resetForTest();
  });

  testWidgets('nguồn thường số dư âm: dòng phụ đỏ, chạm mở form sửa', (tester) async {
    usePhoneSize(tester);
    await dbRun(tester, () => db.insertSource(
        MoneySource(name: 'Ví lỗi', type: 'ewallet', createdAt: now), openingBalance: -30000));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SourcesScreen())));
    await pumpUntil(tester, () => shows(find.text('Ví lỗi')), reason: 'tải danh sách');
    expect(find.text('Số dư âm – chạm để cập nhật'), findsOneWidget);
    expect(find.textContaining('Đang nợ'), findsNothing);
    await tester.tap(find.text('Ví lỗi'));
    await pumpUntil(tester, () => shows(find.byType(SourceFormScreen)), reason: 'mở form sửa');
  });

  testWidgets('màn tháng: Danh mục | Từng ngày, giữ lựa chọn khi vuốt sang tháng trước', (tester) async {
    usePhoneSize(tester);
    final prev = DateTime(today.year, today.month - 1, 5);
    await dbRun(tester, () async {
      for (final d in [today, prev]) {
        await db.insert(Expense(
            amount: 20000, category: 'food', date: d, note: '', createdAt: now, updatedAt: now));
      }
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MonthScreen(onOpenDay: (_) {}))));
    await pumpUntil(tester, () => shows(find.text('Từng ngày')), reason: 'tải tháng');
    expect(find.text('Ăn uống'), findsOneWidget);
    expect(find.text('1 khoản chi'), findsNothing);

    await tester.tap(find.text('Từng ngày'));
    await tester.pump();
    expect(find.text('Ăn uống'), findsNothing);
    expect(find.text('1 khoản chi'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntil(tester, () => shows(find.text('Tháng ${prev.month}/${prev.year}')), reason: 'sang tháng trước');
    await pumpUntil(tester, () => shows(find.text('1 khoản chi')), reason: 'tải tháng trước');
    expect(find.text('Ăn uống'), findsNothing);
  });

  testWidgets('gợi ý vuốt: hiện tới khi vuốt lần đầu, rồi ẩn và nhớ', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DayScreen())));
    await pumpUntil(tester, () => shows(find.textContaining('Vuốt ngang')), reason: 'hiện gợi ý');
    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntil(tester, () => !shows(find.textContaining('Vuốt ngang')), reason: 'ẩn gợi ý');
    await tester.pump(const Duration(seconds: 1));
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getBool('swipe_hint_done'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('swipe_hint_done đã lưu: không hiện gợi ý', (tester) async {
    usePhoneSize(tester);
    SharedPreferences.setMockInitialValues({'swipe_hint_done': true});
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DayScreen())));
    await pumpUntil(tester, () => !shows(find.textContaining('Vuốt ngang')), reason: 'đọc cờ');
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Vuốt ngang'), findsNothing);
  });

  /// Ngày khác hôm nay, không phải tương lai: hôm qua, hoặc (mùng 1) ngày hôm qua của tháng trước.
  DateTime otherDay() => today.subtract(const Duration(days: 1));

  Future<void> pickOtherDay(WidgetTester tester) async {
    await tester.tap(find.byType(DateChip));
    await tester.pumpAndSettle();
    final target = otherDay();
    if (target.month != today.month) {
      await tester.tap(find.byIcon(Icons.chevron_left).last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('${target.day}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('DateChip: chọn ngày khác, lưu khoản chi giữ đúng ngày', (tester) async {
    usePhoneSize(tester);
    await openFromHost(tester, (c) => openExpenseForm(c), ExpenseFormScreen);
    await pumpUntil(tester, () => shows(find.textContaining('Sau khi lưu')), reason: 'tải nguồn');
    await tester.enterText(find.byType(TextField).first, '10000');
    await pickOtherDay(tester);
    expect(find.textContaining('Hôm qua'), findsOneWidget);
    await saveAndWaitClosed(tester, 'Lưu chi tiêu', ExpenseFormScreen);
    expect((await dbRun(tester, db.all)).single.date, otherDay());
  });

  testWidgets('DateChip và Đến nguồn: lưu giao dịch giữ đúng ngày và nguồn nhận', (tester) async {
    usePhoneSize(tester);
    final cash = (await dbRun(tester, db.sourcesWithBalance)).single.id!;
    final a = await dbRun(tester, () => db.insertSource(
        MoneySource(name: 'Ngân hàng A', type: 'bank', createdAt: now), openingBalance: 1000));
    final b = await dbRun(tester, () => db.insertSource(
        MoneySource(name: 'Ngân hàng B', type: 'bank', createdAt: now), openingBalance: 1000));
    await openFromHost(tester, (c) => openMoneyForm(c, kind: MoveKind.move, fromId: cash, toId: a), MoneyFormScreen);
    await pumpUntil(tester, () => shows(find.text('Đến nguồn')), reason: 'tải nguồn');
    await tester.enterText(find.byType(TextField).first, '5000');
    await pickOtherDay(tester);
    await tester.tap(find.byType(PickerField<int>).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Ngân hàng B').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await saveAndWaitClosed(tester, 'Lưu', MoneyFormScreen);
    final m = (await dbRun(tester, db.allMoves)).last;
    expect((m.fromId, m.toId, m.date), (cash, b, otherDay()));
  });

  testWidgets('vuốt màn tháng: ẩn gợi ý và lưu swipe_hint_done', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MonthScreen(onOpenDay: (_) {}))));
    await pumpUntil(tester, () => shows(find.textContaining('Vuốt ngang')), reason: 'hiện gợi ý');
    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntil(tester, () => !shows(find.textContaining('Vuốt ngang')), reason: 'ẩn gợi ý');
    await tester.pump(const Duration(seconds: 1));
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getBool('swipe_hint_done'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('Trả hết dư nợ rồi lưu: số tiền giao dịch bằng dư nợ', (tester) async {
    usePhoneSize(tester);
    final card = await dbRun(tester, () => db.insertSource(
        MoneySource(name: 'Thẻ VIB', type: 'credit', createdAt: now, creditLimit: 10000000),
        openingBalance: -2350000));
    await tester.pumpWidget(MaterialApp(home: SourceDetailScreen(sourceId: card)));
    await pumpUntil(tester, () => shows(find.text('Thanh toán dư nợ')), reason: 'tải chi tiết');
    await tester.tap(find.text('Thanh toán dư nợ'));
    await pumpUntil(tester, () => shows(find.text('Trả hết dư nợ')), reason: 'mở form');
    await tester.tap(find.text('Trả hết dư nợ'));
    await tester.pump();
    await saveAndWaitClosed(tester, 'Lưu thanh toán', MoneyFormScreen);
    final m = (await dbRun(tester, db.allMoves)).last;
    expect((m.kind, m.toId, m.amount), (MoveKind.move, card, 2350000));
  });
}
