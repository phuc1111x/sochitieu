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
}
