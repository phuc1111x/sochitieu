import 'package:flutter/material.dart';

import '../data/expense_db.dart';
import '../models/category.dart';
import '../models/money_move.dart';
import '../models/money_source.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'expense_form_screen.dart';
import 'money_form_screen.dart';
import 'source_form_screen.dart';
import 'sources_screen.dart';

typedef _DetailData = ({
  MoneySource? source,
  ({int inflow, int outflow}) flow,
  List<LedgerEntry> history,
  Map<int, String> names,
  List<MoneySource> active,
});

/// Màn "Chi tiết nguồn tiền": số dư, vào/ra tháng này và lịch sử theo ngày.
class SourceDetailScreen extends StatelessWidget {
  const SourceDetailScreen({super.key, required this.sourceId});

  final int sourceId;

  Future<_DetailData> _load() async {
    final db = ExpenseDb.instance;
    return (
      source: await db.sourceById(sourceId),
      flow: await db.sourceMonthFlow(sourceId, DateTime.now()),
      history: await db.sourceHistory(sourceId),
      names: await db.sourceNames(),
      active: await db.sourcesWithBalance(),
    );
  }

  Future<void> _edit(BuildContext context, MoneySource source) async {
    final navigator = Navigator.of(context);
    final archived = await openSourceForm(context, source: source);
    if (archived) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return DbBuilder<_DetailData>(
      load: _load,
      builder: (context, data) {
        final source = data.source;
        if (source == null) {
          return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(source.name),
            actions: [
              if (!source.archived)
                IconButton(
                  tooltip: source.hasLimit ? 'Sửa thẻ và hạn mức' : 'Sửa nguồn tiền',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit(context, source),
                ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              if (source.hasLimit)
                _CreditCard(source: source)
              else
                _BalanceCard(source: source, inflow: data.flow.inflow, outflow: data.flow.outflow),
              if (!source.archived && source.hasLimit) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ActionTile(
                        vertical: true,
                        icon: Icons.check,
                        label: 'Trả thẻ',
                        onTap: () => openTransfer(context, data.active, toId: source.id),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ActionTile(
                        vertical: true,
                        icon: Icons.add,
                        label: 'Chi tiêu',
                        onTap: () => openExpenseForm(context, sourceId: source.id),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ActionTile(
                        vertical: true,
                        icon: Icons.edit_outlined,
                        label: 'Sửa hạn mức',
                        onTap: () => _edit(context, source),
                      ),
                    ),
                  ],
                ),
              ] else if (!source.archived) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ActionTile(
                        vertical: true,
                        icon: Icons.download_outlined,
                        label: 'Thêm tiền',
                        onTap: () => openMoneyForm(context, kind: MoveKind.income, toId: source.id),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ActionTile(
                        vertical: true,
                        icon: Icons.swap_horiz,
                        label: 'Chuyển tiền',
                        onTap: () => openTransfer(context, data.active, fromId: source.id),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ActionTile(
                        vertical: true,
                        icon: Icons.add,
                        label: 'Chi tiêu',
                        onTap: () => openExpenseForm(context, sourceId: source.id),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              const Text('Lịch sử', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              if (data.history.isEmpty)
                const EmptyState(text: 'Chưa có giao dịch nào với nguồn tiền này.')
              else
                ..._groups(context, data.history, data.names, source),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _groups(BuildContext context, List<LedgerEntry> history, Map<int, String> names, MoneySource source) {
    final today = dateOnly(DateTime.now());
    final groups = <DateTime, List<LedgerEntry>>{};
    for (final e in history) {
      groups.putIfAbsent(e.date, () => []).add(e);
    }
    return [
      for (final g in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
          child: Text(
            historyDayLabel(today, g.key),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted),
          ),
        ),
        ListCard(children: [
          for (final e in g.value) _LedgerTile(entry: e, names: names, isCard: source.isCredit),
        ]),
        const SizedBox(height: 10),
      ],
    ];
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.source, required this.inflow, required this.outflow});

  final MoneySource source;
  final int inflow;
  final int outflow;

  Widget _flow(String label, int amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 2),
          Text(
            amount == 0 ? formatMoney(0) : formatSigned(amount),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: amount == 0 ? AppColors.ink : color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Row(
              children: [
                SourceIcon(type: source.sourceType, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Số dư hiện tại',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted)),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatBalance(source.balance),
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            height: 1.2,
                            color: source.balance < 0 ? AppColors.danger : AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _flow('Vào tháng này', inflow, AppColors.income)),
                const VerticalDivider(width: 1, thickness: 1, color: AppColors.divider),
                Expanded(child: _flow('Ra tháng này', outflow, AppColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Đầu màn chi tiết thẻ tín dụng có hạn mức: "Còn được tiêu", thanh % đã dùng, "Đang nợ" / "Tổng hạn mức".
class _CreditCard extends StatelessWidget {
  const _CreditCard({required this.source});

  final MoneySource source;

  Widget _cell(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = source.available;
    final debt = -source.balance;
    final usedLabel = 'Đã dùng ${source.usedPercent}% hạn mức';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SourceIcon(type: source.sourceType, size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Còn được tiêu',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted)),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formatBalance(available),
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                height: 1.2,
                                color: available < 0 ? AppColors.danger : AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                UsageBar(percent: source.usedPercent, height: 10, label: usedLabel),
                const SizedBox(height: 12),
                Text(usedLabel, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _cell('Đang nợ', formatMoney(debt > 0 ? debt : 0), debt > 0 ? AppColors.danger : AppColors.ink),
                ),
                const VerticalDivider(width: 1, thickness: 1, color: AppColors.divider),
                Expanded(child: _cell('Tổng hạn mức', formatMoney(source.creditLimit!), AppColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chuyển tiền và điều chỉnh số dư dùng màu của loại nguồn "Khác".
final _other = sourceTypeById('other');

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry, required this.names, this.isCard = false});

  final LedgerEntry entry;
  final Map<int, String> names;

  /// Lịch sử của thẻ tín dụng: tiền chuyển vào thẻ là "Trả thẻ".
  final bool isCard;

  Future<void> _open(BuildContext context) async {
    final db = ExpenseDb.instance;
    if (entry.kind == LedgerEntry.expense) {
      final expense = await db.expenseById(entry.refId);
      if (expense != null && context.mounted) await openExpenseForm(context, expense: expense);
    } else {
      final move = await db.moveById(entry.refId);
      if (move != null && context.mounted) await openMoneyForm(context, move: move);
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = entry.note.trim();
    final Widget icon;
    final String title;
    final String kind;
    switch (entry.kind) {
      case LedgerEntry.expense:
        final cat = categoryById(entry.category ?? 'other');
        icon = CategoryIcon(category: cat, size: 40);
        title = note.isEmpty ? cat.name : note;
        kind = 'Chi tiêu · ${cat.name}';
      case MoveKind.income:
        icon = const TintedIcon(
            icon: Icons.download_outlined, fg: AppColors.income, bg: AppColors.incomeSoft, size: 40);
        title = note.isEmpty ? 'Thêm tiền' : note;
        kind = 'Thêm tiền';
      case MoveKind.move when isCard && entry.amount > 0:
        icon = const TintedIcon(icon: Icons.swap_horiz, fg: AppColors.income, bg: AppColors.incomeSoft, size: 40);
        final other = names[entry.otherId] ?? '?';
        title = note.isEmpty ? 'Trả thẻ từ $other' : '$note ← $other';
        kind = 'Trả thẻ';
      case MoveKind.move:
        icon = TintedIcon(icon: Icons.swap_horiz, fg: _other.fg, bg: _other.bg, size: 40);
        final other = names[entry.otherId] ?? '?';
        final base = note.isEmpty ? (entry.amount < 0 ? 'Chuyển' : 'Nhận') : note;
        title = entry.amount < 0 ? '$base → $other' : '$base ← $other';
        kind = 'Chuyển tiền';
      default:
        icon = TintedIcon(icon: Icons.edit_outlined, fg: _other.fg, bg: _other.bg, size: 40);
        title = note.isEmpty ? 'Điều chỉnh số dư' : note;
        kind = 'Điều chỉnh số dư';
    }
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(kind, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatSigned(entry.amount),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: entry.amount > 0 ? AppColors.income : AppColors.ink,
            ),
          ),
        ],
      ),
    );
    // Dòng điều chỉnh số dư chỉ để xem, không sửa được.
    if (entry.kind == MoveKind.adjust) return row;
    return InkWell(onTap: () => _open(context), child: row);
  }
}
