import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sochitieu/screens/backup_screen.dart';
import 'package:sochitieu/screens/privacy_screen.dart';
import 'package:sochitieu/theme.dart';
import 'package:sochitieu/utils/policy_text.dart';

import '../tool/privacy_site.dart';
import 'test_helpers.dart';

PolicyDoc _readDoc(String lang) => parsePolicy(File('docs/privacy/$lang.md').readAsStringSync());

String _plain(List<PolicyInline> parts) => parts.map((p) => p.text).join();

String _home() => buildHomePage(year: policyYear(_readDoc('vi')));

void main() {
  group('parsePolicy', () {
    test('đọc tiêu đề, dòng giới thiệu, mục, đoạn văn và danh sách', () {
      final doc = parsePolicy('''
# Tiêu đề

**Sổ chi tiêu** · Có hiệu lực từ 01/01/2026

### 1. Mục một

Đoạn một
nối dòng.

- **Đậm:** chữ thường
- Tệp `a.json`

Đoạn hai.

## 2. Mục hai
- Một
- Hai
''');
      expect(doc.title, 'Tiêu đề');
      expect(doc.intro, hasLength(1));
      expect(doc.intro.single.items.single, const [
        PolicyInline('Sổ chi tiêu', InlineStyle.bold),
        PolicyInline(' · Có hiệu lực từ 01/01/2026'),
      ]);
      expect(doc.sections.map((s) => s.heading), ['1. Mục một', '2. Mục hai']);

      final one = doc.sections[0].blocks;
      expect(one.map((b) => b.isList), [false, true, false]);
      expect(_plain(one[0].items.single), 'Đoạn một nối dòng.');
      expect(one[1].items, [
        const [PolicyInline('Đậm:', InlineStyle.bold), PolicyInline(' chữ thường')],
        const [PolicyInline('Tệp '), PolicyInline('a.json', InlineStyle.code)],
      ]);
      expect(doc.sections[1].blocks.single.items.length, 2);
    });

    test('dấu ** hoặc ` không có dấu đóng thì giữ nguyên là chữ', () {
      expect(parseInline('a ** b'), const [PolicyInline('a ** b')]);
      expect(parseInline('giá `5'), const [PolicyInline('giá `5')]);
      expect(parseInline('**toàn bộ**'), const [PolicyInline('toàn bộ', InlineStyle.bold)]);
    });
  });

  group('bản chữ docs/privacy', () {
    final vi = _readDoc('vi');
    final en = _readDoc('en');

    test('Tiếng Việt và English có cùng 11 mục, cùng cấu trúc', () {
      expect(vi.title, 'Chính sách quyền riêng tư');
      expect(en.title, 'Privacy Policy');
      expect(vi.sections, hasLength(11));
      expect(en.sections.length, vi.sections.length);
      for (var i = 0; i < vi.sections.length; i++) {
        expect(vi.sections[i].heading, startsWith('${i + 1}. '));
        expect(en.sections[i].heading, startsWith('${i + 1}. '));
        final viShape = [for (final b in vi.sections[i].blocks) b.isList ? b.items.length : 0];
        final enShape = [for (final b in en.sections[i].blocks) b.isList ? b.items.length : 0];
        expect(enShape, viShape, reason: 'mục ${i + 1}');
      }
    });

    test('đã điền ngày hiệu lực và email liên hệ', () {
      final viText = File('docs/privacy/vi.md').readAsStringSync();
      final enText = File('docs/privacy/en.md').readAsStringSync();
      for (final t in [viText, enText]) {
        expect(t, isNot(contains('{EFFECTIVE_DATE}')));
        expect(t, contains('sanchykids@gmail.com'));
        expect(t, contains('drive.appdata'));
      }
      expect(_plain(vi.intro.single.items.single), 'Sổ chi tiêu · Có hiệu lực từ 02/11/2026');
      expect(_plain(en.intro.single.items.single), 'Sổ chi tiêu · Effective 2 November 2026');
    });

    test('chỉ dùng phần Markdown mà bộ đọc hiểu, có tiêu đề #', () {
      for (final lang in ['vi', 'en']) {
        final lines = File('docs/privacy/$lang.md').readAsLinesSync();
        expect(lines.first, startsWith('# '), reason: '$lang.md: dòng đầu phải là tiêu đề #');
        expect(_readDoc(lang).title, isNotEmpty, reason: '$lang.md');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final at = '$lang.md dòng ${i + 1}: "$line"';
          expect(RegExp(r'^\s*\d+[.)]\s').hasMatch(line), isFalse, reason: 'danh sách đánh số không hỗ trợ: $at');
          expect(line.trimLeft().startsWith('>'), isFalse, reason: 'trích dẫn > không hỗ trợ: $at');
          expect(RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line), isFalse, reason: 'đường kẻ --- không hỗ trợ: $at');
          expect(RegExp(r'\[[^\]]*\]\([^)]*\)').hasMatch(line), isFalse, reason: 'liên kết [chữ](url) không hỗ trợ: $at');
          expect(RegExp(r'^\s+[-*]\s').hasMatch(line), isFalse, reason: 'gạch đầu dòng lồng nhau không hỗ trợ: $at');
          expect(RegExp(r'^\s+\S').hasMatch(line), isFalse, reason: 'dòng thụt lề không hỗ trợ: $at');
          if (line.startsWith('#')) {
            expect(RegExp(r'^#{1,3} \S').hasMatch(line), isTrue, reason: 'tiêu đề phải là # hoặc ### : $at');
            expect(line.contains('**') || line.contains('`'), isFalse, reason: 'tiêu đề không được có ** hoặc `: $at');
          }
        }
      }
    });

    test('năm bản quyền lấy từ ngày hiệu lực', () {
      expect(policyYear(vi), '2026');
      expect(policyYear(en), '2026');
      expect(() => policyYear(parsePolicy('# T\n\nkhông có năm\n')), throwsFormatException);
    });

    test('app đóng gói đúng hai file chính sách', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- ${PrivacyScreen.viAsset}'));
      expect(pubspec, contains('- ${PrivacyScreen.enAsset}'));
    });
  });

  group('trang web docs/', () {
    test('docs/privacy/index.html đúng bằng bản tạo từ vi.md và en.md (chạy lại tool/build_privacy_page.dart)', () {
      final html = buildPrivacyPage(vi: _readDoc('vi'), en: _readDoc('en'));
      expect(File('docs/privacy/index.html').readAsStringSync(), html);
    });

    test('docs/index.html đúng bằng bản tạo (chạy lại tool/build_privacy_page.dart)', () {
      expect(File('docs/index.html').readAsStringSync(), _home());
    });

    test('trang chính sách có sẵn cả hai thứ tiếng, không gọi dịch vụ bên ngoài', () {
      final html = buildPrivacyPage(vi: _readDoc('vi'), en: _readDoc('en'));
      expect(html, contains('<article lang="vi" data-l="vi">'));
      expect(html, contains('<article lang="en" data-l="en">'));
      expect(html, contains('Chính sách quyền riêng tư'));
      expect(html, contains('Privacy Policy'));
      expect(html, contains('Có hiệu lực từ 02/11/2026'));
      expect(html, contains('Effective 2 November 2026'));
      expect(html, contains('href="https://myaccount.google.com/connections"'));
      expect(html, isNot(contains('connections."')));
      expect(html, contains('href="mailto:sanchykids@gmail.com"'));
      expect(html, contains('© 2026 Sổ chi tiêu'));
      for (final page in [html, _home()]) {
        // Không có tracker, font hay script tải từ nơi khác; chỉ có liên kết người dùng tự bấm.
        expect(RegExp(r'''(src|href)="https?://(?!myaccount\.google\.com|drive\.google\.com|phuc1111x\.github\.io)''')
            .hasMatch(page), isFalse);
        expect(page, isNot(contains('cookie')));
        expect(page, isNot(contains('<script src')));
      }
    });

    test('trang chủ dẫn tới trang chính sách đúng ngôn ngữ và có email liên hệ', () {
      final home = _home();
      expect(home, contains('href="privacy/#vi"'));
      expect(home, contains('href="privacy/#en"'));
      expect(home, contains('mailto:sanchykids@gmail.com'));
      expect(File('docs/logo.png').existsSync(), isTrue);
      expect(File('docs/.nojekyll').existsSync(), isTrue);
    });
  });

  group('màn Quyền riêng tư', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> openPrivacy(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                Center(child: TextButton(onPressed: () => PrivacyScreen.open(context), child: const Text('Mở'))),
          ),
        ),
      ));
      await tester.tap(find.text('Mở'));
      await pumpUntil(tester, () => shows(find.text('1. Về ứng dụng')), reason: 'tải chính sách');
      await tester.pumpAndSettle();
    }

    testWidgets('mở bằng tiếng Việt, chữ chọn được', (tester) async {
      usePhoneSize(tester);
      await openPrivacy(tester);
      expect(find.text('Quyền riêng tư'), findsOneWidget);
      expect(find.text('Tiếng Việt'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Chính sách quyền riêng tư'), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.text('Privacy Policy'), findsNothing);
    });

    testWidgets('bấm English đổi sang tiếng Anh và cuộn về đầu; bấm Tiếng Việt quay lại', (tester) async {
      usePhoneSize(tester);
      await openPrivacy(tester);
      final list = find.descendant(of: find.byType(PrivacyScreen), matching: find.byType(Scrollable));
      await tester.drag(list, const Offset(0, -1500));
      await tester.pumpAndSettle();
      final position = tester.state<ScrollableState>(list).position;
      expect(position.pixels, greaterThan(0));

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('1. About the app'), findsOneWidget);
      expect(find.text('Chính sách quyền riêng tư'), findsNothing);
      expect(tester.state<ScrollableState>(list).position.pixels, 0);

      await tester.drag(list, const Offset(0, -1500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tiếng Việt'));
      await tester.pumpAndSettle();
      expect(find.text('Chính sách quyền riêng tư'), findsOneWidget);
      expect(tester.state<ScrollableState>(list).position.pixels, 0);
    });

    testWidgets('đóng rồi mở lại thì về tiếng Việt (không nhớ ngôn ngữ)', (tester) async {
      usePhoneSize(tester);
      await openPrivacy(tester);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Privacy Policy'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyScreen), findsNothing);

      await tester.tap(find.text('Mở'));
      await pumpUntil(tester, () => shows(find.text('1. Về ứng dụng')), reason: 'mở lại');
      await tester.pumpAndSettle();
      expect(find.text('Chính sách quyền riêng tư'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsNothing);
    });

    testWidgets('đường link và email chỉ là chữ, không bấm được', (tester) async {
      usePhoneSize(tester);
      await openPrivacy(tester);
      await tester.scrollUntilVisible(find.textContaining('myaccount.google.com', findRichText: true), 300,
          scrollable: find.descendant(of: find.byType(PrivacyScreen), matching: find.byType(Scrollable)));
      final rich = tester.widget<RichText>(find.textContaining('myaccount.google.com', findRichText: true));
      void noTap(InlineSpan span) {
        if (span is TextSpan) {
          expect(span.recognizer, isNull);
          span.children?.forEach(noTap);
        }
      }

      noTap(rich.text);
    });

    testWidgets('chữ **đậm** trong bản chữ hiện bằng nét w600', (tester) async {
      usePhoneSize(tester);
      await openPrivacy(tester);
      const label = 'Thu hồi quyền truy cập Drive:';
      final finder = find.textContaining(label, findRichText: true);
      await tester.scrollUntilVisible(finder, 300,
          scrollable: find.descendant(of: find.byType(PrivacyScreen), matching: find.byType(Scrollable)));
      TextSpan? bold;
      tester.widget<RichText>(finder).text.visitChildren((span) {
        if (span is TextSpan && span.text == label) bold = span;
        return bold == null;
      });
      expect(bold, isNotNull);
      expect(bold!.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('đang tải thì hiện vòng xoay ở giữa', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const PrivacyScreen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await pumpUntil(tester, () => shows(find.text('1. Về ứng dụng')), reason: 'tải chính sách');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('dòng Chính sách quyền riêng tư ở tab Sao lưu', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('luôn hiện khi chưa kết nối Drive và mở màn Quyền riêng tư', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const Scaffold(body: BackupScreen())));
      await tester.pump();
      expect(find.text('Chưa kết nối Google Drive'), findsOneWidget);

      final row = find.text('Chính sách quyền riêng tư');
      await tester.scrollUntilVisible(row, 200);
      expect(find.text('App lưu gì, lưu ở đâu, cách xoá'), findsOneWidget);

      await tester.tap(row);
      await pumpUntil(tester, () => shows(find.text('1. Về ứng dụng')), reason: 'mở chính sách từ Sao lưu');
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyScreen), findsOneWidget);
      expect(find.text('Quyền riêng tư'), findsOneWidget);
    });

    testWidgets('bấm nhanh hai lần chỉ mở một màn; đóng rồi bấm lại vẫn mở được', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const Scaffold(body: BackupScreen())));
      await tester.pump();
      final row = find.text('Chính sách quyền riêng tư');
      await tester.scrollUntilVisible(row, 200);

      // Navigator tự chặn chạm trong khung hình ngay sau push, nên gọi thẳng onTap hai lần
      // (như hai lần bấm lọt qua trên máy chậm) để kiểm tra chốt chặn của chính dòng này.
      final onTap = tester.widget<InkWell>(find.ancestor(of: row, matching: find.byType(InkWell))).onTap!;
      onTap();
      onTap();
      await pumpUntil(tester, () => shows(find.text('1. Về ứng dụng')), reason: 'mở chính sách');
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyScreen, skipOffstage: false), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyScreen, skipOffstage: false), findsNothing);

      await tester.tap(row);
      await pumpUntil(tester, () => shows(find.text('1. Về ứng dụng')), reason: 'mở lại');
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyScreen, skipOffstage: false), findsOneWidget);
    });
  });

  test('ứng dụng không xin thêm quyền và không có QUERY_ALL_PACKAGES', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final permissions = RegExp(r'uses-permission android:name="([^"]+)"').allMatches(manifest).map((m) => m[1]);
    expect(permissions.toSet(), {'android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE'});
    expect(manifest, isNot(contains('android.permission.QUERY_ALL_PACKAGES')));
  });

  // Đúng file đóng gói trong app (rootBundle), không phải file đọc từ đĩa.
  test('rootBundle đọc được file chính sách', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final text = await rootBundle.loadString(PrivacyScreen.viAsset, cache: false);
    expect(parsePolicy(text).sections, hasLength(11));
  });
}
