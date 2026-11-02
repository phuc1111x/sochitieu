// Tạo lại docs/index.html và docs/privacy/index.html từ docs/privacy/vi.md và en.md.
//
//   dart run tool/build_privacy_page.dart
//
// Đường dẫn tính từ thư mục gốc dự án (thư mục cha của tool/), nên chạy từ đâu cũng được.

import 'dart:io';

import 'package:sochitieu/utils/policy_text.dart';

import 'privacy_site.dart';

void main() {
  final root = File.fromUri(Platform.script).parent.parent;
  File at(String path) => File.fromUri(root.uri.resolve(path));

  final vi = parsePolicy(at('docs/privacy/vi.md').readAsStringSync());
  final en = parsePolicy(at('docs/privacy/en.md').readAsStringSync());
  at('docs/privacy/index.html').writeAsStringSync(buildPrivacyPage(vi: vi, en: en));
  at('docs/index.html').writeAsStringSync(buildHomePage(year: policyYear(vi)));
  stdout.writeln('Đã tạo ${at('docs/index.html').path} và ${at('docs/privacy/index.html').path}');
}
