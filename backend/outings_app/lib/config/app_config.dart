// lib/config/app_config.dart

/// Central config values for the app.
/// Set at runtime using:  --dart-define=API_BASE_URL=https://your-env.example.com
class AppConfig {
  /// If you don’t pass --dart-define, this default is used.
  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:4000');

  /// Optional: expose a label just for debugging / UI badges if you want.
  static const String envLabel =
      String.fromEnvironment('APP_ENV', defaultValue: 'local');
}
