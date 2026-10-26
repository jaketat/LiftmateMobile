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
  // Bản đồ Vietmap, giống web (VITE_VIETMAP_KEY). Dùng khóa TILEMAP (chỉ vẽ bản đồ).
  // Chạy: flutter run --dart-define=VIETMAP_KEY=<khóa>
  // Android Studio: Run > Edit Configurations > Additional run args: --dart-define=VIETMAP_KEY=<khóa>
  static const vietmapKey = String.fromEnvironment('VIETMAP_KEY');
  // Style bản đồ đường phố 'tm', cùng style web đang dùng
  static const vietmapStyle = String.fromEnvironment(
    'VIETMAP_STYLE',
    defaultValue: 'https://maps.vietmap.vn/maps/styles/tm/style.json',
  );
  static const mapAttribution = '© VIETMAP';
}
