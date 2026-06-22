import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/pickup_zone.dart';

class GeofenceResult {
  final bool isValid;
  final String? errorMessage;

  const GeofenceResult({required this.isValid, this.errorMessage});
}

class LocationPermissionDeniedException implements Exception {
  final bool permanently;

  LocationPermissionDeniedException({this.permanently = false});
}

class LocationService {
  final TokenStorage _tokenStorage;

  LocationService({TokenStorage? tokenStorage})
    : _tokenStorage = tokenStorage ?? TokenStorage();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _tokenStorage.getAccessToken();

    if (token == null) {
      throw Exception('Niet ingelogd.');
    }

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
        final errorMessage = data['error_message'];

        if (detail != null) return detail.toString();
        if (error != null) return error.toString();
        if (errorMessage != null) return errorMessage.toString();
      }
    } catch (_) {
      // Response was not JSON.
    }

    return fallback;
  }

  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception('Locatievoorziening is uitgeschakeld.');
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        throw LocationPermissionDeniedException();
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw LocationPermissionDeniedException(permanently: true);
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }

  Future<List<PickupZone>> fetchQueues() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/mobile/queues/');

    final response = await http.get(uri, headers: await _authHeaders());

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Kon locaties niet laden.'));
    }

    final data = jsonDecode(response.body);

    // Preferred backend shape:
    // {
    //   "active_entry_uuid": null,
    //   "already_in_queue": false,
    //   "queues": [...]
    // }
    if (data is Map<String, dynamic>) {
      final queues = data['queues'];

      if (queues is List) {
        return queues
            .map((e) => PickupZone.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      throw Exception('Ongeldig locaties-formaat ontvangen.');
    }

    // Temporary backwards compatibility if backend returns a raw list.
    if (data is List) {
      return data
          .map((e) => PickupZone.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw Exception('Ongeldig locaties-formaat ontvangen.');
  }

  Future<GeofenceResult> validateLocation({
    required double lat,
    required double lng,
    required int queueId,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/mobile/queues/$queueId/validate-location/',
    );

    final response = await http.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({'lat': lat, 'lng': lng}),
    );

    if (response.statusCode != 200) {
      return GeofenceResult(
        isValid: false,
        errorMessage: _errorMessage(response, 'Kon locatie niet valideren.'),
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    return GeofenceResult(
      isValid: data['is_valid'] as bool? ?? false,
      errorMessage: data['error_message'] as String?,
    );
  }

  Future<void> joinQueue({
    required int queueId,
    required double lat,
    required double lng,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/mobile/queues/$queueId/join/',
    );

    final response = await http.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({'lat': lat, 'lng': lng}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        _errorMessage(response, 'Aanmelden bij wachtrij mislukt.'),
      );
    }
  }
}
