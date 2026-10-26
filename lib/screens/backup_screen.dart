import 'package:flutter/material.dart';

import '../data/drive_backup.dart';
import '../theme.dart';
import '../utils/format.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _backup = DriveBackup.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _backup.init();
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      _show(await action());
    } on BackupException catch (e) {
      _show(e.message);
    } catch (e) {
      _show('Có lỗi xảy ra, vui lòng thử lại. ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Khôi phục từ Google Drive?'),
        content: const Text('Toàn bộ dữ liệu trên máy sẽ được thay bằng bản sao lưu gần nhất trên Drive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Khôi phục')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async => 'Đã khôi phục ${await _backup.restore()} khoản chi');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          const Text('Sao lưu', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Lưu bản sao lên Google Drive của bạn để không mất dữ liệu khi đổi hoặc mất điện thoại.',
            style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder(
            valueListenable: _backup.account,
            builder: (context, account, _) =>
                account == null ? _buildDisconnected() : _buildConnected(account.email),
          ),
          const SizedBox(height: 16),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.shield_outlined, size: 20, color: AppColors.muted),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Bản sao lưu nằm trong thư mục riêng của app trên Drive, không lẫn với file khác của bạn. '
                  'App vẫn dùng bình thường khi không có mạng.',
                  style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Material(color: Colors.transparent, child: child),
      );

  Widget _buildDisconnected() {
    return _card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.cloud_outlined, size: 32, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 12),
            const Text('Chưa kết nối Google Drive', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              _backup.isConfigured
                  ? 'Dữ liệu hiện chỉ nằm trên điện thoại này. Kết nối để sao lưu và khôi phục khi cần.'
                  : 'Bản cài này chưa được cấu hình Google Drive. Dữ liệu vẫn được lưu an toàn trên điện thoại.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy || !_backup.isConfigured
                  ? null
                  : () => _run(() async {
                        await _backup.connect();
                        return 'Đã kết nối Google Drive';
                      }),
              child: const Text('Kết nối Google Drive'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnected(String email) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.cloud_done_outlined, color: AppColors.accent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Đã kết nối Google Drive',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(email,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Sao lưu gần nhất', style: TextStyle(fontSize: 14, color: AppColors.muted)),
                    ),
                    ValueListenableBuilder(
                      valueListenable: _backup.lastBackup,
                      builder: (context, last, _) => Text(
                        last == null ? 'Chưa sao lưu' : formatLastBackup(last),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _run(() async {
                    await _backup.backup();
                    return 'Đã sao lưu lên Google Drive';
                  }),
          icon: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload_outlined),
          label: const Text('Sao lưu ngay'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : _restore,
          icon: const Icon(Icons.cloud_download_outlined),
          label: const Text('Khôi phục từ Google Drive'),
        ),
        const SizedBox(height: 16),
        _card(
          child: Column(
            children: [
              ValueListenableBuilder(
                valueListenable: _backup.autoBackup,
                builder: (context, on, _) => SwitchListTile(
                  value: on,
                  onChanged: _backup.setAutoBackup,
                  title: const Text('Tự động sao lưu mỗi ngày',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  subtitle: const Text('Khi mở app, tối đa 1 lần mỗi ngày',
                      style: TextStyle(fontSize: 13, color: AppColors.muted)),
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              ValueListenableBuilder(
                valueListenable: _backup.wifiOnly,
                builder: (context, on, _) => SwitchListTile(
                  value: on,
                  onChanged: _backup.setWifiOnly,
                  title: const Text('Chỉ tự động sao lưu khi có Wi-Fi',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  subtitle: const Text('Không tốn dung lượng 4G',
                      style: TextStyle(fontSize: 13, color: AppColors.muted)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                    await _backup.disconnect();
                    return 'Đã ngắt kết nối Google Drive';
                  }),
          style: TextButton.styleFrom(foregroundColor: AppColors.muted, minimumSize: const Size.fromHeight(44)),
          child: const Text('Ngắt kết nối / đổi tài khoản'),
        ),
      ],
    );
  }
}
