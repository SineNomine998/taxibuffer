import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/api_config.dart';
import '../storage/token_storage.dart';

/// Thin HTTP client that:
/// 1. Attaches the JWT access token to every request.
/// 2. On a 401, attempts a silent token refresh and retries once.
/// 3. On a second 401 (refresh rejected), clears tokens and rethrows.
class ApiClient {
  final TokenStorage _tokenStorage;
  final http.Client _http;

  ApiClient({TokenStorage? tokenStorage, http.Client? httpClient})
    : _tokenStorage = tokenStorage ?? TokenStorage(),
      _http = httpClient ?? http.Client();

  Future<http.Response> get(String path, {Map<String, String>? queryParams}) =>
      _withAuth((h) => _http.get(_uri(path, queryParams), headers: h));

  Future<http.Response> post(String path, {Object? body}) =>
      _withAuth((h) => _http.post(_uri(path), headers: h, body: _encode(body)));

  Future<http.Response> patch(String path, {Object? body}) => _withAuth(
    (h) => _http.patch(_uri(path), headers: h, body: _encode(body)),
  );

  Future<http.Response> delete(String path) =>
      _withAuth((h) => _http.delete(_uri(path), headers: h));

  Future<http.Response> _withAuth(
    Future<http.Response> Function(Map<String, String> headers) call,
  ) async {
    final response = await call(await _authHeaders());

    if (response.statusCode != 401) return response;

    // Access token expired -> try a silent refresh.
    final refreshed = await _refreshAccessToken();
    if (!refreshed) throw ApiAuthException();

    // Retry once with the new token.
    final retried = await call(await _authHeaders());
    if (retried.statusCode == 401) throw ApiAuthException();

    return retried;
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _tokenStorage.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await _http.post(
        _uri('/api/mobile/auth/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      );

      if (response.statusCode != 200) {
        await _tokenStorage.clearTokens();
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final access = data['access'] as String?;

      if (access == null || access.isEmpty) {
        await _tokenStorage.clearTokens();
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
    final uri = base.replace(path: path.startsWith('/') ? path : '/$path');
    return queryParams != null
        ? uri.replace(queryParameters: queryParams)
        : uri;
  }

  String? _encode(Object? body) => body != null ? jsonEncode(body) : null;

  void dispose() => _http.close();
}

/// Thrown when a request fails with 401 after a token refresh attempt.
/// Callers should catch this and redirect to the login screen.
class ApiAuthException implements Exception {
  @override
  String toString() =>
      'ApiAuthException: session expired, please log in again.';
}
