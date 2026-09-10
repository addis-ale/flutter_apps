import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/providers.dart';

/// A challenge fetched from the backend. The captcha id is required when
/// submitting the user's solution to the login endpoint.
class CaptchaChallenge {
  const CaptchaChallenge({required this.captchaId, required this.imageBytes});
  final String captchaId;
  final Uint8List imageBytes;
}

/// Port of `shipper/src/services/captchaService.ts`.
///
/// `GET /auth/captcha` returns a PNG body with an `X-Captcha-Id` response
/// header. Sign-in uses *deferred verification* — the captcha id and the
/// user's typed solution are passed straight into `POST /auth/login`, so
/// this service only owns fetching. There is also a `POST /auth/verify-captcha`
/// endpoint, exposed via [verify] for callers that need it (password reset
/// flows etc.), but sign-in doesn't call it.
class CaptchaService {
  CaptchaService(this._client);
  final ApiClient _client;

  Future<CaptchaChallenge?> fetchChallenge() async {
    final response = await _client.getBytes(
      '/auth/captcha',
      timeout: const Duration(seconds: 10),
    );
    if (response == null) return null;

    final captchaId = response.header('X-Captcha-Id') ??
        response.header('Captcha-Id');
    if (captchaId == null || captchaId.isEmpty) return null;

    return CaptchaChallenge(
      captchaId: captchaId,
      imageBytes: response.bytes,
    );
  }

  /// Form-urlencoded `POST /auth/verify-captcha`. Returns the parsed
  /// response body on 2xx, or null on any failure.
  Future<Map<String, dynamic>?> verify({
    required String captchaId,
    required String solution,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/auth/verify-captcha',
      body: <String, dynamic>{
        'captcha_id': captchaId,
        'captcha_solution': solution,
      },
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
    );
    return res.isSuccess ? res.data : null;
  }
}

final captchaServiceProvider = Provider<CaptchaService>((ref) {
  return CaptchaService(ref.watch(apiClientProvider));
});
