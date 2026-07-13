import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../location/services/location_service.dart';
import 'queue_location_tracker.dart';
import 'queue_state.dart';

Future<void> syncQueueTracking(BuildContext context) async {
  final state = await LocationService().fetchQueuesState();

  if (!context.mounted) return;

  final queueState = context.read<QueueState>();
  final tracker = context.read<QueueLocationTracker>();

  if (state.hasActiveQueue) {
    queueState.setActiveEntry(state.activeEntryUuid!);

    if (state.activelyWaiting) {
      tracker.start(state.activeEntryUuid!);
    } else {
      tracker.stop();
    }
  } else {
    queueState.clearActiveEntry();
    tracker.stop();
  }
}
