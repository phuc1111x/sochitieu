// Đọc bản chữ Chính sách quyền riêng tư (docs/privacy/vi.md, en.md).
//
// Chỉ hiểu một phần nhỏ của Markdown, đủ cho chính sách:
//   `# Tiêu đề`, `## / ### Mục`, đoạn văn, dòng `- ` (danh sách), `**đậm**`, `` `mã` ``.
// File này không dùng Flutter để công cụ tạo trang web (tool/build_privacy_page.dart)
// dùng chung đúng bộ đọc này với màn hình trong app.

/// Kiểu chữ của một đoạn chữ nhỏ trong câu.
enum InlineStyle { plain, bold, code }

class PolicyInline {
  const PolicyInline(this.text, [this.style = InlineStyle.plain]);

  final String text;
  final InlineStyle style;

  @override
  bool operator ==(Object other) => other is PolicyInline && other.text == text && other.style == style;

  @override
  int get hashCode => Object.hash(text, style);

  @override
  String toString() => '${style.name}("$text")';
}

/// Một khối: đoạn văn ([isList] = false, đúng một dòng trong [items]) hoặc danh sách gạch đầu dòng.
class PolicyBlock {
  const PolicyBlock({required this.isList, required this.items});

  final bool isList;
  final List<List<PolicyInline>> items;
}

class PolicySection {
  const PolicySection(this.heading, this.blocks);

  final String heading;
  final List<PolicyBlock> blocks;
}

class PolicyDoc {
  const PolicyDoc({required this.title, required this.intro, required this.sections});

  /// Dòng `# ...`.
  final String title;

  /// Các khối nằm giữa tiêu đề và mục đầu tiên (dòng "Sổ chi tiêu · Có hiệu lực từ ...").
  final List<PolicyBlock> intro;
  final List<PolicySection> sections;
}

final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
final _bullet = RegExp(r'^[-*]\s+(.*)$');

PolicyDoc parsePolicy(String source) {
  var title = '';
  final intro = <PolicyBlock>[];
  final sections = <PolicySection>[];
  var blocks = intro;

  final paragraph = <String>[];
  final list = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(PolicyBlock(isList: false, items: [parseInline(paragraph.join(' '))]));
    paragraph.clear();
  }

  void flushList() {
    if (list.isEmpty) return;
    blocks.add(PolicyBlock(isList: true, items: [for (final item in list) parseInline(item)]));
    list.clear();
  }

  for (final raw in source.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      flushParagraph();
      flushList();
      continue;
    }
    final h = _heading.firstMatch(line);
    if (h != null) {
      flushParagraph();
      flushList();
      final text = h.group(2)!.trim();
      if (h.group(1)!.length == 1 && title.isEmpty && sections.isEmpty) {
        title = text;
      } else {
        blocks = <PolicyBlock>[];
        sections.add(PolicySection(text, blocks));
      }
      continue;
    }
    final b = _bullet.firstMatch(line);
    if (b != null) {
      flushParagraph();
      list.add(b.group(1)!.trim());
      continue;
    }
    if (list.isNotEmpty) {
      // Dòng tiếp theo của một gạch đầu dòng dài.
      list[list.length - 1] = '${list.last} $line';
    } else {
      paragraph.add(line);
    }
  }
  flushParagraph();
  flushList();
  return PolicyDoc(title: title, intro: intro, sections: sections);
}

/// Tách `**đậm**` và `` `mã` `` trong một dòng. Dấu mở không có dấu đóng thì giữ nguyên là chữ thường.
List<PolicyInline> parseInline(String text) {
  final out = <PolicyInline>[];
  final plain = StringBuffer();

  void flushPlain() {
    if (plain.isEmpty) return;
    out.add(PolicyInline(plain.toString()));
    plain.clear();
  }

  var i = 0;
  while (i < text.length) {
    if (text.startsWith('**', i)) {
      final end = text.indexOf('**', i + 2);
      if (end > i + 2) {
        flushPlain();
        out.add(PolicyInline(text.substring(i + 2, end), InlineStyle.bold));
        i = end + 2;
        continue;
      }
    } else if (text[i] == '`') {
      final end = text.indexOf('`', i + 1);
      if (end > i + 1) {
        flushPlain();
        out.add(PolicyInline(text.substring(i + 1, end), InlineStyle.code));
        i = end + 1;
        continue;
      }
    }
    plain.write(text[i]);
    i++;
  }
  flushPlain();
  return out;
}
