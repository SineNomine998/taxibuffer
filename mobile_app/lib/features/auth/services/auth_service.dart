import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/api_client.dart';
import 'package:mobile_app/features/account/services/account_service.dart';

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';

class AuthService {
  final TokenStorage _tokenStorage;
  final AccountService accountService = AccountService();

  AuthService({TokenStorage? tokenStorage})
    : _tokenStorage = tokenStorage ?? TokenStorage();

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    await _syncPendingLogoutWithBackend();

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/mobile/auth/login/');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Login failed');
    }

    await _tokenStorage.saveTokens(
      access: data['access'],
      refresh: data['refresh'],
    );
    await _tokenStorage.clearLogoutPending();

    return data['user'];
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStorage.getRefreshToken();

    if (refreshToken != null) {
      await _tokenStorage.savePendingLogoutRefreshToken(refreshToken);
    }

    await _tokenStorage.clearTokens();
    await _tokenStorage.setLogoutPending(true);

    if (refreshToken != null) {
      unawaited(_syncPendingLogoutWithBackend());
    }
  }

  Future<void> _syncPendingLogoutWithBackend() async {
    final pendingRefreshToken = await _tokenStorage
        .getPendingLogoutRefreshToken();

    if (pendingRefreshToken == null) {
      await _tokenStorage.clearLogoutPending();
      return;
    }

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/mobile/auth/logout/');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': pendingRefreshToken}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _tokenStorage.clearPendingLogoutRefreshToken();
        await _tokenStorage.clearLogoutPending();
      }
    } catch (_) {
      // Keep pending token so we can retry later.
    }
  }

  Future<Map<String, dynamic>> signup({
    required String firstName,
    required String lastName,
    required String email,
    required String taxiLicenseNumber,
    required String password,
    required String passwordConfirm,
    required List<Map<String, dynamic>> vehicles,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/mobile/auth/signup/');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'first_name': firstName,
        'last_name': lastName,
        'email': email.trim().toLowerCase(),
        'taxi_license_number': taxiLicenseNumber.trim().toUpperCase(),
        'password': password,
        'password_confirm': passwordConfirm,
        'vehicles': vehicles,
      }),
    );

    if (response.statusCode != 201) {
      String message = 'Registreren mislukt';

      try {
        final errorData = jsonDecode(response.body);
        message = errorData['detail'] ?? errorData.toString();
      } catch (_) {
        message = response.body;
      }

      throw Exception(message);
    }

    final data = jsonDecode(response.body);

    await _tokenStorage.saveTokens(
      access: data['access'],
      refresh: data['refresh'],
    );
    await _tokenStorage.clearLogoutPending();

    return data['user'];
  }

  Future<bool> isEmailAvailable(String email) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/mobile/auth/check-email/');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim().toLowerCase()}),
    );

    if (response.statusCode != 200) {
      throw Exception("Kon emailadres niet controleren.");
    }

    final data = jsonDecode(response.body);
    return data['available'] as bool;
  }

  Future<void> requestPasswordReset(String email) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/mobile/auth/password-reset/',
    );
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim().toLowerCase()}),
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Verzoek mislukt');
    }
  }

  Future<bool> tryRestoreSession() async {
    final accessToken = await _tokenStorage.getAccessToken();
    final refreshToken = await _tokenStorage.getRefreshToken();

    if (accessToken == null || refreshToken == null) {
      return false;
    }

    try {
      await accountService.fetchAccount();
      return true;
    } on ApiAuthException {
      await _tokenStorage.clearTokens();
      return false;
    } catch (_) {
      return false;
    }
  }
}
