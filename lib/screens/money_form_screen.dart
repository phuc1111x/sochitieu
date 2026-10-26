import 'package:flutter/material.dart';

import '../data/expense_db.dart';
import '../models/money_move.dart';
import '../models/money_source.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// Mở màn "Thêm tiền / Chuyển tiền". [move] = sửa một giao dịch đã có,
/// nếu không thì [kind] (`in` hoặc `move`) cùng nguồn chọn sẵn [fromId] / [toId].
Future<void> openMoneyForm(
  BuildContext context, {
  MoneyMove? move,
  String kind = MoveKind.income,
  int? fromId,
  int? toId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => MoneyFormScreen(move: move, kind: move?.kind ?? kind, fromId: fromId, toId: toId),
    ),
  );
  if (message != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class MoneyFormScreen extends StatefulWidget {
  const MoneyFormScreen({super.key, this.move, required this.kind, this.fromId, this.toId});

  final MoneyMove? move;
  final String kind;
  final int? fromId;
  final int? toId;

  @override
  State<MoneyFormScreen> createState() => _MoneyFormScreenState();
}

class _MoneyFormScreenState extends State<MoneyFormScreen> {
  late String _kind = widget.kind == MoveKind.move ? MoveKind.move : MoveKind.income;
  late final _amount = TextEditingController(
    text: widget.move == null ? '' : formatNumber(widget.move!.amount),
  );
  late final _note = TextEditingController(text: widget.move?.note ?? '');
  late DateTime _date = widget.move?.date ?? dateOnly(DateTime.now());
  late int? _fromId = widget.move?.fromId ?? widget.fromId;
  late int? _toId = widget.move?.toId ?? widget.toId;
  List<MoneySource> _sources = const [];
  bool _loaded = false;
  bool _saving = false;

  bool get _isEdit => widget.move != null;
  bool get _isMove => _kind == MoveKind.move;
  int get _amountValue => parseAmount(_amount.text);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Nguồn để chọn: các nguồn chưa xoá, cộng nguồn (đã xoá) mà giao dịch đang sửa dùng tới.
  Future<void> _load() async {
    final all = await ExpenseDb.instance.sourcesWithBalance(includeArchived: true);
    if (!mounted) return;
    final used = {widget.move?.fromId, widget.move?.toId};
    setState(() {
      _sources = all.where((s) => !s.archived || used.contains(s.id)).toList();
      _loaded = true;
      if (!_isEdit) _fillDefaults();
    });
  }

  List<MoneySource> get _active => _sources.where((s) => !s.archived).toList();

  int? get _defaultId {
    final active = _active;
    for (final s in active) {
      if (s.isDefault) return s.id;
    }
    return active.isEmpty ? null : active.first.id;
  }

  bool _exists(int? id) => id != null && _sources.any((s) => s.id == id);

  /// Chọn sẵn nguồn còn trống: tiền vào → nguồn mặc định; chuyển tiền → từ nguồn mặc định sang nguồn khác.
  void _fillDefaults() {
    if (_isMove) {
      if (!_exists(_fromId)) _fromId = _exists(_toId) ? _toId : _defaultId;
      if (!_exists(_toId) || _toId == _fromId) {
        _toId = _active.where((s) => s.id != _fromId).map((s) => s.id).firstOrNull;
      }
    } else {
      if (!_exists(_toId)) _toId = _exists(_fromId) ? _fromId : _defaultId;
    }
  }

  void _setKind(String kind) {
    // Chưa tải xong nguồn tiền thì chưa biết có đủ hai nguồn để chuyển hay không.
    if (kind == _kind || !_loaded || _isEdit) return;
    if (kind == MoveKind.move && _active.length < 2) {
      _show('Cần ít nhất hai nguồn tiền để chuyển tiền');
      return;
    }
    setState(() {
      if (kind == MoveKind.move) {
        // Nguồn đang chọn ở "Thêm tiền" trở thành nguồn chuyển đi.
        _fromId = _toId;
        _toId = null;
      } else {
        // Quay lại "Thêm tiền": tiền vào lại nguồn đã chọn trước đó, bỏ nguồn chuyển.
        _toId = _fromId ?? _toId;
        _fromId = null;
      }
      _kind = kind;
      _fillDefaults();
    });
  }

  // Chọn trùng nguồn ở ô bên kia thì đổi chỗ hai nguồn.
  void _pickFrom(int id) => setState(() {
        if (id == _toId) _toId = _fromId;
        _fromId = id;
      });

  void _pickTo(int id) => setState(() {
        if (_isMove && id == _fromId) _fromId = _toId;
        _toId = id;
      });

  MoneySource? _byId(int? id) {
    for (final s in _sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Số dư hiện tại của [s] khi bỏ ảnh hưởng của chính giao dịch đang sửa.
  int _baseBalance(MoneySource s) => s.balance - (widget.move?.effectOn(s.id!) ?? 0);

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final amount = _amountValue;
    if (amount <= 0) {
      _show('Vui lòng nhập số tiền');
      return;
    }
    final to = _byId(_toId);
    final from = _isMove ? _byId(_fromId) : null;
    if (to == null || (_isMove && (from == null || from.id == to.id))) {
      _show(_isMove ? 'Chọn hai nguồn khác nhau để chuyển tiền' : 'Chọn nguồn nhận tiền');
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final move = MoneyMove(
      id: widget.move?.id,
      kind: _kind,
      amount: amount,
      fromId: from?.id,
      toId: to.id,
      date: _date,
      note: _note.text.trim(),
      createdAt: widget.move?.createdAt ?? now,
      updatedAt: now,
    );
    final db = ExpenseDb.instance;
    try {
      if (_isEdit) {
        await db.updateMove(move);
      } else {
        await db.insertMove(move);
      }
      if (!mounted) return;
      Navigator.of(context).pop(_isEdit
          ? 'Đã lưu thay đổi'
          : _isMove
              ? 'Đã chuyển ${formatMoney(amount)} sang ${to.name}'
              : 'Đã thêm ${formatMoney(amount)} vào ${to.name}');
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
        title: const Text('Xoá giao dịch này?'),
        content: Text('${formatMoney(widget.move!.amount)} · '
            '${widget.move!.kind == MoveKind.move ? 'Chuyển tiền' : 'Thêm tiền'}\n'
            'Số dư các nguồn liên quan sẽ được tính lại. Không thể hoàn tác sau khi xoá.'),
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
    await ExpenseDb.instance.deleteMove(widget.move!.id!);
    if (!mounted) return;
    Navigator.of(context).pop('Đã xoá giao dịch');
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
        title: Text(_isEdit
            ? (_isMove ? 'Sửa chuyển tiền' : 'Sửa thêm tiền')
            : (_isMove ? 'Chuyển tiền' : 'Thêm tiền')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // Khi sửa không đổi được loại giao dịch: nút chọn bị làm mờ và không bấm được.
          Opacity(
            opacity: _isEdit ? 0.5 : 1,
            child: IgnorePointer(
              ignoring: _isEdit,
              child: _KindSwitch(kind: _kind, onChanged: _setKind),
            ),
          ),
          const SizedBox(height: 22),
          AmountCard(
            controller: _amount,
            autofocus: !_isEdit,
            onChanged: (_) => setState(() {}),
          ),
          if (_loaded) ...[
            if (_isMove) ...[
              const SizedBox(height: 22),
              const FieldLabel('Từ nguồn'),
              _SourceChips(sources: _sources, selected: _fromId, onPick: _pickFrom),
            ],
            const SizedBox(height: 22),
            FieldLabel(_isMove ? 'Đến nguồn' : 'Vào nguồn'),
            _SourceChips(sources: _sources, selected: _toId, onPick: _pickTo),
            const SizedBox(height: 22),
            _buildPreview(),
          ],
          const SizedBox(height: 22),
          const FieldLabel('Ngày'),
          DateField(date: _date, onChanged: (d) => setState(() => _date = d)),
          const SizedBox(height: 22),
          const NoteLabel(),
          TextBox(controller: _note, hint: _isMove ? 'Ví dụ: Rút tiền mặt' : 'Ví dụ: Lương tháng 10'),
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
              label: const Text('Xoá giao dịch này'),
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
              label: Text(_isEdit
                  ? 'Lưu thay đổi'
                  : _isMove
                      ? 'Lưu chuyển tiền'
                      : 'Lưu khoản tiền vào'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final amount = _amountValue;
    final lines = <({String name, int before, int after})>[];
    final from = _isMove ? _byId(_fromId) : null;
    final to = _byId(_toId);
    if (from != null) {
      final b = _baseBalance(from);
      lines.add((name: from.name, before: b, after: b - amount));
    }
    if (to != null) {
      final b = _baseBalance(to);
      lines.add((name: to.name, before: b, after: b + amount));
    }
    TextSpan money(int n) =>
        TextSpan(text: formatBalance(n), style: TextStyle(color: n < 0 ? AppColors.danger : AppColors.ink));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Sau khi lưu',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(l.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 12),
                  // Số tiền dài (tỷ đồng) thì thu nhỏ chữ thay vì tràn ra ngoài.
                  Flexible(
                    flex: 5,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text.rich(
                        TextSpan(children: [money(l.before), const TextSpan(text: ' → '), money(l.after)]),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_isMove)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Chuyển tiền không tính là chi tiêu, tổng tiền hiện có không đổi.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
        ],
      ),
    );
  }
}

/// Hai nút "Thêm tiền" | "Chuyển tiền" dạng segmented.
class _KindSwitch extends StatelessWidget {
  const _KindSwitch({required this.kind, required this.onChanged});

  final String kind;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String id, String label) {
      final selected = id == kind;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: GestureDetector(
            onTap: () => onChanged(id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                boxShadow: selected
                    ? const [BoxShadow(color: Color(0x1F101828), blurRadius: 3, offset: Offset(0, 1))]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.ink : AppColors.muted,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.segmentTrack, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          tab(MoveKind.income, 'Thêm tiền'),
          const SizedBox(width: 4),
          tab(MoveKind.move, 'Chuyển tiền'),
        ],
      ),
    );
  }
}

/// Dải thẻ nguồn tiền cuộn ngang, mỗi thẻ có tên và số dư.
class _SourceChips extends StatelessWidget {
  const _SourceChips({required this.sources, required this.selected, required this.onPick});

  final List<MoneySource> sources;
  final int? selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: sources.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final s = sources[i];
          final sel = s.id == selected;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: sel ? AppColors.selectedFill : AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: sel ? AppColors.accent : AppColors.line, width: sel ? 2 : 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onPick(s.id!),
                child: Semantics(
                  selected: sel,
                  button: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
                    child: Row(
                      children: [
                        SourceIcon(type: s.sourceType, size: 36),
                        const SizedBox(width: 10),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 1),
                            Text(
                              formatBalance(s.balance),
                              style: TextStyle(
                                fontSize: 12,
                                color: s.balance < 0 ? AppColors.danger : AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
