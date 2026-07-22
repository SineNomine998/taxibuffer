import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/api_client.dart';
import 'package:mobile_app/core/config/api_config.dart';
import 'package:mobile_app/features/compliance/privacy/services/privacy_service.dart';

import '../models/terms_of_use_data.dart';

class TermsService {
  final ApiClient _api;

  TermsService({ApiClient? api}) : _api = api ?? ApiClient();

  Map<String, dynamic> _decodeMap(String body, String fallback) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) return data;
    } catch (_) {}

    throw Exception(fallback);
  }

  String _errorMessage(http.Response response, String fallback) {
    try {
      final data = jsonDecode(response.body);

      if (data is Map<String, dynamic>) {
        final detail = data['detail'];
        final error = data['error'];

        if (detail != null) return detail.toString();
        if (error != null) return error.toString();
      }
    } catch (_) {}

    return fallback;
  }

  Future<BootstrapStatus> fetchBootstrapStatus() async {
    final response = await _api.get('/api/mobile/bootstrap/');

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Kon app-status niet laden.'));
    }

    final data = _decodeMap(
      response.body,
      'Ongeldig app-status formaat ontvangen.',
    );

    return BootstrapStatus.fromJson(data);
  }

  Future<TermsOfUseData> fetchTermsOfUse() async {
    final response = await _api.get('/api/mobile/terms-of-use/');

    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Kon gebruiksvoorwaarden niet laden.'),
      );
    }

    final data = _decodeMap(
      response.body,
      'Ongeldig gebruiksvoorwaarden formaat ontvangen.',
    );

    return TermsOfUseData.fromJson(data);
  }

  Future<TermsOfUseData> fetchPublicTermsOfUse() async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/mobile/terms-of-use/public/',
    );

    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Kon gebruiksvoorwaarden niet laden.'),
      );
    }

    final data = _decodeMap(
      response.body,
      'Ongeldig gebruiksvoorwaarden formaat ontvangen.',
    );

    return TermsOfUseData.fromJson({...data, 'accepted': false});
  }

  Future<void> acceptTermsOfUse(String version) async {
    final response = await _api.post(
      '/api/mobile/terms-of-use/accept/',
      body: {'version': version},
    );

    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Kon gebruiksvoorwaarden niet accepteren.'),
      );
    }
  }
}
