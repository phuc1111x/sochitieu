import 'package:flutter/material.dart';

import '../theme.dart';

class SourceType {
  const SourceType({
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

/// Loại nguồn tiền cố định. `id` được lưu trong database và file sao lưu, không được đổi.
const sourceTypes = [
  SourceType(
    id: 'cash',
    name: 'Tiền mặt',
    icon: Icons.payments_outlined,
    fg: AppColors.income,
    bg: AppColors.incomeSoft,
  ),
  SourceType(
    id: 'bank',
    name: 'Ngân hàng',
    icon: Icons.account_balance_outlined,
    fg: Color(0xFF1D4ED8),
    bg: Color(0xFFEAF0FF),
  ),
  SourceType(
    id: 'ewallet',
    name: 'Ví điện tử',
    icon: Icons.smartphone_outlined,
    fg: Color(0xFFBE185D),
    bg: Color(0xFFFDECF4),
  ),
  SourceType(
    id: 'credit',
    name: 'Thẻ tín dụng',
    icon: Icons.credit_card_outlined,
    fg: Color(0xFFC2410C),
    bg: Color(0xFFFFF1E8),
  ),
  SourceType(
    id: 'saving',
    name: 'Tiết kiệm',
    icon: Icons.savings_outlined,
    fg: Color(0xFF7E22CE),
    bg: Color(0xFFF4EBFF),
  ),
  SourceType(
    id: 'other',
    name: 'Khác',
    icon: Icons.account_balance_wallet_outlined,
    fg: AppColors.neutral,
    bg: AppColors.neutralSoft,
  ),
];

SourceType sourceTypeById(String id) =>
    sourceTypes.firstWhere((t) => t.id == id, orElse: () => sourceTypes.last);

/// Một nơi giữ tiền: ví tiền mặt, tài khoản ngân hàng, ví điện tử, thẻ tín dụng...
/// Số dư không lưu trong bảng mà luôn tính từ sổ cái ([balance] chỉ có khi đọc ra).
class MoneySource {
  const MoneySource({
    this.id,
    required this.name,
    required this.type,
    this.isDefault = false,
    this.inTotal = true,
    this.archived = false,
    required this.createdAt,
    this.balance = 0,
    this.creditLimit,
    this.appPackage,
  });

  final int? id;
  final String name;
  final String type;
  final bool isDefault;
  final bool inTotal;

  /// Nguồn đã xoá: ẩn khỏi danh sách, không tính vào tổng, nhưng giữ lịch sử.
  final bool archived;
  final int createdAt;

  /// Số dư tính từ sổ cái (âm = đang nợ, ví dụ thẻ tín dụng).
  final int balance;

  /// Tổng hạn mức của thẻ tín dụng (chỉ có với loại `credit`; thẻ tạo từ bản 0.2.0 có thể chưa có).
  /// Đây là giá trị duy nhất được lưu: số nợ vẫn tính từ sổ cái, hạn mức còn lại = hạn mức + số dư.
  final int? creditLimit;

  /// Ứng dụng thanh toán gắn với nguồn (tên gói Android, ví dụ `com.mservice.momotransfer`):
  /// thêm khoản chi bằng nguồn này thì có nút "Lưu & mở {app}". Tiền mặt không có.
  final String? appPackage;

  SourceType get sourceType => sourceTypeById(type);

  bool get isCredit => type == 'credit';

  /// Thẻ tín dụng đã nhập tổng hạn mức: hiện "Còn được tiêu" và thanh % đã dùng.
  bool get hasLimit => isCredit && (creditLimit ?? 0) > 0;

  /// "Còn được tiêu" = tổng hạn mức + số dư (số dư âm = số nợ). Âm = đã vượt hạn mức.
  int get available => (creditLimit ?? 0) + balance;

  /// Phần trăm hạn mức đã dùng (0–100, làm tròn).
  int get usedPercent {
    final limit = creditLimit ?? 0;
    return limit > 0 ? usedPercentOf(-balance, limit) : 0;
  }

  static const _keep = Object();

  /// [creditLimit] / [appPackage] truyền `null` để xoá; bỏ trống để giữ nguyên.
  MoneySource copyWith({
    String? name,
    String? type,
    bool? isDefault,
    bool? inTotal,
    bool? archived,
    Object? creditLimit = _keep,
    Object? appPackage = _keep,
  }) =>
      MoneySource(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        isDefault: isDefault ?? this.isDefault,
        inTotal: inTotal ?? this.inTotal,
        archived: archived ?? this.archived,
        createdAt: createdAt,
        balance: balance,
        creditLimit: identical(creditLimit, _keep) ? this.creditLimit : creditLimit as int?,
        appPackage: identical(appPackage, _keep) ? this.appPackage : appPackage as String?,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'type': type,
        'is_default': isDefault ? 1 : 0,
        'in_total': inTotal ? 1 : 0,
        'archived': archived ? 1 : 0,
        'created_at': createdAt,
        // Chỉ thẻ tín dụng có hạn mức: đổi sang loại khác thì hạn mức bị xoá (NULL).
        'credit_limit': isCredit ? creditLimit : null,
        // Tiền mặt không gắn ứng dụng thanh toán: đổi sang tiền mặt thì bỏ liên kết (NULL).
        'app_package': type == 'cash' ? null : appPackage,
      };

  factory MoneySource.fromMap(Map<String, Object?> m) => MoneySource(
        id: (m['id'] as num?)?.toInt(),
        name: m['name'] as String,
        type: m['type'] as String,
        isDefault: (m['is_default'] as num? ?? 0) != 0,
        inTotal: (m['in_total'] as num? ?? 1) != 0,
        archived: (m['archived'] as num? ?? 0) != 0,
        createdAt: (m['created_at'] as num? ?? 0).toInt(),
        balance: (m['balance'] as num? ?? 0).toInt(),
        creditLimit: (m['credit_limit'] as num?)?.toInt(),
        appPackage: switch (m['app_package']) {
          final String p when p.isNotEmpty => p,
          _ => null,
        },
      );
}

/// Phần trăm [debt] trên [limit], làm tròn và giới hạn trong 0–100 (dùng cho thanh hạn mức).
int usedPercentOf(int debt, int limit) {
  if (limit <= 0) return 0;
  return (debt * 100 / limit).round().clamp(0, 100);
}
