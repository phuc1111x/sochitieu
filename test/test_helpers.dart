import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sochitieu/data/expense_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tạo database mới trong thư mục tạm và gắn làm `ExpenseDb.instance` cho một test.
/// Gọi trong `setUp`; database cũ được trả lại và thư mục tạm bị xoá khi test xong.
Future<ExpenseDb> useFreshDb() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('sochitieu_widget');
  final original = ExpenseDb.instance;
  final db = ExpenseDb.forTesting(databaseFactoryFfi, p.join(dir.path, 'test.db'));
  // Mở database ngay ở đây (thời gian thật). Nếu để widget mở lần đầu trong fake async
  // của testWidgets thì lúc đóng database sẽ treo.
  await db.db;
  ExpenseDb.instance = db;
  addTearDown(() async {
    ExpenseDb.instance = original;
    await db.close();
    await dir.delete(recursive: true);
  });
  return db;
}

/// Màn hình cỡ điện thoại (360 x 800) để mọi phần chính của form nằm trong khung.
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Chạy một thao tác database thật (sqflite FFI cần thời gian thật, không chạy trong fake async).
Future<T> dbRun<T>(WidgetTester tester, Future<T> Function() action) async => (await tester.runAsync(action)) as T;

/// Cho thời gian thật trôi và vẽ lại cho tới khi [done] đúng (tối đa khoảng 200 vòng).
Future<void> pumpUntil(WidgetTester tester, bool Function() done, {String reason = ''}) async {
  for (var i = 0; i < 200; i++) {
    if (done()) return;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!done()) fail('Hết thời gian chờ: $reason');
}

bool shows(Finder f) => f.evaluate().isNotEmpty;

/// Mở một màn từ nút "Mở" trên màn trống, giống như người dùng chuyển màn.
Future<void> openFromHost(WidgetTester tester, void Function(BuildContext context) open, Type screen) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(child: TextButton(onPressed: () => open(context), child: const Text('Mở'))),
      ),
    ),
  ));
  await tester.tap(find.text('Mở'));
  await pumpUntil(tester, () => shows(find.byType(screen)), reason: 'mở $screen');
}

/// Bấm nút lưu rồi chờ màn [screen] đóng lại (dữ liệu đã ghi xong).
Future<void> saveAndWaitClosed(WidgetTester tester, String button, Type screen) async {
  await tester.tap(find.text(button));
  await pumpUntil(tester, () => !shows(find.byType(screen)), reason: 'đóng $screen');
  // Cho SnackBar báo kết quả chạy hết để không còn timer treo khi test kết thúc.
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(seconds: 1));
}
