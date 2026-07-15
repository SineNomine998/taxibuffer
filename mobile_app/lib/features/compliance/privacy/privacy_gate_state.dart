import 'package:flutter/foundation.dart';

import 'services/privacy_service.dart';

enum PrivacyGateStatus { unknown, checking, required, accepted, error }

class PrivacyGateState extends ChangeNotifier {
  final PrivacyService _service;

  PrivacyGateState({PrivacyService? service})
    : _service = service ?? PrivacyService();

  PrivacyGateStatus _status = PrivacyGateStatus.unknown;
  String? _error;

  PrivacyGateStatus get status => _status;
  String? get error => _error;

  bool get isAccepted => _status == PrivacyGateStatus.accepted;
  bool get isRequired => _status == PrivacyGateStatus.required;

  Future<void> check() async {
    if (_status == PrivacyGateStatus.checking) return;

    _status = PrivacyGateStatus.checking;
    _error = null;
    notifyListeners();

    try {
      final bootstrap = await _service.fetchBootstrapStatus();

      _status = bootstrap.privacyPolicyRequired
          ? PrivacyGateStatus.required
          : PrivacyGateStatus.accepted;
    } catch (_) {
      _status = PrivacyGateStatus.error;
      _error = 'Kon privacy-status niet controleren.';
    }

    notifyListeners();
  }

  void setFromBootstrap(BootstrapStatus bootstrap) {
    _status = bootstrap.privacyPolicyRequired
        ? PrivacyGateStatus.required
        : PrivacyGateStatus.accepted;

    _error = null;
    notifyListeners();
  }

  void markAccepted() {
    _status = PrivacyGateStatus.accepted;
    _error = null;
    notifyListeners();
  }

  void reset() {
    _status = PrivacyGateStatus.unknown;
    _error = null;
    notifyListeners();
  }
}
