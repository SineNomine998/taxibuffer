import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/features/queue/queue_location_tracker.dart';
import 'package:mobile_app/features/queue/queue_state.dart';
import 'package:provider/provider.dart';
import '../../../core/dialogs.dart';
import '../../../core/theme.dart';
import '../../../widgets/app_shell_scaffold.dart';
import '../../../widgets/bottom_nav.dart';
import '../models/queue_status.dart';
import '../services/queue_service.dart';
import '../widgets/queue_overview_sheet.dart';

class QueueStatusScreen extends StatefulWidget {
  final String entryUuid;
  const QueueStatusScreen({required this.entryUuid, super.key});

  @override
  State<QueueStatusScreen> createState() => _QueueStatusScreenState();
}

class _QueueStatusScreenState extends State<QueueStatusScreen>
    with WidgetsBindingObserver {
  late QueueService _queueService;
  QueueStatus? _status;
  bool _isConnecting = true;
  bool _isLeaving = false;
  String? _connectionError;
  final Set<int> _seenNotificationIds = {};
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isDisposed = false;
  bool _isReconnecting = false;
  bool _hasExited = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _queueService = QueueService();
    // Mark this entry as active globally so BottomNav and other screens know.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<QueueState>().setActiveEntry(widget.entryUuid);
      }
    });
    _connect();
  }

  Future<void> _connect({
    bool showLoading = true,
    bool forceRefreshToken = false,
  }) async {
    if (_isDisposed || !mounted) return;

    if (showLoading) {
      setState(() {
        _isConnecting = true;
        _connectionError = null;
      });
    }

    try {
      await _subscription?.cancel();
      _subscription = null;

      await _queueService.connect(
        widget.entryUuid,
        forceRefreshToken: forceRefreshToken,
      );

      _subscription = _queueService.statusStream.listen(
        _onStatus,
        onError: (e) {
          if (_isDisposed || !mounted) return;

          setState(() {
            _connectionError = 'Verbinding verbroken. Opnieuw verbinden...';
          });

          _scheduleReconnect();
        },
        onDone: () {
          if (_isDisposed || !mounted) return;

          setState(() {
            _connectionError = 'Verbinding verbroken. Opnieuw verbinden...';
          });

          _scheduleReconnect();
        },
        cancelOnError: false,
      );

      if (!mounted) return;

      setState(() {
        _connectionError = null;
      });

      _reconnectAttempts = 0;
    } catch (e) {
      if (_isDisposed || !mounted) return;

      setState(() {
        _connectionError = e.toString();
      });

      _scheduleReconnect();
    } finally {
      if (mounted && showLoading) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _onStatus(QueueStatus status) async {
    if (_isDisposed || !mounted) return;

    setState(() {
      _status = status;
      _connectionError = null;
    });

    final tracker = context.read<QueueLocationTracker>();

    // Entry no longer active: officer/system marked chauffeur as handled/dequeued.
    if (!status.active) {
      await _exitQueue();
      return;
    }

    if (status.status == 'waiting') {
      if (!tracker.isRunning) {
        unawaited(tracker.start(widget.entryUuid));
      }
    } else {
      unawaited(tracker.stop());
    }

    if (!mounted) return;

    // If the chauffeur is called while this screen is open,
    // WebSocket shows the in-app popup immediately.
    if (status.hasNotification && status.notification != null) {
      final notification = status.notification!;
      final notifId = notification.id;

      if (!_seenNotificationIds.contains(notifId)) {
        _seenNotificationIds.add(notifId);
        _showTurnNotification(notification);
      }
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed || !mounted) return;
    if (_isReconnecting) return;

    _reconnectTimer?.cancel();

    _reconnectAttempts++;

    final delaySeconds = _reconnectAttempts <= 1
        ? 2
        : _reconnectAttempts <= 3
        ? 5
        : 10;

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_isDisposed || !mounted) return;

      _isReconnecting = true;

      try {
        await _reconnect(showLoading: false);
      } finally {
        _isReconnecting = false;
      }
    });
  }

  /// Clears global queue state and navigates away.
  /// Call this whenever the user is no longer in the queue,
  /// whether by leaving voluntarily or being dequeued externally.
  Future<void> _exitQueue() async {
    if (_hasExited) return;
    _hasExited = true;

    if (!mounted || _isDisposed) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _subscription?.cancel();
    _subscription = null;

    if (!mounted) return;

    await context.read<QueueLocationTracker>().stop();

    if (!mounted || _isDisposed) return;

    context.read<QueueState>().clearActiveEntry();
    context.go('/locations');
  }

  Future<void> _showTurnNotification(QueueNotification notification) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppColors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: kGradient,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '✓',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'U mag doorrijden\n#${notification.sequenceNumber ?? '--'}',
                style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: AppColors.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Rij door naar de ophaallocatie en laat uw nummer zien.',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 15,
                  height: 1.4,
                  color: Color(0xFF4B4B4B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: kGradient,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: TextButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();

                    try {
                      await _queueService.respondToNotification(
                        notification.id,
                        'accepted',
                      );
                    } catch (_) {
                      // Not critical. The chauffeur has already been notified.
                    }

                    if (!mounted) return;
                    context.go('/numbers');
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Bekijk oproepnummer',
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Color(0xFF222222),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onLeave() async {
    final confirmed = await showAppConfirm(
      context: context,
      title: 'Wachtrij verlaten',
      message: 'U staat op het punt de wachtrij te verlaten. Weet u het zeker?',
      confirmLabel: 'Verlaten',
      cancelLabel: 'Blijven',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isLeaving = true);
    try {
      final success = await _queueService.leaveQueue();
      if (!mounted) return;
      if (success) {
        await _exitQueue();
      } else {
        await showAppAlert(
          context: context,
          title: 'Fout',
          message: 'Kon niet verlaten. Probeer opnieuw.',
          svgAsset: 'assets/pop-up-denied.svg',
        );
      }
    } catch (e) {
      if (!mounted) return;

      await showAppAlert(
        context: context,
        title: 'Fout',
        message: e.toString().replaceFirst('Exception: ', ''),
        svgAsset: 'assets/pop-up-denied.svg',
      );
    } finally {
      if (mounted) setState(() => _isLeaving = false);
    }
  }

  void _showQueueOverview() {
    if (_status == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QueueOverviewSheet(status: _status!),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _queueService.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconnect(showLoading: false));

      final tracker = context.read<QueueLocationTracker>();
      unawaited(tracker.reportNow());
    }
  }

  Future<void> _reconnect({bool showLoading = true}) async {
    if (_isDisposed || !mounted) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _subscription?.cancel();
    _subscription = null;

    _queueService.dispose();

    if (_isDisposed || !mounted) return;

    _queueService = QueueService();

    await _connect(showLoading: showLoading, forceRefreshToken: true);

    if (!mounted || _isDisposed) return;

    await context.read<QueueLocationTracker>().reportNow();
  }

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      activeTab: NavTab.queue,
      child: _isConnecting
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gradientStart),
            )
          : _connectionError != null && _status == null
          ? _ErrorState(
              message: _connectionError!,
              onRetry: () {
                unawaited(_connect(forceRefreshToken: true));
              },
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final locationTracker = context.watch<QueueLocationTracker>();
    final status = _status;
    if (status == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gradientStart),
      );
    }

    final isNotified = status.isNotified;

    return RefreshIndicator(
      onRefresh: () async {
        await context.read<QueueLocationTracker>().reportNow();
        await _reconnect(showLoading: false);
      },
      color: AppColors.gradientStart,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isNotified ? 'U bent opgeroepen!' : 'Aangemeld!',
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isNotified
                  ? 'Rij door naar de ophaallocatie en laat uw nummer zien.'
                  : 'U krijgt een seintje als u door mag rijden.',
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 14),

            if (locationTracker.hasWarning)
              _LocationWarningBanner(
                remainingSeconds: locationTracker.graceRemainingSeconds!,
              ),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    height: 220,
                    child: _QueueImage(imageUrl: status.imageUrl),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  status.queueName,
                                  style: const TextStyle(
                                    fontFamily: 'DM Sans',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0B0B0B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF16A34A),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            status.queueAddress ??
                                'Wilhelminakade 699, 3072 AP, Rotterdam',
                            style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 13,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'U staat momenteel op plek:',
                            style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Center(
                            child: Text(
                              status.position != null
                                  ? '${status.position}'
                                  : '-',
                              style: const TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 44,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _isLeaving || isNotified
                                  ? null
                                  : _onLeave,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 18,
                                ),
                                side: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  width: 3,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: Text(
                                _isLeaving
                                    ? 'Bezig...'
                                    : isNotified
                                    ? 'Opgeroepen'
                                    : 'Verlaten',
                                style: const TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF4B4B4B),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            GestureDetector(
              onTap: _showQueueOverview,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x38E0BD22),
                  border: Border.all(color: const Color(0x99E0BD22)),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Center(
                  child: Text(
                    'Bekijk volledige wachtrij',
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2F2F2F),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            if (_connectionError != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🔴', style: TextStyle(fontSize: 12)),
                      SizedBox(width: 6),
                      Text(
                        'Verbinding verbroken',
                        style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8B1C1C),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QueueImage extends StatelessWidget {
  final String? imageUrl;
  const _QueueImage({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Image.asset('assets/cruise-terminal.png', fit: BoxFit.cover),
      );
    }
    return Image.asset('assets/cruise-terminal.png', fit: BoxFit.cover);
  }
}

class _LocationWarningBanner extends StatelessWidget {
  final int remainingSeconds;

  const _LocationWarningBanner({required this.remainingSeconds});

  @override
  Widget build(BuildContext context) {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;

    final timeText = '$minutes:${seconds.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7D6),
        border: Border.all(color: const Color(0xFFE0BD22)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'U bent buiten de bufferzone. Keer terug binnen $timeText om in de wachtrij te blijven.',
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4B3A00),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 15,
              color: Color(0xFF8A1C1C),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onRetry,
            child: const Text('Opnieuw verbinden'),
          ),
        ],
      ),
    );
  }
}
