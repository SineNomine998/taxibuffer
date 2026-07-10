import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_app/core/notifications/notification_service.dart';
import '../config/api_client.dart';

class QueuePermissionStatus {
  final bool locationGranted;
  final bool locationPermanentlyDenied;
  final bool notificationGranted;
  final bool notificationPermanentlyDenied;

  const QueuePermissionStatus({
    required this.locationGranted,
    required this.locationPermanentlyDenied,
    required this.notificationGranted,
    required this.notificationPermanentlyDenied,
  });

  bool get canJoinQueue => locationGranted && notificationGranted;
}

class QueuePermissionGate {
  final ApiClient _api;

  QueuePermissionGate({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<QueuePermissionStatus> check() async {
    final locationPermission = await Geolocator.checkPermission();

    final locationGranted =
        locationPermission == LocationPermission.always ||
        locationPermission == LocationPermission.whileInUse;

    final locationPermanentlyDenied =
        locationPermission == LocationPermission.deniedForever;

    final notificationSettings = await FirebaseMessaging.instance
        .getNotificationSettings();

    final notificationGranted =
        notificationSettings.authorizationStatus ==
            AuthorizationStatus.authorized ||
        notificationSettings.authorizationStatus ==
            AuthorizationStatus.provisional;

    if (notificationGranted) {
      await NotificationService.instance.requestAndRegisterToken();
    }

    final notificationPermanentlyDenied =
        notificationSettings.authorizationStatus == AuthorizationStatus.denied;

    return QueuePermissionStatus(
      locationGranted: locationGranted,
      locationPermanentlyDenied: locationPermanentlyDenied,
      notificationGranted: notificationGranted,
      notificationPermanentlyDenied: notificationPermanentlyDenied,
    );
  }

  Future<QueuePermissionStatus> requestMissingPermissions() async {
    var locationPermission = await Geolocator.checkPermission();

    if (locationPermission == LocationPermission.denied) {
      locationPermission = await Geolocator.requestPermission();
    }

    final locationGranted =
        locationPermission == LocationPermission.always ||
        locationPermission == LocationPermission.whileInUse;

    final locationPermanentlyDenied =
        locationPermission == LocationPermission.deniedForever;

    final notificationSettings = await FirebaseMessaging.instance
        .requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

    final notificationGranted =
        notificationSettings.authorizationStatus ==
            AuthorizationStatus.authorized ||
        notificationSettings.authorizationStatus ==
            AuthorizationStatus.provisional;

    if (notificationGranted) {
      await NotificationService.instance.requestAndRegisterToken();
    }

    final notificationPermanentlyDenied =
        notificationSettings.authorizationStatus == AuthorizationStatus.denied;

    if (notificationGranted) {
      await _registerPushToken();
    }

    return QueuePermissionStatus(
      locationGranted: locationGranted,
      locationPermanentlyDenied: locationPermanentlyDenied,
      notificationGranted: notificationGranted,
      notificationPermanentlyDenied: notificationPermanentlyDenied,
    );
  }

  Future<void> _registerPushToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    await _api.post(
      '/api/mobile/push-token/',
      body: {
        'token': token,
        'platform': Platform.isAndroid ? 'android' : 'ios',
      },
    );
  }
}
