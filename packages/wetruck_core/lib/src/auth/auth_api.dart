import '../api/api_client.dart';
import '../api/api_response.dart';

/// Thin wrapper over [ApiClient] for the auth endpoints. Direct port of
/// `shipper/src/components/providers/AuthProvider.tsx` (login/logout/me) and
/// `shipper/src/app/modules/auth/server/api/auth.api.ts` (password reset).
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  /// Logs the user in. Mirrors the request shape used in the Next.js app.
  /// `captchaId` and `captchaSolution` are optional — when omitted, the
  /// payload simply doesn't carry them. The backend may or may not require
  /// them; that's discovered at runtime.
  Future<ApiResponse<Map<String, dynamic>>> login({
    required String email,
    required String password,
    String role = 'shipper',
    String? captchaId,
    String? captchaSolution,
  }) {
    return _client.post<Map<String, dynamic>>(
      '/auth/login',
      body: <String, dynamic>{
        'email': email,
        'password': password,
        'role': role,
        if (captchaId != null && captchaId.isNotEmpty) 'captcha_id': captchaId,
        if (captchaSolution != null && captchaSolution.isNotEmpty)
          'captcha_solution': captchaSolution,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> me() =>
      _client.get<Map<String, dynamic>>('/auth/me');

  Future<ApiResponse<Map<String, dynamic>>> logout() =>
      _client.post<Map<String, dynamic>>('/auth/logout');

  Future<ApiResponse<dynamic>> requestPasswordReset(String email) =>
      _client.post<dynamic>(
        '/auth/password-reset/request',
        body: <String, dynamic>{'email': email},
      );

  Future<ApiResponse<dynamic>> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) =>
      _client.post<dynamic>(
        '/auth/password-reset/confirm',
        body: <String, dynamic>{
          'code': code,
          'new_password': newPassword,
        },
      );

  /// Authenticated change-password (`POST /auth/password-reset`). The backend
  /// verifies [currentPassword] and rejects with 403 if it's wrong.
  Future<ApiResponse<dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _client.post<dynamic>(
        '/auth/password-reset',
        body: <String, dynamic>{
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
}
