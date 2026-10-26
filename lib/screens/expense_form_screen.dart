import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/expense_db.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Mở màn thêm (khi [expense] = null) hoặc sửa chi tiêu, rồi báo kết quả bằng SnackBar.
Future<void> openExpenseForm(BuildContext context, {Expense? expense, DateTime? date}) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => ExpenseFormScreen(expense: expense, initialDate: date)),
  );
  if (message != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, this.expense, this.initialDate});

  final Expense? expense;
  final DateTime? initialDate;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  static const _maxAmount = 999999999999;
  static const _quickAmounts = [10000, 50000, 100000, 200000];

  late final _amount = TextEditingController(
    text: widget.expense == null ? '' : formatNumber(widget.expense!.amount),
  );
  late final _note = TextEditingController(text: widget.expense?.note ?? '');
  late String _category = widget.expense?.category ?? categories.first.id;
  late DateTime _date = widget.expense?.date ?? widget.initialDate ?? dateOnly(DateTime.now());
  bool _saving = false;

  bool get _isEdit => widget.expense != null;

  int get _amountValue => int.tryParse(_amount.text.replaceAll('.', '')) ?? 0;

  set _amountValue(int v) {
    final text = v == 0 ? '' : formatNumber(v);
    _amount.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'Chọn ngày chi',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = _amountValue;
    if (amount <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Vui lòng nhập số tiền')));
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final note = _note.text.trim();
    final db = ExpenseDb.instance;
    if (_isEdit) {
      await db.update(widget.expense!.copyWith(
        amount: amount,
        category: _category,
        date: _date,
        note: note,
        updatedAt: now,
      ));
    } else {
      await db.insert(Expense(
        amount: amount,
        category: _category,
        date: _date,
        note: note,
        createdAt: now,
        updatedAt: now,
      ));
    }
    if (!mounted) return;
    Navigator.of(context).pop(_isEdit ? 'Đã lưu thay đổi' : 'Đã thêm ${formatMoney(amount)}');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá khoản chi này?'),
        content: Text('${formatMoney(widget.expense!.amount)} · ${categoryById(widget.expense!.category).name}\n'
            'Không thể hoàn tác sau khi xoá.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ExpenseDb.instance.delete(widget.expense!.id!);
    if (!mounted) return;
    Navigator.of(context).pop('Đã xoá khoản chi');
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final back = daysBefore(today, _date);
    final dateText = switch (back) {
      0 => 'Hôm nay, ${formatDate(_date)}',
      1 => 'Hôm qua, ${formatDate(_date)}',
      _ => formatFullDate(_date),
    };

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Đóng',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_isEdit ? 'Sửa chi tiêu' : 'Thêm chi tiêu'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _AmountCard(
            controller: _amount,
            autofocus: !_isEdit,
            onClear: () => setState(() => _amountValue = 0),
            quickAmounts: _quickAmounts,
            onQuickAdd: (n) => setState(() => _amountValue = (_amountValue + n).clamp(0, _maxAmount)),
          ),
          const SizedBox(height: 22),
          const Text('Danh mục', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 88,
            ),
            itemBuilder: (context, i) {
              final c = categories[i];
              return _CategoryButton(
                category: c,
                selected: c.id == _category,
                onTap: () => setState(() => _category = c.id),
              );
            },
          ),
          const SizedBox(height: 22),
          const Text('Ngày', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.line),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickDate,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Icon(Icons.calendar_today_outlined, color: AppColors.accent, size: 22),
                    const SizedBox(width: 12),
                    Expanded(child: Text(dateText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                    const Icon(Icons.chevron_right, color: AppColors.muted),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Ghi chú ', style: TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: '(không bắt buộc)', style: TextStyle(color: AppColors.muted)),
            ]),
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 100,
            decoration: InputDecoration(
              hintText: 'Ví dụ: Phở bò sáng',
              counterText: '',
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
              ),
            ),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _saving ? null : _delete,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
                minimumSize: const Size.fromHeight(48),
                textStyle: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 15, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Xoá khoản chi này'),
            ),
          ],
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_isEdit ? 'Lưu thay đổi' : 'Lưu chi tiêu'),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.controller,
    required this.autofocus,
    required this.onClear,
    required this.quickAmounts,
    required this.onQuickAdd,
  });

  final TextEditingController controller;
  final bool autofocus;
  final VoidCallback onClear;
  final List<int> quickAmounts;
  final ValueChanged<int> onQuickAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Số tiền', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted)),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: autofocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_ThousandsFormatter()],
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                  decoration: const InputDecoration(
                    hintText: '0',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const Text('đ', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.muted)),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Xoá số tiền',
                onPressed: onClear,
                style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F2F4)),
                icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
              ),
            ],
          ),
          Container(height: 2, color: AppColors.accent),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < quickAmounts.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onQuickAdd(quickAmounts[i]),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      padding: EdgeInsets.zero,
                      backgroundColor: const Color(0xFFF8F9FA),
                      side: const BorderSide(color: AppColors.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    child: FittedBox(child: Text('+${formatNumber(quickAmounts[i])}')),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({required this.category, required this.selected, required this.onTap});

  final ExpenseCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0x140F766E) : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? AppColors.accent : AppColors.line, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Semantics(
          selected: selected,
          button: true,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CategoryIcon(category: category, size: 40),
              const SizedBox(height: 8),
              Text(category.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chỉ cho nhập số và tự thêm dấu chấm phân cách hàng nghìn: 50000 → 50.000.
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 12) digits = digits.substring(0, 12);
    final n = int.tryParse(digits) ?? 0;
    final text = n == 0 ? '' : formatNumber(n);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
