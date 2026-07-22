import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';

import '../../../core/models/vehicle.dart';

class SignupFormState extends ChangeNotifier {
  String firstName = '';
  String lastName = '';
  String email = '';
  String taxiLicenseNumber = '';

  String password = '';
  String passwordConfirm = '';

  final List<Vehicle> vehicles = [];

  bool privacyPolicyAccepted = false;
  bool termsOfUseAccepted = false;

  String? acceptedPrivacyPolicyVersion;
  String? acceptedTermsOfUseVersion;

  void setPersonalDetails({
    required String firstName,
    required String lastName,
    required String email,
    required String taxiLicenseNumber,
  }) {
    this.firstName = firstName.trim();
    this.lastName = lastName.trim();
    this.email = email.trim().toLowerCase();
    this.taxiLicenseNumber = taxiLicenseNumber.trim().toUpperCase();
    notifyListeners();
  }

  void setPassword(String password, String passwordConfirm) {
    this.password = password;
    this.passwordConfirm = passwordConfirm;
    notifyListeners();
  }

  void addVehicle(Vehicle vehicle) {
    final normalized = Vehicle(
      nickname: vehicle.nickname.trim(),
      licensePlate: vehicle.licensePlate.trim().toUpperCase(),
      vehicleType: vehicle.vehicleType,
      isCurrent: vehicle.isCurrent || vehicles.isEmpty,
    );

    final alreadyExists = vehicles.any(
      (v) => v.licensePlate.toUpperCase() == normalized.licensePlate,
    );

    if (alreadyExists) {
      throw Exception('Dit kenteken is al toegevoegd.');
    }

    if (normalized.isCurrent) {
      for (var i = 0; i < vehicles.length; i++) {
        final v = vehicles[i];
        vehicles[i] = Vehicle(
          nickname: v.nickname,
          licensePlate: v.licensePlate,
          vehicleType: v.vehicleType,
          isCurrent: false,
        );
      }
    }

    vehicles.add(normalized);
    notifyListeners();
  }

  void removeVehicle(Vehicle vehicle) {
    final wasCurrent = vehicle.isCurrent;

    vehicles.removeWhere(
      (v) => v.licensePlate.toUpperCase() == vehicle.licensePlate.toUpperCase(),
    );

    if (wasCurrent && vehicles.isNotEmpty) {
      final first = vehicles.first;
      vehicles[0] = Vehicle(
        nickname: first.nickname,
        licensePlate: first.licensePlate,
        vehicleType: first.vehicleType,
        isCurrent: true,
      );
    }

    notifyListeners();
  }

  void setCurrentVehicle(Vehicle target) {
    for (var i = 0; i < vehicles.length; i++) {
      final v = vehicles[i];
      vehicles[i] = Vehicle(
        nickname: v.nickname,
        licensePlate: v.licensePlate,
        vehicleType: v.vehicleType,
        isCurrent:
            v.licensePlate.toUpperCase() == target.licensePlate.toUpperCase(),
      );
    }

    notifyListeners();
  }

  void acceptPrivacyPolicy(String version) {
    privacyPolicyAccepted = true;
    acceptedPrivacyPolicyVersion = version;
    notifyListeners();
  }

  void acceptTermsOfUse(String version) {
    termsOfUseAccepted = true;
    acceptedTermsOfUseVersion = version;
    notifyListeners();
  }

  Vehicle? get currentVehicle => vehicles.firstWhereOrNull((v) => v.isCurrent);

  List<Vehicle> get otherVehicles =>
      vehicles.where((v) => !v.isCurrent).toList();

  void reset() {
    firstName = '';
    lastName = '';
    email = '';
    taxiLicenseNumber = '';

    password = '';
    passwordConfirm = '';

    vehicles.clear();

    privacyPolicyAccepted = false;
    acceptedPrivacyPolicyVersion = null;

    termsOfUseAccepted = false;
    acceptedTermsOfUseVersion = null;

    notifyListeners();
  }
}
