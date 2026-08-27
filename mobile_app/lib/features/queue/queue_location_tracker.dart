import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tracelet/tracelet.dart' as tl;
import 'package:geolocator/geolocator.dart';
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
  Timer? _providerWatchdogTimer;
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
  static const Duration _unavailableDebounceWindow = Duration(seconds: 20);

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
      await tl.Tracelet.start();
      _startProviderWatchdog();
    } catch (_) {
      await _reportLocationUnavailable(force: true);
      return;
    }

    await _reportCurrentPositionOnce();
  }

  Future<void> stop() async {
    _reportRequestId++;
    _lastSuccessfulLocationReportAt = null;
    _consecutiveUnavailableReports = 0;

    _providerWatchdogTimer?.cancel();
    _providerWatchdogTimer = null;

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
      await tl.Tracelet.stop();
    } catch (_) {}

    notifyListeners();
  }

  void _startProviderWatchdog() {
    _providerWatchdogTimer?.cancel();

    _providerWatchdogTimer = Timer.periodic(const Duration(seconds: 20), (
      _,
    ) async {
      if (!_isRunning || _entryUuid == null) return;

      try {
        final locationEnabled = await Geolocator.isLocationServiceEnabled();

        if (!locationEnabled) {
          await _reportLocationUnavailable(force: true);
          return;
        }

        await _reportCurrentPositionOnce();
      } catch (e) {
        debugPrint('Provider watchdog failed: $e');
        await _reportLocationUnavailable(force: true);
      }
    });
  }

  Future<void> _configureIfNeeded() async {
    if (_configured) return;

    tl.Tracelet.onLocation((tl.Location location) {
      debugPrint('DEBUG: Tracelet location event received');
      unawaited(_handleNativeLocation(location));
    });

    tl.Tracelet.onProviderChange((tl.ProviderChangeEvent event) {
      debugPrint('DEBUG: Tracelet provider changed enabled=${event.enabled}');

      if (!event.enabled) {
        unawaited(_reportLocationUnavailable(force: true));
        return;
      }

      _consecutiveUnavailableReports = 0;
      unawaited(_reportCurrentPositionOnce());
    });

    tl.Tracelet.onHeartbeat((tl.HeartbeatEvent event) {
      debugPrint('DEBUG: Tracelet heartbeat event received');
      unawaited(_reportCurrentPositionOnce());
    });

    await tl.Tracelet.ready(
      tl.Config(
        geo: tl.GeoConfig(
          desiredAccuracy: tl.DesiredAccuracy.high,
          distanceFilter: 0,
        ),
        app: tl.AppConfig(
          stopOnTerminate: false,
          startOnBoot: false,
          heartbeatInterval: 30,
        ),
        android: tl.AndroidConfig(
          foregroundService: tl.ForegroundServiceConfig(
            enabled: true,
            notificationTitle: 'TaxiBuffer actief',
            notificationText: 'Locatiecontrole actief voor uw wachtrij.',
            channelName: 'TaxiBuffer locatiecontrole',
            notificationSmallIcon: 'ic_notification',
            notificationOngoing: true,
            showNotificationOnPauseOnly: false,
            notificationPriority: tl.NotificationPriority.low,
          ),
          locationUpdateInterval: 30000,
          fastestLocationUpdateInterval: 15000,
        ),
        ios: tl.IosConfig(
          showsBackgroundLocationIndicator: true,
          pausesLocationUpdatesAutomatically: false,
        ),
        motion: tl.MotionConfig(disableMotionActivityUpdates: true),
        logger: tl.LoggerConfig(debug: false, logLevel: tl.LogLevel.off),
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
      final location = await tl.Tracelet.getCurrentPosition(
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
    } catch (error, stackTrace) {
      debugPrint('Queue current position failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (requestId != _reportRequestId) return;

      _isReporting = false;
      await _reportLocationUnavailable();
      return;
    } finally {
      if (requestId == _reportRequestId) {
        _isReporting = false;
      }
    }
  }

  Future<void> _handleNativeLocation(tl.Location location) async {
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
    if (!_isRunning || _entryUuid == null) return;

    if (_isReporting) {
      if (!force) return;

      _reportRequestId++;
      _isReporting = false;
    }

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

      _providerWatchdogTimer?.cancel();
      _providerWatchdogTimer = null;

      _dequeued = true;
      _dequeueMessage =
          data['message']?.toString() ?? 'U bent uit de wachtrij verwijderd.';
      _dequeueEventId++;

      _isRunning = false;
      _isReporting = false;

      unawaited(_stopTraceletQuietly());

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

  Future<void> _stopTraceletQuietly() async {
    try {
      await tl.Tracelet.stop();
    } catch (error, stackTrace) {
      debugPrint('Tracelet stop failed: $error');
      debugPrintStack(stackTrace: stackTrace);
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
    _providerWatchdogTimer?.cancel();

    try {
      tl.Tracelet.stop();
      tl.Tracelet.removeListeners();
    } catch (_) {}

    _queueService.dispose();

    super.dispose();
  }
}
