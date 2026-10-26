import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sochitieu/data/payment_apps.dart';

/// Kênh "sochitieu/payment_apps": tên hàm và tham số phải khớp MainActivity.kt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('sochitieu/payment_apps');
  final apps = ChannelPaymentApps();
  final icon = Uint8List.fromList([137, 80, 78, 71]);
  final calls = <MethodCall>[];

  void reply(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('dùng đúng tên kênh của MainActivity.kt', () {
    expect(ChannelPaymentApps.channel.name, 'sochitieu/payment_apps');
  });

  test('listApps: đọc tên, tên gói, biểu tượng (có hoặc không); bỏ dòng sai dạng', () async {
    reply((_) => [
          {'label': 'MoMo', 'package': 'com.mservice.momotransfer', 'icon': icon},
          {'label': 'Zalo', 'package': 'com.zing.zalo', 'icon': null},
          {'label': 'Hỏng', 'package': null, 'icon': null},
          'không phải map',
          {'label': '', 'package': 'com.no.label'},
        ]);
    final list = await apps.listApps();
    expect(calls.single.method, 'listApps');
    expect(calls.single.arguments, isNull);
    expect(list.map((a) => (a.label, a.package)), [
      ('MoMo', 'com.mservice.momotransfer'),
      ('Zalo', 'com.zing.zalo'),
      ('com.no.label', 'com.no.label'),
    ]);
    expect(list[0].icon, equals(icon));
    expect(list[1].icon, isNull);
    expect(list[2].icon, isNull);
  });

  test('appInfo: gửi tham số "package", đọc kết quả; null khi ứng dụng không còn', () async {
    reply((call) => call.arguments['package'] == 'com.zing.zalo'
        ? {'label': 'Zalo', 'package': 'com.zing.zalo', 'icon': icon}
        : null);
    final zalo = await apps.appInfo('com.zing.zalo');
    expect(calls.last.method, 'appInfo');
    expect(calls.last.arguments, {'package': 'com.zing.zalo'});
    expect((zalo!.label, zalo.package), ('Zalo', 'com.zing.zalo'));
    expect(zalo.icon, equals(icon));
    expect(await apps.appInfo('com.gone'), isNull);
  });

  test('launch: gửi tham số "package", trả về kết quả của Android', () async {
    reply((call) => call.arguments['package'] == 'com.zing.zalo');
    expect(await apps.launch('com.zing.zalo'), isTrue);
    expect(calls.last.method, 'launch');
    expect(calls.last.arguments, {'package': 'com.zing.zalo'});
    expect(await apps.launch('com.gone'), isFalse);
  });

  test('lỗi từ Android: [] / null / false, không ném lỗi', () async {
    reply((_) => throw PlatformException(code: 'payment_apps', message: 'OutOfMemoryError'));
    expect(await apps.listApps(), isEmpty);
    expect(await apps.appInfo('com.zing.zalo'), isNull);
    expect(await apps.launch('com.zing.zalo'), isFalse);
  });

  test('dữ liệu sai kiểu: [] / null / false', () async {
    reply((_) => 'sai kiểu');
    expect(await apps.listApps(), isEmpty);
    expect(await apps.appInfo('com.zing.zalo'), isNull);
    expect(await apps.launch('com.zing.zalo'), isFalse);
  });

  test('không có kênh (chạy trên máy tính): [] / null / false', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await apps.listApps(), isEmpty);
    expect(await apps.appInfo('com.zing.zalo'), isNull);
    expect(await apps.launch('com.zing.zalo'), isFalse);
  });
}
