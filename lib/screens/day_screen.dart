import 'package:flutter/material.dart';

import '../data/expense_db.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'expense_form_screen.dart';

/// Màn "Theo ngày". Vuốt sang phải = ngày trước, vuốt sang trái = ngày sau.
class DayScreen extends StatefulWidget {
  const DayScreen({super.key});

  @override
  State<DayScreen> createState() => DayScreenState();
}

class DayScreenState extends State<DayScreen> {
  static const _maxDays = 3650;
  static const _duration = Duration(milliseconds: 280);

  // reverse: true nên trang 0 (hôm nay) nằm bên phải, trang lớn hơn là ngày cũ hơn.
  final _controller = PageController();
  final DateTime _today = dateOnly(DateTime.now());
  int _back = 0;

  DateTime _dayAt(int back) => DateTime(_today.year, _today.month, _today.day - back);

  DateTime get currentDay => _dayAt(_back);

  void jumpTo(DateTime day) {
    final back = daysBefore(_today, day).clamp(0, _maxDays - 1);
    if (_controller.hasClients) _controller.jumpToPage(back);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            label: relativeDayLabel(_back),
            title: formatFullDate(currentDay),
            hint: 'Vuốt ngang để đổi ngày',
            prevTooltip: 'Ngày trước',
            nextTooltip: 'Ngày sau',
            onPrev: _back < _maxDays - 1
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
              itemCount: _maxDays,
              onPageChanged: (i) => setState(() => _back = i),
              itemBuilder: (context, i) {
                final day = _dayAt(i);
                return _DayPage(key: ValueKey(day), day: day, back: i);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DayPage extends StatelessWidget {
  const _DayPage({super.key, required this.day, required this.back});

  final DateTime day;
  final int back;

  Future<({List<Expense> items, int monthTotal})> _load() async {
    final db = ExpenseDb.instance;
    final items = await db.byDay(day);
    final monthTotal = await db.monthTotal(day);
    return (items: items, monthTotal: monthTotal);
  }

  @override
  Widget build(BuildContext context) {
    return DbBuilder(
      load: _load,
      builder: (context, data) {
        final total = data.items.fold<int>(0, (t, e) => t + e.amount);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
          children: [
            SummaryCard(
              label: back == 0 ? 'Tổng chi hôm nay' : 'Tổng chi ngày ${formatDayMonth(day)}',
              total: formatMoney(total),
              footer: Row(
                children: [
                  Expanded(child: Text('${data.items.length} khoản chi')),
                  Text('Tháng ${day.month}: ${formatMoney(data.monthTotal)}'),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SectionHeader(
              title: 'Các khoản chi',
              hint: data.items.isEmpty ? null : 'Chạm để sửa hoặc xoá',
            ),
            if (data.items.isEmpty)
              const EmptyState(text: 'Chưa có khoản chi nào trong ngày này.\nBấm "Thêm chi tiêu" để ghi lại.')
            else
              ListCard(children: [for (final e in data.items) _ExpenseTile(expense: e)]),
          ],
        );
      },
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final cat = categoryById(expense.category);
    final hasNote = expense.note.trim().isNotEmpty;
    return InkWell(
      onTap: () => openExpenseForm(context, expense: expense),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CategoryIcon(category: cat),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasNote ? expense.note : cat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  if (hasNote) ...[
                    const SizedBox(height: 2),
                    Text(cat.name, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(formatMoney(expense.amount), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
