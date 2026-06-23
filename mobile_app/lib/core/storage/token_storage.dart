import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();
  static const _logoutPendingKey = 'logout_pending';
  static const _pendingLogoutRefreshKey = 'pending_logout_refresh';

  Future<void> savePendingLogoutRefreshToken(String refreshToken) async {
    await _storage.write(key: _pendingLogoutRefreshKey, value: refreshToken);
  }

  Future<String?> getPendingLogoutRefreshToken() async {
    return _storage.read(key: _pendingLogoutRefreshKey);
  }

  Future<void> clearPendingLogoutRefreshToken() async {
    await _storage.delete(key: _pendingLogoutRefreshKey);
  }

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
  }

  Future<void> saveAccessToken(String access) async {
    await _storage.write(key: 'accesss_token', value: access);
  }

  Future<String?> getAccessToken() {
    return _storage.read(key: 'access_token');
  }

  Future<String?> getRefreshToken() {
    return _storage.read(key: 'refresh_token');
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  Future<void> setLogoutPending(bool value) async {
    await _storage.write(
      key: _logoutPendingKey,
      value: value ? 'true' : 'false',
    );
  }

  Future<bool> isLogoutPending() async {
    final value = await _storage.read(key: _logoutPendingKey);
    return value == 'true';
  }

  Future<void> clearLogoutPending() async {
    await _storage.delete(key: _logoutPendingKey);
  }
}
