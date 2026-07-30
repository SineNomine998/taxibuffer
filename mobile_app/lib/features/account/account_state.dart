import 'package:flutter/foundation.dart';
import 'package:mobile_app/core/config/api_client.dart';
import 'package:mobile_app/core/models/tto_option.dart';
import '../../../core/models/vehicle.dart';
import 'models/account_profile.dart';
import 'services/account_service.dart';

class AccountState extends ChangeNotifier {
  final AccountService _accountService;

  AccountState({AccountService? accountService})
    : _accountService = accountService ?? AccountService();

  bool _disposed = false;

  AccountProfile? profile;
  List<Vehicle> vehicles = [];
  bool isLoading = false;
  String? loadError;
  List<TtoOption> ttoOptions = [];

  Vehicle? get currentVehicle =>
      vehicles.where((v) => v.isCurrent).cast<Vehicle?>().firstOrNull;

  List<Vehicle> get otherVehicles =>
      vehicles.where((v) => !v.isCurrent).toList();

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    if (_disposed) return;

    isLoading = true;
    loadError = null;
    _safeNotify();

    try {
      final accountFuture = _accountService.fetchAccount();
      final ttoFuture = _accountService.fetchTtoOptions();

      final data = await accountFuture;
      final ttos = await ttoFuture;

      if (_disposed) return;

      profile = AccountProfile.fromJson(data['profile']);
      vehicles = (data['vehicles'] as List)
          .map((v) => Vehicle.fromJson(v as Map<String, dynamic>))
          .toList();
      ttoOptions = ttos;
    } on ApiAuthException {
      rethrow;
    } catch (e) {
      if (_disposed) return;
      loadError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (!_disposed) {
        isLoading = false;
        _safeNotify();
      }
    }
  }

  Future<void> updateProfile(AccountProfile updated) async {
    final saved = await _accountService.updateProfile(updated);
    if (_disposed) return;

    profile = saved;
    _safeNotify();
  }

  Future<void> addVehicle(Vehicle vehicle) async {
    final saved = await _accountService.addVehicle(vehicle);
    if (_disposed) return;

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
    _safeNotify();
  }

  Future<void> setCurrentVehicle(Vehicle target) async {
    await _accountService.setCurrentVehicle(target.id!);
    if (_disposed) return;

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

    _safeNotify();
  }

  Future<void> removeVehicle(Vehicle target) async {
    await _accountService.removeVehicle(target.id!);
    if (_disposed) return;

    vehicles = vehicles.where((v) => v.id != target.id).toList();

    if (vehicles.isNotEmpty && vehicles.every((v) => !v.isCurrent)) {
      await load();
      return;
    }

    _safeNotify();
  }

  Future<void> adjustVehicle(Vehicle target) async {
    final saved = await _accountService.adjustVehicle(target);
    if (_disposed) return;

    vehicles = vehicles.map((v) {
      if (v.id != saved.id) return v;
      return saved;
    }).toList();

    _safeNotify();
  }
}
