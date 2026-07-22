import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:mobile_app/core/config/api_client.dart';

import 'services/queue_service.dart';

class QueueLocationTracker extends ChangeNotifier {
  final QueueService _queueService;

  QueueLocationTracker({QueueService? queueService})
    : _queueService = queueService ?? QueueService();

  String? _entryUuid;

  bool _isRunning = false;
  bool _isReporting = false;
  bool _configured = false;
  bool _expiredReportTriggered = false;

  Timer? _countdownTimer;

  int? _graceRemainingSeconds;
  String? _warningMessage;

  bool _outsideWarningActive = false;
  int _outsideWarningEventId = 0;

  bool _dequeued = false;
  String? _dequeueMessage;
  int _dequeueEventId = 0;

  bool get isRunning => _isRunning;

  int? get graceRemainingSeconds => _graceRemainingSeconds;
  String? get warningMessage => _warningMessage;
  bool get hasWarning => _graceRemainingSeconds != null;

  bool get outsideWarningActive => _outsideWarningActive;
  int get outsideWarningEventId => _outsideWarningEventId;

  bool get dequeued => _dequeued;
  String? get dequeueMessage => _dequeueMessage;
  int get dequeueEventId => _dequeueEventId;

  Future<void> start(String entryUuid) async {
    if (_isRunning && _entryUuid == entryUuid) return;

    await stop();

    _entryUuid = entryUuid;
    _isRunning = true;
    _isReporting = false;
    _dequeued = false;
    _dequeueMessage = null;
    _expiredReportTriggered = false;

    notifyListeners();

    await _configureIfNeeded();

    try {
      await bg.BackgroundGeolocation.start();
    } catch (_) {
      await _reportLocationUnavailable();
      return;
    }

    await _reportCurrentPositionOnce();
  }

  Future<void> stop() async {
    _countdownTimer?.cancel();
    _countdownTimer = null;

    _entryUuid = null;
    _isRunning = false;
    _isReporting = false;
    _graceRemainingSeconds = null;
    _warningMessage = null;
    _outsideWarningActive = false;
    _dequeued = false;
    _dequeueMessage = null;
    _expiredReportTriggered = false;

    try {
      await bg.BackgroundGeolocation.stop();
    } catch (_) {}

    notifyListeners();
  }

  Future<void> _configureIfNeeded() async {
    if (_configured) return;

    bg.BackgroundGeolocation.onLocation(
      (bg.Location location) {
        debugPrint('DEBUG: BG location event received');
        unawaited(_handleNativeLocation(location));
      },
      (bg.LocationError error) {
        debugPrint('DEBUG: BG location error: ${error.code} ${error.message}');
        unawaited(_reportLocationUnavailable());
      },
    );

    bg.BackgroundGeolocation.onProviderChange((bg.ProviderChangeEvent event) {
      debugPrint('DEBUG: BG provider changed enabled=${event.enabled}');

      if (!event.enabled) {
        unawaited(_reportLocationUnavailable());
      }
    });

    bg.BackgroundGeolocation.onHeartbeat((bg.HeartbeatEvent event) {
      debugPrint('DEBUG: BG heartbeat event received');
      unawaited(_reportCurrentPositionOnce());
    });

    await bg.BackgroundGeolocation.ready(
      bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,

        // Test/strict mode: tries to update about every 30 seconds.
        locationUpdateInterval: 30000,
        fastestLocationUpdateInterval: 15000,
        distanceFilter: 0,

        heartbeatInterval: 30,

        foregroundService: true,
        stopOnTerminate: false,
        startOnBoot: false,
        enableHeadless: false,

        pausesLocationUpdatesAutomatically: false,
        disableStopDetection: true,

        notification: bg.Notification(
          title: 'TaxiBuffer actief',
          text: 'Uw wachtrijlocatie wordt gecontroleerd.',
          channelName: 'TaxiBuffer locatiecontrole',
          smallIcon: 'drawable/ic_notification',
        ),

        debug: false,
        logLevel: bg.Config.LOG_LEVEL_OFF,
      ),
    );

    _configured = true;
  }

  Future<void> reportNow() async {
    if (!_isRunning || _entryUuid == null) return;

    await _reportCurrentPositionOnce();
  }

  Future<void> _reportCurrentPositionOnce() async {
    if (!_isRunning || _entryUuid == null) return;

    try {
      final location = await bg.BackgroundGeolocation.getCurrentPosition(
        samples: 1,
        persist: false,
        timeout: 30,
      );

      await _handleNativeLocation(location);
    } catch (_) {
      try {
        final location = await bg.BackgroundGeolocation.getCurrentPosition(
          samples: 1,
          persist: false,
          timeout: 15,
        );

        await _handleNativeLocation(location);
      } catch (_) {
        await _reportLocationUnavailable();
      }
    }
  }

  Future<void> _handleNativeLocation(bg.Location location) async {
    if (!_isRunning || _entryUuid == null || _isReporting) return;

    _isReporting = true;

    try {
      final result = await _queueService.reportQueueLocation(
        entryUuid: _entryUuid!,
        lat: location.coords.latitude,
        lng: location.coords.longitude,
      );

      _handleResult(result);
    } on ApiAuthException catch (e) {
      debugPrint('Queue location auth failed: $e');
      await stop();
    } catch (error, stackTrace) {
      debugPrint('Queue location report failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isReporting = false;
    }
  }

  Future<void> _reportLocationUnavailable() async {
    if (!_isRunning || _entryUuid == null || _isReporting) return;

    _isReporting = true;

    try {
      final result = await _queueService.reportQueueLocationUnavailable(
        entryUuid: _entryUuid!,
      );

      _handleResult(result);
    } on ApiAuthException catch (e) {
      debugPrint('Queue location unavailable auth failed: $e');
      await stop();
    } catch (error, stackTrace) {
      debugPrint('Queue location report failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isReporting = false;
    }
  }

  void _handleResult(Map<String, dynamic> result) {
    debugPrint('Queue location result: $result');
    final action = result['action']?.toString();

    if (action == 'inside_buffer') {
      _clearWarning();
      notifyListeners();
      return;
    }

    if (action == 'outside_warning' ||
        action == 'outside_grace' ||
        action == 'location_unavailable_warning' ||
        action == 'location_unavailable_grace') {
      final seconds =
          (result['remaining_seconds'] as num?)?.toInt() ??
          (result['grace_seconds'] as num?)?.toInt() ??
          240;

      _warningMessage =
          result['message']?.toString() ??
          'Keer terug naar de bufferzone om in de wachtrij te blijven.';

      final wasAlreadyWarning = _outsideWarningActive;
      _outsideWarningActive = true;

      if (!wasAlreadyWarning) {
        _outsideWarningEventId++;
      }

      _startCountdown(seconds);
      notifyListeners();
      return;
    }

    if (result['dequeued'] == true) {
      _dequeued = true;
      _dequeueMessage =
          result['message']?.toString() ??
          'U bent uit de wachtrij verwijderd omdat u buiten de bufferzone bent gebleven.';
      _dequeueEventId++;

      _clearWarning();

      _isRunning = false;
      _isReporting = false;

      try {
        bg.BackgroundGeolocation.stop();
      } catch (_) {}

      notifyListeners();
    }
  }

  void _startCountdown(int seconds) {
    _graceRemainingSeconds = seconds;
    _expiredReportTriggered = false;

    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final current = _graceRemainingSeconds;

      if (current == null) {
        timer.cancel();
        return;
      }

      if (current <= 1) {
        _graceRemainingSeconds = 0;
        timer.cancel();
        notifyListeners();

        unawaited(_forceExpireNow());
        return;
      }

      _graceRemainingSeconds = current - 1;
      notifyListeners();
    });
  }

  Future<void> _forceExpireNow() async {
    if (_expiredReportTriggered) return;

    _expiredReportTriggered = true;

    await _reportCurrentPositionOnce();
  }

  void _clearWarning() {
    _countdownTimer?.cancel();
    _countdownTimer = null;

    _graceRemainingSeconds = null;
    _warningMessage = null;
    _outsideWarningActive = false;
    _expiredReportTriggered = false;
  }

  void acknowledgeOutsideWarning() {
    notifyListeners();
  }

  void acknowledgeDequeued() {
    _dequeued = false;
    _dequeueMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();

    try {
      bg.BackgroundGeolocation.stop();
      bg.BackgroundGeolocation.removeListeners();
    } catch (_) {}

    _queueService.dispose();

    super.dispose();
  }
}
