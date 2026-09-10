/// Resolves the API base URL.
///
/// Mirrors the Next.js logic in `shipper/src/lib/api-client.ts`:
///   - reads from a build-time define (`API_BASE_URL`),
///   - falls back to the public dev backend,
///   - strips trailing slashes,
///   - ensures `/api/v1` exists exactly once.
///
/// Default: `https://dev-api.wetruck.ai/api/v1` — works out of the box on
/// emulator or a physical phone with internet access.
///
/// Override at build/run time, e.g. against a local backend:
///     flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
/// (`10.0.2.2` is the Android emulator's alias for the host machine.
/// On a physical phone, use your PC's LAN IP instead.)
class ApiConfig {
  ApiConfig._(this.baseUrl);

  final String baseUrl;

  static ApiConfig fromEnvironment() {
    const raw = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://dev-api.wetruck.ai',
    );

    final trimmed = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    final withApiPath =
        trimmed.endsWith('/api/v1') ? trimmed : '$trimmed/api/v1';

    return ApiConfig._(withApiPath);
  }
}
