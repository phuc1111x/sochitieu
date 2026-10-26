import 'package:flutter/material.dart';

import '../data/expense_db.dart';
import '../models/money_source.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// Mở màn thêm (khi [source] = null) hoặc sửa nguồn tiền, báo kết quả bằng SnackBar.
/// Trả về `true` nếu nguồn tiền vừa bị xoá.
Future<bool> openSourceForm(BuildContext context, {MoneySource? source}) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await Navigator.of(context).push<({String message, bool archived})>(
    MaterialPageRoute(builder: (_) => SourceFormScreen(source: source)),
  );
  if (result == null) return false;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(result.message)));
  return result.archived;
}

class SourceFormScreen extends StatefulWidget {
  const SourceFormScreen({super.key, this.source});

  final MoneySource? source;

  @override
  State<SourceFormScreen> createState() => _SourceFormScreenState();
}

class _SourceFormScreenState extends State<SourceFormScreen> {
  late final _name = TextEditingController(text: widget.source?.name ?? '');
  late String _type = widget.source?.type ?? 'cash';
  late final _balance = TextEditingController();
  bool _balanceTouched = false;
  late bool _isDefault = widget.source?.isDefault ?? false;

  /// Thêm mới: "Tính vào tổng" đi theo loại (tắt cho tiết kiệm) cho tới khi người dùng tự bật/tắt.
  late bool? _inTotalChoice = widget.source?.inTotal;
  bool _saving = false;

  bool get _isEdit => widget.source != null;
  bool get _isCredit => _type == 'credit';
  bool get _inTotal => _inTotalChoice ?? _type != 'saving';

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _showCurrentBalance();
    } else {
      // Chỉ bật sẵn "Dùng mặc định" khi chưa có nguồn tiền nào.
      ExpenseDb.instance.sourcesWithBalance().then((active) {
        if (mounted && active.isEmpty) setState(() => _isDefault = true);
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  /// Khi sửa: hiện số dư (hoặc số nợ với thẻ tín dụng) hiện tại trong ô nhập.
  void _showCurrentBalance() {
    final balance = widget.source!.balance;
    setAmount(_balance, (_isCredit ? -balance : balance).clamp(0, maxAmount));
  }

  /// Số dư hiện tại không ghi được vào ô nhập (âm với nguồn thường, dương với thẻ tín dụng).
  bool get _balanceNotShown {
    final balance = widget.source?.balance ?? 0;
    return _isEdit && !_balanceTouched && (_isCredit ? balance > 0 : balance < 0);
  }

  void _pickType(String id) {
    setState(() {
      _type = id;
      if (_isEdit && !_balanceTouched) _showCurrentBalance();
    });
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _show('Vui lòng nhập tên nguồn tiền');
      return;
    }
    setState(() => _saving = true);
    try {
      final value = parseAmount(_balance.text);
      final balance = _isCredit ? -value : value;
      final db = ExpenseDb.instance;
      if (_isEdit) {
        await db.updateSource(
          widget.source!.copyWith(name: name, type: _type, isDefault: _isDefault, inTotal: _inTotal),
          newBalance: _balanceTouched ? balance : null,
        );
      } else {
        await db.insertSource(
          MoneySource(
            name: name,
            type: _type,
            isDefault: _isDefault,
            inTotal: _inTotal,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          openingBalance: balance,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop((message: _isEdit ? 'Đã lưu thay đổi' : 'Đã thêm nguồn tiền $name', archived: false));
    } catch (e) {
      if (mounted) _show(e is DataException ? e.message : 'Không lưu được, vui lòng thử lại. ($e)');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá nguồn tiền này?'),
        content: Text('${widget.source!.name} sẽ được ẩn khỏi danh sách và không tính vào tổng tiền. '
            'Lịch sử và các khoản chi đã ghi vẫn được giữ lại.'),
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
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ExpenseDb.instance.archiveSource(widget.source!.id!);
      if (!mounted) return;
      Navigator.of(context).pop((message: 'Đã xoá nguồn tiền', archived: true));
    } catch (e) {
      if (mounted) _show(e is DataException ? e.message : 'Không xoá được, vui lòng thử lại. ($e)');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = _isCredit
        ? 'Khoản chi trả bằng thẻ sẽ cộng vào số nợ. Khi trả thẻ, dùng Chuyển tiền từ tài khoản ngân hàng sang thẻ.'
        : _isEdit
            ? 'Nếu số dư thật khác với app, sửa ở đây. App ghi lại một dòng “Điều chỉnh số dư”, không tính là chi tiêu.'
            : 'Nhập số tiền đang có thật trong nguồn này. Từ giờ, mỗi khoản chi trả bằng nguồn này sẽ tự trừ vào đây.';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Đóng',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_isEdit ? 'Sửa nguồn tiền' : 'Thêm nguồn tiền'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const FieldLabel('Tên nguồn tiền'),
          TextBox(controller: _name, hint: 'Ví dụ: Vietcombank, MoMo', maxLength: 40),
          const SizedBox(height: 22),
          const FieldLabel('Loại'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sourceTypes.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 88,
            ),
            itemBuilder: (context, i) {
              final t = sourceTypes[i];
              return _TypeButton(type: t, selected: t.id == _type, onTap: () => _pickType(t.id));
            },
          ),
          const SizedBox(height: 22),
          AmountCard(
            controller: _balance,
            label: _isCredit ? 'Số tiền đang nợ trên thẻ' : 'Số dư hiện tại',
            fontSize: 34,
            onChanged: (_) => setState(() => _balanceTouched = true),
            hint: _balanceNotShown
                ? 'Số dư trong app hiện là ${formatBalance(widget.source!.balance)}. $hint'
                : hint,
          ),
          const SizedBox(height: 22),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  SwitchListTile(
                    value: _isDefault,
                    onChanged: (v) => setState(() => _isDefault = v),
                    title: const Text('Dùng mặc định khi chi tiêu',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    subtitle: const Text('Tự chọn sẵn nguồn này ở màn Thêm chi tiêu',
                        style: TextStyle(fontSize: 13, color: AppColors.muted)),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  SwitchListTile(
                    value: _inTotal,
                    onChanged: (v) => setState(() => _inTotalChoice = v),
                    title: const Text('Tính vào tổng tiền hiện có',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    subtitle: const Text('Tắt cho tiền tiết kiệm không muốn đụng tới',
                        style: TextStyle(fontSize: 13, color: AppColors.muted)),
                  ),
                ],
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
              label: const Text('Xoá nguồn tiền này'),
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
              label: Text(_isEdit ? 'Lưu thay đổi' : 'Lưu nguồn tiền'),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({required this.type, required this.selected, required this.onTap});

  final SourceType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.selectedFill : AppColors.surface,
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
              SourceIcon(type: type, size: 40),
              const SizedBox(height: 8),
              Text(type.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
