import 'dart:convert';
import 'package:mobile_app/core/config/api_client.dart';
import '../../../core/models/vehicle.dart';
import '../models/account_profile.dart';

class AccountService {
  final ApiClient _api;

  AccountService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> fetchAccount() async {
    final response = await _api.get('/api/mobile/account/');
    if (response.statusCode != 200) {
      throw Exception('Kon accountgegevens niet laden.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<AccountProfile> updateProfile(AccountProfile profile) async {
    final response = await _api.patch(
      '/api/mobile/account/profile/',
      body: profile.toJson(),
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Bijwerken mislukt.');
    }
    return AccountProfile.fromJson(jsonDecode(response.body));
  }

  Future<Vehicle> addVehicle(Vehicle vehicle) async {
    final response = await _api.post(
      '/api/mobile/account/vehicles/',
      body: vehicle.toJson(),
    );
    if (response.statusCode != 201) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Voertuig toevoegen mislukt.');
    }
    return Vehicle.fromJson(jsonDecode(response.body));
  }

  Future<void> setCurrentVehicle(int vehicleId) async {
    final response = await _api.post(
      '/api/mobile/account/vehicles/$vehicleId/set-current/',
    );
    if (response.statusCode != 200) {
      // throw Exception('Kon huidig voertuig niet instellen.');
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<void> removeVehicle(int vehicleId) async {
    final response = await _api.delete(
      '/api/mobile/account/vehicles/$vehicleId/',
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      // throw Exception('Kon voertuig niet verwijderen.');
      throw Exception(jsonDecode(response.body)['detail']);
    }
  }

  Future<Vehicle> adjustVehicle(Vehicle vehicle) async {
    final response = await _api.patch(
      '/api/mobile/account/vehicles/${vehicle.id}/',
      body: vehicle.toJson(),
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Voertuig bijwerken mislukt.');
    }

    return Vehicle.fromJson(jsonDecode(response.body));
  }
}
