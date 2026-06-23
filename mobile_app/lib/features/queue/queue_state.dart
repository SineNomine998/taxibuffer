import 'package:flutter/foundation.dart';

/// Tracks whether the current user is actively in a queue.
/// Injected at the app root so any screen can read or mutate it.
class QueueState extends ChangeNotifier {
  String? _activeEntryUuid;

  String? get activeEntryUuid => _activeEntryUuid;
  bool get isInQueue => _activeEntryUuid != null;

  void setActiveEntry(String uuid) {
    if (_activeEntryUuid == uuid) return;
    _activeEntryUuid = uuid;
    notifyListeners();
  }

  void clear() {
    if (_activeEntryUuid == null) return;
    _activeEntryUuid = null;
    notifyListeners();
  }
}
