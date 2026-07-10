import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/api_client.dart';
import '../router.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();

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

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(android: androidInit);

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;

        final data = jsonDecode(payload) as Map<String, dynamic>;
        _handleNotificationData(data);
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_queueChannel);

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationData(message.data);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationData(initialMessage.data);
    }

    _messaging.onTokenRefresh.listen((newToken) {
      _registerToken(newToken);
    });
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

    await _localNotifications.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _queueChannel.id,
          _queueChannel.name,
          channelDescription: _queueChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleNotificationData(Map<String, dynamic> data) {
    final type = data['type'];
    final entryUuid = data['entry_uuid'];

    if (type == 'queue_called' && entryUuid != null) {
      router.go('/numbers');
    }
  }
}
