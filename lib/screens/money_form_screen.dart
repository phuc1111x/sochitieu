import 'package:flutter/material.dart';

import '../data/expense_db.dart';
import '../models/money_move.dart';
import '../models/money_source.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// Mở màn "Tiền vào / Chuyển giữa các nguồn". [move] = sửa một giao dịch đã có,
/// nếu không thì [kind] (`in` hoặc `move`) cùng nguồn chọn sẵn [fromId] / [toId].
Future<void> openMoneyForm(
  BuildContext context, {
  MoneyMove? move,
  String kind = MoveKind.income,
  int? fromId,
  int? toId,
  bool cardPayment = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => MoneyFormScreen(
        move: move,
        kind: move?.kind ?? kind,
        fromId: fromId,
        toId: toId,
        cardPayment: cardPayment,
      ),
    ),
  );
  if (message != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class MoneyFormScreen extends StatefulWidget {
  const MoneyFormScreen({super.key, this.move, required this.kind, this.fromId, this.toId, this.cardPayment = false});

  final MoneyMove? move;
  final String kind;
  final int? fromId;
  final int? toId;

  /// "Thanh toán dư nợ thẻ": biểu mẫu chuyển tiền vào thẻ tín dụng (chỉ khi thêm mới).
  final bool cardPayment;

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
  bool get _cardPay => widget.cardPayment && !_isEdit && _isMove;
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

  /// Nguồn trả tiền khi chỉ chọn sẵn nguồn nhận (ví dụ "Thanh toán dư nợ"): nguồn mặc định nếu nó không phải
  /// nguồn nhận và không phải thẻ tín dụng; nếu không thì nguồn đầu tiên không phải thẻ tín dụng; rồi
  /// nguồn bất kỳ khác nguồn nhận; không còn nguồn nào khác thì giữ như cũ (chính nguồn nhận).
  int _payerFor(int toId) {
    final others = _active.where((s) => s.id != toId).toList();
    for (final s in others) {
      if (s.isDefault && !s.isCredit) return s.id!;
    }
    for (final s in others) {
      if (!s.isCredit) return s.id!;
    }
    return others.isEmpty ? toId : others.first.id!;
  }

  /// Chọn sẵn nguồn còn trống: tiền vào → nguồn mặc định; chuyển giữa các nguồn → từ nguồn mặc định sang nguồn khác.
  void _fillDefaults() {
    if (_isMove) {
      if (!_exists(_fromId)) _fromId = _exists(_toId) ? _payerFor(_toId!) : _defaultId;
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
      _show('Cần ít nhất hai nguồn tiền để chuyển giữa các nguồn');
      return;
    }
    setState(() {
      if (kind == MoveKind.move) {
        // Nguồn đang chọn ở "Tiền vào" trở thành nguồn chuyển đi.
        _fromId = _toId;
        _toId = null;
      } else {
        // Quay lại "Tiền vào": tiền vào lại nguồn đã chọn trước đó, bỏ nguồn chuyển.
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
      _show(_isMove ? 'Chọn hai nguồn khác nhau để chuyển giữa các nguồn' : 'Chọn nguồn nhận tiền');
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
      note: singleLineNote(_note.text),
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
              : 'Đã ghi ${formatMoney(amount)} tiền vào ${to.name}');
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
            '${widget.move!.kind == MoveKind.move ? 'Chuyển giữa các nguồn' : 'Tiền vào'}\n'
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
        title: Text(_cardPay
            ? 'Thanh toán dư nợ thẻ'
            : _isEdit
                ? (_isMove ? 'Sửa chuyển giữa các nguồn' : 'Sửa tiền vào')
                : (_isMove ? 'Chuyển giữa các nguồn' : 'Tiền vào')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // Khi sửa không đổi được loại giao dịch: nút chọn bị làm mờ và không bấm được.
          if (!_cardPay) ...[
            Opacity(
              opacity: _isEdit ? 0.5 : 1,
              child: IgnorePointer(
                ignoring: _isEdit,
                child: SegmentedTabs(
                  labels: const ['Tiền vào', 'Chuyển giữa các nguồn'],
                  selected: _isMove ? 1 : 0,
                  onChanged: (i) => _setKind(i == 1 ? MoveKind.move : MoveKind.income),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          AmountCard(
            controller: _amount,
            autofocus: !_isEdit,
            labelTrailing: DateChip(date: _date, onChanged: (d) => setState(() => _date = d)),
            footer: _buildDebtRow(),
            onChanged: (_) => setState(() {}),
          ),
          if (_loaded) ...[
            if (_isMove) ...[
              const SizedBox(height: 18),
              const FieldLabel('Từ nguồn'),
              _sourcePicker('Từ nguồn', _fromId, _pickFrom),
            ],
            const SizedBox(height: 18),
            FieldLabel(
              _cardPay ? 'Thẻ được thanh toán' : (_isMove ? 'Đến nguồn' : 'Vào nguồn'),
              trailing: _isMove && !_cardPay ? _swapButton() : null,
            ),
            _sourcePicker('Đến nguồn', _toId, _pickTo),
            const SizedBox(height: 18),
            _buildPreview(),
          ],
          const SizedBox(height: 18),
          const NoteLabel(),
          TextBox(
            controller: _note,
            minLines: 1,
            maxLines: 3,
            maxLength: 500,
            textInputAction: TextInputAction.done,
            hint: _cardPay
                ? 'Ví dụ: Thanh toán sao kê tháng 10'
                : _isMove
                    ? 'Ví dụ: Rút tiền mặt'
                    : 'Ví dụ: Lương tháng 10',
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
                  : _cardPay
                      ? 'Lưu thanh toán'
                      : _isMove
                          ? 'Lưu'
                          : 'Lưu tiền vào'),
            ),
          ),
        ),
      ),
    );
  }

  /// Ô chọn nguồn dạng thả xuống: biểu tượng, tên và số dư bên phải (thẻ tín dụng: "Dư nợ X").
  Widget _sourcePicker(String label, int? selected, ValueChanged<int> onPick) {
    return PickerField<int>(
      semanticLabel: label,
      selected: selected ?? -1,
      onChanged: onPick,
      options: [
        for (final s in _sources)
          PickerOption<int>(
            value: s.id!,
            leading: (size) => SourceIcon(type: s.sourceType, size: size),
            title: s.name,
            trailing: s.isCredit && s.balance < 0 ? 'Dư nợ ${formatMoney(-s.balance)}' : formatBalance(s.balance),
            trailingColor: !s.isCredit && s.balance < 0 ? AppColors.danger : AppColors.muted,
          ),
      ],
    );
  }

  void _swap() {
    if (_fromId == null || _toId == null) return;
    setState(() {
        final from = _fromId;
        _fromId = _toId;
        _toId = from;
    });
  }

  Widget _swapButton() {
    return Material(
      color: AppColors.selectedFill,
      shape: const StadiumBorder(side: BorderSide(color: AppColors.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _swap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_vert, size: 16, color: AppColors.accent),
              SizedBox(width: 4),
              Text('Đổi chiều', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  /// "Dư nợ hiện tại X đ" + nút "Trả hết dư nợ" (chỉ khi thanh toán thẻ còn dư nợ).
  Widget? _buildDebtRow() {
    if (!_cardPay) return null;
    final card = _byId(_toId);
    if (card == null || !card.isCredit || card.balance >= 0) return null;
    final debt = -card.balance;
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Dư nợ hiện tại '),
              TextSpan(
                  text: formatMoney(debt),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
            ]),
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ),
        TextButton(
          onPressed: () => setState(() => setAmount(_amount, debt.clamp(0, maxAmount))),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: const Text('Trả hết dư nợ'),
        ),
      ],
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
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  _cardPay
                      ? 'Không tính là chi tiêu: các khoản đã tính lúc quẹt thẻ.'
                      : 'Không tính là chi tiêu, tổng tiền hiện có không đổi.',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
        ],
      ),
    );
  }
}
