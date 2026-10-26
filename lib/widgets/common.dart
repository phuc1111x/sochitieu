import 'package:flutter/material.dart';

import '../data/expense_db.dart';
import '../models/category.dart';
import '../models/money_source.dart';
import '../theme.dart';

/// Tải dữ liệu từ database và tự tải lại khi dữ liệu thay đổi.
class DbBuilder<T> extends StatefulWidget {
  const DbBuilder({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<DbBuilder<T>> createState() => _DbBuilderState<T>();
}

class _DbBuilderState<T> extends State<DbBuilder<T>> {
  late Future<T> _future = widget.load();

  @override
  void initState() {
    super.initState();
    ExpenseDb.instance.changes.addListener(_reload);
  }

  @override
  void dispose() {
    ExpenseDb.instance.changes.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    // Không dùng `setState(() => ...)`: phép gán trả về Future, setState sẽ báo lỗi ở bản debug.
    setState(() {
      _future = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Lỗi đọc dữ liệu: ${snap.error}'));
          }
          if (!snap.hasData) return const SizedBox.shrink();
          return widget.builder(context, snap.data as T);
        },
      );
}

/// Thanh chọn ngày/tháng: ◀ nhãn ▶ và dòng nhắc vuốt ngang.
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({
    super.key,
    required this.label,
    required this.title,
    required this.hint,
    required this.prevTooltip,
    required this.nextTooltip,
    this.onPrev,
    this.onNext,
  });

  final String label;
  final String title;
  final String hint;
  final String prevTooltip;
  final String nextTooltip;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
          child: Row(
            children: [
              _RoundButton(icon: Icons.chevron_left, tooltip: prevTooltip, onPressed: onPrev),
              Expanded(
                child: Column(
                  children: [
                    Text(label,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted)),
                    const SizedBox(height: 2),
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              _RoundButton(icon: Icons.chevron_right, tooltip: nextTooltip, onPressed: onNext),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.swap_horiz, size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Text(hint, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.35 : 1,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, color: AppColors.ink),
        ),
      ),
    );
  }
}

/// Thẻ tổng màu chủ đạo ở đầu màn Ngày và Tháng.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.label, required this.total, required this.footer});

  final String label;
  final String total;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(20)),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                total,
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.2),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x4DFFFFFF)))),
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                child: footer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          if (hint != null) Text(hint!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// Khung trắng bo góc chứa danh sách, có đường kẻ giữa các dòng.
class ListCard extends StatelessWidget {
  const ListCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: AppColors.divider),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class CategoryIcon extends StatelessWidget {
  const CategoryIcon({super.key, required this.category, this.size = 44});

  final ExpenseCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: category.bg, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(category.icon, color: category.fg, size: size * 0.5),
    );
  }
}

class SourceIcon extends StatelessWidget {
  const SourceIcon({super.key, required this.type, this.size = 44});

  final SourceType type;
  final double size;

  @override
  Widget build(BuildContext context) => TintedIcon(icon: type.icon, fg: type.fg, bg: type.bg, size: size);
}

/// Ô vuông bo góc có nền nhạt và biểu tượng đậm cùng tông màu.
class TintedIcon extends StatelessWidget {
  const TintedIcon({super.key, required this.icon, required this.fg, required this.bg, this.size = 44});

  final IconData icon;
  final Color fg;
  final Color bg;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, color: fg, size: size * 0.5),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 36, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// Thanh "% hạn mức đã dùng" của thẻ tín dụng: cam, chuyển đỏ khi từ 90 % trở lên.
class UsageBar extends StatelessWidget {
  const UsageBar({
    super.key,
    required this.percent,
    required this.height,
    required this.label,
    this.track = AppColors.track,
  });

  final int percent;
  final double height;

  /// Câu đọc cho trình đọc màn hình, ví dụ "Đã dùng 24% hạn mức".
  final String label;
  final Color track;

  static Color colorFor(int percent) => percent >= 90 ? AppColors.danger : AppColors.creditBar;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return Semantics(
      label: label,
      image: true,
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: track, borderRadius: radius),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: percent.clamp(0, 100) / 100,
            child: DecoratedBox(decoration: BoxDecoration(color: colorFor(percent), borderRadius: radius)),
          ),
        ),
      ),
    );
  }
}
