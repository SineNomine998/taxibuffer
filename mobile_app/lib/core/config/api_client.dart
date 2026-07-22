import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/api_config.dart';

import '../storage/token_storage.dart';

class ApiClient {
  final TokenStorage _tokenStorage;
  final http.Client _http;

  Future<bool>? _refreshFuture;

  ApiClient({TokenStorage? tokenStorage, http.Client? httpClient})
    : _tokenStorage = tokenStorage ?? TokenStorage(),
      _http = httpClient ?? http.Client();

  Future<http.Response> get(String path, {Map<String, String>? queryParams}) {
    return _withAuth(
      (headers) => _http.get(_uri(path, queryParams), headers: headers),
    );
  }

  Future<http.Response> post(String path, {Object? body}) {
    return _withAuth(
      (headers) =>
          _http.post(_uri(path), headers: headers, body: _encode(body)),
    );
  }

  Future<http.Response> patch(String path, {Object? body}) {
    return _withAuth(
      (headers) =>
          _http.patch(_uri(path), headers: headers, body: _encode(body)),
    );
  }

  Future<http.Response> delete(String path) {
    return _withAuth((headers) => _http.delete(_uri(path), headers: headers));
  }

  Future<http.Response> _withAuth(
    Future<http.Response> Function(Map<String, String> headers) call,
  ) async {
    final firstResponse = await call(await _authHeaders());

    if (firstResponse.statusCode != 401) {
      return firstResponse;
    }

    final refreshed = await _refreshAccessTokenSingleFlight();

    if (!refreshed) {
      await _tokenStorage.clearTokens();
      throw const ApiAuthException('Sessie verlopen.');
    }

    final secondResponse = await call(await _authHeaders());

    if (secondResponse.statusCode == 401) {
      await _tokenStorage.clearTokens();
      throw const ApiAuthException('Sessie verlopen.');
    }

    return secondResponse;
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _tokenStorage.getAccessToken();

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<String> getAccessTokenOrRefresh() async {
    final accessToken = await _tokenStorage.getAccessToken();

    if (accessToken != null && accessToken.isNotEmpty) {
      return accessToken;
    }

    return refreshAndGetAccessToken();
  }

  Future<String> refreshAndGetAccessToken() async {
    final refreshed = await _refreshAccessTokenSingleFlight();

    if (!refreshed) {
      await _tokenStorage.clearTokens();
      throw const ApiAuthException('Sessie verlopen.');
    }

    final newAccessToken = await _tokenStorage.getAccessToken();

    if (newAccessToken == null || newAccessToken.isEmpty) {
      await _tokenStorage.clearTokens();
      throw const ApiAuthException('Geen access token ontvangen.');
    }

    return newAccessToken;
  }

  Future<bool> _refreshAccessTokenSingleFlight() {
    _refreshFuture ??= _refreshAccessToken();

    return _refreshFuture!.whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken = await _tokenStorage.getRefreshToken();

    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    try {
      final response = await _http.post(
        _uri('/api/mobile/auth/refresh/'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'refresh': refreshToken}),
      );

      if (response.statusCode != 200) {
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final access = data['access']?.toString();

      if (access == null || access.isEmpty) {
        return false;
      }

      await _tokenStorage.saveAccessToken(access);
      return true;
    } catch (_) {
      return false;
    }
  }

  Uri _uri(String path, [Map<String, String>? queryParams]) {
    final base = Uri.parse(ApiConfig.baseUrl);

    final normalizedPath = path.startsWith('/') ? path : '/$path';

    final uri = base.replace(path: normalizedPath);

    if (queryParams == null || queryParams.isEmpty) {
      return uri;
    }

    return uri.replace(queryParameters: queryParams);
  }

  String? _encode(Object? body) {
    if (body == null) return null;
    return jsonEncode(body);
  }

  Future<void> clearTokens() async {
    await _tokenStorage.clearTokens();
  }

  void dispose() {
    _http.close();
  }
}

class ApiAuthException implements Exception {
  final String message;

  const ApiAuthException(this.message);

  @override
  String toString() => 'ApiAuthException: $message';
}
