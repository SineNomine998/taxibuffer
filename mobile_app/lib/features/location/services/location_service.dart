import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_app/core/config/api_client.dart';
import 'package:http/http.dart' as http;
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

class QueueListState {
  final String? activeEntryUuid;
  final bool alreadyInQueue;
  final bool activelyWaiting;
  final List<PickupZone> queues;

  const QueueListState({
    required this.activeEntryUuid,
    required this.alreadyInQueue,
    required this.activelyWaiting,
    required this.queues,
  });

  bool get hasActiveQueue =>
      activeEntryUuid != null && activeEntryUuid!.isNotEmpty;
}

class LocationService {
  final ApiClient _api;

  LocationService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

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
      throw const LocationUnavailableException(
        'Locatievoorziening is uitgeschakeld.',
      );
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

  Future<QueueListState> fetchQueuesState() async {
    final response = await _api.get('/api/mobile/queues/');

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
      final queuesJson = data['queues'];

      if (queuesJson is! List) {
        throw Exception('Ongeldig locaties-formaat ontvangen.');
      }

      final queues = queuesJson
          .map((e) => PickupZone.fromJson(e as Map<String, dynamic>))
          .toList();

      return QueueListState(
        activeEntryUuid: data['active_entry_uuid'] as String?,
        alreadyInQueue: data['already_in_queue'] as bool? ?? false,
        activelyWaiting: data['actively_waiting'] as bool? ?? false,
        queues: queues,
      );
    }

    // Temporary backwards compatibility if backend returns a raw list.
    if (data is List) {
      final queues = data
          .map((e) => PickupZone.fromJson(e as Map<String, dynamic>))
          .toList();

      return QueueListState(
        activeEntryUuid: null,
        alreadyInQueue: false,
        activelyWaiting: false,
        queues: queues,
      );
    }

    throw Exception('Ongeldig locaties-formaat ontvangen.');
  }

  Future<List<PickupZone>> fetchQueues() async {
    final state = await fetchQueuesState();
    return state.queues;
  }

  Future<GeofenceResult> validateLocation({
    required double lat,
    required double lng,
    required int queueId,
  }) async {
    final response = await _api.post(
      '/api/mobile/queues/$queueId/validate-location/',
      body: {'lat': lat, 'lng': lng},
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

  Future<String> joinQueue({
    required int queueId,
    required double lat,
    required double lng,
  }) async {
    final response = await _api.post(
      '/api/mobile/queues/$queueId/join/',
      body: {'lat': lat, 'lng': lng},
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Aanmelden bij wachtrij mislukt.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final entryUuid = data['entry_uuid'];

    if (entryUuid == null || entryUuid.toString().isEmpty) {
      throw Exception('Geen actieve wachtrij gevonden.');
    }

    return entryUuid.toString();
  }
}

class LocationUnavailableException implements Exception {
  final String message;

  const LocationUnavailableException(this.message);

  @override
  String toString() => message;
}
