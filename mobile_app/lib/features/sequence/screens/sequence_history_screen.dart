import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

class _SequenceHistoryScreenState extends State<SequenceHistoryScreen> {
  final _service = SequenceService();
  List<SequenceNotification> _notifications = [];
  bool _isLoading = true;
  String? _error;

  String get _todayDate =>
      DateFormat('d MMMM yyyy', 'nl').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await _service.fetchTodaysNotifications();
      if (!mounted) return;
      setState(() => _notifications = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    final shouldDrive = isTopItem && notification.response == 'accepted';

    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${notification.sequenceNumber}',
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
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
              shouldDrive
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7D6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Rij door',
                        style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2F2F2F),
                        ),
                      ),
                    )
                  : const Text(
                      'Afgehandeld',
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
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
