import 'package:flutter/material.dart';
import 'package:mobile_app/core/router.dart';

class SessionManager {
  static bool _isHandlingExpiredSession = false;

  static void handleAuthExpired() {
    if (_isHandlingExpiredSession) return;
    _isHandlingExpiredSession = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentLocation = router.routerDelegate.currentConfiguration.uri
          .toString();

      final next = Uri.encodeComponent(currentLocation);

      router.go('/login?next=$next');

      Future.delayed(const Duration(seconds: 1), () {
        _isHandlingExpiredSession = false;
      });
    });
  }
}
