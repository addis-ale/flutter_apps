import 'package:flutter_test/flutter_test.dart';

import 'package:wetruck_core/wetruck_core.dart';

void main() {
  group('ApiConfig.fromEnvironment', () {
    test('defaults to the dev backend with /api/v1', () {
      // No --dart-define passed → defaults to https://dev-api.wetruck.ai.
      final config = ApiConfig.fromEnvironment();
      expect(config.baseUrl, 'https://dev-api.wetruck.ai/api/v1');
    });
  });

  group('ApiResponse', () {
    test('success is marked successful', () {
      final r = ApiResponse<Map<String, dynamic>>.success({'ok': true}, 200);
      expect(r.isSuccess, isTrue);
      expect(r.data, isNotNull);
      expect(r.error, isNull);
    });

    test('failure carries error and raw body', () {
      final r = ApiResponse<Map<String, dynamic>>.failure(
        error: 'Invalid credentials',
        status: 401,
        errorData: {'detail': 'Invalid credentials'},
      );
      expect(r.isSuccess, isFalse);
      expect(r.status, 401);
      expect(r.error, 'Invalid credentials');
    });

    test('networkError uses status 0', () {
      final r = ApiResponse<Object>.networkError();
      expect(r.status, 0);
      expect(r.isSuccess, isFalse);
      expect(r.error, isNotNull);
    });
  });
}
