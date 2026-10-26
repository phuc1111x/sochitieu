import 'package:flutter/material.dart';

import '../data/expense_db.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../models/money_source.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import 'sources_screen.dart';

/// Mở màn thêm (khi [expense] = null) hoặc sửa chi tiêu, rồi báo kết quả bằng SnackBar.
/// [sourceId] chọn sẵn nguồn trả tiền (ví dụ khi mở từ màn chi tiết nguồn tiền).
Future<void> openExpenseForm(BuildContext context, {Expense? expense, DateTime? date, int? sourceId}) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => ExpenseFormScreen(expense: expense, initialDate: date, presetSourceId: sourceId),
    ),
  );
  if (message != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, this.expense, this.initialDate, this.presetSourceId});

  final Expense? expense;
  final DateTime? initialDate;
  final int? presetSourceId;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

/// Biểu tượng cho lựa chọn "không trừ vào nguồn nào" (khoản chi cũ), dùng màu của loại "Khác".
final _noSource = SourceType(
  id: 'none',
  name: '',
  icon: Icons.block_outlined,
  fg: sourceTypeById('other').fg,
  bg: sourceTypeById('other').bg,
);

/// Câu "Sau khi lưu, ..." dưới ô "Trả bằng", tách phần chữ và phần số tiền (số tiền âm tô đỏ):
/// còn số dư → "còn 1.205.000 đ"; nguồn thường bị âm → "âm 500.000 đ"; thẻ tín dụng → "nợ 2.350.000 đ".
@visibleForTesting
({String text, String amount, bool negative}) afterSaveParts(MoneySource source, int after) {
  final name = source.name;
  if (after >= 0) return (text: 'Sau khi lưu, $name còn ', amount: formatBalance(after), negative: false);
  if (source.type == 'credit') return (text: 'Sau khi lưu, $name nợ ', amount: formatMoney(-after), negative: true);
  return (text: 'Sau khi lưu, $name âm ', amount: formatMoney(-after), negative: true);
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  static const _quickAmounts = [10000, 50000, 100000, 200000];

  late final _amount = TextEditingController(
    text: widget.expense == null ? '' : formatNumber(widget.expense!.amount),
  );
  late final _note = TextEditingController(text: widget.expense?.note ?? '');
  late String _category = widget.expense?.category ?? categories.first.id;
  late DateTime _date = widget.expense?.date ?? widget.initialDate ?? dateOnly(DateTime.now());
  late int? _sourceId = widget.expense?.sourceId;
  List<MoneySource> _sources = const [];
  bool _sourcesLoaded = false;

  /// Khoản chi đang sửa không có nguồn (khoản chi cũ, hoặc nguồn không còn trong máy):
  /// cho chọn "Không trừ vào nguồn nào".
  bool _noOriginalSource = false;
  bool _saving = false;

  bool get _isEdit => widget.expense != null;

  int get _amountValue => parseAmount(_amount.text);

  set _amountValue(int v) => setAmount(_amount, v);

  @override
  void initState() {
    super.initState();
    ExpenseDb.instance.changes.addListener(_loadSources);
    _loadSources();
  }

  @override
  void dispose() {
    ExpenseDb.instance.changes.removeListener(_loadSources);
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Nguồn để chọn: các nguồn chưa xoá, cộng nguồn cũ của khoản chi đang sửa (nếu đã bị xoá).
  Future<void> _loadSources() async {
    final all = await ExpenseDb.instance.sourcesWithBalance(includeArchived: true);
    if (!mounted) return;
    final original = widget.expense?.sourceId;
    final usable = all.where((s) => !s.archived || s.id == original).toList();
    setState(() {
      _sources = usable;
      final stillThere = usable.any((s) => s.id == _sourceId);
      if (!_sourcesLoaded) {
        if (_isEdit) {
          _noOriginalSource = !stillThere;
          if (!stillThere) _sourceId = null;
        } else {
          _sourceId = _pickInitial(usable);
        }
        _sourcesLoaded = true;
      } else if (_sourceId != null && !stillThere) {
        _sourceId = _noOriginalSource ? null : _pickInitial(usable);
      }
    });
  }

  int? _pickInitial(List<MoneySource> usable) {
    final active = usable.where((s) => !s.archived).toList();
    if (active.any((s) => s.id == widget.presetSourceId)) return widget.presetSourceId;
    for (final s in active) {
      if (s.isDefault) return s.id;
    }
    return active.isEmpty ? null : active.first.id;
  }

  MoneySource? get _selectedSource {
    for (final s in _sources) {
      if (s.id == _sourceId) return s;
    }
    return null;
  }

  /// Số dư nguồn [s] sau khi lưu, không tính lại phần của chính khoản chi đang sửa.
  int _balanceAfterSave(MoneySource s) {
    final original = widget.expense;
    final base = s.balance + (original != null && original.sourceId == s.id ? original.amount : 0);
    return base - _amountValue;
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
        sourceId: _sourceId,
        updatedAt: now,
      ));
    } else {
      await db.insert(Expense(
        amount: amount,
        category: _category,
        date: _date,
        note: note,
        sourceId: _sourceId,
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

  void _manageSources() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SourcesScreen(asRoute: true)));
  }

  @override
  Widget build(BuildContext context) {
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
          AmountCard(
            controller: _amount,
            autofocus: !_isEdit,
            onChanged: (_) => setState(() {}),
            onClear: () => setState(() => _amountValue = 0),
            quickAmounts: _quickAmounts,
            onQuickAdd: (n) => setState(() => _amountValue = (_amountValue + n).clamp(0, maxAmount)),
          ),
          const SizedBox(height: 22),
          const FieldLabel('Danh mục'),
          PickerField<String>(
            semanticLabel: 'Danh mục',
            selected: _category,
            onChanged: (id) => setState(() => _category = id),
            options: [
              for (final c in categories)
                PickerOption(value: c.id, leading: (size) => CategoryIcon(category: c, size: size), title: c.name),
            ],
          ),
          const SizedBox(height: 22),
          FieldLabel(
            'Trả bằng',
            trailing: InkWell(
              onTap: _manageSources,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('Quản lý',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent)),
              ),
            ),
          ),
          if (_sourcesLoaded) ..._buildSourcePicker(),
          const SizedBox(height: 22),
          const FieldLabel('Ngày'),
          DateField(date: _date, helpText: 'Chọn ngày chi', onChanged: (d) => setState(() => _date = d)),
          const SizedBox(height: 22),
          const NoteLabel(),
          TextBox(controller: _note, hint: 'Ví dụ: Phở bò sáng'),
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

  List<Widget> _buildSourcePicker() {
    // Khoản chi cũ chưa có nguồn: cho phép giữ nguyên "không trừ vào nguồn nào".
    final allowNone = _sources.isEmpty || _noOriginalSource;
    final selected = _selectedSource;
    return [
      PickerField<int?>(
        semanticLabel: 'Trả bằng',
        selected: _sourceId,
        onChanged: (id) => setState(() => _sourceId = id),
        options: [
          if (allowNone)
            PickerOption<int?>(
              value: null,
              leading: (size) => SourceIcon(type: _noSource, size: size),
              title: 'Không trừ vào nguồn nào',
            ),
          for (final s in _sources)
            PickerOption<int?>(
              value: s.id,
              leading: (size) => SourceIcon(type: s.sourceType, size: size),
              title: s.name,
              trailing: formatBalance(s.balance),
              trailingColor: s.balance < 0 ? AppColors.danger : AppColors.muted,
            ),
        ],
      ),
      if (selected != null) ...[
        const SizedBox(height: 10),
        Builder(builder: (context) {
          final parts = afterSaveParts(selected, _balanceAfterSave(selected));
          return Text.rich(
            TextSpan(children: [
              TextSpan(text: parts.text),
              TextSpan(
                text: parts.amount,
                style: TextStyle(color: parts.negative ? AppColors.danger : AppColors.muted),
              ),
            ]),
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          );
        }),
      ],
    ];
  }
}
