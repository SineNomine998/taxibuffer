import 'dart:convert';

import 'package:mobile_app/core/config/api_client.dart';
import 'package:mobile_app/features/activity/models/activity_log_item.dart';

class ActivityService {
  final ApiClient _api;

  ActivityService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<ActivityLogItem>> fetchActivityLogs() async {
    final response = await _api.get('/api/mobile/activity/');

    if (response.statusCode != 200) {
      throw Exception('Kon activiteiten niet laden.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List? ?? [];

    return results
        .map((item) => ActivityLogItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
