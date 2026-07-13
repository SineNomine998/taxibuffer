import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mobile_app/core/config/api_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/config/api_config.dart';
import '../models/queue_status.dart';

class QueueService {
  WebSocketChannel? _channel;
  final _controller = StreamController<QueueStatus>.broadcast();

  final ApiClient _apiClient;

  // Resolved when the server replies to a leave action.
  Completer<bool>? _leaveCompleter;

  QueueService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Stream<QueueStatus> get statusStream => _controller.stream;

  Future<void> connect(
    String entryUuid, {
    bool forceRefreshToken = false,
  }) async {
    final token = forceRefreshToken
        ? await _apiClient.refreshAndGetAccessToken()
        : await _apiClient.getAccessTokenOrRefresh();

    final wsBase = ApiConfig.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    final uri = Uri.parse(
      '$wsBase/ws/queue/$entryUuid/',
    ).replace(queryParameters: {'token': token});

    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      _onRawMessage,
      onError: (e) {
        if (!_controller.isClosed) {
          _controller.addError(e);
        }
      },
      onDone: () {
        if (!_controller.isClosed) {
          _controller.addError(Exception('Verbinding verbroken.'));
        }

        if (_leaveCompleter != null && !_leaveCompleter!.isCompleted) {
          _leaveCompleter!.complete(false);
        }

        _leaveCompleter = null;
      },
    );
  }

  void _onRawMessage(dynamic raw) {
    debugPrint('WS RAW: $raw');
    final data = jsonDecode(raw as String) as Map<String, dynamic>;

    switch (data['type']) {
      case 'status':
        _controller.add(QueueStatus.fromJson(data));
        break;
      case 'leave_result':
        final success = data['success'] as bool? ?? false;
        _leaveCompleter?.complete(success);
        _leaveCompleter = null;
        break;
      case 'error':
        _controller.addError(
          Exception(data['detail']?.toString() ?? 'WebSocket error'),
        );
        break;
    }
  }

  Future<bool> leaveQueue() async {
    if (_channel == null) return false;

    _leaveCompleter = Completer<bool>();
    _channel!.sink.add(jsonEncode({'action': 'leave'}));

    return _leaveCompleter!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _leaveCompleter = null;
        return false;
      },
    );
  }

  Future<void> respondToNotification(
    int notificationId,
    String response,
  ) async {
    final result = await _apiClient.post(
      '/api/mobile/notifications/respond/',
      body: {'notification_id': notificationId, 'response': response},
    );

    if (result.statusCode != 200) {
      String message = 'Kon oproep niet bevestigen.';

      try {
        final data = jsonDecode(result.body);
        if (data is Map<String, dynamic> && data['detail'] != null) {
          message = data['detail'].toString();
        }
      } catch (_) {}

      throw Exception(message);
    }
  }

  void dispose() {
    if (_leaveCompleter != null && !_leaveCompleter!.isCompleted) {
      _leaveCompleter!.complete(false);
    }

    _leaveCompleter = null;
    _channel?.sink.close();

    if (!_controller.isClosed) {
      _controller.close();
    }

    _apiClient.dispose();
  }

  Future<Map<String, dynamic>> reportQueueLocation({
    required String entryUuid,
    required double lat,
    required double lng,
  }) async {
    final response = await _apiClient.post(
      '/api/mobile/queue/$entryUuid/location-report/',
      body: {'lat': lat, 'lng': lng},
    );

    if (response.statusCode != 200) {
      throw Exception('Locatiecontrole mislukt.');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reportQueueLocationUnavailable({
    required String entryUuid,
  }) async {
    final response = await _apiClient.post(
      '/api/mobile/queue/$entryUuid/location-report/',
      body: {},
    );

    if (response.statusCode != 200) {
      throw Exception('Locatiecontrole mislukt.');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
