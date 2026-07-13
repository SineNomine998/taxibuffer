import 'dart:async';

import 'package:flutter/foundation.dart';

import '../location/services/location_service.dart';
import 'services/queue_service.dart';

class QueueLocationTracker extends ChangeNotifier {
  final QueueService _queueService;
  final LocationService _locationService;

  QueueLocationTracker({
    QueueService? queueService,
    LocationService? locationService,
  }) : _queueService = queueService ?? QueueService(),
       _locationService = locationService ?? LocationService();

  Timer? _pingTimer;
  Timer? _countdownTimer;
  String? _entryUuid;
  bool _isRunning = false;
  bool _isReporting = false;
  int? _graceRemainingSeconds;
  String? _warningMessage;
  bool _dequeued = false;
  String? _dequeueMessage;
  bool _expiredReportTriggered = false;
  int _dequeueEventId = 0;
  bool _outsideWarningActive = false;
  int _outsideWarningEventId = 0;

  bool get outsideWarningActive => _outsideWarningActive;
  int get outsideWarningEventId => _outsideWarningEventId;
  bool get dequeued => _dequeued;
  String? get dequeueMessage => _dequeueMessage;
  int get dequeueEventId => _dequeueEventId;
  bool get isRunning => _isRunning;
  int? get graceRemainingSeconds => _graceRemainingSeconds;
  String? get warningMessage => _warningMessage;
  bool get hasWarning => _graceRemainingSeconds != null;

  void start(String entryUuid) {
    if (_isRunning && _entryUuid == entryUuid) return;

    stop();

    _entryUuid = entryUuid;
    _isRunning = true;
    _dequeued = false;
    _dequeueMessage = null;
    _expiredReportTriggered = false;

    _reportNow();

    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _reportNow();
    });

    notifyListeners();
  }

  void stop() {
    _pingTimer?.cancel();
    _pingTimer = null;

    _countdownTimer?.cancel();
    _countdownTimer = null;

    _entryUuid = null;
    _isRunning = false;
    _isReporting = false;
    _graceRemainingSeconds = null;
    _warningMessage = null;
    _dequeued = false;
    _dequeueMessage = null;

    notifyListeners();
  }

  Future<void> _reportNow({bool force = false}) async {
    if (!_isRunning || _entryUuid == null) return;
    if (_isReporting && !force) return;

    _isReporting = true;

    try {
      final position = await _locationService.getCurrentPosition();

      final result = await _queueService.reportQueueLocation(
        entryUuid: _entryUuid!,
        lat: position.latitude,
        lng: position.longitude,
      );

      _handleResult(result);
    } catch (_) {
      // Do not dequeue on GPS/API failure.
    } finally {
      _isReporting = false;
    }
  }

  void _handleResult(Map<String, dynamic> result) {
    final action = result['action'];

    if (action == 'inside_buffer') {
      _clearWarning();
      notifyListeners();
      return;
    }

    if (action == 'outside_warning' || action == 'outside_grace') {
      final seconds =
          result['remaining_seconds'] as int? ??
          result['grace_seconds'] as int? ??
          240;

      _warningMessage =
          result['message']?.toString() ??
          'U bent buiten de bufferzone. Keer terug om in de wachtrij te blijven.';

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
      _pingTimer?.cancel();
      _pingTimer = null;
      _isRunning = false;

      notifyListeners();
      return;
    }
  }

  void acknowledgeDequeued() {
    _dequeued = false;
    _dequeueMessage = null;
    notifyListeners();
  }

  void acknowledgeOutsideWarning() {
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

        _forceExpireNow();
        return;
      }

      _graceRemainingSeconds = current - 1;
      notifyListeners();
    });
  }

  Future<void> _forceExpireNow() async {
    if (_expiredReportTriggered) return;
    _expiredReportTriggered = true;

    await _reportNow(force: true);
  }

  void _clearWarning() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _graceRemainingSeconds = null;
    _warningMessage = null;
    _expiredReportTriggered = false;
    _outsideWarningActive = false;
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _countdownTimer?.cancel();
    _queueService.dispose();
    super.dispose();
  }
}
