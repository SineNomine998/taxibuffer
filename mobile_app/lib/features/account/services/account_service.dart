import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/api_client.dart';
import '../../../core/models/vehicle.dart';
import '../models/account_profile.dart';

class AccountService {
  final ApiClient _api;

  AccountService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

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

  Map<String, dynamic> _jsonMap(http.Response response, String fallback) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) return data;
    } catch (_) {}

    throw Exception(fallback);
  }

  Future<Map<String, dynamic>> fetchAccount() async {
    final response = await _api.get('/api/mobile/account/');

    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Kon accountgegevens niet laden.'),
      );
    }

    return _jsonMap(response, 'Ongeldig account-formaat ontvangen.');
  }

  Future<AccountProfile> updateProfile(AccountProfile profile) async {
    final response = await _api.patch(
      '/api/mobile/account/profile/',
      body: profile.toJson(),
    );

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Bijwerken mislukt.'));
    }

    return AccountProfile.fromJson(
      _jsonMap(response, 'Ongeldig profiel-formaat ontvangen.'),
    );
  }

  Future<Vehicle> addVehicle(Vehicle vehicle) async {
    final response = await _api.post(
      '/api/mobile/account/vehicles/',
      body: vehicle.toJson(),
    );

    if (response.statusCode != 201) {
      throw Exception(_errorMessage(response, 'Voertuig toevoegen mislukt.'));
    }

    return Vehicle.fromJson(
      _jsonMap(response, 'Ongeldig voertuig-formaat ontvangen.'),
    );
  }

  Future<void> setCurrentVehicle(int vehicleId) async {
    final response = await _api.post(
      '/api/mobile/account/vehicles/$vehicleId/set-current/',
    );

    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Kon huidig voertuig niet instellen.'),
      );
    }
  }

  Future<void> removeVehicle(int vehicleId) async {
    final response = await _api.delete(
      '/api/mobile/account/vehicles/$vehicleId/',
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(
        _errorMessage(response, 'Kon voertuig niet verwijderen.'),
      );
    }
  }

  Future<Vehicle> adjustVehicle(Vehicle vehicle) async {
    final response = await _api.patch(
      '/api/mobile/account/vehicles/${vehicle.id}/',
      body: vehicle.toJson(),
    );

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Voertuig bijwerken mislukt.'));
    }

    return Vehicle.fromJson(
      _jsonMap(response, 'Ongeldig voertuig-formaat ontvangen.'),
    );
  }
}
