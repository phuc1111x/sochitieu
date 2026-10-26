/// Mã "Web client ID" của Google Cloud, cần cho đăng nhập Google trên Android.
/// Truyền khi build: flutter build apk --dart-define=GOOGLE_WEB_CLIENT_ID=xxx.apps.googleusercontent.com
/// Để trống thì app vẫn chạy bình thường, chỉ có tính năng sao lưu Google Drive bị tắt.
const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
