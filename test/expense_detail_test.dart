import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sochitieu/data/expense_db.dart';
import 'package:sochitieu/models/expense.dart';
import 'package:sochitieu/models/money_move.dart';
import 'package:sochitieu/models/money_source.dart';
import 'package:sochitieu/screens/day_screen.dart';
import 'package:sochitieu/screens/expense_form_screen.dart';
import 'package:sochitieu/screens/money_form_screen.dart';
import 'package:sochitieu/screens/source_detail_screen.dart';
import 'package:sochitieu/theme.dart';
import 'package:sochitieu/utils/format.dart';
import 'package:sochitieu/widgets/common.dart';
import 'package:sochitieu/widgets/expense_detail_sheet.dart';

import 'test_helpers.dart';

void main() {
  group('singleLineNote', () {
    test('gộp mỗi khoảng trắng có xuống dòng thành một dấu cách', () {
      expect(singleLineNote('Phở\n  Cà phê'), 'Phở Cà phê');
      expect(singleLineNote('a\r\nb'), 'a b');
      expect(singleLineNote('a \n \n b'), 'a b');
      expect(singleLineNote('\n  Trà sữa  \n'), 'Trà sữa');
    });

    test('ngắt dòng Unicode và \\v, \\f cũng là xuống dòng', () {
      expect(singleLineNote('Phở\u2028Cà phê'), 'Phở Cà phê');
      expect(singleLineNote('Phở \u2029 Cà phê'), 'Phở Cà phê');
      expect(singleLineNote('Phở\u0085Cà phê'), 'Phở Cà phê');
      expect(singleLineNote('Phở\vCà phê'), 'Phở Cà phê');
      expect(singleLineNote('Phở\fCà phê'), 'Phở Cà phê');
      expect(singleLineNote('a \u2028\r\n\v b'), 'a b');
    });

    test('giữ nguyên khoảng trắng không có xuống dòng (chỉ bỏ hai đầu)', () {
      expect(singleLineNote('  Phở  bò '), 'Phở  bò');
      expect(singleLineNote(''), '');
    });
  });

  // Nạp font thật của ứng dụng để chiều cao chữ và chỗ xuống dòng giống trên điện thoại.
  setUpAll(() async {
    final loader = FontLoader('BeVietnamPro');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final bytes = File('assets/fonts/BeVietnamPro-$w.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  late ExpenseDb db;
  final today = dateOnly(DateTime.now());
  final now = DateTime.now().millisecondsSinceEpoch;

  setUp(() async {
    db = await useFreshDb();
    SharedPreferences.setMockInitialValues({});
    SwipeHint.resetForTest();
    resetExpenseDetailForTest();
  });

  Future<int> cashId(WidgetTester tester) =>
      dbRun(tester, () async => (await db.sourcesWithBalance()).single.id!);

  /// Thêm một khoản chi (mặc định hôm nay), trả về khoản chi đã lưu (có id).
  Future<Expense> addExpense(WidgetTester tester,
          {String note = '', int? sourceId, int amount = 45000, DateTime? date}) =>
      dbRun(tester, () async {
        await db.insert(Expense(
            amount: amount,
            category: 'food',
            date: date ?? today,
            note: note,
            sourceId: sourceId,
            createdAt: now,
            updatedAt: now));
        return (await db.all()).last;
      });

  Widget app(Widget home) => MaterialApp(theme: buildTheme(), home: home);

  Future<void> pumpDay(WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app(const Scaffold(body: DayScreen())));
    await pumpUntil(tester, () => shows(find.text('Các khoản chi')), reason: 'tải danh sách');
  }

  Future<void> waitSheet(WidgetTester tester) async {
    await pumpUntil(tester, () => shows(find.byType(BottomSheet)), reason: 'mở bảng chi tiết');
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Mở bảng chi tiết trực tiếp từ một nút trên màn trống.
  Future<void> openSheet(WidgetTester tester, Expense e) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app(Scaffold(
      body: Builder(
        builder: (context) =>
            Center(child: TextButton(onPressed: () => showExpenseDetail(context, e), child: const Text('Mở'))),
      ),
    )));
    await tester.tap(find.text('Mở'));
    await waitSheet(tester);
  }

  Future<void> waitSheetClosed(WidgetTester tester) async {
    await pumpUntil(tester, () => !shows(find.byType(BottomSheet)), reason: 'đóng bảng chi tiết');
  }

  testWidgets('ghi chú dài: danh sách 1 dòng, chạm mở bảng chi tiết với đủ ghi chú, không mở form', (tester) async {
    final note = 'Ăn trưa với cả nhóm ở quán cơm gà, chia tiền xong còn mua thêm trà sữa mang về văn phòng '
        'cho mọi người cùng uống buổi chiều';
    final cash = await cashId(tester);
    await addExpense(tester, note: note, sourceId: cash);
    await pumpDay(tester);
    expect(find.text('Chạm để xem chi tiết'), findsOneWidget);
    final row = tester.widget<Text>(find.text(note));
    expect(row.maxLines, 1);

    await tester.tap(find.text(note));
    await waitSheet(tester);
    expect(find.byType(ExpenseFormScreen), findsNothing);

    final full = find.byType(SelectableText);
    expect(tester.widget<SelectableText>(full).data, note);
    // Toàn bộ ghi chú nằm trong màn hình (360 x 800), không bị cắt.
    final rect = tester.getRect(full);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(800));
    expect(find.text('Ăn uống'), findsWidgets);
    expect(find.text('45.000 đ'), findsWidgets);
    expect(find.text('Hôm nay · ${formatFullDate(today)}'), findsOneWidget);
    expect(find.text('Trả bằng'), findsOneWidget);
    expect(find.text('Tiền mặt'), findsWidgets);
    expect(find.text('Ghi lúc'), findsOneWidget);
    final created = DateTime.fromMillisecondsSinceEpoch(now);
    expect(find.text('${formatTime(created)} · ${formatDate(created)}'), findsOneWidget);
  });

  testWidgets('ghi chú 500 ký tự: phần ghi chú cuộn, đầu bảng và nút vẫn hiện', (tester) async {
    final note = List.filled(50, 'Ghi chú dài').join(' ').substring(0, 500);
    final e = await addExpense(tester, note: note);
    await openSheet(tester, e);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    for (final f in [find.text('45.000 đ'), find.text('Sửa'), find.text('Đóng')]) {
      final r = tester.getRect(f);
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(800));
    }
    expect(tester.getRect(find.byType(BottomSheet)).height, lessThanOrEqualTo(800 * 0.85 + 1));
  });

  testWidgets('không có ghi chú: "Không có ghi chú"; khoản chi cũ: "Không trừ vào nguồn nào"', (tester) async {
    final e = await addExpense(tester);
    await openSheet(tester, e);
    expect(find.text('Không có ghi chú'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('Không trừ vào nguồn nào'), findsOneWidget);
  });

  testWidgets('nguồn đã xoá: "{tên} (đã xoá)"', (tester) async {
    final vcb = await dbRun(tester, () => db.insertSource(MoneySource(name: 'Vietcombank', type: 'bank', createdAt: now)));
    final e = await addExpense(tester, note: 'Điện', sourceId: vcb);
    await dbRun(tester, () => db.archiveSource(vcb));
    await openSheet(tester, e);
    expect(find.text('Vietcombank (đã xoá)'), findsOneWidget);
  });

  testWidgets('Đóng: bảng đóng lại, không ghi gì, không mở form', (tester) async {
    final e = await addExpense(tester, note: 'Phở');
    await openSheet(tester, e);
    await tester.tap(find.text('Đóng'));
    await waitSheetClosed(tester);
    expect(find.byType(ExpenseFormScreen), findsNothing);
    final saved = await dbRun(tester, db.all);
    expect(saved.single.updatedAt, now);
  });

  testWidgets('Sửa: bảng đóng rồi mới mở form sửa; Back từ form về danh sách', (tester) async {
    await addExpense(tester, note: 'Phở bò');
    await pumpDay(tester);
    await tester.tap(find.text('Phở bò'));
    await waitSheet(tester);
    await tester.tap(find.text('Sửa'));
    await pumpUntil(tester, () => shows(find.byType(ExpenseFormScreen)), reason: 'mở form sửa');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Sửa chi tiêu'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, 'Phở bò');

    await tester.tap(find.byTooltip('Đóng'));
    await pumpUntil(tester, () => !shows(find.byType(ExpenseFormScreen)), reason: 'đóng form');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Phở bò'), findsOneWidget);
  });

  testWidgets('chạm hai lần nhanh vào một dòng: chỉ mở một bảng; đóng rồi mở lại được', (tester) async {
    await addExpense(tester, note: 'Phở bò');
    await pumpDay(tester);
    await tester.tap(find.text('Phở bò'));
    await tester.tap(find.text('Phở bò'));
    await waitSheet(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.text('Đóng'));
    await waitSheetClosed(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Phở bò'));
    await waitSheet(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('ngày: hôm qua có "Hôm qua · ", 5 ngày trước chỉ có ngày đầy đủ', (tester) async {
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final e = await addExpense(tester, date: yesterday);
    await openSheet(tester, e);
    expect(find.text('Hôm qua · ${formatFullDate(yesterday)}'), findsOneWidget);
  });

  testWidgets('ngày cũ hơn hôm qua: chỉ "Thứ ..., dd/MM/yyyy"', (tester) async {
    final d = DateTime(today.year, today.month, today.day - 5);
    final e = await addExpense(tester, date: d);
    await openSheet(tester, e);
    expect(find.text(formatFullDate(d)), findsOneWidget);
    expect(find.textContaining(' · ${formatFullDate(d)}'), findsNothing);
  });

  testWidgets('bảng bị màn khác che khi khoản chi bị xoá: vẫn được gỡ khỏi navigator', (tester) async {
    final e = await addExpense(tester, note: 'Phở');
    await openSheet(tester, e);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Màn che'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Màn che'), findsOneWidget);

    await dbRun(tester, () => db.replaceAll(const []));
    await pumpUntil(tester, () => !shows(find.byType(BottomSheet, skipOffstage: false)), reason: 'gỡ bảng');
    expect(tester.takeException(), isNull);
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Mở'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('Sửa rồi lưu: SnackBar "Đã lưu thay đổi" hiện trên danh sách', (tester) async {
    await addExpense(tester, note: 'Phở bò');
    await pumpDay(tester);
    await tester.tap(find.text('Phở bò'));
    await waitSheet(tester);
    await tester.tap(find.text('Sửa'));
    await pumpUntil(tester, () => shows(find.text('Lưu thay đổi')), reason: 'mở form sửa');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField).last, 'Phở gà');
    await tester.pump();
    await tester.tap(find.text('Lưu thay đổi'));
    await pumpUntil(tester, () => !shows(find.byType(ExpenseFormScreen)), reason: 'đóng form');
    await pumpUntil(tester, () => shows(find.text('Đã lưu thay đổi')), reason: 'SnackBar');
    expect(find.byType(DayScreen), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await pumpUntil(tester, () => shows(find.text('Phở gà')), reason: 'danh sách cập nhật');
    expect((await dbRun(tester, db.all)).single.note, 'Phở gà');
    // Cho SnackBar chạy hết để không còn timer treo.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('khoản chi bị xoá khi bảng đang mở: bảng tự đóng, không lỗi', (tester) async {
    final e = await addExpense(tester, note: 'Phở');
    await openSheet(tester, e);
    await dbRun(tester, () => db.replaceAll(const []));
    await waitSheetClosed(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Mở'), findsOneWidget);
  });

  testWidgets('lịch sử nguồn tiền: dòng chi tiêu mở bảng chi tiết, dòng tiền vào vẫn mở form tiền', (tester) async {
    usePhoneSize(tester);
    final cash = await cashId(tester);
    await addExpense(tester, note: 'Bún chả', sourceId: cash);
    await dbRun(tester, () => db.insertMove(MoneyMove(
        kind: MoveKind.income,
        amount: 500000,
        toId: cash,
        date: today,
        note: 'Lương',
        createdAt: now,
        updatedAt: now)));
    await tester.pumpWidget(app(SourceDetailScreen(sourceId: cash)));
    await pumpUntil(tester, () => shows(find.text('Bún chả')), reason: 'tải lịch sử');

    await tester.tap(find.text('Bún chả'));
    await waitSheet(tester);
    expect(find.byType(ExpenseFormScreen), findsNothing);
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data, 'Bún chả');
    await tester.tap(find.text('Đóng'));
    await waitSheetClosed(tester);

    await tester.tap(find.text('Lương'));
    await pumpUntil(tester, () => shows(find.byType(MoneyFormScreen)), reason: 'mở form tiền');
    expect(find.byType(BottomSheet), findsNothing);
  });

  group('ô ghi chú', () {
    Future<void> openAddForm(WidgetTester tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(app(Scaffold(
        body: Builder(
          builder: (context) =>
              Center(child: TextButton(onPressed: () => openExpenseForm(context), child: const Text('Mở'))),
        ),
      )));
      await tester.tap(find.text('Mở'));
      await pumpUntil(tester, () => shows(find.textContaining('Sau khi lưu')), reason: 'mở form');
    }

    testWidgets('kiểu một dòng (Enter = xong), xuống dòng tối đa 3 dòng, nhận hơn 100 ký tự', (tester) async {
      await openAddForm(tester);
      final noteField = find.byType(TextField).last;
      final field = tester.widget<TextField>(noteField);
      expect(field.keyboardType, TextInputType.text);
      expect(field.textInputAction, TextInputAction.done);
      expect((field.minLines, field.maxLines, field.maxLength), (1, 3, 500));

      final long = List.filled(12, 'Phở bò tái').join(' '); // 131 ký tự
      expect(long.length, greaterThan(120));
      await tester.enterText(noteField, long);
      await tester.pump();
      expect(field.controller!.text, long);
    });

    testWidgets('Enter (xong) trên bàn phím: kết thúc nhập, không chèn xuống dòng', (tester) async {
      await openAddForm(tester);
      final noteField = find.byType(TextField).last;
      await tester.showKeyboard(noteField);
      await tester.enterText(noteField, 'Phở bò tái');
      await tester.pump();
      final editable = find.descendant(of: noteField, matching: find.byType(EditableText));
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      final field = tester.widget<TextField>(noteField);
      expect(field.controller!.text, 'Phở bò tái');
      expect(field.controller!.text.contains('\n'), isFalse);
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isFalse);
    });

    testWidgets('form sửa với ghi chú 3 dòng vẫn nằm gọn trong màn 360 x 800', (tester) async {
      final note = List.filled(50, 'Ghi chú dài').join(' ').substring(0, 500);
      final cash = await cashId(tester);
      await dbRun(tester, () async => db.updateSource((await db.sourceById(cash))!, newBalance: 1000000));
      final e = await addExpense(tester, note: note, sourceId: cash);
      usePhoneSize(tester);
      // Dùng theme thật của ứng dụng để kích thước giống trên điện thoại.
      await tester.pumpWidget(app(ExpenseFormScreen(expense: e)));
      await pumpUntil(tester, () => shows(find.textContaining('Sau khi lưu')), reason: 'tải nguồn');
      final noteRect = tester.getRect(find.byType(TextField).last);
      final listRect = tester.getRect(find.byType(ListView));
      final save = tester.getRect(find.text('Lưu thay đổi'));
      // Ô ghi chú nằm trọn trong phần nhìn thấy (trên thanh nút lưu), nút lưu nằm trong màn hình.
      expect(noteRect.top, greaterThanOrEqualTo(listRect.top));
      expect(noteRect.bottom, lessThanOrEqualTo(listRect.bottom));
      expect(save.bottom, lessThanOrEqualTo(800));
      // Ô ghi chú cao đúng 3 dòng chữ.
      final editable = tester.state<EditableTextState>(find.byType(EditableText).last).renderEditable;
      expect(editable.size.height, closeTo(editable.preferredLineHeight * 3, 0.5));
    });

    testWidgets('dán chữ nhiều dòng: lưu thành một dòng (khoản chi)', (tester) async {
      await openAddForm(tester);
      await tester.enterText(find.byType(TextField).first, '30000');
      await tester.enterText(find.byType(TextField).last, 'Phở\n  Cà phê');
      await tester.pump();
      await saveAndWaitClosed(tester, 'Lưu chi tiêu', ExpenseFormScreen);
      expect((await dbRun(tester, db.all)).single.note, 'Phở Cà phê');
    });

    testWidgets('dán chữ nhiều dòng: lưu thành một dòng (tiền vào), nhận hơn 100 ký tự', (tester) async {
      usePhoneSize(tester);
      final cash = await cashId(tester);
      await openFromHost(tester, (c) => openMoneyForm(c, kind: MoveKind.income, toId: cash), MoneyFormScreen);
      await pumpUntil(tester, () => shows(find.text('Vào nguồn')), reason: 'tải nguồn tiền');
      final noteField = find.byType(TextField).last;
      final field = tester.widget<TextField>(noteField);
      expect((field.keyboardType, field.maxLines, field.maxLength), (TextInputType.text, 3, 500));
      await tester.enterText(find.byType(TextField).first, '200000');
      final long = 'Lương tháng 10\n  ${List.filled(12, 'thưởng dự án').join(' ')}';
      await tester.enterText(noteField, long);
      await tester.pump();
      await saveAndWaitClosed(tester, 'Lưu tiền vào', MoneyFormScreen);
      final saved = (await dbRun(tester, db.allMoves)).last.note;
      expect(saved, singleLineNote(long));
      expect(saved.contains('\n'), isFalse);
      expect(saved.length, greaterThan(100));
    });
  });
}
