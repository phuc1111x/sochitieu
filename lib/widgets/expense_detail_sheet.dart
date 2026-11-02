import 'package:flutter/material.dart';

import '../data/expense_db.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../models/money_source.dart';
import '../screens/expense_form_screen.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'common.dart';

typedef _DetailData = ({Expense? expense, MoneySource? source});

Future<_DetailData> _loadDetail(int id) async {
  final db = ExpenseDb.instance;
  final expense = await db.expenseById(id);
  final sourceId = expense?.sourceId;
  final source = sourceId == null ? null : await db.sourceById(sourceId);
  return (expense: expense, source: source);
}

/// Bảng "Chi tiết khoản chi" trượt từ dưới lên: chỉ để đọc (ghi chú đầy đủ, nguồn trả, lúc ghi).
/// Đóng bằng vuốt xuống, chạm ra ngoài, nút Back hoặc "Đóng". Nút "Sửa" đóng bảng rồi mới mở
/// form sửa trên navigator của nơi gọi, nên Back từ form quay về danh sách và SnackBar vẫn như cũ.
Future<void> showExpenseDetail(BuildContext context, Expense expense) async {
  final id = expense.id;
  // Chạm hai lần nhanh: lần sau bị bỏ qua khi bảng đang tải hoặc đang mở (không chồng hai bảng).
  if (id == null || _sheetBusy) return;
  _sheetBusy = true;
  Expense? edit;
  try {
    // Tải sẵn để bảng có nội dung ngay từ khung hình đầu (không trượt lên một bảng trống).
    final initial = await _loadDetail(id);
    if (initial.expense == null || !context.mounted) return;
    edit = await showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      barrierColor: AppColors.sheetBarrier,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ExpenseDetailSheet(id: id, initial: initial),
    );
  } finally {
    _sheetBusy = false;
  }
  if (edit != null && context.mounted) await openExpenseForm(context, expense: edit);
}

/// Đang tải hoặc đang hiện bảng chi tiết.
bool _sheetBusy = false;

/// Test kết thúc khi bảng còn mở thì cờ [_sheetBusy] không được xoá: gọi hàm này trong `setUp`.
@visibleForTesting
void resetExpenseDetailForTest() => _sheetBusy = false;

class _ExpenseDetailSheet extends StatefulWidget {
  const _ExpenseDetailSheet({required this.id, required this.initial});

  final int id;
  final _DetailData initial;

  @override
  State<_ExpenseDetailSheet> createState() => _ExpenseDetailSheetState();
}

class _ExpenseDetailSheetState extends State<_ExpenseDetailSheet> {
  bool _closing = false;

  /// Khoản chi đã bị xoá (ví dụ khôi phục bản sao lưu) trong lúc bảng đang mở: tự đóng một lần.
  void _closeGone() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      // Bảng không nằm trên cùng (đã có màn khác mở đè) thì gỡ thẳng khỏi navigator.
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Chi tiết khoản chi',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: DbBuilder<_DetailData>(
          load: () => _loadDetail(widget.id),
          initialData: widget.initial,
          builder: (context, data) {
            final expense = data.expense;
            if (expense == null) {
              _closeGone();
              return const SizedBox(height: 120);
            }
            return _content(context, expense, data.source);
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, Expense e, MoneySource? source) {
    final cat = categoryById(e.category);
    final note = e.note.trim();
    final created = DateTime.fromMillisecondsSinceEpoch(e.createdAt);
    const footerText = TextStyle(fontFamily: 'BeVietnamPro', fontSize: 15, fontWeight: FontWeight.w600);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CategoryIcon(category: cat),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cat.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(_dateLabel(e.date), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                formatMoney(e.amount),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.56, height: 1.2),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ghi chú',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                if (note.isEmpty)
                  const Text(
                    'Không có ghi chú',
                    style: TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: AppColors.muted),
                  )
                else
                  SelectableText(note, style: const TextStyle(fontSize: 16, height: 1.45, color: AppColors.ink)),
                const SizedBox(height: 18),
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                _InfoRow(label: 'Trả bằng', value: _sourceValue(source)),
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                _InfoRow(
                  label: 'Ghi lúc',
                  value: Text('${formatTime(created)} · ${formatDate(created)}', style: _InfoRow.valueStyle),
                ),
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
              ],
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(e),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.lineStrong),
                        textStyle: footerText,
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Sửa'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(textStyle: footerText),
                      child: const Text('Đóng'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// "Hôm nay · Thứ Hai, 02/11/2026", "Hôm qua · ...", ngày cũ hơn chỉ có "Thứ ..., dd/MM/yyyy".
  static String _dateLabel(DateTime date) {
    final full = formatFullDate(date);
    final back = daysBefore(dateOnly(DateTime.now()), date);
    return back == 0 || back == 1 ? '${relativeDayLabel(back)} · $full' : full;
  }

  /// Nguồn đã trả: khoản chi cũ không gắn nguồn → "Không trừ vào nguồn nào"; nguồn đã xoá → "(đã xoá)".
  static Widget _sourceValue(MoneySource? source) {
    final other = sourceTypeById('other');
    final icon = source == null
        ? TintedIcon(icon: Icons.block_outlined, fg: other.fg, bg: other.bg, size: 24)
        : SourceIcon(type: source.sourceType, size: 24);
    final name = source == null
        ? 'Không trừ vào nguồn nào'
        : source.archived
        ? '${source.name} (đã xoá)'
        : source.name;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 8),
        Flexible(
          child: Text(name, textAlign: TextAlign.end, style: _InfoRow.valueStyle),
        ),
      ],
    );
  }
}

/// Một dòng thông tin "nhãn ........ giá trị" trong bảng chi tiết.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  static const valueStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink);

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: value),
          ),
        ],
      ),
    );
  }
}
