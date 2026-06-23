import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/sequence_notification.dart';

class SequenceService {
  final TokenStorage _tokenStorage;

  SequenceService({TokenStorage? tokenStorage})
    : _tokenStorage = tokenStorage ?? TokenStorage();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _tokenStorage.getAccessToken();

    if (token == null) throw Exception('Niet ingelogd.');

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
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

  Future<List<SequenceNotification>> fetchTodaysNotifications() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/mobile/sequence-history/');

    final response = await http.get(uri, headers: await _authHeaders());

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Kon nummers niet laden.'));
    }

    final data = jsonDecode(response.body);

    if (data is Map<String, dynamic>) {
      final items = data['items'];

      if (items is List) {
        return items
            .map(
              (e) => SequenceNotification.fromJson(e as Map<String, dynamic>),
            )
            .toList();
      }
    }

    throw Exception('Ongeldig ophaalnummerhistorie-format ontvangen.');
  }
}
