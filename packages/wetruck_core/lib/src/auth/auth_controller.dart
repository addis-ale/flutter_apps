import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';
import 'auth_api.dart';
import 'auth_user.dart';
import 'token_storage.dart';

enum AuthStatus { initializing, signedOut, signedIn }

class AuthState {
  const AuthState({required this.status, this.user, this.error});

  final AuthStatus status;
  final AuthUser? user;
  final String? error;

  bool get isSignedIn => status == AuthStatus.signedIn && user != null;
  bool get isInitializing => status == AuthStatus.initializing;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? error,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      error: clearError ? null : (error ?? this.error),
    );
  }

  static const initial = AuthState(status: AuthStatus.initializing);
}

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(apiClientProvider));
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    api: ref.watch(authApiProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    apiClient: ref.watch(apiClientProvider),
  )..bootstrap();
});

class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required AuthApi api,
    required TokenStorage tokenStorage,
    required dynamic apiClient,
  })  : _api = api,
        _tokenStorage = tokenStorage,
        _apiClient = apiClient,
        super(AuthState.initial);

  final AuthApi _api;
  final TokenStorage _tokenStorage;
  final dynamic _apiClient; // ApiClient, kept dynamic to avoid a circular type

  /// Called once when the app boots — equivalent to the `initAuth` effect in
  /// `AuthProvider.tsx`. Reads the cached user from secure storage, then
  /// verifies the session with `/auth/me`. On any failure, signs the user out.
  Future<void> bootstrap() async {
    final cachedRaw = await _tokenStorage.readUser();
    final cachedUser = AuthUser.tryDecode(cachedRaw);

    if (cachedUser == null) {
      state = const AuthState(status: AuthStatus.signedOut);
      return;
    }

    final me = await _api.me();
    if (!me.isSuccess) {
      await _tokenStorage.clear();
      state = const AuthState(status: AuthStatus.signedOut);
      return;
    }

    // Prefer the freshest user data from the server when available.
    AuthUser freshUser = cachedUser;
    final meData = me.data;
    if (meData != null) {
      freshUser = cachedUser.copyWith(
        id: meData['id']?.toString(),
        email: meData['email'] as String? ?? cachedUser.email,
        role:
            meData['user_type'] as String? ?? meData['role'] as String? ?? cachedUser.role,
      );
      await _tokenStorage.writeUser(freshUser.encode());
    }

    state = AuthState(status: AuthStatus.signedIn, user: freshUser);
  }

  Future<void> login({
    required String email,
    required String password,
    String? captchaId,
    String? captchaSolution,
  }) async {
    state = state.copyWith(clearError: true);

    final res = await _api.login(
      email: email,
      password: password,
      captchaId: captchaId,
      captchaSolution: captchaSolution,
    );

    if (!res.isSuccess) {
      state = state.copyWith(
        status: AuthStatus.signedOut,
        error: res.error ?? 'Login failed',
        clearUser: true,
      );
      throw _AuthException(res.error ?? 'Login failed');
    }

    final data = res.data ?? const <String, dynamic>{};

    final accessToken = data['access_token'];
    if (accessToken is String && accessToken.isNotEmpty) {
      await _tokenStorage.writeAccessToken(accessToken);
    }
    final refreshToken = data['refresh_token'];
    if (refreshToken is String && refreshToken.isNotEmpty) {
      await _tokenStorage.writeRefreshToken(refreshToken);
    }

    final user = AuthUser(
      email: email,
      role: data['role'] as String? ?? 'shipper',
      name: email.contains('@') ? email.split('@').first : email,
    );
    await _tokenStorage.writeUser(user.encode());

    state = AuthState(status: AuthStatus.signedIn, user: user);
  }

  Future<void> logout() async {
    // Best-effort server call. We sign out locally either way.
    try {
      await _api.logout();
    } catch (_) {}
    await _tokenStorage.clear();
    await _apiClient.clearCookies();
    state = const AuthState(status: AuthStatus.signedOut);
  }
}

class _AuthException implements Exception {
  _AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
