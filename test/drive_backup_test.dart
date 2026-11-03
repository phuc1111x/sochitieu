import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sochitieu/data/drive_backup.dart';
import 'package:sochitieu/screens/backup_screen.dart';
import 'package:sochitieu/theme.dart';

import 'test_helpers.dart';

/// Google giả: ghi lại mọi lần app gọi đăng nhập / xin quyền, không bao giờ cấp token.
class FakeGoogle extends GoogleSignInPlatform {
  final calls = <String>[];
  final authorizeRequests = <AuthorizationRequestDetails>[];

  @override
  Future<void> init(InitParameters params) async => calls.add('init');

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(AttemptLightweightAuthenticationParameters params) {
    calls.add('lightweight');
    return null;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) {
    calls.add('authenticate');
    throw const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
      ClientAuthorizationTokensForScopesParameters params) async {
    calls.add('authorize');
    authorizeRequests.add(params.request);
    return null;
  }

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
          ServerAuthorizationTokensForScopesParameters params) async =>
      null;

  @override
  Future<void> signOut(SignOutParams params) async => calls.add('signOut');

  @override
  Future<void> disconnect(DisconnectParams params) async => calls.add('disconnect');
}

void main() {
  late FakeGoogle google;
  final backup = DriveBackup.instance;

  /// Một lần mở app mới với các cài đặt đã lưu trên máy.
  Future<void> openApp(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    google = FakeGoogle();
    GoogleSignInPlatform.instance = google;
    backup.resetForTesting();
    await backup.init();
  }

  Future<void> pumpBackupTab(WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const Scaffold(body: BackupScreen())));
    await tester.pump();
  }

  group('mở app không đăng nhập Google', () {
    test('đã kết nối: chỉ khởi tạo, không đăng nhập', () async {
      await openApp({'drive_connected': true, 'drive_email': 'chu@gmail.com', 'wifi_only': false});
      expect(google.calls, ['init']);
      expect(backup.connected.value, isTrue);
      expect(backup.email.value, 'chu@gmail.com');
    });

    test('tự sao lưu xin quyền im lặng cho đúng tài khoản; thiếu quyền thì bỏ qua, không hiện gì', () async {
      await openApp({'drive_connected': true, 'drive_email': 'chu@gmail.com', 'wifi_only': false});
      await backup.maybeAutoBackup();
      expect(google.calls, ['init', 'authorize']);
      final request = google.authorizeRequests.single;
      expect(request.promptIfUnauthorized, isFalse);
      expect(request.email, 'chu@gmail.com');
      expect(backup.lastBackup.value, isNull);
    });

    test('chưa kết nối: tự sao lưu không gọi Google', () async {
      await openApp({'wifi_only': false});
      await backup.maybeAutoBackup();
      expect(google.calls, ['init']);
    });

    test('ngắt kết nối: xin quyền im lặng rồi thu hồi, xoá email đã lưu', () async {
      await openApp({'drive_connected': true, 'drive_email': 'chu@gmail.com'});
      await backup.disconnect();
      expect(google.calls, ['init', 'authorize', 'disconnect']);
      expect(google.authorizeRequests.single.promptIfUnauthorized, isFalse);
      expect(backup.connected.value, isFalse);
      expect(backup.email.value, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('drive_connected'), isFalse);
      expect(prefs.getString('drive_email'), isNull);
    });
  });

  group('tab Sao lưu', () {
    testWidgets('hiện email của lần đồng bộ gần nhất mà không đăng nhập', (tester) async {
      await tester.runAsync(() => openApp({'drive_connected': true, 'drive_email': 'chu@gmail.com'}));
      await pumpBackupTab(tester);
      expect(find.text('Đã kết nối Google Drive'), findsOneWidget);
      expect(find.text('chu@gmail.com'), findsOneWidget);
      expect(google.calls, ['init']);
    });

    testWidgets('máy kết nối từ bản cũ (chưa lưu email) vẫn hiện đã kết nối', (tester) async {
      await tester.runAsync(() => openApp({'drive_connected': true}));
      await pumpBackupTab(tester);
      expect(find.text('Đã kết nối Google Drive'), findsOneWidget);
      expect(find.text('Sao lưu ngay'), findsOneWidget);
      expect(google.calls, ['init']);
    });

    testWidgets('chưa kết nối', (tester) async {
      await tester.runAsync(() => openApp({}));
      await pumpBackupTab(tester);
      expect(find.text('Chưa kết nối Google Drive'), findsOneWidget);
    });
  });
}
