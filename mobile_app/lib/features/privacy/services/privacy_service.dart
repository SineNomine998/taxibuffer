import 'dart:convert';

import 'package:mobile_app/core/config/api_config.dart';

import '../../../core/config/api_client.dart';
import 'package:http/http.dart' as http;

class BootstrapStatus {
  final bool privacyPolicyRequired;
  final String? currentPrivacyPolicyVersion;

  const BootstrapStatus({
    required this.privacyPolicyRequired,
    required this.currentPrivacyPolicyVersion,
  });

  factory BootstrapStatus.fromJson(Map<String, dynamic> json) {
    return BootstrapStatus(
      privacyPolicyRequired: json['privacy_policy_required'] == true,
      currentPrivacyPolicyVersion: json['current_privacy_policy_version']
          ?.toString(),
    );
  }
}

class PrivacyPolicyData {
  final int id;
  final String version;
  final String title;
  final String bodyNl;
  final bool accepted;

  const PrivacyPolicyData({
    required this.id,
    required this.version,
    required this.title,
    required this.bodyNl,
    required this.accepted,
  });

  factory PrivacyPolicyData.fromJson(Map<String, dynamic> json) {
    return PrivacyPolicyData(
      id: json['id'] as int? ?? 0,
      version: json['version']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Privacyverklaring',
      bodyNl: json['body_nl']?.toString() ?? '',
      accepted: json['accepted'] == true,
    );
  }
}

class PrivacyService {
  final ApiClient _api;

  PrivacyService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<BootstrapStatus> fetchBootstrapStatus() async {
    final response = await _api.get('/api/mobile/bootstrap/');

    if (response.statusCode != 200) {
      throw Exception('Kon app-status niet laden.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return BootstrapStatus.fromJson(data);
  }

  Future<PrivacyPolicyData> fetchPrivacyPolicy() async {
    final response = await _api.get('/api/mobile/privacy-policy/');

    if (response.statusCode != 200) {
      throw Exception('Kon privacyverklaring niet laden.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return PrivacyPolicyData.fromJson(data);
  }

  Future<PrivacyPolicyData> fetchPublicPrivacyPolicy() async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/mobile/privacy-policy/public/',
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Kon privacyverklaring niet laden.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    return PrivacyPolicyData.fromJson({...data, 'id': 0, 'accepted': false});
  }

  Future<void> acceptPrivacyPolicy(String version) async {
    final response = await _api.post(
      '/api/mobile/privacy-policy/accept/',
      body: {'version': version},
    );

    if (response.statusCode != 200) {
      throw Exception('Kon privacyverklaring niet accepteren.');
    }
  }
}
