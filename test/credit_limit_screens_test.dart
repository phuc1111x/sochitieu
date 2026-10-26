import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sochitieu/data/expense_db.dart';
import 'package:sochitieu/models/money_move.dart';
import 'package:sochitieu/models/money_source.dart';
import 'package:sochitieu/screens/expense_form_screen.dart';
import 'package:sochitieu/screens/money_form_screen.dart';
import 'package:sochitieu/screens/source_detail_screen.dart';
import 'package:sochitieu/screens/source_form_screen.dart';
import 'package:sochitieu/screens/sources_screen.dart';

import 'test_helpers.dart';

void main() {
  late ExpenseDb db;
  final now = DateTime.now().millisecondsSinceEpoch;

  setUp(() async => db = await useFreshDb());

  /// Thẻ VIB: hạn mức 10.000.000, đang nợ 2.350.000 (còn được tiêu 7.650.000).
  Future<int> addCard(WidgetTester tester, {int? limit = 10000000, String name = 'Thẻ VIB'}) => dbRun(
      tester,
      () => db.insertSource(MoneySource(name: name, type: 'credit', createdAt: now, creditLimit: limit),
          openingBalance: -2350000));

  Future<int> addCardWith(WidgetTester tester, {required int opening, bool isDefault = false}) => dbRun(
      tester,
      () => db.insertSource(
          MoneySource(name: 'Thẻ VIB', type: 'credit', createdAt: now, creditLimit: 10000000, isDefault: isDefault),
          openingBalance: opening));

  Future<MoneySource> sourceOf(WidgetTester tester, int id) => dbRun(tester, () async => (await db.sourceById(id))!);

  Future<List<MoneyMove>> adjustsOf(WidgetTester tester, int id) => dbRun(
      tester, () async => (await db.allMoves()).where((m) => m.kind == MoveKind.adjust && m.toId == id).toList());

  // TextField trong form thẻ: 0 = tên, 1 = tổng hạn mức, 2 = hạn mức còn lại.
  Finder field(int i) => find.byType(TextField).at(i);

  group('form thẻ tín dụng', () {
    testWidgets('thẻ mới 10.000.000 / còn 7.650.000: app tính nợ 2.350.000, đã dùng 24%', (tester) async {
      usePhoneSize(tester);
      await openFromHost(tester, (c) => openSourceForm(c), SourceFormScreen);
      await tester.enterText(field(0), 'Thẻ VIB');
      await tester.tap(find.text('Thẻ tín dụng'));
      await tester.pump();
      expect(find.text('Tổng hạn mức của thẻ'), findsOneWidget);
      expect(find.text('Nhập tổng hạn mức để xem đã dùng bao nhiêu'), findsOneWidget);

      await tester.enterText(field(1), '10000000');
      await tester.enterText(field(2), '7650000');
      await tester.pump();
      expect(find.text('10.000.000'), findsOneWidget);
      expect(find.text('7.650.000'), findsOneWidget);
      expect(find.text('App tự tính: đang nợ'), findsOneWidget);
      expect(find.text('2.350.000 đ'), findsOneWidget);
      expect(find.text('Đã dùng 24% hạn mức'), findsOneWidget);
      final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
      await tester.scrollUntilVisible(find.text('Số nợ thẻ được trừ khỏi tổng tiền'), 200, scrollable: list);

      await saveAndWaitClosed(tester, 'Lưu nguồn tiền', SourceFormScreen);
      final card = (await dbRun(tester, db.sourcesWithBalance)).firstWhere((s) => s.name == 'Thẻ VIB');
      expect(card.type, 'credit');
      expect(card.creditLimit, 10000000);
      expect(card.balance, -2350000);
      final adj = await adjustsOf(tester, card.id!);
      expect(adj.single.amount, -2350000);
      expect(adj.single.note, 'Số dư ban đầu');
    });

    testWidgets('hạn mức còn lại lớn hơn tổng hạn mức: báo đỏ, không lưu', (tester) async {
      usePhoneSize(tester);
      await openFromHost(tester, (c) => openSourceForm(c), SourceFormScreen);
      await tester.enterText(field(0), 'Thẻ');
      await tester.tap(find.text('Thẻ tín dụng'));
      await tester.pump();
      await tester.enterText(field(1), '5000000');
      await tester.enterText(field(2), '6000000');
      await tester.pump();
      expect(find.text('Hạn mức còn lại không được lớn hơn tổng hạn mức.'), findsOneWidget);

      await tester.tap(find.text('Lưu nguồn tiền'));
      await tester.pump();
      expect(find.byType(SourceFormScreen), findsOneWidget);
      expect(await dbRun(tester, db.sourcesWithBalance), hasLength(1));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('thẻ chưa nhập tổng hạn mức: không lưu', (tester) async {
      usePhoneSize(tester);
      await openFromHost(tester, (c) => openSourceForm(c), SourceFormScreen);
      await tester.enterText(field(0), 'Thẻ');
      await tester.tap(find.text('Thẻ tín dụng'));
      await tester.pump();
      await tester.enterText(field(2), '1000000');
      await tester.tap(find.text('Lưu nguồn tiền'));
      await tester.pump();
      expect(find.text('Vui lòng nhập tổng hạn mức của thẻ'), findsWidgets);
      expect(find.byType(SourceFormScreen), findsOneWidget);
      expect(await dbRun(tester, db.sourcesWithBalance), hasLength(1));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('thẻ mới để trống hạn mức còn lại: không lưu', (tester) async {
      usePhoneSize(tester);
      await openFromHost(tester, (c) => openSourceForm(c), SourceFormScreen);
      await tester.enterText(field(0), 'Thẻ');
      await tester.tap(find.text('Thẻ tín dụng'));
      await tester.pump();
      await tester.enterText(field(1), '10000000');
      await tester.tap(find.text('Lưu nguồn tiền'));
      await tester.pump();
      expect(find.text('Vui lòng nhập hạn mức còn lại của thẻ'), findsWidgets);
      expect(find.byType(SourceFormScreen), findsOneWidget);
      expect(await dbRun(tester, db.sourcesWithBalance), hasLength(1));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('thẻ mới gõ 0 vào hạn mức còn lại: lưu với nợ bằng cả hạn mức', (tester) async {
      usePhoneSize(tester);
      await openFromHost(tester, (c) => openSourceForm(c), SourceFormScreen);
      await tester.enterText(field(0), 'Thẻ');
      await tester.tap(find.text('Thẻ tín dụng'));
      await tester.pump();
      await tester.enterText(field(1), '10000000');
      await tester.enterText(field(2), '0');
      await tester.pump();

      await saveAndWaitClosed(tester, 'Lưu nguồn tiền', SourceFormScreen);
      final card = (await dbRun(tester, db.sourcesWithBalance)).firstWhere((s) => s.name == 'Thẻ');
      expect(card.creditLimit, 10000000);
      expect(card.balance, -10000000);
    });

    testWidgets('thẻ trả dư (còn lại > hạn mức) chỉ đổi tên: không báo đỏ, lưu được, không ghi sổ cái', (tester) async {
      usePhoneSize(tester);
      final id = await addCardWith(tester, opening: 500000);
      final card = await sourceOf(tester, id);
      await openFromHost(tester, (c) => openSourceForm(c, source: card), SourceFormScreen);
      expect(find.text('10.500.000'), findsOneWidget);
      await tester.enterText(field(0), 'Thẻ VIB mới');
      await tester.pump();
      expect(find.text('Hạn mức còn lại không được lớn hơn tổng hạn mức.'), findsNothing);

      await saveAndWaitClosed(tester, 'Lưu thay đổi', SourceFormScreen);
      final after = await sourceOf(tester, id);
      expect(after.name, 'Thẻ VIB mới');
      expect(after.balance, 500000);
      expect(await adjustsOf(tester, id), hasLength(1));
    });

    testWidgets('sửa chỉ tổng hạn mức 10tr → 15tr: còn lại thành 12.650.000, không ghi sổ cái', (tester) async {
      usePhoneSize(tester);
      final id = await addCard(tester);
      final card = await sourceOf(tester, id);
      await openFromHost(tester, (c) => openSourceForm(c, source: card), SourceFormScreen);
      expect(find.text('10.000.000'), findsOneWidget);
      expect(find.text('7.650.000'), findsOneWidget);

      await tester.enterText(field(1), '15000000');
      await tester.pump();
      expect(find.text('12.650.000'), findsOneWidget);
      expect(find.text('2.350.000 đ'), findsOneWidget);

      await saveAndWaitClosed(tester, 'Lưu thay đổi', SourceFormScreen);
      final after = await sourceOf(tester, id);
      expect(after.creditLimit, 15000000);
      expect(after.available, 12650000);
      expect(await adjustsOf(tester, id), hasLength(1));
    });

    testWidgets('sửa hạn mức còn lại 7.650.000 → 7.000.000: ghi "Số dư thực tế" −650.000', (tester) async {
      usePhoneSize(tester);
      final id = await addCard(tester);
      final card = await sourceOf(tester, id);
      await openFromHost(tester, (c) => openSourceForm(c, source: card), SourceFormScreen);
      await tester.enterText(field(2), '7000000');
      await tester.pump();
      expect(find.text('3.000.000 đ'), findsOneWidget);
      expect(find.text('Đã dùng 30% hạn mức'), findsOneWidget);

      await saveAndWaitClosed(tester, 'Lưu thay đổi', SourceFormScreen);
      final adj = await adjustsOf(tester, id);
      expect(adj.last.amount, -650000);
      expect(adj.last.note, 'Số dư thực tế');
      expect((await sourceOf(tester, id)).available, 7000000);
    });

    testWidgets('thẻ cũ chưa có hạn mức: ô trống, nhập hạn mức thì tự điền còn lại = hạn mức − nợ', (tester) async {
      usePhoneSize(tester);
      final id = await addCard(tester, limit: null);
      final card = await sourceOf(tester, id);
      await openFromHost(tester, (c) => openSourceForm(c, source: card), SourceFormScreen);
      expect(find.text('Nhập tổng hạn mức để xem đã dùng bao nhiêu'), findsOneWidget);
      final limitText = tester.widget<TextField>(field(1)).controller!.text;
      final remainingText = tester.widget<TextField>(field(2)).controller!.text;
      expect((limitText, remainingText), ('', ''));

      await tester.enterText(field(1), '10000000');
      await tester.pump();
      expect(find.text('7.650.000'), findsOneWidget);
      await saveAndWaitClosed(tester, 'Lưu thay đổi', SourceFormScreen);
      final after = await sourceOf(tester, id);
      expect(after.creditLimit, 10000000);
      expect(after.balance, -2350000);
      expect(await adjustsOf(tester, id), hasLength(1));
    });

    testWidgets('đổi thẻ sang Ngân hàng: xoá hạn mức', (tester) async {
      usePhoneSize(tester);
      final id = await addCard(tester);
      final card = await sourceOf(tester, id);
      await openFromHost(tester, (c) => openSourceForm(c, source: card), SourceFormScreen);
      await tester.tap(find.text('Ngân hàng'));
      await tester.pump();
      expect(find.text('Số dư hiện tại'), findsOneWidget);
      await saveAndWaitClosed(tester, 'Lưu thay đổi', SourceFormScreen);
      final after = await sourceOf(tester, id);
      expect(after.type, 'bank');
      expect(after.creditLimit, isNull);
      expect(after.balance, -2350000);
    });
  });

  group('danh sách và chi tiết thẻ', () {
    testWidgets('danh sách: thẻ có hạn mức hiện "Còn được tiêu", thẻ cũ giữ kiểu cũ', (tester) async {
      usePhoneSize(tester);
      await addCard(tester);
      await addCard(tester, limit: null, name: 'Thẻ cũ');
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SourcesScreen())));
      await pumpUntil(tester, () => shows(find.text('Thẻ VIB')), reason: 'tải danh sách');
      expect(find.text('Còn được tiêu 7.650.000 đ'), findsOneWidget);
      expect(
          find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Đã dùng 24% hạn mức 10.000.000 đ'),
          findsOneWidget);
      expect(find.text('Thẻ tín dụng · Đang nợ'), findsOneWidget);
      expect(find.text('−2.350.000 đ'), findsNWidgets(2));
    });

    testWidgets('chi tiết thẻ: còn được tiêu, đang nợ, tổng hạn mức; Trả thẻ chuyển tiền vào thẻ', (tester) async {
      usePhoneSize(tester);
      final id = await addCard(tester);
      final cash = await dbRun(tester, () async => (await db.sourcesWithBalance()).first.id!);
      await tester.pumpWidget(MaterialApp(home: SourceDetailScreen(sourceId: id)));
      await pumpUntil(tester, () => shows(find.text('Còn được tiêu')), reason: 'tải chi tiết');
      expect(find.text('7.650.000 đ'), findsOneWidget);
      expect(find.text('Đã dùng 24% hạn mức'), findsOneWidget);
      expect(find.text('Đang nợ'), findsOneWidget);
      expect(find.text('2.350.000 đ'), findsOneWidget);
      expect(find.text('Tổng hạn mức'), findsOneWidget);
      expect(find.text('10.000.000 đ'), findsOneWidget);
      expect(find.text('Vào tháng này'), findsNothing);
      expect(find.text('Sửa hạn mức'), findsOneWidget);

      await tester.tap(find.text('Trả thẻ'));
      await pumpUntil(tester, () => shows(find.text('Lưu chuyển tiền')), reason: 'mở chuyển tiền');
      await tester.enterText(find.descendant(of: find.byType(MoneyFormScreen), matching: find.byType(TextField)).first,
          '3000000');
      await saveAndWaitClosed(tester, 'Lưu chuyển tiền', MoneyFormScreen);

      final move = (await dbRun(tester, db.allMoves)).last;
      expect((move.kind, move.fromId, move.toId, move.amount), (MoveKind.move, cash, id, 3000000));
      await pumpUntil(tester, () => shows(find.text('10.650.000 đ')), reason: 'tải lại chi tiết');
      expect(find.text('Trả thẻ từ Tiền mặt'), findsOneWidget);
      expect(find.text('+3.000.000 đ'), findsOneWidget);
      // "Trả thẻ" là cả nút hành động và loại dòng lịch sử.
      expect(find.text('Trả thẻ'), findsNWidgets(2));
    });
  });

  group('trả thẻ và thẻ đã xoá', () {
    testWidgets('Trả thẻ khi thẻ là nguồn mặc định: chuyển từ Tiền mặt vào thẻ', (tester) async {
      usePhoneSize(tester);
      final cash = await dbRun(tester, () async => (await db.sourcesWithBalance()).single.id!);
      final id = await addCardWith(tester, opening: -2350000, isDefault: true);
      expect((await sourceOf(tester, id)).isDefault, isTrue);
      await tester.pumpWidget(MaterialApp(home: SourceDetailScreen(sourceId: id)));
      await pumpUntil(tester, () => shows(find.text('Trả thẻ')), reason: 'tải chi tiết');

      await tester.tap(find.text('Trả thẻ'));
      await pumpUntil(tester, () => shows(find.text('Lưu chuyển tiền')), reason: 'mở chuyển tiền');
      await tester.enterText(
          find.descendant(of: find.byType(MoneyFormScreen), matching: find.byType(TextField)).first, '1000000');
      await saveAndWaitClosed(tester, 'Lưu chuyển tiền', MoneyFormScreen);

      final move = (await dbRun(tester, db.allMoves)).last;
      expect((move.kind, move.fromId, move.toId), (MoveKind.move, cash, id));
    });

    testWidgets('thẻ đã xoá: vẫn hiện đầu thẻ, không có Trả thẻ / Sửa hạn mức', (tester) async {
      usePhoneSize(tester);
      final id = await addCard(tester);
      await dbRun(tester, () => db.archiveSource(id));
      await tester.pumpWidget(MaterialApp(home: SourceDetailScreen(sourceId: id)));
      await pumpUntil(tester, () => shows(find.text('Còn được tiêu')), reason: 'tải chi tiết');
      expect(find.text('Đã dùng 24% hạn mức'), findsOneWidget);
      expect(find.text('Tổng hạn mức'), findsOneWidget);
      expect(find.text('Trả thẻ'), findsNothing);
      expect(find.text('Sửa hạn mức'), findsNothing);
      expect(find.byTooltip('Sửa thẻ và hạn mức'), findsNothing);
    });
  });

  group('form chi tiêu bằng thẻ', () {
    Future<void> openWithCard(WidgetTester tester, int card) async {
      usePhoneSize(tester);
      await openFromHost(tester, (c) => openExpenseForm(c, sourceId: card), ExpenseFormScreen);
      await pumpUntil(tester, () => shows(find.textContaining('Sau khi lưu')), reason: 'tải nguồn tiền');
    }

    testWidgets('50.000: thẻ còn được tiêu 7.600.000; ô chọn hiện "còn 7.650.000 đ"', (tester) async {
      final card = await addCard(tester);
      await openWithCard(tester, card);
      expect(find.text('còn 7.650.000 đ'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '50000');
      await tester.pump();
      expect(find.text('Sau khi lưu, thẻ còn được tiêu 7.600.000 đ'), findsOneWidget);
      expect(find.textContaining('Vượt hạn mức'), findsNothing);
    });

    testWidgets('8.000.000 vượt hạn mức: cảnh báo đỏ nhưng vẫn lưu được', (tester) async {
      final card = await addCard(tester);
      await openWithCard(tester, card);
      await tester.enterText(find.byType(TextField).first, '8000000');
      await tester.pump();
      expect(find.text('Vượt hạn mức 350.000 đ. Ngân hàng có thể từ chối giao dịch.'), findsOneWidget);
      expect(find.text('Sau khi lưu, thẻ nợ 10.350.000 đ'), findsOneWidget);

      await saveAndWaitClosed(tester, 'Lưu chi tiêu', ExpenseFormScreen);
      expect((await sourceOf(tester, card)).available, -350000);
    });
  });

  test('câu "Sau khi lưu" và cảnh báo của thẻ có hạn mức', () {
    final card = MoneySource(name: 'Thẻ VIB', type: 'credit', createdAt: 0, creditLimit: 10000000);
    final ok = afterSaveParts(card, -2400000);
    expect('${ok.text}${ok.amount}', 'Sau khi lưu, thẻ còn được tiêu 7.600.000 đ');
    expect(ok.negative, isFalse);
    expect(overLimitText(card, -2400000), isNull);
    expect(overLimitText(card, -10350000), 'Vượt hạn mức 350.000 đ. Ngân hàng có thể từ chối giao dịch.');
    final old = MoneySource(name: 'Thẻ cũ', type: 'credit', createdAt: 0);
    expect(overLimitText(old, -99999999), isNull);
  });
}
