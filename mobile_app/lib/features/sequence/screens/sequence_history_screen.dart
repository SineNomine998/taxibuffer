import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/config/api_client.dart';
import 'package:mobile_app/features/queue/queue_tracking_sync.dart';
import '../../../core/theme.dart';
import '../../../widgets/app_shell_scaffold.dart';
import '../../../widgets/bottom_nav.dart';
import '../../../widgets/footer_note.dart';
import '../models/sequence_notification.dart';
import '../services/sequence_service.dart';

class SequenceHistoryScreen extends StatefulWidget {
  const SequenceHistoryScreen({super.key});

  @override
  State<SequenceHistoryScreen> createState() => _SequenceHistoryScreenState();
}

class _SequenceHistoryScreenState extends State<SequenceHistoryScreen>
    with WidgetsBindingObserver {
  final _service = SequenceService();
  List<SequenceNotification> _notifications = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  String? _error;

  String get _todayDate =>
      DateFormat('d MMMM yyyy', 'nl').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await syncQueueTracking(context);
    });
    _load();

    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final results = await _service.fetchTodaysNotifications();

      if (!mounted) return;

      setState(() {
        _notifications = results;
        _error = null;
      });
    } on ApiAuthException {
      // ApiClient already triggered SessionManager.handleAuthExpired().
      // So don't show an error message here.
      return;
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Kon gegevens niet laden. Probeer opnieuw.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      activeTab: NavTab.numbers,
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.gradientStart,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mijn Ophaalnummers',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Ontvangen op $_todayDate',
                style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 14),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.gradientStart,
                    ),
                  ),
                )
              else if (_error != null)
                _ErrorState(message: _error!, onRetry: _load)
              else if (_notifications.isEmpty)
                const _EmptyState()
              else
                _NumbersList(notifications: _notifications),
              const SizedBox(height: 24),
              const FooterNote(),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumbersList extends StatelessWidget {
  final List<SequenceNotification> notifications;
  const _NumbersList({required this.notifications});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        notifications.length,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _NumberCard(
            notification: notifications[index],
            isTopItem: index == 0,
          ),
        ),
      ),
    );
  }
}

class _NumberCard extends StatelessWidget {
  final SequenceNotification notification;
  final bool isTopItem;
  const _NumberCard({required this.notification, required this.isTopItem});

  @override
  Widget build(BuildContext context) {
    final isActiveCall = notification.isActiveCall;
    final isHandled = notification.isHandled;

    final Color borderColor = isActiveCall
        ? const Color(0xFF16A34A)
        : const Color(0xFFE5E7EB);

    final Color backgroundColor = isActiveCall
        ? const Color(0xFFF0FDF4)
        : Colors.white;

    final Color badgeColor = isActiveCall
        ? const Color(0xFF15803D)
        : const Color(0xFFE5E7EB);

    final Color badgeTextColor = isActiveCall
        ? Colors.white
        : const Color(0xFF374151);

    final String badgeText = isActiveCall
        ? 'Rij door'
        : isHandled
        ? 'Afgehandeld'
        : 'In behandeling';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isActiveCall ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${notification.sequenceNumber}',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: isActiveCall ? 36 : 28,
                    fontWeight: FontWeight.w800,
                    color: isActiveCall
                        ? const Color(0xFF15803D)
                        : const Color(0xFF111827),
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notification.queueName,
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                notification.localTime,
                style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: badgeTextColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Column(
        children: [
          Text('#', style: TextStyle(fontSize: 40)),
          SizedBox(height: 10),
          Text(
            'Nog geen nummers vandaag',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Zodra u een ophaalnummer ontvangt, verschijnt het hier.',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
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
          TextButton(onPressed: onRetry, child: const Text('Opnieuw proberen')),
        ],
      ),
    );
  }
}
