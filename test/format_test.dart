import 'package:flutter_test/flutter_test.dart';
import 'package:sochitieu/utils/format.dart';

void main() {
  test('formatMoney thêm dấu chấm hàng nghìn', () {
    expect(formatMoney(0), '0 đ');
    expect(formatMoney(500), '500 đ');
    expect(formatMoney(45000), '45.000 đ');
    expect(formatMoney(4250000), '4.250.000 đ');
    expect(formatMoney(1000000000), '1.000.000.000 đ');
  });

  test('ngày và thứ tiếng Việt', () {
    final d = DateTime(2026, 10, 26);
    expect(formatFullDate(d), 'Thứ Hai, 26/10/2026');
    expect(weekdayName(DateTime(2026, 10, 25)), 'Chủ Nhật');
    expect(dateKey(d), '2026-10-26');
    expect(parseDateKey('2026-10-26'), d);
  });

  test('đếm số ngày lùi và số ngày trong tháng', () {
    final today = DateTime(2026, 3, 1);
    expect(daysBefore(today, DateTime(2026, 2, 28)), 1);
    expect(daysBefore(today, today), 0);
    expect(daysInMonth(DateTime(2024, 2)), 29);
    expect(daysInMonth(DateTime(2026, 10)), 31);
    expect(relativeDayLabel(1), 'Hôm qua');
    expect(relativeMonthLabel(3), '3 tháng trước');
  });

  test('số dư và số tiền có dấu dùng dấu trừ U+2212', () {
    expect(formatBalance(1205000), '1.205.000 đ');
    expect(formatBalance(-2350000), '\u22122.350.000 đ');
    expect(formatBalance(0), '0 đ');
    expect(formatSigned(15000000), '+15.000.000 đ');
    expect(formatSigned(-55000), '\u221255.000 đ');
  });

  test('nhãn ngày trong lịch sử nguồn tiền', () {
    final today = DateTime(2026, 10, 26);
    expect(historyDayLabel(today, today), 'Hôm nay · 26/10');
    expect(historyDayLabel(today, DateTime(2026, 10, 25)), 'Hôm qua · 25/10');
    expect(historyDayLabel(today, DateTime(2026, 10, 23)), 'Thứ Sáu · 23/10');
    expect(historyDayLabel(today, DateTime(2025, 12, 31)), 'Thứ Tư · 31/12/2025');
  });
}
