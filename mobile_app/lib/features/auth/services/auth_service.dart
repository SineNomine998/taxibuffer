import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';

class AuthService {
  final TokenStorage _tokenStorage;

  AuthService({TokenStorage? tokenStorage})
    : _tokenStorage = tokenStorage ?? TokenStorage();

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
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

    return data['user'];
  }

  Future<Map<String, dynamic>> getMe() async {
    final accessToken = await _tokenStorage.getAccessToken();

    if (accessToken == null) {
      throw Exception('No access token found');
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/mobile/me/');

    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Could not fetch user');
    }

    return data;
  }

  Future<void> logout() async {
    final accessToken = await _tokenStorage.getAccessToken();
    final refreshToken = await _tokenStorage.getRefreshToken();

    if (accessToken != null && refreshToken != null) {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/mobile/auth/logout/');

      await http.post(
        uri,
        headers: {
          'Content-type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'refresh': refreshToken}),
      );
    }

    await _tokenStorage.clearTokens();
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
}
