import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/expense.dart';
import '../models/money_move.dart';
import '../models/money_source.dart';
import 'expense_db.dart';

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sao lưu / khôi phục toàn bộ dữ liệu thành một file JSON trong thư mục
/// riêng của app trên Google Drive (appDataFolder: người dùng không thấy,
/// app khác không đọc được).
class DriveBackup {
  DriveBackup._();

  static final instance = DriveBackup._();

  static const _scopes = [drive.DriveApi.driveAppdataScope];
  static const _fileName = 'sochitieu-backup.json';
  static const _kLastBackup = 'last_backup_at';
  static const _kAuto = 'auto_backup';
  static const _kWifiOnly = 'wifi_only';
  static const _kConnected = 'drive_connected';

  final _signIn = GoogleSignIn.instance;

  final account = ValueNotifier<GoogleSignInAccount?>(null);
  final lastBackup = ValueNotifier<DateTime?>(null);
  final autoBackup = ValueNotifier<bool>(true);
  final wifiOnly = ValueNotifier<bool>(true);

  bool get isConfigured => googleWebClientId.isNotEmpty;

  Future<void>? _init;

  Future<void> init() => _init ??= _doInit();

  Future<void> _doInit() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kLastBackup);
    lastBackup.value = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
    autoBackup.value = prefs.getBool(_kAuto) ?? true;
    wifiOnly.value = prefs.getBool(_kWifiOnly) ?? true;
    if (!isConfigured) return;

    try {
      await _signIn.initialize(serverClientId: googleWebClientId);
      _signIn.authenticationEvents.listen((event) {
        account.value = switch (event) {
          GoogleSignInAuthenticationEventSignIn() => event.user,
          GoogleSignInAuthenticationEventSignOut() => null,
        };
      }, onError: (Object e) => debugPrint('Google sign-in: $e'));
      // Chỉ tự đăng nhập lại khi người dùng đã từng kết nối: nếu chưa,
      // attemptLightweightAuthentication sẽ bật bảng chọn tài khoản mỗi lần mở app.
      if (prefs.getBool(_kConnected) ?? false) {
        account.value = await _signIn.attemptLightweightAuthentication();
      }
    } catch (e) {
      debugPrint('Google sign-in init: $e');
    }
  }

  Future<void> setAutoBackup(bool value) async {
    autoBackup.value = value;
    await (await SharedPreferences.getInstance()).setBool(_kAuto, value);
  }

  Future<void> setWifiOnly(bool value) async {
    wifiOnly.value = value;
    await (await SharedPreferences.getInstance()).setBool(_kWifiOnly, value);
  }

  Future<void> connect() async {
    await init();
    if (!isConfigured) {
      throw const BackupException('Tính năng sao lưu chưa được cấu hình trong bản cài này.');
    }
    try {
      final user = await _signIn.authenticate(scopeHint: _scopes);
      account.value = user;
      await user.authorizationClient.authorizeScopes(_scopes);
      await (await SharedPreferences.getInstance()).setBool(_kConnected, true);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const BackupException('Đã huỷ đăng nhập Google.');
      }
      throw BackupException('Không đăng nhập được Google (${e.code.name}).');
    }
  }

  Future<void> disconnect() async {
    await _signIn.disconnect();
    account.value = null;
    await (await SharedPreferences.getInstance()).setBool(_kConnected, false);
  }

  Future<drive.DriveApi> _api({required bool interactive}) async {
    final user = account.value;
    if (user == null) throw const BackupException('Chưa kết nối Google Drive.');
    var authorization = await user.authorizationClient.authorizationForScopes(_scopes);
    if (authorization == null && interactive) {
      authorization = await user.authorizationClient.authorizeScopes(_scopes);
    }
    if (authorization == null) throw const BackupException('Cần cấp quyền Google Drive.');
    return drive.DriveApi(authorization.authClient(scopes: _scopes));
  }

  Future<String?> _findBackupFileId(drive.DriveApi api) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_fileName' and trashed = false",
      $fields: 'files(id, modifiedTime)',
      orderBy: 'modifiedTime desc',
    );
    final files = list.files;
    return (files == null || files.isEmpty) ? null : files.first.id;
  }

  Future<void> backup({bool interactive = true}) async {
    final api = await _api(interactive: interactive);
    final now = DateTime.now();
    final bytes = utf8.encode(jsonEncode(await exportJson(ExpenseDb.instance, now)));
    final media = drive.Media(Stream.value(bytes), bytes.length, contentType: 'application/json');

    final existingId = await _findBackupFileId(api);
    if (existingId == null) {
      await api.files.create(
        drive.File()
          ..name = _fileName
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
    } else {
      await api.files.update(drive.File(), existingId, uploadMedia: media);
    }

    lastBackup.value = now;
    await (await SharedPreferences.getInstance()).setInt(_kLastBackup, now.millisecondsSinceEpoch);
  }

  /// Thay dữ liệu trên máy bằng bản sao lưu. Trả về số khoản chi đã khôi phục.
  Future<int> restore() async {
    final api = await _api(interactive: true);
    final id = await _findBackupFileId(api);
    if (id == null) throw const BackupException('Chưa có bản sao lưu nào trên Google Drive.');

    final media = await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return importJson(ExpenseDb.instance, data);
  }

  static const _backupVersion = 2;

  /// Nội dung file sao lưu. Phiên bản 2 thêm `sources` và `moves` (giữ id để các
  /// khoản chi và giao dịch trỏ đúng nguồn), khoản chi có thêm `source_id`.
  /// Từ app 0.3.0, mỗi nguồn có thêm `credit_limit` (tổng hạn mức thẻ, có thể null). Trường này
  /// không bắt buộc nên vẫn giữ `version: 2`: file v2 cũ không có trường này khôi phục với NULL.
  /// Từ app 0.4.0, mỗi nguồn có thêm `app_package` (ứng dụng thanh toán, có thể null), cũng không
  /// bắt buộc. Khôi phục trên máy chưa cài ứng dụng đó thì form hiện "Ứng dụng không còn trên máy".
  /// Dữ liệu được đọc trong một transaction nên không lẫn trạng thái cũ và mới.
  @visibleForTesting
  static Future<Map<String, Object?>> exportJson(ExpenseDb db, DateTime now) async {
    final snap = await db.snapshot();
    return {
      'app': 'sochitieu',
      'version': _backupVersion,
      'exportedAt': now.toIso8601String(),
      'expenses': [for (final e in snap.expenses) e.toMap()..remove('id')],
      'sources': [for (final s in snap.sources) s.toMap()],
      'moves': [for (final m in snap.moves) m.toMap()],
    };
  }

  /// Thay dữ liệu trên máy bằng nội dung file sao lưu (đọc được cả phiên bản 1 và 2).
  /// - Bản cũ (v1) không có nguồn tiền: nguồn tiền trở về một "Tiền mặt" mặc định, xoá giao dịch tiền.
  /// - Bản từ app mới hơn (version > 2): từ chối trước khi đụng vào dữ liệu.
  /// - Khoản chi trỏ tới nguồn không có trong file thì bỏ nguồn (NULL); giao dịch trỏ tới nguồn
  ///   không có hoặc sai dạng so với loại của nó thì bỏ qua.
  /// - Không còn nguồn nào đang dùng thì thêm "Tiền mặt"; luôn còn đúng một nguồn mặc định.
  @visibleForTesting
  static Future<int> importJson(ExpenseDb db, Map<String, dynamic> data) async {
    final version = (data['version'] as num?)?.toInt() ?? 1;
    if (version > _backupVersion) {
      throw const BackupException('Bản sao lưu được tạo từ phiên bản app mới hơn. Hãy cập nhật app rồi thử lại.');
    }
    List<Map<String, Object?>> rows(String key) => [
          for (final m in (data[key] as List?) ?? const []) Map<String, Object?>.from(m as Map),
        ];
    final sources = version >= 2 ? rows('sources').map(MoneySource.fromMap).toList() : <MoneySource>[];
    final ids = {for (final s in sources) ?s.id};
    final expenses = [
      for (final e in rows('expenses').map(Expense.fromMap))
        ids.contains(e.sourceId) ? e : e.copyWith(sourceId: null),
    ];
    final moves = [
      if (version >= 2)
        for (final m in rows('moves').map(MoneyMove.fromMap))
          if (_fitsKind(m, ids)) m,
    ];
    await db.replaceAll(expenses, sources: sources, moves: moves);
    return expenses.length;
  }

  /// Giao dịch hợp lệ: nguồn tồn tại và đúng dạng theo loại (tiền vào / chuyển tiền / điều chỉnh).
  static bool _fitsKind(MoneyMove m, Set<int> ids) {
    bool known(int? id) => id != null && ids.contains(id);
    return switch (m.kind) {
      MoveKind.income => known(m.toId) && m.fromId == null && m.amount > 0,
      MoveKind.move => known(m.fromId) && known(m.toId) && m.fromId != m.toId && m.amount > 0,
      MoveKind.adjust => known(m.toId) && m.fromId == null,
      _ => false,
    };
  }

  /// Gọi khi mở app: tự sao lưu nếu đã bật và lần gần nhất cách đây hơn 1 ngày.
  Future<void> maybeAutoBackup() async {
    await init();
    if (!isConfigured || !autoBackup.value || account.value == null) return;
    final last = lastBackup.value;
    if (last != null && DateTime.now().difference(last) < const Duration(days: 1)) return;
    if (wifiOnly.value) {
      final types = await Connectivity().checkConnectivity();
      if (!types.contains(ConnectivityResult.wifi) && !types.contains(ConnectivityResult.ethernet)) return;
    }
    try {
      await backup(interactive: false);
    } catch (e) {
      debugPrint('Auto backup skipped: $e');
    }
  }
}
