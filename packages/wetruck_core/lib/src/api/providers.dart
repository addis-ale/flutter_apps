import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_storage.dart';
import 'api_client.dart';
import 'api_config.dart';

final apiConfigProvider = Provider<ApiConfig>((ref) {
  return ApiConfig.fromEnvironment();
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage();
});

/// Apps override this with a callback that boots them back to the sign-in
/// screen (e.g. `router.go('/sign-in')`). Default no-op keeps the package
/// usable in isolation (tests, previews).
final authFailureHandlerProvider =
    Provider<Future<void> Function()>((ref) => () async {});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    config: ref.watch(apiConfigProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    onAuthFailure: ref.watch(authFailureHandlerProvider),
  );
});
