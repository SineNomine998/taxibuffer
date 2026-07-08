import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });
    try {
      await _queueService.connect(widget.entryUuid);
      _subscription = _queueService.statusStream.listen(
        _onStatus,
        onError: (e) {
          if (!mounted) return;
          setState(() => _connectionError = e.toString());
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _connectionError = e.toString());
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _onStatus(QueueStatus status) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _connectionError = null;
    });

    // Entry no longer active - dequeued externally.
    if (!status.active) {
      _exitQueue();
      return;
    }

    // Notification handling
    // TODO: When FCM is wired, move this trigger to the FCM onMessage handler
    // so it fires even when the app is backgrounded. For now, triggers on WS push.
    if (status.hasNotification && status.notification != null) {
      final notifId = status.notification!.id;
      if (!_seenNotificationIds.contains(notifId)) {
        _seenNotificationIds.add(notifId);
        _showTurnNotification(status.notification!);
      }
    }
  }

  /// Clears global queue state and navigates away.
  /// Call this whenever the user is no longer in the queue,
  /// whether by leaving voluntarily or being dequeued externally.
  void _exitQueue() {
    if (!mounted) return;
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
                'Rij door naar de ophaallocatie. Volg de borden en laat uw nummer zien.',
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
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    // TODO: call respondToNotification(notification.id, 'accepted') via HTTP or WebSocket? once endpoint exists
                    _exitQueue();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Begrepen',
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
        _exitQueue();
      } else {
        await showAppAlert(
          context: context,
          title: 'Fout',
          message: 'Kon niet verlaten. Probeer opnieuw.',
          svgAsset: 'assets/pop-up-denied.svg',
        );
      }
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
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _queueService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconnect();
    }
  }

  Future<void> _reconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    _queueService.dispose();

    if (!mounted) return;

    _queueService = QueueService();
    await _connect();
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
          ? _ErrorState(message: _connectionError!, onRetry: _connect)
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final status = _status;
    if (status == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gradientStart),
      );
    }

    return RefreshIndicator(
      onRefresh: _reconnect,
      color: AppColors.gradientStart,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aangemeld!',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'U krijgt een seintje als u door mag rijden.',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 14),

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
                              onPressed: _isLeaving ? null : _onLeave,
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
                                _isLeaving ? 'Bezig...' : 'Verlaten',
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
