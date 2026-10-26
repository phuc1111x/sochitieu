/// Định dạng tiền và ngày theo kiểu Việt Nam, không cần thư viện ngoài.
library;

String formatNumber(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return n < 0 ? '-$buf' : buf.toString();
}

String formatMoney(int amount) => '${formatNumber(amount)} đ';

String two(int n) => n.toString().padLeft(2, '0');

const _weekdays = [
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ Nhật',
];

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];

String formatDayMonth(DateTime d) => '${two(d.day)}/${two(d.month)}';

String formatDate(DateTime d) => '${formatDayMonth(d)}/${d.year}';

String formatFullDate(DateTime d) => '${weekdayName(d)}, ${formatDate(d)}';

String formatTime(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

/// Khoá ngày lưu trong database, dạng yyyy-MM-dd (so sánh chuỗi = so sánh ngày).
String dateKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

DateTime parseDateKey(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Số ngày từ [d] đến hôm nay (0 = hôm nay).
int daysBefore(DateTime today, DateTime d) => DateTime.utc(today.year, today.month, today.day)
    .difference(DateTime.utc(d.year, d.month, d.day))
    .inDays;

int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

String relativeDayLabel(int back) => switch (back) {
      0 => 'Hôm nay',
      1 => 'Hôm qua',
      _ => '$back ngày trước',
    };

String relativeMonthLabel(int back) => switch (back) {
      0 => 'Tháng này',
      1 => 'Tháng trước',
      _ => '$back tháng trước',
    };

String formatLastBackup(DateTime t) {
  final today = dateOnly(DateTime.now());
  final back = daysBefore(today, t);
  final day = switch (back) {
    0 => 'Hôm nay',
    1 => 'Hôm qua',
    _ => formatDate(t),
  };
  return '${formatTime(t)} · $day';
}

/// Dấu trừ dùng khi hiển thị số âm (U+2212), rõ hơn gạch nối "-".
const minusSign = '−';

/// Số dư: âm thì có dấu "−" (ví dụ thẻ tín dụng đang nợ), dương thì không có dấu.
String formatBalance(int amount) => '${amount < 0 ? minusSign : ''}${formatNumber(amount.abs())} đ';

/// Số tiền có dấu trong lịch sử: "+15.000.000 đ" hoặc "−55.000 đ".
String formatSigned(int amount) => '${amount < 0 ? minusSign : '+'}${formatNumber(amount.abs())} đ';

/// Tiêu đề nhóm ngày trong lịch sử: "Hôm nay · 26/10", "Hôm qua · 25/10", "Thứ Sáu · 23/10".
String historyDayLabel(DateTime today, DateTime d) {
  final back = daysBefore(today, d);
  final name = switch (back) {
    0 => 'Hôm nay',
    1 => 'Hôm qua',
    _ => weekdayName(d),
  };
  final date = d.year == today.year ? formatDayMonth(d) : formatDate(d);
  return '$name · $date';
}
