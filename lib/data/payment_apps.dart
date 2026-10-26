import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Một ứng dụng đã cài trên điện thoại (có biểu tượng trên màn hình chính).
class InstalledApp {
  const InstalledApp({required this.label, required this.package, this.icon});

  /// Tên hiện trên điện thoại, ví dụ "MoMo".
  final String label;

  /// Tên gói Android, ví dụ `com.mservice.momotransfer`. Đây là giá trị lưu trong nguồn tiền.
  final String package;

  /// Biểu tượng ứng dụng dạng PNG (null nếu không đọc được).
  final Uint8List? icon;
}

/// Ứng dụng thanh toán gắn với nguồn tiền: liệt kê ứng dụng đã cài, đọc tên + biểu tượng của
/// một ứng dụng và mở nó sau khi lưu khoản chi.
///
/// Bản thật nói chuyện với Android qua [MethodChannel] (`MainActivity.kt`). Test thay
/// [instance] bằng bản giả. Không đọc số dư hay dữ liệu gì của ứng dụng khác.
abstract class PaymentApps {
  static PaymentApps instance = ChannelPaymentApps();

  /// Mọi ứng dụng có biểu tượng trên màn hình chính, sắp theo tên (trừ chính Sổ chi tiêu).
  Future<List<InstalledApp>> listApps();

  /// Tên + biểu tượng của ứng dụng [package], hoặc `null` nếu ứng dụng không còn mở được
  /// (đã gỡ, bị tắt, hoặc khôi phục bản sao lưu trên máy khác).
  Future<InstalledApp?> appInfo(String package);

  /// Mở ứng dụng [package]. Trả về `false` nếu không mở được.
  Future<bool> launch(String package);
}

/// Bản thật: gọi sang Android. Lỗi bất kỳ (kênh không có khi chạy trên máy tính, lỗi Android,
/// dữ liệu trả về sai dạng) đều coi như không có ứng dụng / không mở được, không làm hỏng form.
class ChannelPaymentApps extends PaymentApps {
  static const channel = MethodChannel('sochitieu/payment_apps');

  /// Một dòng từ Android; `null` nếu sai dạng (thiếu tên gói...).
  static InstalledApp? _parse(Object? row) {
    if (row is! Map) return null;
    final package = row['package'];
    if (package is! String || package.isEmpty) return null;
    final label = row['label'];
    final icon = row['icon'];
    return InstalledApp(
      label: label is String && label.trim().isNotEmpty ? label : package,
      package: package,
      icon: icon is Uint8List ? icon : null,
    );
  }

  @override
  Future<List<InstalledApp>> listApps() async {
    try {
      final rows = await channel.invokeMethod<List<Object?>>('listApps') ?? const [];
      return [for (final r in rows) ?_parse(r)];
    } catch (e) {
      debugPrint('listApps failed: $e');
      return const [];
    }
  }

  @override
  Future<InstalledApp?> appInfo(String package) async {
    try {
      return _parse(await channel.invokeMethod<Object?>('appInfo', {'package': package}));
    } catch (e) {
      debugPrint('appInfo failed: $e');
      return null;
    }
  }

  @override
  Future<bool> launch(String package) async {
    try {
      return await channel.invokeMethod<bool>('launch', {'package': package}) ?? false;
    } catch (e) {
      debugPrint('launch failed: $e');
      return false;
    }
  }
}
