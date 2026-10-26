import 'package:flutter/material.dart';

class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.fg,
    required this.bg,
  });

  final String id;
  final String name;
  final IconData icon;
  final Color fg;
  final Color bg;
}

/// Danh mục cố định. `id` được lưu trong database và file sao lưu, không được đổi.
const categories = [
  ExpenseCategory(
    id: 'food',
    name: 'Ăn uống',
    icon: Icons.restaurant_outlined,
    fg: Color(0xFFC2410C),
    bg: Color(0xFFFFF1E8),
  ),
  ExpenseCategory(
    id: 'transport',
    name: 'Đi lại',
    icon: Icons.directions_car_outlined,
    fg: Color(0xFF1D4ED8),
    bg: Color(0xFFEAF0FF),
  ),
  ExpenseCategory(
    id: 'shopping',
    name: 'Mua sắm',
    icon: Icons.shopping_bag_outlined,
    fg: Color(0xFF7E22CE),
    bg: Color(0xFFF4EBFF),
  ),
  ExpenseCategory(
    id: 'home',
    name: 'Nhà cửa',
    icon: Icons.home_outlined,
    fg: Color(0xFF0F766E),
    bg: Color(0xFFE6F4F2),
  ),
  ExpenseCategory(
    id: 'fun',
    name: 'Giải trí',
    icon: Icons.play_circle_outline,
    fg: Color(0xFFBE185D),
    bg: Color(0xFFFDECF4),
  ),
  ExpenseCategory(
    id: 'other',
    name: 'Khác',
    icon: Icons.grid_view_outlined,
    fg: Color(0xFF475569),
    bg: Color(0xFFEEF1F4),
  ),
];

ExpenseCategory categoryById(String id) =>
    categories.firstWhere((c) => c.id == id, orElse: () => categories.last);
