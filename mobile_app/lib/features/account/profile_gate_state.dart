import 'package:flutter/foundation.dart';
import 'package:mobile_app/features/compliance/privacy/services/privacy_service.dart';

enum ProfileGateStatus { unknown, checking, required, completed }

class ProfileGateState extends ChangeNotifier {
  ProfileGateStatus _status = ProfileGateStatus.unknown;

  ProfileGateStatus get status => _status;

  bool get isRequired => _status == ProfileGateStatus.required;
  bool get isCompleted => _status == ProfileGateStatus.completed;

  void setRequired() {
    _status = ProfileGateStatus.required;
    notifyListeners();
  }

  void markCompleted() {
    _status = ProfileGateStatus.completed;
    notifyListeners();
  }

  void reset() {
    _status = ProfileGateStatus.unknown;
    notifyListeners();
  }

  void setFromBootstrap(bool required) {
    _status = required
        ? ProfileGateStatus.required
        : ProfileGateStatus.completed;
    notifyListeners();
  }

  Future<void> check() async {
    if (_status == ProfileGateStatus.checking) return;

    _status = ProfileGateStatus.checking;
    notifyListeners();

    try {
      final bootstrap = await PrivacyService().fetchBootstrapStatus();

      _status = bootstrap.profileCompletionRequired
          ? ProfileGateStatus.required
          : ProfileGateStatus.completed;
    } catch (_) {
      _status = ProfileGateStatus.required;
    }

    notifyListeners();
  }
}
