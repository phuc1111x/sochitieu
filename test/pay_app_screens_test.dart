import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sochitieu/data/expense_db.dart';
import 'package:sochitieu/data/payment_apps.dart';
import 'package:sochitieu/models/expense.dart';
import 'package:sochitieu/models/money_source.dart';
import 'package:sochitieu/screens/expense_form_screen.dart';
import 'package:sochitieu/screens/source_form_screen.dart';
import 'package:sochitieu/utils/format.dart';
import 'package:sochitieu/widgets/app_picker.dart';

import 'test_helpers.dart';

/// Ứng dụng đã cài giả: không gọi Android, ghi lại các lần mở.
class FakePaymentApps extends PaymentApps {
  FakePaymentApps(this.installed);

  final List<InstalledApp> installed;
  final launched = <String>[];
  bool launchOk = true;

  /// Đặt để appInfo chờ tới khi hoàn thành (giả lập đọc ứng dụng chậm).
  Completer<void>? appInfoGate;

  /// true: listApps báo lỗi.
  bool listFails = false;

  @override
  Future<List<InstalledApp>> listApps() async {
    if (listFails) throw StateError('listApps');
    return [...installed]..sort((a, b) => a.label.compareTo(b.label));
  }

  /// true: appInfo báo lỗi.
  bool infoFails = false;

  @override
  Future<InstalledApp?> appInfo(String package) async {
    await appInfoGate?.future;
    if (infoFails) throw StateError('appInfo');
    return installed.where((a) => a.package == package).firstOrNull;
  }

  @override
  Future<bool> launch(String package) async {
    launched.add(package);
    return launchOk;
  }
}

const momo = 'com.mservice.momotransfer';
const zalo = 'com.zing.zalo';

void main() {
  late ExpenseDb db;
  late FakePaymentApps apps;
  final today = dateOnly(DateTime.now());
  final now = DateTime.now().millisecondsSinceEpoch;

  setUp(() async {
    db = await useFreshDb();
    apps = FakePaymentApps(const [
      InstalledApp(label: 'MoMo', package: momo),
      InstalledApp(label: 'Zalo', package: zalo),
      InstalledApp(label: 'VCB Digibank', package: 'com.VCB'),
    ]);
    final original = PaymentApps.instance;
    PaymentApps.instance = apps;
    addTearDown(() => PaymentApps.instance = original);
  });

  /// "Ví MoMo" (ví điện tử) số dư 300.000, gắn ứng dụng [app]. Trả về id.
  Future<int> addWallet(WidgetTester tester, {String? app = momo, int balance = 300000}) => dbRun(
      tester,
      () => db.insertSource(MoneySource(name: 'Ví MoMo', type: 'ewallet', createdAt: now, appPackage: app),
          openingBalance: balance));

  Future<MoneySource> sourceOf(WidgetTester tester, int id) => dbRun(tester, () async => (await db.sourceById(id))!);

  Finder scrollable() => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

  /// Cuộn form tới [f] và đưa lên đầu màn (không bị thanh nút lưu che).
  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: scrollable());
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  group('form nguồn tiền: ứng dụng thanh toán', () {
    Future<void> openEdit(WidgetTester tester, int id) async {
      usePhoneSize(tester);
      final source = await sourceOf(tester, id);
      await openFromHost(tester, (c) => openSourceForm(c, source: source), SourceFormScreen);
      await tester.pump();
    }

    testWidgets('gắn MoMo từ danh sách ứng dụng đã cài, tìm kiếm được', (tester) async {
      final id = await addWallet(tester, app: null);
      await openEdit(tester, id);
      await reveal(tester, find.text('Chọn ứng dụng'));
      expect(find.text('Ứng dụng thanh toán (không bắt buộc)'), findsOneWidget);
      expect(find.textContaining('ghi khoản chi xong sẽ mở ứng dụng này'), findsOneWidget);

      await tester.tap(find.text('Chọn ứng dụng'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn ứng dụng thanh toán'), findsOneWidget);
      expect(find.text('Các ứng dụng đã cài trên điện thoại'), findsOneWidget);
      expect(find.text('MoMo'), findsOneWidget);
      expect(find.text('Zalo'), findsOneWidget);
      expect(find.text('Bỏ liên kết'), findsNothing, reason: 'chưa gắn thì không có Bỏ liên kết');

      await tester.enterText(find.widgetWithText(TextField, 'Tìm ứng dụng'), 'mo');
      await tester.pump();
      expect(find.text('MoMo'), findsOneWidget);
      expect(find.text('Zalo'), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, 'mo'), 'xyz');
      await tester.pump();
      expect(find.text('Không tìm thấy ứng dụng'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'xyz'), '');
      await tester.pump();

      await tester.tap(find.text('MoMo'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn ứng dụng thanh toán'), findsNothing);
      expect(find.text('MoMo'), findsOneWidget);
      expect(find.text('Mở sau khi lưu khoản chi'), findsOneWidget);
      expect(find.text('Đổi'), findsOneWidget);

      await saveAndWaitClosed(tester, 'Lưu thay đổi', SourceFormScreen);
      expect((await sourceOf(tester, id)).appPackage, momo);
    });

    testWidgets('bỏ liên kết', (tester) async {
      final id = await addWallet(tester);
      await openEdit(tester, id);
      await reveal(tester, find.text('Mở sau khi lưu khoản chi'));
      expect(find.text('MoMo'), findsOneWidget);
      await tester.tap(find.text('Đổi'));
      await tester.pumpAndSettle();
      // Ứng dụng đang gắn có dấu ✓ trong danh sách.
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.byIcon(Icons.check)), findsOneWidget);
      await tester.tap(find.text('Bỏ liên kết'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn ứng dụng'), findsOneWidget);

      await saveAndWaitClosed(tester, 'Lưu thay đổi', SourceFormScreen);
      expect((await sourceOf(tester, id)).appPackage, isNull);
    });

    testWidgets('tiền mặt: không có mục ứng dụng; đổi loại sang tiền mặt thì bỏ liên kết', (tester) async {
      final id = await addWallet(tester);
      await openEdit(tester, id);
      expect(find.text('Ứng dụng thanh toán (không bắt buộc)', skipOffstage: false), findsOneWidget);
      await tester.tap(find.text('Tiền mặt'));
      await tester.pump();
      expect(find.text('Ứng dụng thanh toán (không bắt buộc)', skipOffstage: false), findsNothing);

      await saveAndWaitClosed(tester, 'Lưu thay đổi', SourceFormScreen);
      final s = await sourceOf(tester, id);
      expect(s.type, 'cash');
      expect(s.appPackage, isNull);
    });

    testWidgets('thêm nguồn mới mặc định là tiền mặt: chưa có mục ứng dụng, chọn Ngân hàng thì hiện', (tester) async {
      usePhoneSize(tester);
      await openFromHost(tester, (c) => openSourceForm(c), SourceFormScreen);
      expect(find.text('Ứng dụng thanh toán (không bắt buộc)', skipOffstage: false), findsNothing);
      await tester.enterText(find.byType(TextField).at(0), 'VCB');
      await tester.tap(find.text('Ngân hàng'));
      await tester.pump();
      await reveal(tester, find.text('Chọn ứng dụng'));
      await tester.tap(find.text('Chọn ứng dụng'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VCB Digibank'));
      await tester.pumpAndSettle();
      await saveAndWaitClosed(tester, 'Lưu nguồn tiền', SourceFormScreen);
      final vcb = (await dbRun(tester, db.sourcesWithBalance)).firstWhere((s) => s.name == 'VCB');
      expect(vcb.appPackage, 'com.VCB');
    });

    testWidgets('đang đọc ứng dụng: hiện vòng xoay; đọc lỗi thì không treo, coi như không còn trên máy',
        (tester) async {
      final gate = apps.appInfoGate = Completer<void>();
      apps.infoFails = true;
      final id = await addWallet(tester);
      await openEdit(tester, id);
      // Có vòng xoay nên không dùng pumpAndSettle.
      await tester.scrollUntilVisible(find.text('Đang đọc ứng dụng…'), 200, scrollable: scrollable());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Đang đọc ứng dụng…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Ứng dụng không còn trên máy'), findsOneWidget);
    });

    testWidgets('ứng dụng đã gỡ: "Ứng dụng không còn trên máy", chọn lại được', (tester) async {
      final id = await addWallet(tester, app: 'com.gone.app');
      await openEdit(tester, id);
      await reveal(tester, find.text('Ứng dụng không còn trên máy'));
      await tester.tap(find.text('Ứng dụng không còn trên máy'));
      await tester.pumpAndSettle();
      expect(find.text('Bỏ liên kết'), findsOneWidget);
      await tester.tap(find.text('Zalo'));
      await tester.pumpAndSettle();
      expect(find.text('Ứng dụng không còn trên máy'), findsNothing);
      await saveAndWaitClosed(tester, 'Lưu thay đổi', SourceFormScreen);
      expect((await sourceOf(tester, id)).appPackage, zalo);
    });
  });

  group('form chi tiêu: lưu & mở ứng dụng', () {
    Future<void> openAdd(WidgetTester tester, {int? sourceId}) async {
      usePhoneSize(tester);
      await openFromHost(tester, (c) => openExpenseForm(c, sourceId: sourceId), ExpenseFormScreen);
      await pumpUntil(tester, () => shows(find.textContaining('Sau khi lưu')), reason: 'tải nguồn tiền');
      await tester.pump();
    }

    /// Bấm [button], chờ form đóng, trả về câu SnackBar rồi cho SnackBar chạy hết.
    Future<void> tapAndExpectClosed(WidgetTester tester, String button, String snack) async {
      await tester.tap(find.text(button));
      await pumpUntil(tester, () => !shows(find.byType(ExpenseFormScreen)), reason: 'đóng form');
      expect(find.text(snack), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('nguồn có gắn MoMo: "Chỉ lưu" + "Lưu & mở MoMo"; bấm lưu & mở thì lưu rồi mở MoMo', (tester) async {
      final id = await addWallet(tester);
      await openAdd(tester, sourceId: id);
      await pumpUntil(tester, () => shows(find.text('Lưu & mở MoMo')), reason: 'đọc ứng dụng');
      expect(find.text('Chỉ lưu'), findsOneWidget);
      expect(find.text('Lưu chi tiêu'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '45000');
      await tester.pump();
      expect(find.text('Sau khi lưu, Ví MoMo còn 255.000 đ'), findsOneWidget);

      await tapAndExpectClosed(tester, 'Lưu & mở MoMo', 'Đã thêm 45.000 đ');
      expect(apps.launched, [momo]);
      final saved = (await dbRun(tester, db.all)).single;
      expect((saved.amount, saved.sourceId), (45000, id));
      expect((await sourceOf(tester, id)).balance, 255000);
    });

    testWidgets('"Chỉ lưu": lưu như cũ, không mở ứng dụng', (tester) async {
      final id = await addWallet(tester);
      await openAdd(tester, sourceId: id);
      await pumpUntil(tester, () => shows(find.text('Chỉ lưu')), reason: 'đọc ứng dụng');
      await tester.enterText(find.byType(TextField).first, '45000');
      await tapAndExpectClosed(tester, 'Chỉ lưu', 'Đã thêm 45.000 đ');
      expect(apps.launched, isEmpty);
      expect((await dbRun(tester, db.all)).single.amount, 45000);
    });

    testWidgets('mở ứng dụng thất bại: khoản chi vẫn được lưu, báo "Không mở được MoMo"', (tester) async {
      apps.launchOk = false;
      final id = await addWallet(tester);
      await openAdd(tester, sourceId: id);
      await pumpUntil(tester, () => shows(find.text('Lưu & mở MoMo')), reason: 'đọc ứng dụng');
      await tester.enterText(find.byType(TextField).first, '45000');
      await tapAndExpectClosed(tester, 'Lưu & mở MoMo', 'Đã lưu. Không mở được MoMo.');
      expect(apps.launched, [momo]);
      expect((await dbRun(tester, db.all)).single.sourceId, id);
    });

    testWidgets('nguồn không gắn ứng dụng, hoặc ứng dụng đã gỡ: một nút "Lưu chi tiêu"', (tester) async {
      final gone = await addWallet(tester, app: 'com.gone.app');
      await openAdd(tester, sourceId: gone);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Lưu chi tiêu'), findsOneWidget);
      expect(find.text('Chỉ lưu'), findsNothing);

      // Đổi sang Tiền mặt (không gắn) rồi sang lại: vẫn một nút.
      await tester.tap(find.text('Ví MoMo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tiền mặt').last);
      await tester.pumpAndSettle();
      expect(find.text('Lưu chi tiêu'), findsOneWidget);
      expect(find.text('Chỉ lưu'), findsNothing);
    });

    testWidgets('đổi nguồn trong form: nút đi theo nguồn đang chọn', (tester) async {
      await addWallet(tester);
      await openAdd(tester);
      expect(find.text('Lưu chi tiêu'), findsOneWidget, reason: 'mặc định Tiền mặt');
      await tester.tap(find.text('Tiền mặt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ví MoMo').last);
      await tester.pumpAndSettle();
      expect(find.text('Lưu & mở MoMo'), findsOneWidget);
    });

    testWidgets('tiền mặt còn sót tên gói trong database: không có nút mở ứng dụng', (tester) async {
      final cash = await dbRun(tester, () async {
        final id = (await db.sourcesWithBalance()).single.id!;
        await (await db.db).update('sources', {'app_package': momo}, where: 'id = ?', whereArgs: [id]);
        return id;
      });
      await openAdd(tester, sourceId: cash);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Lưu chi tiêu'), findsOneWidget);
      expect(find.text('Chỉ lưu'), findsNothing);
    });

    testWidgets('sửa khoản chi: "Lưu thay đổi", không mở ứng dụng', (tester) async {
      final id = await addWallet(tester);
      await dbRun(
          tester,
          () => db.insert(Expense(
              amount: 45000, category: 'food', date: today, sourceId: id, createdAt: now, updatedAt: now)));
      final e = (await dbRun(tester, db.all)).single;
      usePhoneSize(tester);
      await openFromHost(tester, (c) => openExpenseForm(c, expense: e), ExpenseFormScreen);
      await pumpUntil(tester, () => shows(find.textContaining('Sau khi lưu')), reason: 'tải nguồn tiền');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Lưu thay đổi'), findsOneWidget);
      expect(find.text('Chỉ lưu'), findsNothing);
      expect(find.textContaining('Lưu & mở'), findsNothing);
      await tapAndExpectClosed(tester, 'Lưu thay đổi', 'Đã lưu thay đổi');
      expect(apps.launched, isEmpty);
    });

    testWidgets('thêm mới: chưa đọc xong ứng dụng thì chưa bấm lưu được, đọc xong thì hiện cặp nút', (tester) async {
      final gate = apps.appInfoGate = Completer<void>();
      final id = await addWallet(tester);
      await openAdd(tester, sourceId: id);
      await tester.enterText(find.byType(TextField).first, '45000');
      await tester.pump();
      final single = find.ancestor(of: find.text('Lưu chi tiêu'), matching: find.byWidgetPredicate((w) => w is FilledButton));
      expect(single, findsOneWidget);
      expect(tester.widget<FilledButton>(single).onPressed, isNull);
      await tester.tap(find.text('Lưu chi tiêu'), warnIfMissed: false);
      await tester.pump();
      expect(find.byType(ExpenseFormScreen), findsOneWidget);
      expect(await dbRun(tester, db.all), isEmpty);

      gate.complete();
      await pumpUntil(tester, () => shows(find.text('Lưu & mở MoMo')), reason: 'đọc ứng dụng');
      expect(find.text('Lưu chi tiêu'), findsNothing);
      final pay = find.ancestor(of: find.text('Lưu & mở MoMo'), matching: find.byType(FilledButton));
      expect(tester.widget<FilledButton>(pay).onPressed, isNotNull);
      final only = find.ancestor(of: find.text('Chỉ lưu'), matching: find.byType(OutlinedButton));
      expect(tester.widget<OutlinedButton>(only).onPressed, isNotNull);
    });

    testWidgets('không đủ tiền: cảnh báo đỏ, vẫn lưu được', (tester) async {
      final id = await addWallet(tester);
      await openAdd(tester, sourceId: id);
      await tester.enterText(find.byType(TextField).first, '500000');
      await tester.pump();
      expect(find.text('Sau khi lưu, Ví MoMo âm 200.000 đ'), findsOneWidget);
      expect(find.text('Không đủ tiền trong Ví MoMo, thiếu 200.000 đ.'), findsOneWidget);
      expect(find.text('Chọn nguồn khác ở trên. Vẫn lưu được nếu số dư trong app chưa cập nhật.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '300000');
      await tester.pump();
      expect(find.textContaining('Không đủ tiền'), findsNothing, reason: 'vừa đủ thì không cảnh báo');

      await tester.enterText(find.byType(TextField).first, '500000');
      await pumpUntil(tester, () => shows(find.text('Chỉ lưu')), reason: 'đọc ứng dụng');
      await tapAndExpectClosed(tester, 'Chỉ lưu', 'Đã thêm 500.000 đ');
      expect((await sourceOf(tester, id)).balance, -200000);
    });
  });

  group('bảng chọn ứng dụng', () {
    Future<void> openPicker(WidgetTester tester, {String? selected}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(onPressed: () => showAppPicker(context, selected: selected), child: const Text('Mở')),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();
    }

    testWidgets('tìm không phân biệt dấu, tìm cả theo tên gói', (tester) async {
      usePhoneSize(tester);
      PaymentApps.instance = FakePaymentApps(const [
        InstalledApp(label: 'Ví MoMo', package: momo),
        InstalledApp(label: 'Ngân hàng Đông Á', package: 'com.dongabank'),
        InstalledApp(label: 'Zalo', package: zalo),
      ]);
      await openPicker(tester);
      final search = find.byType(TextField);

      await tester.enterText(search, 'vi');
      await tester.pump();
      expect(find.text('Ví MoMo'), findsOneWidget);
      expect(find.text('Zalo'), findsNothing);

      await tester.enterText(search, 'ngan hang');
      await tester.pump();
      expect(find.text('Ngân hàng Đông Á'), findsOneWidget);
      expect(find.text('Ví MoMo'), findsNothing);

      await tester.enterText(search, 'DONG A');
      await tester.pump();
      expect(find.text('Ngân hàng Đông Á'), findsOneWidget);

      await tester.enterText(search, 'mservice');
      await tester.pump();
      expect(find.text('Ví MoMo'), findsOneWidget);
      expect(find.text('Ngân hàng Đông Á'), findsNothing);
    });

    testWidgets('đọc danh sách lỗi: "Không đọc được danh sách ứng dụng"', (tester) async {
      usePhoneSize(tester);
      apps.listFails = true;
      await openPicker(tester);
      expect(find.text('Không đọc được danh sách ứng dụng'), findsOneWidget);
      expect(find.text('Không tìm thấy ứng dụng'), findsNothing);
    });

    testWidgets('màn nhỏ 360x560, bàn phím mở: bảng không bị tràn', (tester) async {
      tester.view.physicalSize = const Size(1080, 1680);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      PaymentApps.instance = FakePaymentApps([
        for (var i = 0; i < 30; i++) InstalledApp(label: 'Ứng dụng $i', package: 'com.app$i'),
      ]);
      await openPicker(tester, selected: 'com.app3');
      expect(find.text('Bỏ liên kết'), findsOneWidget);

      // Bàn phím cao vừa (còn 260) rồi rất cao (còn 140): không có lỗi tràn ở cả hai dạng.
      for (final keyboard in [300.0, 420.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Chọn ứng dụng thanh toán'), findsOneWidget);
        expect(find.text('Bỏ liên kết'), findsNothing, reason: 'bàn phím mở thì ẩn nút Bỏ liên kết');
        await tester.enterText(find.byType(TextField), 'ung dung 2');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Dạng thấp: dòng có thể nằm ngay dưới mép, cuộn tới được (đã dựng nhưng chưa hiện).
        expect(find.text('Ứng dụng 2', skipOffstage: false), findsOneWidget);
        expect(find.text('Ứng dụng 1', skipOffstage: false), findsNothing);
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
      }
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Bỏ liên kết'), findsOneWidget);
    });
  });

  test('tìm ứng dụng: bỏ dấu tiếng Việt cả hai phía', () {
    expect(foldVietnamese('Ngân Hàng Đông Á'), 'ngan hang dong a');
    expect(foldVietnamese('Ví điện tử'), 'vi dien tu');
    expect(appMatches(const InstalledApp(label: 'Ví MoMo', package: momo), 'vi'), isTrue);
    expect(appMatches(const InstalledApp(label: 'Vietcombank', package: 'com.VCB'), 'ví'), isTrue);
    expect(appMatches(const InstalledApp(label: 'Ngân hàng ACB', package: 'mobile.acb.com.vn'), 'ngan hang'), isTrue);
    expect(appMatches(const InstalledApp(label: 'Zalo', package: zalo), 'momo'), isFalse);
    expect(appMatches(const InstalledApp(label: 'Zalo', package: zalo), '  '), isTrue);
  });

  test('câu "Không đủ tiền": chỉ nguồn thường bị âm, thẻ tín dụng không', () {
    MoneySource src(String type) => MoneySource(name: 'Ví MoMo', type: type, createdAt: 0);
    expect(shortText(src('ewallet'), -200000), 'Không đủ tiền trong Ví MoMo, thiếu 200.000 đ.');
    expect(shortText(src('cash'), 0), isNull);
    expect(shortText(src('bank'), 5), isNull);
    expect(shortText(src('credit'), -200000), isNull);
    final card = MoneySource(name: 'Thẻ', type: 'credit', createdAt: 0, creditLimit: 1000000);
    expect(shortText(card, -2000000), isNull);
    expect(overLimitText(card, -2000000), isNotNull);
  });
}
