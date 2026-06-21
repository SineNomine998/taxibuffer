import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/models/vehicle.dart';
import '../models/account_profile.dart';

class AccountService {
  final TokenStorage _tokenStorage;

  AccountService({TokenStorage? tokenStorage})
    : _tokenStorage = tokenStorage ?? TokenStorage();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _tokenStorage.getAccessToken();
    if (token == null) throw Exception('Niet ingelogd.');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> fetchAccount() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/mobile/account/');
    final response = await http.get(uri, headers: await _authHeaders());
    if (response.statusCode != 200) {
      throw Exception('Kon accountgegevens niet laden.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<AccountProfile> updateProfile(AccountProfile profile) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/mobile/account/profile/');
    final response = await http.patch(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode(profile.toJson()),
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Bijwerken mislukt.');
    }
    return AccountProfile.fromJson(jsonDecode(response.body));
  }

  Future<Vehicle> addVehicle(Vehicle vehicle) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/mobile/account/vehicles/');
    final response = await http.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode(vehicle.toJson()),
    );
    if (response.statusCode != 201) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Voertuig toevoegen mislukt.');
    }
    return Vehicle.fromJson(jsonDecode(response.body));
  }

  Future<void> setCurrentVehicle(int vehicleId) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/mobile/account/vehicles/$vehicleId/set-current/',
    );
    final response = await http.post(uri, headers: await _authHeaders());
    if (response.statusCode != 200) {
      throw Exception('Kon huidig voertuig niet instellen.');
    }
  }

  Future<void> removeVehicle(int vehicleId) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/mobile/account/vehicles/$vehicleId/',
    );
    final response = await http.delete(uri, headers: await _authHeaders());
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Kon voertuig niet verwijderen.');
    }
  }
}
