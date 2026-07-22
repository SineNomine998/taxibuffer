import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_client.dart';
import '../router.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  static const _handledNotificationKey = 'handled_notification_ids';
  bool _initialized = false;

  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final ApiClient _api = ApiClient();

  static const AndroidNotificationChannel _queueChannel =
      AndroidNotificationChannel(
        'queue_calls',
        'Wachtrij oproepen',
        description: 'Meldingen wanneer een chauffeur mag doorrijden.',
        importance: Importance.high,
      );

  static const AndroidNotificationChannel _generalChannel =
      AndroidNotificationChannel(
        'taxibuffer_general',
        'TaxiBuffer meldingen',
        description: 'Algemene TaxiBuffer meldingen',
        importance: Importance.max,
      );

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    const androidInit = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );

    const initSettings = InitializationSettings(android: androidInit);

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) async {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;

        Map<String, dynamic> data;

        try {
          data = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          return;
        }

        final notificationId = data['notification_id']?.toString();

        if (notificationId != null && notificationId.isNotEmpty) {
          final id = int.tryParse(notificationId);
          if (id != null) {
            await _localNotifications.cancel(id: id);
          }

          final shouldHandle = await _markNotificationHandled(notificationId);
          if (!shouldHandle) return;
        }

        await _handleNotificationData(data);
      },
    );

    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await android?.createNotificationChannel(_queueChannel);
    await android?.createNotificationChannel(_generalChannel);

    FirebaseMessaging.onMessage.listen((message) async {
      final type = message.data['type']?.toString();

      if (type == 'test_push') {
        await _showLocalNotification(
          title: message.notification?.title ?? 'Pushmeldingen werken goed',
          body:
              message.notification?.body ??
              'U ontvangt meldingen van TaxiBuffer correct.',
          payload: jsonEncode({'type': 'test_push'}),
        );
        return;
      }

      final notificationId =
          message.data['notification_id']?.toString() ??
          '${message.data['type']}_${message.data['entry_uuid']}';

      final shouldShow = await _markNotificationSeen(notificationId);
      if (!shouldShow) return;

      await _handleForegroundMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      final notificationId = message.data['notification_id']?.toString();

      if (notificationId != null && notificationId.isNotEmpty) {
        final shouldHandle = await _markNotificationSeen(notificationId);
        if (!shouldHandle) return;
      }

      await _handleNotificationData(message.data);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      final notificationId = initialMessage.data['notification_id']?.toString();

      if (notificationId != null && notificationId.isNotEmpty) {
        final shouldHandle = await _markNotificationSeen(notificationId);
        if (!shouldHandle) return;
      }

      await _handleNotificationData(initialMessage.data);
    }

    _messaging.onTokenRefresh.listen((newToken) {
      _registerToken(newToken);
    });
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _generalChannel.id,
      _generalChannel.name,
      channelDescription: _generalChannel.description,
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );

    final details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  Future<bool> requestAndRegisterToken() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final allowed =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!allowed) return false;

    final token = await _messaging.getToken();

    if (token == null || token.isEmpty) return false;

    await _registerToken(token);

    return true;
  }

  Future<void> _registerToken(String token) async {
    await _api.post(
      '/api/mobile/push-token/',
      body: {
        'token': token,
        'platform': Platform.isAndroid ? 'android' : 'ios',
      },
    );
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ?? 'U mag doorrijden';
    final body =
        message.notification?.body ??
        'U bent aan de beurt. Rij naar de ophaallocatie.';
    final notificationId = int.tryParse(
      message.data['notification_id']?.toString() ?? '',
    );

    if (notificationId == null) return;

    await _localNotifications.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _queueChannel.id,
          _queueChannel.name,
          channelDescription: _queueChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _handleNotificationData(Map<String, dynamic> data) async {
    final type = data['type'];

    if (type == 'test_push') return;

    if (type == 'location_lost') {
      final entryUuid = data['entry_uuid']?.toString();

      if (entryUuid == null || entryUuid.isEmpty) return;

      try {
        await _api.refreshAndGetAccessToken();
      } catch (_) {
        router.go('/login?next=${Uri.encodeComponent('/queue/$entryUuid')}');
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        router.go('/queue/$entryUuid');
      });

      return;
    }

    if (type != 'queue_called') return;

    final notificationId = data['notification_id']?.toString();

    if (notificationId != null && notificationId.isNotEmpty) {
      final shouldHandle = await _markNotificationHandled(notificationId);
      if (!shouldHandle) return;
    }

    try {
      await _api.refreshAndGetAccessToken();
    } catch (_) {
      router.go('/login?next=${Uri.encodeComponent('/numbers')}');
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.go('/numbers');
    });
  }

  Future<bool> _markNotificationHandled(String notificationId) async {
    final prefs = await SharedPreferences.getInstance();

    final handled = prefs.getStringList(_handledNotificationKey) ?? [];

    if (handled.contains(notificationId)) {
      return false;
    }

    handled.add(notificationId);

    // Keep list small.
    final trimmed = handled.length > 50
        ? handled.sublist(handled.length - 50)
        : handled;

    await prefs.setStringList(_handledNotificationKey, trimmed);

    return true;
  }

  Future<bool> _markNotificationSeen(String notificationId) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList('seen_notification_ids') ?? [];

    if (seen.contains(notificationId)) return false;

    seen.add(notificationId);

    final trimmed = seen.length > 50 ? seen.sublist(seen.length - 50) : seen;

    await prefs.setStringList('seen_notification_ids', trimmed);
    return true;
  }
}
