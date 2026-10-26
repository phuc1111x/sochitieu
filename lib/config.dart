/// Mã "Web client ID" của Google Cloud, cần cho đăng nhập Google trên Android.
/// Mặc định là client của dự án Google Cloud "So chi tieu"; có thể ghi đè khi build:
/// flutter build apk --dart-define=GOOGLE_WEB_CLIENT_ID=xxx.apps.googleusercontent.com
/// Để trống thì app vẫn chạy bình thường, chỉ có tính năng sao lưu Google Drive bị tắt.
const googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: '51412195762-l2end74jvkrfdgcfcb2mdu7n0r9ss8mq.apps.googleusercontent.com',
);
