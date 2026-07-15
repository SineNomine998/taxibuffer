import 'package:flutter/foundation.dart';
import 'package:mobile_app/core/config/api_client.dart';

enum AuthGateStatus { unknown, checking, authenticated, unauthenticated }

class AuthGateState extends ChangeNotifier {
  final ApiClient _apiClient;

  AuthGateState({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  AuthGateStatus _status = AuthGateStatus.unknown;

  AuthGateStatus get status => _status;
  bool get isAuthenticated => _status == AuthGateStatus.authenticated;

  Future<void> check() async {
    if (_status == AuthGateStatus.checking) return;

    _status = AuthGateStatus.checking;
    notifyListeners();

    try {
      final token = await _apiClient.getAccessTokenOrRefresh();
      _status = token.isNotEmpty
          ? AuthGateStatus.authenticated
          : AuthGateStatus.unauthenticated;
    } catch (_) {
      _status = AuthGateStatus.unauthenticated;
    }

    notifyListeners();
  }

  void markAuthenticated() {
    _status = AuthGateStatus.authenticated;
    notifyListeners();
  }

  void markUnauthenticated() {
    _status = AuthGateStatus.unauthenticated;
    notifyListeners();
  }

  void reset() {
    _status = AuthGateStatus.unknown;
    notifyListeners();
  }
}
