import 'package:flutter/material.dart';

import '../data/expense_db.dart';
import '../models/money_move.dart';
import '../models/money_source.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'money_form_screen.dart';
import 'source_detail_screen.dart';
import 'source_form_screen.dart';

/// Hiện SnackBar báo kết quả (dùng chung cho các màn nguồn tiền).
void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Mở "Chuyển tiền", nhưng chỉ khi có ít nhất hai nguồn tiền.
/// [toId] chọn sẵn nguồn nhận (ví dụ "Trả thẻ": chuyển từ nguồn khác vào thẻ tín dụng).
Future<void> openTransfer(BuildContext context, List<MoneySource> active, {int? fromId, int? toId}) async {
  if (active.length < 2) {
    showMessage(context, 'Cần ít nhất hai nguồn tiền để chuyển tiền');
    return;
  }
  await openMoneyForm(context, kind: MoveKind.move, fromId: fromId, toId: toId);
}

/// Màn "Nguồn tiền" (tab thứ 3). [asRoute] = mở từ form chi tiêu ("Quản lý"), có nút quay lại.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key, this.asRoute = false});

  final bool asRoute;

  Future<({List<MoneySource> sources, int total, int spent})> _load() async {
    final db = ExpenseDb.instance;
    final sources = await db.sourcesWithBalance();
    final total = await db.totalBalance();
    final spent = await db.monthTotal(DateTime.now());
    return (sources: sources, total: total, spent: spent);
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(asRoute ? 8 : 20, 20, 12, 12),
            child: Row(
              children: [
                if (asRoute)
                  IconButton(
                    tooltip: 'Quay lại',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                const Expanded(
                  child: Text('Nguồn tiền', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                ),
                Material(
                  color: AppColors.surface,
                  shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
                  child: IconButton(
                    tooltip: 'Thêm nguồn tiền',
                    onPressed: () => openSourceForm(context),
                    icon: const Icon(Icons.add, color: AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: DbBuilder(
              load: _load,
              builder: (context, data) => _buildList(context, data.sources, data.total, data.spent),
            ),
          ),
        ],
      ),
    );
    return asRoute ? Scaffold(body: body) : body;
  }

  Widget _buildList(BuildContext context, List<MoneySource> sources, int total, int spent) {
    MoneySource? def;
    for (final s in sources) {
      if (s.isDefault) def = s;
    }
    def ??= sources.isEmpty ? null : sources.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        SummaryCard(
          label: 'Tổng tiền hiện có',
          total: formatBalance(total),
          footer: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _Stat(label: 'Đã chi tháng này', value: formatMoney(spent))),
              const SizedBox(width: 12),
              Expanded(child: _Stat(label: 'Số nguồn tiền', value: '${sources.length} nguồn')),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: ActionTile(
                icon: Icons.download_outlined,
                label: 'Thêm tiền',
                onTap: () => openMoneyForm(context, kind: MoveKind.income, toId: def?.id),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ActionTile(
                icon: Icons.swap_horiz,
                label: 'Chuyển tiền',
                onTap: () => openTransfer(context, sources, fromId: def?.id),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Các nguồn tiền', hint: 'Chạm để xem lịch sử'),
        ListCard(children: [for (final s in sources) _SourceTile(source: s)]),
      ],
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
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Nút hành động trắng viền xám (Thêm tiền / Chuyển tiền / Chi tiêu).
/// [vertical] = biểu tượng nằm trên chữ (màn chi tiết nguồn).
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.label, required this.onTap, this.vertical = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, color: AppColors.accent, size: vertical ? 22 : 20),
      SizedBox(width: vertical ? 0 : 8, height: vertical ? 6 : 0),
      // Màn hẹp hoặc chữ hệ thống to: thu nhỏ chữ thay vì tràn ra ngoài.
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: TextStyle(fontSize: vertical ? 13 : 15, fontWeight: FontWeight.w600)),
        ),
      ),
    ];
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: vertical ? 72 : 52,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: vertical
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: children)
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: children),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final MoneySource source;

  @override
  Widget build(BuildContext context) {
    final type = source.sourceType;
    final extra = source.isDefault
        ? ' · Mặc định'
        : !source.inTotal
            ? ' · Không tính vào tổng'
            : source.balance < 0
                ? ' · Đang nợ'
                : '';
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SourceDetailScreen(sourceId: source.id!)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SourceIcon(type: type),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  if (source.hasLimit) ...[
                    // Thẻ có hạn mức: số còn được tiêu + thanh % đã dùng.
                    // Giữ một dòng như bản thiết kế; màn hẹp thì thu nhỏ chữ một chút.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Còn được tiêu ${formatBalance(source.available)}',
                          style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                    ),
                    const SizedBox(height: 6),
                    UsageBar(
                      percent: source.usedPercent,
                      height: 6,
                      label: 'Đã dùng ${source.usedPercent}% hạn mức ${formatMoney(source.creditLimit!)}',
                    ),
                  ] else
                    Text('${type.name}$extra', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatBalance(source.balance),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: source.balance < 0 ? AppColors.danger : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
