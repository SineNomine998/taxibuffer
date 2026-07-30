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
  int _reportRequestId = 0;
  int _acknowledgedOutsideWarningEventId = 0;
  DateTime? _lastSuccessfulLocationReportAt;
  int _consecutiveUnavailableReports = 0;
  static const Duration _unavailableDebounceWindow = Duration(seconds: 7);

  bool get isRunning => _isRunning;
  int? get graceRemainingSeconds => _graceRemainingSeconds;
  String? get warningMessage => _warningMessage;
  bool get hasWarning => _graceRemainingSeconds != null;
  bool get outsideWarningActive => _outsideWarningActive;
  int get outsideWarningEventId => _outsideWarningEventId;
  bool get dequeued => _dequeued;
  String? get dequeueMessage => _dequeueMessage;
  int get dequeueEventId => _dequeueEventId;
  bool get shouldShowOutsideWarningPopup =>
      _outsideWarningActive &&
      _outsideWarningEventId != _acknowledgedOutsideWarningEventId;

  Future<void> start(String entryUuid) async {
    if (_isRunning && _entryUuid == entryUuid) return;

    await stop();

    _entryUuid = entryUuid;
    _isRunning = true;
    _isReporting = false;
    _dequeued = false;
    _dequeueMessage = null;
    _expiredReportTriggered = false;
    _reportRequestId = 0;

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
    _reportRequestId++;
    _lastSuccessfulLocationReportAt = null;
    _consecutiveUnavailableReports = 0;

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
        unawaited(_reportLocationUnavailable(force: true));
        return;
      }

      _consecutiveUnavailableReports = 0;
      unawaited(_reportCurrentPositionOnce());
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
    if (!_isRunning || _entryUuid == null || _isReporting) return;

    final requestId = ++_reportRequestId;
    _isReporting = true;

    try {
      final location = await bg.BackgroundGeolocation.getCurrentPosition(
        samples: 1,
        persist: false,
        timeout: 30,
      );

      if (requestId != _reportRequestId) return;

      final data = await _queueService.reportQueueLocation(
        entryUuid: _entryUuid!,
        lat: location.coords.latitude,
        lng: location.coords.longitude,
      );

      if (requestId != _reportRequestId) return;

      _handleLocationReportResponse(data);
    } catch (_) {
      if (requestId != _reportRequestId) return;

      final data = await _queueService.reportQueueLocationUnavailable(
        entryUuid: _entryUuid!,
      );

      if (requestId != _reportRequestId) return;

      _handleLocationReportResponse(data);
    } finally {
      if (requestId == _reportRequestId) {
        _isReporting = false;
      }
    }
  }

  Future<void> _handleNativeLocation(bg.Location location) async {
    if (!_isRunning || _entryUuid == null || _isReporting) return;

    final requestId = ++_reportRequestId;
    final entryUuid = _entryUuid!;
    _isReporting = true;

    try {
      final result = await _queueService.reportQueueLocation(
        entryUuid: entryUuid,
        lat: location.coords.latitude,
        lng: location.coords.longitude,
      );

      if (requestId != _reportRequestId) return;

      _handleLocationReportResponse(result);
    } on ApiAuthException catch (e) {
      debugPrint('Queue location auth failed: $e');
      await stop();
    } catch (error, stackTrace) {
      debugPrint('Queue location report failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (requestId == _reportRequestId) {
        _isReporting = false;
      }
    }
  }

  Future<void> _reportLocationUnavailable({bool force = false}) async {
    if (!_isRunning || _entryUuid == null || _isReporting) return;

    final now = DateTime.now();

    final recentlyHadGoodLocation =
        _lastSuccessfulLocationReportAt != null &&
        now.difference(_lastSuccessfulLocationReportAt!) <
            _unavailableDebounceWindow;

    if (!force && recentlyHadGoodLocation) {
      debugPrint(
        'Skipping unavailable report: recent successful location report.',
      );
      return;
    }

    _consecutiveUnavailableReports++;

    if (!force && _consecutiveUnavailableReports < 2) {
      debugPrint('Skipping unavailable report: waiting for repeated failure.');
      return;
    }

    final requestId = ++_reportRequestId;
    final entryUuid = _entryUuid!;
    _isReporting = true;

    try {
      final result = await _queueService.reportQueueLocationUnavailable(
        entryUuid: entryUuid,
      );

      if (requestId != _reportRequestId) return;

      _handleLocationReportResponse(result);
    } on ApiAuthException catch (e) {
      debugPrint('Queue location unavailable auth failed: $e');
      await stop();
    } catch (error, stackTrace) {
      debugPrint('Queue location report failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (requestId == _reportRequestId) {
        _isReporting = false;
      }
    }
  }

  void _handleLocationReportResponse(Map<String, dynamic> data) {
    debugPrint('Queue location result: $data');

    final action = data['action']?.toString();

    if (action == 'inside_buffer' || action == 'no_buffer') {
      _lastSuccessfulLocationReportAt = DateTime.now();
      _consecutiveUnavailableReports = 0;
      _clearLocationWarning();
      return;
    }

    if (data['dequeued'] == true) {
      _clearLocationWarning();

      _dequeued = true;
      _dequeueMessage =
          data['message']?.toString() ?? 'U bent uit de wachtrij verwijderd.';
      _dequeueEventId++;

      _isRunning = false;
      _isReporting = false;

      try {
        bg.BackgroundGeolocation.stop();
      } catch (_) {}

      notifyListeners();
      return;
    }

    if (action == 'outside_warning' ||
        action == 'outside_grace' ||
        action == 'location_unavailable_warning' ||
        action == 'location_unavailable_grace') {
      if (action == 'location_unavailable_warning' ||
          action == 'location_unavailable_grace') {
        final recentlyHadGoodLocation =
            _lastSuccessfulLocationReportAt != null &&
            DateTime.now().difference(_lastSuccessfulLocationReportAt!) <
                _unavailableDebounceWindow;

        if (recentlyHadGoodLocation) {
          debugPrint('Ignoring unavailable warning: recent good location.');
          return;
        }
      }
      final seconds =
          (data['remaining_seconds'] as num?)?.toInt() ??
          (data['grace_seconds'] as num?)?.toInt() ??
          240;

      _warningMessage =
          data['message']?.toString() ??
          'Keer terug naar de bufferzone om in de wachtrij te blijven.';

      final wasAlreadyWarning = _outsideWarningActive;
      _outsideWarningActive = true;

      if (!wasAlreadyWarning) {
        _outsideWarningEventId++;
      }

      _startCountdown(seconds);
      notifyListeners();
    }
  }

  void _clearLocationWarning() {
    _countdownTimer?.cancel();
    _countdownTimer = null;

    _graceRemainingSeconds = null;
    _warningMessage = null;
    _outsideWarningActive = false;
    _expiredReportTriggered = false;
    _acknowledgedOutsideWarningEventId = 0;

    notifyListeners();
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

  void acknowledgeOutsideWarning() {
    _acknowledgedOutsideWarningEventId = _outsideWarningEventId;
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
