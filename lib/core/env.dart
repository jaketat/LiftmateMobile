class Env {
  // apiBase dùng cho phần gọi API. webBase dùng để mở trang 3D
  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://app.liftmate.com.vn/api/v1',
  );
  static const webBase = String.fromEnvironment(
    'WEB_BASE',
    defaultValue: 'https://app.liftmate.com.vn',
  );
}
