import 'package:flutter/foundation.dart';
import 'package:mobile_app/features/compliance/privacy/services/privacy_service.dart';

import 'package:mobile_app/features/compliance/terms_of_use/services/terms_service.dart';

enum TermsGateStatus { unknown, checking, required, accepted, error }

class TermsGateState extends ChangeNotifier {
  final TermsService _service;

  TermsGateState({TermsService? service})
    : _service = service ?? TermsService();

  TermsGateStatus _status = TermsGateStatus.unknown;
  String? _error;

  TermsGateStatus get status => _status;
  String? get error => _error;

  bool get isAccepted => _status == TermsGateStatus.accepted;
  bool get isRequired => _status == TermsGateStatus.required;

  Future<void> check() async {
    if (_status == TermsGateStatus.checking) return;

    _status = TermsGateStatus.checking;
    _error = null;
    notifyListeners();

    try {
      final bootstrap = await _service.fetchBootstrapStatus();

      _status = bootstrap.termsOfUseRequired
          ? TermsGateStatus.required
          : TermsGateStatus.accepted;
    } catch (_) {
      _status = TermsGateStatus.error;
      _error = 'Kon gebruiksvoorwaarden-status niet controleren.';
    }

    notifyListeners();
  }

  void setFromBootstrap(BootstrapStatus bootstrap) {
    _status = bootstrap.termsOfUseRequired
        ? TermsGateStatus.required
        : TermsGateStatus.accepted;

    _error = null;
    notifyListeners();
  }

  void markAccepted() {
    _status = TermsGateStatus.accepted;
    _error = null;
    notifyListeners();
  }

  void reset() {
    _status = TermsGateStatus.unknown;
    _error = null;
    notifyListeners();
  }
}
