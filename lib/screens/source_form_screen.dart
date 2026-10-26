import 'package:flutter/material.dart';

import '../data/expense_db.dart';
import '../data/payment_apps.dart';
import '../models/money_source.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/app_picker.dart';
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
  static const overLimitMessage = 'Hạn mức còn lại không được lớn hơn tổng hạn mức.';

  late final _name = TextEditingController(text: widget.source?.name ?? '');
  late String _type = widget.source?.type ?? 'cash';

  /// Nguồn thường: "Số dư hiện tại".
  late final _balance = TextEditingController();
  bool _balanceTouched = false;

  /// Thẻ tín dụng: "Tổng hạn mức" và "Hạn mức còn lại"; app tự tính số nợ = hạn mức − còn lại.
  late final _limit = TextEditingController();
  late final _remaining = TextEditingController();
  bool _remainingTouched = false;
  late bool _isDefault = widget.source?.isDefault ?? false;

  /// Thêm mới: "Tính vào tổng" đi theo loại (tắt cho tiết kiệm) cho tới khi người dùng tự bật/tắt.
  late bool? _inTotalChoice = widget.source?.inTotal;

  /// Ứng dụng thanh toán đang gắn (tên gói) và tên + biểu tượng đọc từ điện thoại.
  /// Gói có mà [_app] null sau khi đọc xong: ứng dụng không còn trên máy.
  late String? _appPackage = widget.source?.appPackage;
  InstalledApp? _app;
  bool _appLoading = false;
  bool _saving = false;

  bool get _isEdit => widget.source != null;
  bool get _isCredit => _type == 'credit';
  bool get _inTotal => _inTotalChoice ?? _type != 'saving';

  /// Tiền mặt không có ứng dụng thanh toán.
  bool get _showApp => _type != 'cash';

  int get _limitValue => parseAmount(_limit.text);
  int get _remainingValue => parseAmount(_remaining.text);

  /// Hạn mức còn lại lớn hơn tổng hạn mức. Khi sửa mà chưa chạm vào ô "còn lại" thì không báo:
  /// lúc đó ô chỉ hiện số app đang có và sẽ không ghi gì vào sổ cái.
  bool get _overLimit =>
      _limitValue > 0 && _remainingValue > _limitValue && (!_isEdit || _remainingTouched);

  @override
  void initState() {
    super.initState();
    final pkg = _appPackage;
    if (pkg != null) {
      _appLoading = true;
      // Lỗi khi đọc thì coi như ứng dụng không còn trên máy (vẫn chọn lại được), không treo ở "đang đọc".
      PaymentApps.instance.appInfo(pkg).then<InstalledApp?>((app) => app, onError: (Object _) => null).then((app) {
        if (!mounted || _appPackage != pkg) return;
        setState(() {
          _app = app;
          _appLoading = false;
        });
      });
    }
    if (_isEdit) {
      final source = widget.source!;
      if (source.isCredit && (source.creditLimit ?? 0) > 0) setAmount(_limit, source.creditLimit!);
      _showCurrentBalance();
      _syncRemaining();
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
    _limit.dispose();
    _remaining.dispose();
    super.dispose();
  }

  /// Khi sửa: hiện số dư hiện tại trong ô nhập của nguồn thường.
  void _showCurrentBalance() {
    setAmount(_balance, widget.source!.balance.clamp(0, maxAmount));
  }

  /// Khi sửa thẻ mà chưa chạm vào ô "Hạn mức còn lại": ô này luôn bằng tổng hạn mức − số nợ
  /// trong app (thẻ cũ chưa có hạn mức: để trống cho tới khi nhập hạn mức).
  void _syncRemaining() {
    if (!_isEdit || _remainingTouched) return;
    final limit = _limitValue;
    setAmount(_remaining, limit > 0 ? (limit + widget.source!.balance).clamp(0, maxAmount) : 0);
  }

  /// Số dư hiện tại không ghi được vào ô nhập "Số dư hiện tại" (số âm).
  bool get _balanceNotShown => _isEdit && !_balanceTouched && widget.source!.balance < 0;

  void _pickType(String id) {
    setState(() {
      _type = id;
      // Đổi sang tiền mặt thì bỏ liên kết ứng dụng thanh toán.
      if (!_showApp) _setApp(null);
      if (_isEdit && !_balanceTouched) _showCurrentBalance();
      _syncRemaining();
    });
  }

  void _setApp(InstalledApp? app) {
    _appPackage = app?.package;
    _app = app;
    _appLoading = false;
  }

  Future<void> _chooseApp() async {
    // Bỏ focus ô số dư: nếu không, đóng bảng chọn xong bàn phím lại bật lên.
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await showAppPicker(context, selected: _appPackage);
    if (result == null || !mounted) return;
    setState(() => _setApp(result.app));
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
    final int balance;
    final bool touched;
    int? creditLimit;
    if (_isCredit) {
      creditLimit = _limitValue;
      if (creditLimit <= 0) {
        _show('Vui lòng nhập tổng hạn mức của thẻ');
        return;
      }
      // Thẻ mới: ô "còn lại" để trống sẽ thành nợ bằng cả hạn mức, nên bắt nhập (thẻ đã dùng
      // hết hạn mức thì gõ 0).
      if (!_isEdit && _remaining.text.trim().isEmpty) {
        _show('Vui lòng nhập hạn mức còn lại của thẻ');
        return;
      }
      if (_overLimit) {
        _show(overLimitMessage);
        return;
      }
      // Số dư của thẻ = −số nợ = hạn mức còn lại − tổng hạn mức.
      balance = _remainingValue - creditLimit;
      touched = _remainingTouched;
    } else {
      balance = parseAmount(_balance.text);
      touched = _balanceTouched;
    }
    setState(() => _saving = true);
    try {
      final db = ExpenseDb.instance;
      if (_isEdit) {
        await db.updateSource(
          widget.source!.copyWith(
            name: name,
            type: _type,
            isDefault: _isDefault,
            inTotal: _inTotal,
            creditLimit: creditLimit,
            appPackage: _showApp ? _appPackage : null,
          ),
          newBalance: touched ? balance : null,
        );
      } else {
        await db.insertSource(
          MoneySource(
            name: name,
            type: _type,
            isDefault: _isDefault,
            inTotal: _inTotal,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            creditLimit: creditLimit,
            appPackage: _showApp ? _appPackage : null,
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
    final hint = _isEdit
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
          if (_isCredit)
            _buildCreditCard()
          else
            AmountCard(
              controller: _balance,
              label: 'Số dư hiện tại',
              fontSize: 34,
              onChanged: (_) => setState(() => _balanceTouched = true),
              hint: _balanceNotShown
                  ? 'Số dư trong app hiện là ${formatBalance(widget.source!.balance)}. $hint'
                  : hint,
            ),
          if (_showApp) ...[
            const SizedBox(height: 22),
            _buildAppField(),
          ],
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
                    subtitle: Text(
                        _isCredit ? 'Số nợ thẻ được trừ khỏi tổng tiền' : 'Tắt cho tiền tiết kiệm không muốn đụng tới',
                        style: const TextStyle(fontSize: 13, color: AppColors.muted)),
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

  /// Mục "Ứng dụng thanh toán (không bắt buộc)": ô bấm mở bảng chọn ứng dụng đã cài.
  Widget _buildAppField() {
    final pkg = _appPackage;
    final app = _app;
    final Widget leading;
    final Widget body;
    final Widget trailing;
    const changeText = Text('Đổi', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.accent));
    if (pkg == null) {
      leading = const _DashedTile(size: 40);
      body = const Text('Chọn ứng dụng', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500));
      trailing = const Icon(Icons.chevron_right, size: 22, color: AppColors.muted);
    } else if (app == null && _appLoading) {
      leading = const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
      body = const Text('Đang đọc ứng dụng…', style: TextStyle(fontSize: 15, color: AppColors.muted));
      trailing = changeText;
    } else if (app != null) {
      leading = AppIconTile(app: app, size: 40);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(app.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          const Text('Mở sau khi lưu khoản chi', style: TextStyle(fontSize: 13, color: AppColors.muted)),
        ],
      );
      trailing = changeText;
    } else {
      // Đã gắn nhưng ứng dụng không còn mở được (đã gỡ, hoặc khôi phục trên máy khác).
      leading = const TintedIcon(
          icon: Icons.error_outline, fg: AppColors.danger, bg: AppColors.dangerSoft, size: 40);
      body = const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ứng dụng không còn trên máy',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.danger)),
          SizedBox(height: 2),
          Text('Chọn lại hoặc bỏ liên kết', style: TextStyle(fontSize: 13, color: AppColors.muted)),
        ],
      );
      trailing = changeText;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Ứng dụng thanh toán ', style: TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: '(không bắt buộc)', style: TextStyle(color: AppColors.muted)),
            ]),
            style: TextStyle(fontSize: 15),
          ),
        ),
        Semantics(
          label: 'Ứng dụng thanh toán',
          button: true,
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.line),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _saving ? null : _chooseApp,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  child: Row(
                    children: [
                      leading,
                      const SizedBox(width: 12),
                      Expanded(child: body),
                      const SizedBox(width: 8),
                      trailing,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Khi chi tiêu bằng nguồn này, Sổ chi tiêu ghi khoản chi xong sẽ mở ứng dụng này để bạn thanh toán.',
          style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
        ),
      ],
    );
  }

  /// Khung thẻ tín dụng: Tổng hạn mức + Hạn mức còn lại, ô "App tự tính: đang nợ" kèm thanh % đã dùng.
  Widget _buildCreditCard() {
    final limit = _limitValue;
    // Khi sửa mà chưa chạm vào ô "còn lại": số nợ thật trong sổ cái (kể cả khi đã vượt hạn mức,
    // lúc ô "còn lại" chỉ hiện được 0).
    final debt = _isEdit && !_remainingTouched ? -widget.source!.balance : limit - _remainingValue;
    final used = usedPercentOf(debt, limit);
    final usedLabel = limit > 0 ? 'Đã dùng $used% hạn mức' : 'Nhập tổng hạn mức để xem đã dùng bao nhiêu';
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
          MoneyLineField(
            controller: _limit,
            label: 'Tổng hạn mức của thẻ',
            fontSize: 24,
            emphasized: false,
            onChanged: (_) => setState(_syncRemaining),
          ),
          const SizedBox(height: 18),
          MoneyLineField(
            controller: _remaining,
            label: 'Hạn mức còn lại (khả dụng)',
            allowZero: true,
            onChanged: (_) => setState(() => _remainingTouched = true),
          ),
          if (_overLimit) ...[
            const SizedBox(height: 18),
            Semantics(
              liveRegion: true,
              child: const Text(overLimitMessage,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.danger)),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.fieldFill, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Expanded(
                      child: Text('App tự tính: đang nợ', style: TextStyle(fontSize: 14, color: AppColors.muted)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMoney(debt > 0 ? debt : 0),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.danger),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                UsageBar(percent: used, height: 8, label: usedLabel, track: AppColors.line),
                const SizedBox(height: 8),
                Text(usedLabel, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Mở app ngân hàng, chép số “Hạn mức khả dụng” vào ô Hạn mức còn lại. Chi bằng thẻ thì hạn mức '
            'còn lại giảm; trả thẻ (Chuyển tiền từ ngân hàng sang thẻ) thì tăng lại.',
            style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
          ),
        ],
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

/// Ô vuông viền nét đứt có dấu + (chưa chọn ứng dụng thanh toán).
class _DashedTile extends StatelessWidget {
  const _DashedTile({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.add, size: 20, color: AppColors.muted),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.lineStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)).deflate(0.75);
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}
