import 'dart:convert';

import 'package:mobile_app/core/config/api_client.dart';
import 'package:mobile_app/core/config/api_config.dart';
import 'package:mobile_app/features/compliance/privacy/services/privacy_service.dart';
import '../models/terms_of_use_data.dart';
import 'package:http/http.dart' as http;

class TermsService {
  final ApiClient _api;

  TermsService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<BootstrapStatus> fetchBootstrapStatus() async {
    final response = await _api.get('/api/mobile/bootstrap/');

    if (response.statusCode != 200) {
      throw Exception('Kon app-status niet laden.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return BootstrapStatus.fromJson(data);
  }

  Future<TermsOfUseData> fetchTermsOfUse() async {
    final response = await _api.get('/api/mobile/terms-of-use/');

    if (response.statusCode != 200) {
      throw Exception('Kon gebruiksvoorwaarden niet laden.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return TermsOfUseData.fromJson(data);
  }

  Future<TermsOfUseData> fetchPublicTermsOfUse() async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/mobile/terms-of-use/public/',
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Kon gebruiksvoorwaarden niet laden.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    return TermsOfUseData.fromJson({...data, 'accepted': false});
  }

  Future<void> acceptTermsOfUse(String version) async {
    final response = await _api.post(
      '/api/mobile/terms-of-use/accept/',
      body: {'version': version},
    );

    if (response.statusCode != 200) {
      throw Exception('Kon gebruiksvoorwaarden niet accepteren.');
    }
  }
}
