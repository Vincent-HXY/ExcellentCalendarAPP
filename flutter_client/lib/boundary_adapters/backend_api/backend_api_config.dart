/// Connection settings for the Flutter → Backend HTTPS API (contracts v1).
///
/// The base URL can be overridden at build time:
/// flutter run --dart-define=BACKEND_BASE_URL=http://192.168.1.20:8080
class BackendApiConfig {
  const BackendApiConfig({
    this.baseUrl = baseUrlFromEnvironment,
    this.basePath = basePathDefault,
    this.connectTimeout = const Duration(seconds: 10),
    this.sendTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 20),
  });

  /// Android emulator loopback alias for the developer machine.
  static const baseUrlFromEnvironment = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );
  static const basePathDefault = '/api/v1';
  static const contractVersion = 1;

  final String baseUrl;
  final String basePath;
  final Duration connectTimeout;
  final Duration sendTimeout;
  final Duration receiveTimeout;
}
