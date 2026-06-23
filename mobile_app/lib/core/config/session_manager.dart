import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SessionManager {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static void handleAuthExpired() {
    navigatorKey.currentContext?.go('/login');
  }
}
