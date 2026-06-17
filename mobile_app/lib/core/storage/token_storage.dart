import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
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
}
