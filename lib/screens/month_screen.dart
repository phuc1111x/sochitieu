import 'package:flutter/material.dart';

import '../data/expense_db.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Màn "Theo tháng". Vuốt sang phải = tháng trước, vuốt sang trái = tháng sau.
class MonthScreen extends StatefulWidget {
  const MonthScreen({super.key, required this.onOpenDay});

  /// Gọi khi chạm vào một ngày trong danh sách để mở màn "Theo ngày".
  final ValueChanged<DateTime> onOpenDay;

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {
  static const _maxMonths = 600;
  static const _duration = Duration(milliseconds: 280);

  final _controller = PageController();
  final DateTime _today = dateOnly(DateTime.now());
  int _back = 0;

  DateTime _monthAt(int back) => DateTime(_today.year, _today.month - back, 1);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final month = _monthAt(_back);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text('Sổ chi tiêu', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          PeriodSwitcher(
            label: relativeMonthLabel(_back),
            title: 'Tháng ${month.month}/${month.year}',
            hint: 'Vuốt ngang để đổi tháng',
            prevTooltip: 'Tháng trước',
            nextTooltip: 'Tháng sau',
            onPrev: _back < _maxMonths - 1
                ? () => _controller.nextPage(duration: _duration, curve: Curves.easeOut)
                : null,
            onNext: _back > 0
                ? () => _controller.previousPage(duration: _duration, curve: Curves.easeOut)
                : null,
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              reverse: true,
              itemCount: _maxMonths,
              onPageChanged: (i) => setState(() => _back = i),
              itemBuilder: (context, i) {
                final m = _monthAt(i);
                return _MonthPage(key: ValueKey(m), month: m, today: _today, onOpenDay: widget.onOpenDay);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthPage extends StatelessWidget {
  const _MonthPage({super.key, required this.month, required this.today, required this.onOpenDay});

  final DateTime month;
  final DateTime today;
  final ValueChanged<DateTime> onOpenDay;

  Future<({List<DayTotal> days, Map<String, int> byCategory})> _load() async {
    final db = ExpenseDb.instance;
    final days = await db.dayTotals(month);
    final byCategory = await db.categoryTotals(month);
    return (days: days, byCategory: byCategory);
  }

  @override
  Widget build(BuildContext context) {
    return DbBuilder(
      load: _load,
      builder: (context, data) {
        final total = data.days.fold<int>(0, (t, d) => t + d.total);
        final isCurrent = month.year == today.year && month.month == today.month;
        final elapsedDays = isCurrent ? today.day : daysInMonth(month);
        // Làm tròn trung bình đến nghìn đồng cho dễ đọc.
        final avg = ((total / elapsedDays) / 1000).round() * 1000;
        DayTotal? peak;
        for (final d in data.days) {
          if (peak == null || d.total > peak.total) peak = d;
        }
        final cats = categories.where((c) => (data.byCategory[c.id] ?? 0) > 0).toList()
          ..sort((a, b) => data.byCategory[b.id]!.compareTo(data.byCategory[a.id]!));

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            SummaryCard(
              label: 'Tổng chi tháng ${month.month}',
              total: formatMoney(total),
              footer: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _Stat(label: 'Trung bình mỗi ngày', value: formatMoney(avg))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Stat(
                      label: 'Ngày chi nhiều nhất',
                      value: peak == null ? '—' : '${formatDayMonth(peak.date)} · ${formatMoney(peak.total)}',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (data.days.isEmpty)
              const EmptyState(text: 'Chưa có khoản chi nào trong tháng này.')
            else ...[
              const SectionHeader(title: 'Theo danh mục'),
              ListCard(children: [
                for (final c in cats) _CategoryRow(category: c, amount: data.byCategory[c.id]!, total: total),
              ]),
              const SizedBox(height: 22),
              const SectionHeader(title: 'Theo ngày', hint: 'Chạm để xem chi tiết'),
              ListCard(children: [
                for (final d in data.days) _DayRow(day: d, onTap: () => onOpenDay(d.date)),
              ]),
            ],
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.amount, required this.total});

  final ExpenseCategory category;
  final int amount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : amount / total;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              CategoryIcon(category: category, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(category.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              ),
              Text('${(ratio * 100).round()}%', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(width: 12),
              Text(formatMoney(amount), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                color: category.fg,
                backgroundColor: AppColors.track,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.onTap});

  final DayTotal day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatDayMonth(day.date), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(weekdayName(day.date), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            Expanded(
              child: Text('${day.count} khoản chi', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            ),
            Text(formatMoney(day.total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
