import 'package:flutter/foundation.dart';

/// Tracks whether the current user is actively in a queue.
/// Injected at the app root so any screen can read or mutate it.
class QueueState extends ChangeNotifier {
  String? _activeEntryUuid;

  String? get activeEntryUuid => _activeEntryUuid;

  bool get isInQueue =>
      _activeEntryUuid != null && _activeEntryUuid!.isNotEmpty;

  void setActiveEntry(String entryUuid) {
    _activeEntryUuid = entryUuid;
    notifyListeners();
  }

  void clearActiveEntry() {
    _activeEntryUuid = null;
    notifyListeners();
  }
}
