import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../utils/format.dart';

/// Số tiền tối đa nhập được (12 chữ số).
const maxAmount = 999999999999;

/// Đọc số tiền từ ô nhập đã có dấu chấm hàng nghìn ("45.000" → 45000).
int parseAmount(String text) => int.tryParse(text.replaceAll('.', '')) ?? 0;

/// Ghi số tiền vào ô nhập (0 = để trống), đặt con trỏ ở cuối.
void setAmount(TextEditingController c, int v) {
  final text = v == 0 ? '' : formatNumber(v);
  c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
}

/// Chỉ cho nhập số và tự thêm dấu chấm phân cách hàng nghìn: 50000 → 50.000.
class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 12) digits = digits.substring(0, 12);
    final n = int.tryParse(digits) ?? 0;
    final text = n == 0 ? '' : formatNumber(n);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Khung trắng nhập số tiền lớn, gạch chân màu chủ đạo.
class AmountCard extends StatelessWidget {
  const AmountCard({
    super.key,
    required this.controller,
    this.label = 'Số tiền',
    this.fontSize = 40,
    this.autofocus = false,
    this.onChanged,
    this.onClear,
    this.quickAmounts = const [],
    this.onQuickAdd,
    this.hint,
  });

  final TextEditingController controller;
  final String label;
  final double fontSize;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  /// Có giá trị thì hiện nút ✕ xoá số tiền.
  final VoidCallback? onClear;
  final List<int> quickAmounts;
  final ValueChanged<int>? onQuickAdd;

  /// Dòng giải thích nhỏ dưới ô nhập.
  final String? hint;

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
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted)),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: autofocus,
                  onChanged: onChanged,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsFormatter()],
                  style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                  decoration: const InputDecoration(
                    hintText: '0',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              Text('đ', style: TextStyle(fontSize: fontSize * 0.68, fontWeight: FontWeight.w600, color: AppColors.muted)),
              if (onClear != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Xoá số tiền',
                  onPressed: onClear,
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F2F4)),
                  icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
                ),
              ],
            ],
          ),
          Container(height: 2, color: AppColors.accent),
          if (quickAmounts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < quickAmounts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onQuickAdd?.call(quickAmounts[i]),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        padding: EdgeInsets.zero,
                        backgroundColor: const Color(0xFFF8F9FA),
                        side: const BorderSide(color: AppColors.line),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle:
                            const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      child: FittedBox(child: Text('+${formatNumber(quickAmounts[i])}')),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (hint != null) ...[
            const SizedBox(height: 12),
            Text(hint!, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }
}

/// Tiêu đề một mục trong form ("Danh mục", "Ngày"...), có thể kèm nút bên phải.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          ?trailing,
        ],
      ),
    );
  }
}

/// Ô chọn ngày; ngày tương lai không chọn được.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.date, required this.onChanged, this.helpText = 'Chọn ngày'});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final String helpText;

  Future<void> _pick(BuildContext context) async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: date.isAfter(today) ? today : date,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: helpText,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final back = daysBefore(dateOnly(DateTime.now()), date);
    final text = switch (back) {
      0 => 'Hôm nay, ${formatDate(date)}',
      1 => 'Hôm qua, ${formatDate(date)}',
      _ => formatFullDate(date),
    };
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _pick(context),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.calendar_today_outlined, color: AppColors.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
              const Icon(Icons.chevron_right, color: AppColors.muted),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ô nhập chữ trắng bo góc dùng chung cho tên và ghi chú.
class TextBox extends StatelessWidget {
  const TextBox({super.key, required this.controller, required this.hint, this.maxLength = 100, this.onChanged});

  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textCapitalization: TextCapitalization.sentences,
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hint,
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
    );
  }
}

/// Nhãn "Ghi chú (không bắt buộc)".
class NoteLabel extends StatelessWidget {
  const NoteLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: 'Ghi chú ', style: TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: '(không bắt buộc)', style: TextStyle(color: AppColors.muted)),
        ]),
        style: TextStyle(fontSize: 15),
      ),
    );
  }
}

/// Một lựa chọn trong [PickerField].
class PickerOption<T> {
  const PickerOption({
    required this.value,
    required this.leading,
    required this.title,
    this.trailing,
    this.trailingColor = AppColors.muted,
  });

  final T value;

  /// Biểu tượng bên trái, vẽ theo kích thước được truyền vào.
  final Widget Function(double size) leading;
  final String title;
  final String? trailing;
  final Color trailingColor;
}

/// Ô chọn dạng danh sách thả xuống (danh mục, nguồn tiền) theo bản thiết kế.
class PickerField<T> extends StatefulWidget {
  const PickerField({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.semanticLabel,
  });

  final List<PickerOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final String semanticLabel;

  @override
  State<PickerField<T>> createState() => _PickerFieldState<T>();
}

class _PickerFieldState<T> extends State<PickerField<T>> {
  final _controller = MenuController();
  bool _open = false;

  Widget _row(PickerOption<T> o, {required double iconSize, bool check = false, bool selected = false}) {
    return Row(
      children: [
        o.leading(iconSize),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            o.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink),
          ),
        ),
        if (o.trailing != null) ...[
          const SizedBox(width: 8),
          Text(o.trailing!, style: TextStyle(fontSize: 13, color: o.trailingColor)),
        ],
        if (check) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 20,
            child: selected ? const Icon(Icons.check, size: 20, color: AppColors.accent) : null,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.options.firstWhere(
      (o) => o.value == widget.selected,
      orElse: () => widget.options.first,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MenuAnchor(
          controller: _controller,
          onOpen: () => setState(() => _open = true),
          onClose: () => setState(() => _open = false),
          alignmentOffset: const Offset(0, 6),
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shadowColor: const WidgetStatePropertyAll(Color(0x29101828)),
            elevation: const WidgetStatePropertyAll(10),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(Size(width, 420)),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.line),
            )),
          ),
          menuChildren: [
            for (var i = 0; i < widget.options.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: AppColors.divider),
              MenuItemButton(
                onPressed: () => widget.onChanged(widget.options[i].value),
                style: ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(width, 52)),
                  padding: const WidgetStatePropertyAll(EdgeInsets.fromLTRB(10, 0, 14, 0)),
                  backgroundColor: WidgetStatePropertyAll(
                    widget.options[i].value == widget.selected ? AppColors.selectedFill : AppColors.surface,
                  ),
                ),
                child: SizedBox(
                  width: width - 24,
                  child: _row(
                    widget.options[i],
                    iconSize: 32,
                    check: true,
                    selected: widget.options[i].value == widget.selected,
                  ),
                ),
              ),
            ],
          ],
          builder: (context, controller, _) => Semantics(
            label: widget.semanticLabel,
            button: true,
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: _open ? AppColors.accent : AppColors.line, width: _open ? 2 : 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => controller.isOpen ? controller.close() : controller.open(),
                child: SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
                    child: Row(
                      children: [
                        Expanded(child: _row(current, iconSize: 36)),
                        const SizedBox(width: 8),
                        Icon(_open ? Icons.expand_less : Icons.expand_more, color: AppColors.muted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
