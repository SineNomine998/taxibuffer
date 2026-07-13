import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_app/core/dialogs.dart';
import 'package:mobile_app/core/router.dart';
import 'package:mobile_app/features/queue/queue_location_tracker.dart';
import 'package:mobile_app/features/queue/queue_state.dart';
import 'package:mobile_app/features/queue/queue_tracking_sync.dart';
import 'package:provider/provider.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  bool _syncingQueueTracking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncQueueTracking();
    });
  }

  Future<void> _syncQueueTracking() async {
    if (_syncingQueueTracking || !mounted) return;

    _syncingQueueTracking = true;

    try {
      await syncQueueTracking(context);
    } catch (_) {
      // Ignore here. ApiClient/session handling can deal with auth issues.
    } finally {
      _syncingQueueTracking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncQueueTracking();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TaxiBuffer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: GoogleFonts.dmSansTextTheme(),
        fontFamily: GoogleFonts.dmSans().fontFamily,
      ),
      routerConfig: router,
      builder: (materialContext, child) {
        return _GlobalQueueListener(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

class _GlobalQueueListener extends StatefulWidget {
  final Widget child;

  const _GlobalQueueListener({required this.child});

  @override
  State<_GlobalQueueListener> createState() => _GlobalQueueListenerState();
}

class _GlobalQueueListenerState extends State<_GlobalQueueListener> {
  int _lastHandledOutsideWarningEventId = 0;
  int _lastHandledDequeueEventId = 0;

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<QueueLocationTracker>();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (tracker.outsideWarningActive &&
          tracker.outsideWarningEventId != _lastHandledOutsideWarningEventId) {
        _lastHandledOutsideWarningEventId = tracker.outsideWarningEventId;

        final dialogContext = rootNavigatorKey.currentContext;
        if (dialogContext == null) return;

        await showDialog(
          context: dialogContext,
          barrierDismissible: true,
          builder: (_) => _OutsideBufferWarningDialog(tracker: tracker),
        );

        tracker.acknowledgeOutsideWarning();
      }

      if (tracker.dequeued &&
          tracker.dequeueEventId != _lastHandledDequeueEventId) {
        _lastHandledDequeueEventId = tracker.dequeueEventId;

        if (!context.mounted) return;

        context.read<QueueState>().clearActiveEntry();

        final dialogContext = rootNavigatorKey.currentContext;
        if (dialogContext == null) return;

        await showAppAlert(
          context: dialogContext,
          title: 'Uit wachtrij verwijderd',
          message:
              tracker.dequeueMessage ??
              'U bent uit de wachtrij verwijderd omdat u buiten de bufferzone bent gebleven.',
          svgAsset: 'assets/pop-up-denied.svg',
        );

        if (!mounted) return;

        tracker.acknowledgeDequeued();
        router.go('/locations');
      }
    });

    return widget.child;
  }
}

class _OutsideBufferWarningDialog extends StatelessWidget {
  final QueueLocationTracker tracker;

  const _OutsideBufferWarningDialog({required this.tracker});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tracker,
      builder: (context, _) {
        final remaining = tracker.graceRemainingSeconds ?? 0;
        final minutes = remaining ~/ 60;
        final seconds = remaining % 60;
        final timeText = '$minutes:${seconds.toString().padLeft(2, '0')}';

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/warning-badge.svg',
                  height: 76,
                  errorBuilder: (_, _, _) {
                    return const Icon(
                      Icons.warning_rounded,
                      size: 72,
                      color: Color(0xFFE0BD22),
                    );
                  },
                ),
                const SizedBox(height: 18),

                const Text(
                  'Buiten bufferzone',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 10),

                Text(
                  tracker.warningMessage ??
                      'Keer terug naar de bufferzone om in de wachtrij te blijven.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 15,
                    height: 1.35,
                    color: Color(0xFF4B5563),
                  ),
                ),
                const SizedBox(height: 18),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7D6),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE0BD22)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Resterende tijd',
                        style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B5A00),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeText,
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF2F2F2F),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE0BD22),
                      foregroundColor: const Color(0xFF222222),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      'Begrepen',
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
