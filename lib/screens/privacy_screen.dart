import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../utils/policy_text.dart';
import '../widgets/common.dart';

/// Màn "Quyền riêng tư": đọc Chính sách quyền riêng tư đóng gói sẵn trong app
/// (docs/privacy/vi.md và en.md, cùng file với trang web), chạy cả khi không có mạng.
/// Luôn mở bằng tiếng Việt; nút chuyển Tiếng Việt / English không được nhớ lại.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  static const viAsset = 'docs/privacy/vi.md';
  static const enAsset = 'docs/privacy/en.md';

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()));

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late final Future<List<PolicyDoc>> _docs = Future.wait([
    for (final asset in [PrivacyScreen.viAsset, PrivacyScreen.enAsset])
      // cache: false: chữ nhỏ, chỉ đọc khi mở màn; không giữ Future cũ trong bộ nhớ đệm.
      rootBundle.loadString(asset, cache: false).then(parsePolicy),
  ]);
  // Mỗi lần đổi ngôn ngữ, danh sách được tạo mới (key theo ngôn ngữ) nên luôn bắt đầu ở đầu trang;
  // keepScrollOffset: false để không khôi phục chỗ đã cuộn của lần xem trước.
  final _scroll = ScrollController(keepScrollOffset: false);

  /// 0 = Tiếng Việt, 1 = English.
  int _lang = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _pick(int lang) {
    if (lang == _lang) return;
    setState(() => _lang = lang);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 4,
        title: const Text('Quyền riêng tư'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Semantics(
              label: 'Ngôn ngữ',
              container: true,
              child: SegmentedTabs(labels: const ['Tiếng Việt', 'English'], selected: _lang, onChanged: _pick),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<PolicyDoc>>(
              future: _docs,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Không mở được chính sách. Vui lòng thử lại.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: AppColors.muted),
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(
                    child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  );
                }
                return SelectionArea(
                  child: _PolicyView(key: ValueKey(_lang), doc: snap.data![_lang], controller: _scroll),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyView extends StatelessWidget {
  const _PolicyView({super.key, required this.doc, required this.controller});

  final PolicyDoc doc;
  final ScrollController controller;

  static const _body = TextStyle(fontSize: 15, height: 1.6, color: AppColors.bodyText);

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + MediaQuery.paddingOf(context).bottom),
      children: [
        Text(doc.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.25)),
        for (final block in doc.intro) ...[
          const SizedBox(height: 6),
          for (final item in block.items)
            Text.rich(_spans(item, ink: AppColors.muted), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        ],
        for (final section in doc.sections) ...[
          const SizedBox(height: 24),
          Text(section.heading, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.35)),
          for (final block in section.blocks) ...[
            const SizedBox(height: 10),
            if (block.isList) _list(block) else Text.rich(_spans(block.items.single), style: _body),
          ],
        ],
      ],
    );
  }

  Widget _list(PolicyBlock block) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < block.items.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 20,
                    // Dấu chấm đầu dòng: không chọn được, để chép chữ ra không dính "•".
                    child: SelectionContainer.disabled(child: Text('•', style: _body)),
                  ),
                  Expanded(child: Text.rich(_spans(block.items[i]), style: _body)),
                ],
              ),
            ),
        ],
      );

  /// [ink]: màu chữ đậm (dòng "Sổ chi tiêu · Có hiệu lực từ ..." giữ màu xám như bản thiết kế).
  static TextSpan _spans(List<PolicyInline> parts, {Color ink = AppColors.ink}) => TextSpan(children: [
        for (final p in parts)
          TextSpan(
            text: p.text,
            style: switch (p.style) {
              InlineStyle.bold => TextStyle(fontWeight: FontWeight.w600, color: ink),
              InlineStyle.code => TextStyle(fontWeight: FontWeight.w500, color: ink),
              InlineStyle.plain => null,
            },
          ),
      ]);
}
