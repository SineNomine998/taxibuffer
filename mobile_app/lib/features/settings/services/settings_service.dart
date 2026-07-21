import '../../../core/config/api_client.dart';

class SettingsService {
  final ApiClient _api;

  SettingsService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<void> testPushNotification() async {
    final response = await _api.post('/api/mobile/push/test/');

    if (response.statusCode != 200) {
      throw Exception('Testmelding kon niet worden verzonden.');
    }
  }
}
