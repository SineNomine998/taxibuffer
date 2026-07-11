import 'package:flutter/foundation.dart';
import '../../../core/models/vehicle.dart';
import 'package:collection/collection.dart';

/// Accumulates data across all signup steps. Created once above the
/// signup route subtree and read/written by each step screen.
/// Submitted as a single payload to mobile_api only on final confirmation.
class SignupFormState extends ChangeNotifier {
  // Step 1 - personal details
  String firstName = '';
  String lastName = '';
  String email = '';
  String taxiLicenseNumber = '';

  // Step 2 - credentials
  String password = '';
  String passwordConfirm = '';

  // Step 3 - vehicles
  final List<Vehicle> vehicles = [];
  bool privacyPolicyAccepted = false;
  String? acceptedPrivacyPolicyVersion;

  void setPersonalDetails({
    required String firstName,
    required String lastName,
    required String email,
    required String taxiLicenseNumber,
  }) {
    this.firstName = firstName;
    this.lastName = lastName;
    this.email = email;
    this.taxiLicenseNumber = taxiLicenseNumber;
    notifyListeners();
  }

  void setPassword(String password, String passwordConfirm) {
    this.password = password;
    this.passwordConfirm = passwordConfirm;
    notifyListeners();
  }

  void addVehicle(Vehicle vehicle) {
    if (vehicle.isCurrent) {
      for (var i = 0; i < vehicles.length; i++) {
        final v = vehicles[i];
        // make it no more current
        if (v.isCurrent) {
          vehicles[i] = Vehicle(
            nickname: v.nickname,
            licensePlate: v.licensePlate,
            vehicleType: v.vehicleType,
            isCurrent: false,
          );
        }
      }
    }
    vehicles.add(vehicle);
    notifyListeners();
  }

  void removeVehicle(Vehicle vehicle) {
    vehicles.remove(vehicle);
    notifyListeners();
  }

  void setCurrentVehicle(Vehicle target) {
    for (var i = 0; i < vehicles.length; i++) {
      final v = vehicles[i];
      vehicles[i] = Vehicle(
        nickname: v.nickname,
        licensePlate: v.licensePlate,
        vehicleType: v.vehicleType,
        isCurrent: v == target,
      );
    }
    notifyListeners();
  }

  void acceptPrivacyPolicy(String version) {
    privacyPolicyAccepted = true;
    acceptedPrivacyPolicyVersion = version;
    notifyListeners();
  }

  Vehicle? get currentVehicle =>
      vehicles.where((v) => v.isCurrent).cast<Vehicle?>().firstOrNull;

  List<Vehicle> get otherVehicles =>
      vehicles.where((v) => !v.isCurrent).toList();

  /// Resets everything - call after a successful signup submission
  /// or if the user abandons the flow.
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
    notifyListeners();
  }
}
