import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted token storage. Direct port of `shipper/src/lib/auth-token.ts`,
/// with two upgrades:
///   1. Backed by the OS keystore (Android Keystore / iOS Keychain) instead
///      of localStorage, so tokens survive uninstall-less data clears and
///      are not readable by the browser process.
///   2. Single source of truth for the storage keys — the Next.js codebase
///      currently has a typo (`wettruck_*` written on refresh vs
///      `wetruck_*` read on request). This port standardizes on
///      `wetruck_*` to match the read side.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  // Keys mirror the Next.js localStorage names the existing app reads from.
  static const _accessTokenKey = 'wetruck_access_token';
  static const _refreshTokenKey = 'wetruck_refresh_token';
  static const _userKey = 'wetruck_user';

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);
  Future<String?> readUser() => _storage.read(key: _userKey);

  Future<void> writeAccessToken(String token) =>
      _storage.write(key: _accessTokenKey, value: token);

  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshTokenKey, value: token);

  Future<void> writeUser(String userJson) =>
      _storage.write(key: _userKey, value: userJson);

  /// Wipes every Wetruck-owned key. Called on logout and on refresh failure.
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _userKey),
    ]);
  }
}
