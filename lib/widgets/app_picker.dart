import 'package:flutter/material.dart';

import '../data/payment_apps.dart';
import '../theme.dart';
import '../utils/format.dart';

/// Biểu tượng của một ứng dụng đã cài (ảnh lấy từ điện thoại); không có ảnh thì hiện chữ cái đầu.
class AppIconTile extends StatelessWidget {
  const AppIconTile({super.key, required this.app, this.size = 40});

  final InstalledApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.3);
    final icon = app.icon;
    if (icon != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(icon, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
      );
    }
    final label = app.label.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.neutralSoft, borderRadius: radius),
      child: Text(
        label.isEmpty ? '?' : label.characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: AppColors.neutral),
      ),
    );
  }
}

/// Kết quả của [showAppPicker]: [app] là ứng dụng vừa chọn, `null` nghĩa là "Bỏ liên kết".
typedef AppPickResult = ({InstalledApp? app});

/// Ứng dụng [app] khớp ô tìm kiếm [query]: không phân biệt hoa thường và dấu tiếng Việt
/// ("ngan hang" tìm được "Ngân hàng"), so với cả tên hiện trên máy lẫn tên gói.
@visibleForTesting
bool appMatches(InstalledApp app, String query) {
  final q = foldVietnamese(query.trim());
  if (q.isEmpty) return true;
  return foldVietnamese(app.label).contains(q) || app.package.toLowerCase().contains(q);
}

/// Bảng chọn ứng dụng thanh toán (trượt từ dưới lên): ô tìm kiếm + danh sách ứng dụng đã cài.
/// [selected] là tên gói đang gắn (hiện dấu ✓ và nút "Bỏ liên kết").
/// Trả về `null` nếu người dùng đóng bảng mà không chọn gì.
Future<AppPickResult?> showAppPicker(BuildContext context, {String? selected}) {
  return showModalBottomSheet<AppPickResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    barrierColor: AppColors.sheetBarrier,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => _AppPickerSheet(selected: selected),
  );
}

class _AppPickerSheet extends StatefulWidget {
  const _AppPickerSheet({this.selected});

  final String? selected;

  @override
  State<_AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends State<_AppPickerSheet> {
  /// Thấp hơn mức này (bàn phím mở trên màn nhỏ) thì cả bảng cuộn chung, tiêu đề không đứng yên.
  static const _compactHeight = 220.0;

  /// Nút "Bỏ liên kết" chỉ hiện khi bảng đủ cao và bàn phím đang đóng.
  static const _footerMinHeight = 320.0;

  final _query = TextEditingController();

  /// Giữ nguyên ô tìm kiếm (và focus, bàn phím) khi bảng chuyển giữa dạng thường và dạng thấp.
  final _headerKey = GlobalKey();
  late final Future<List<InstalledApp>> _apps = PaymentApps.instance.listApps();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Chọn ứng dụng thanh toán', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: AppColors.searchFill, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 20, color: AppColors.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _query,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 15),
                        decoration: const InputDecoration(
                          hintText: 'Tìm ứng dụng',
                          hintStyle: TextStyle(color: AppColors.placeholder),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('Các ứng dụng đã cài trên điện thoại',
                  style: TextStyle(fontSize: 13, color: AppColors.muted)),
            ],
          ),
        ),
      ],
    );
  }

  /// Phần danh sách (dạng sliver): đang đọc / lỗi / không thấy / các dòng ứng dụng.
  List<Widget> _listSlivers(AsyncSnapshot<List<InstalledApp>> snap) {
    Widget message(String text) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          ),
        );
    if (snap.connectionState != ConnectionState.done) {
      return const [
        SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        ),
      ];
    }
    if (snap.hasError) return [message('Không đọc được danh sách ứng dụng')];
    final shown = (snap.data ?? const <InstalledApp>[]).where((a) => appMatches(a, _query.text)).toList();
    if (shown.isEmpty) return [message('Không tìm thấy ứng dụng')];
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        sliver: SliverList.builder(
          itemCount: shown.length,
          itemBuilder: (context, i) => _AppRow(
            app: shown[i],
            selected: shown[i].package == widget.selected,
            onTap: () => Navigator.of(context).pop((app: shown[i])),
          ),
        ),
      ),
    ];
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: TextButton(
        onPressed: () => Navigator.of(context).pop((app: null)),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.danger,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: const Text('Bỏ liên kết'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final screen = MediaQuery.sizeOf(context).height;
    return LayoutBuilder(builder: (context, constraints) {
      final maxHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : screen;
      // Cao như thiết kế (tối đa 640), nhưng không vượt phần còn lại phía trên bàn phím.
      final preferred = screen * 0.76 > 640 ? 640.0 : screen * 0.76;
      final room = maxHeight - inset;
      final height = (preferred < room ? preferred : room).clamp(0.0, double.infinity);
      final compact = height < _compactHeight;
      final showFooter = widget.selected != null && inset == 0 && height >= _footerMinHeight;
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SizedBox(
          height: height,
          child: FutureBuilder<List<InstalledApp>>(
            future: _apps,
            builder: (context, snap) {
              if (compact) {
                // Màn quá thấp: tiêu đề, ô tìm và danh sách cuộn chung để không bị tràn.
                return CustomScrollView(slivers: [SliverToBoxAdapter(child: KeyedSubtree(key: _headerKey, child: _header())), ..._listSlivers(snap)]);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyedSubtree(key: _headerKey, child: _header()),
                  Expanded(child: CustomScrollView(slivers: _listSlivers(snap))),
                  if (showFooter) _footer(),
                ],
              );
            },
          ),
        ),
      );
    });
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.selected, required this.onTap});

  final InstalledApp app;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.selectedFill : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Semantics(
          selected: selected,
          button: true,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  AppIconTile(app: app, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(app.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                  if (selected) const Icon(Icons.check, size: 20, color: AppColors.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
