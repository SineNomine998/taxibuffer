import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/api_client.dart';
import '../models/sequence_notification.dart';

class SequenceService {
  final ApiClient _api;

  SequenceService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

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
    final response = await _api.get('/api/mobile/sequence-history/');

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Kon nummers niet laden.'));
    }

    final data = jsonDecode(response.body);

    if (data is Map<String, dynamic>) {
      final items = data['items'];

      if (items is List) {
        final sequenceNumbers = items
            .map(
              (e) => SequenceNotification.fromJson(e as Map<String, dynamic>),
            )
            .toList();

        sequenceNumbers.sort(
          (a, b) => b.sequenceNumber.compareTo(a.sequenceNumber),
        );

        return sequenceNumbers;
      }
    }

    throw Exception('Ongeldig ophaalnummerhistorie-format ontvangen.');
  }
}
