import 'package:flutter/foundation.dart';
import 'package:mobile_app/core/config/api_client.dart';
import '../../../core/models/vehicle.dart';
import 'models/account_profile.dart';
import 'services/account_service.dart';

class AccountState extends ChangeNotifier {
  final AccountService _accountService;

  AccountState({AccountService? accountService})
    : _accountService = accountService ?? AccountService();

  AccountProfile? profile;
  List<Vehicle> vehicles = [];
  bool isLoading = false;
  String? loadError;

  Vehicle? get currentVehicle =>
      vehicles.where((v) => v.isCurrent).cast<Vehicle?>().firstOrNull;

  List<Vehicle> get otherVehicles =>
      vehicles.where((v) => !v.isCurrent).toList();

  Future<void> load() async {
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      final data = await _accountService.fetchAccount();

      profile = AccountProfile.fromJson(data['profile']);
      vehicles = (data['vehicles'] as List)
          .map((v) => Vehicle.fromJson(v as Map<String, dynamic>))
          .toList();
    } on ApiAuthException {
      rethrow;
    } catch (e) {
      loadError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateProfile(AccountProfile updated) async {
    final saved = await _accountService.updateProfile(updated);
    profile = saved;
    notifyListeners();
  }

  Future<void> addVehicle(Vehicle vehicle) async {
    final saved = await _accountService.addVehicle(vehicle);
    if (vehicle.isCurrent) {
      vehicles = vehicles
          .map(
            (v) => Vehicle(
              id: v.id,
              nickname: v.nickname,
              licensePlate: v.licensePlate,
              vehicleType: v.vehicleType,
              isCurrent: false,
            ),
          )
          .toList();
    }
    vehicles.add(saved);
    notifyListeners();
  }

  Future<void> setCurrentVehicle(Vehicle target) async {
    await _accountService.setCurrentVehicle(target.id!);
    vehicles = vehicles
        .map(
          (v) => Vehicle(
            id: v.id,
            nickname: v.nickname,
            licensePlate: v.licensePlate,
            vehicleType: v.vehicleType,
            isCurrent: v.id == target.id,
          ),
        )
        .toList();
    notifyListeners();
  }

  Future<void> removeVehicle(Vehicle target) async {
    await _accountService.removeVehicle(target.id!);

    vehicles = vehicles.where((v) => v.id != target.id).toList();

    if (vehicles.isNotEmpty && vehicles.every((v) => !v.isCurrent)) {
      await load();
      return;
    }

    notifyListeners();
  }

  Future<void> adjustVehicle(Vehicle target) async {
    final saved = await _accountService.adjustVehicle(target);

    vehicles = vehicles.map((v) {
      if (v.id != saved.id) return v;
      return saved;
    }).toList();

    notifyListeners();
  }
}
