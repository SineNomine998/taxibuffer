import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/widgets/screen_header.dart';

import '../../../core/theme.dart';
import '../models/activity_log_item.dart';
import '../services/activity_service.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final ActivityService _service = ActivityService();
  late final String _todayKey;

  bool _loading = true;
  String? _error;
  List<ActivityLogItem> _items = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _todayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _service.fetchActivityLogs();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon activiteiten niet laden. Probeer het opnieuw.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, List<ActivityLogItem>> _groupByDate(List<ActivityLogItem> items) {
    final grouped = <String, List<ActivityLogItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.localDate, () => []);
      grouped[item.localDate]!.add(item);
    }
    return grouped;
  }

  String _dateLabel(String date) {
    if (date == _todayKey) return 'Vandaag';

    final yesterdayDate = DateTime.now().subtract(const Duration(days: 1));
    final yesterday =
        '${yesterdayDate.year.toString().padLeft(4, '0')}-${yesterdayDate.month.toString().padLeft(2, '0')}-${yesterdayDate.day.toString().padLeft(2, '0')}';

    if (date == yesterday) return 'Gisteren';
    return date;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate(_items);

    return Scaffold(
      backgroundColor: AppColors.cardBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.gradientStart,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 4),
                  child: ScreenHeader(
                    title: 'Mijn activiteiten',
                    subtitle: 'Uw wachtrij- en locatiegeschiedenis',
                    onBack: () => context.pop(),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _ActivitySummaryCard(
                  totalToday: grouped[_todayKey]?.length ?? 0,
                  latest: _items.isNotEmpty ? _items.first : null,
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.gradientStart,
                    ),
                  ),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(message: _error!, onRetry: _load),
                )
              else if (_items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                )
              else
                _ActivityList(grouped: grouped, dateLabelBuilder: _dateLabel),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  final Map<String, List<ActivityLogItem>> grouped;
  final String Function(String date) dateLabelBuilder;

  const _ActivityList({required this.grouped, required this.dateLabelBuilder});

  @override
  Widget build(BuildContext context) {
    final dates = grouped.keys.toList();

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
      sliver: SliverList.builder(
        itemCount: dates.length,
        itemBuilder: (context, index) {
          final date = dates[index];
          final items = grouped[date]!;

          return _ActivityDaySection(
            title: dateLabelBuilder(date),
            items: items,
          );
        },
      ),
    );
  }
}

class _ActivityDaySection extends StatelessWidget {
  final String title;
  final List<ActivityLogItem> items;

  const _ActivityDaySection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.gradientStart.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  _ActivityTile(item: items[i]),
                  if (i != items.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 62),
                      child: Container(
                        width: 2,
                        height: 14,
                        color: AppColors.cardBorder,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final ActivityLogItem item;

  const _ActivityTile({required this.item});

  IconData get _icon {
    switch (item.eventType) {
      case 'queue_joined':
        return Icons.login_rounded;
      case 'queue_left':
        return Icons.logout_rounded;
      case 'location_outside_warning':
      case 'location_unavailable':
        return Icons.warning_rounded;
      case 'location_recovered':
        return Icons.location_on_rounded;
      case 'location_timeout_dequeued':
        return Icons.block_rounded;
      case 'notified':
        return Icons.notifications_active_rounded;
      case 'notification_accepted':
        return Icons.check_circle_rounded;
      case 'officer_dequeued':
        return Icons.flag_rounded;
      case 'system_dequeued':
        return Icons.settings_rounded;
      default:
        return Icons.circle_rounded;
    }
  }

  Color get _iconColor {
    switch (item.eventType) {
      case 'location_outside_warning':
      case 'location_unavailable':
        return const Color(0xFFE0BD22);
      case 'location_timeout_dequeued':
      case 'system_dequeued':
        return const Color(0xFFDC2626);
      case 'location_recovered':
      case 'notification_accepted':
        return const Color(0xFF16A34A);
      case 'notified':
        return const Color(0xFF2563EB);
      case 'queue_joined':
        return const Color(0xFF111827);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String get _fallbackMessage {
    switch (item.eventType) {
      case 'queue_joined':
        return 'U bent aangemeld voor de wachtrij.';
      case 'queue_left':
        return 'U heeft de wachtrij verlaten.';
      case 'location_outside_warning':
        return 'U was buiten de bufferzone.';
      case 'location_unavailable':
        return 'Uw locatie was niet beschikbaar.';
      case 'location_recovered':
        return 'U bent teruggekeerd naar de bufferzone.';
      case 'location_timeout_dequeued':
        return 'U bent verwijderd door locatiecontrole.';
      case 'notified':
        return 'U bent opgeroepen om door te rijden.';
      case 'notification_accepted':
        return 'U heeft de oproep bevestigd.';
      case 'officer_dequeued':
        return 'Uw rit is afgehandeld.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = <String>[];

    if (item.queueName != null && item.queueName!.isNotEmpty) {
      details.add(item.queueName!);
    }

    if (item.previousQueuePosition != null && item.queuePosition != null) {
      details.add(
        'Van #${item.previousQueuePosition} naar #${item.queuePosition}',
      );
    } else if (item.queuePosition != null) {
      details.add('Positie #${item.queuePosition}');
    }

    if (item.sequenceNumber != null) {
      details.add('Oproepnummer #${item.sequenceNumber}');
    }

    final message = item.message.isNotEmpty ? item.message : _fallbackMessage;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text(
              item.localTime,
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _iconColor.withValues(alpha: .13),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _iconColor.withValues(alpha: .25),
                    width: 1.5,
                  ),
                ),
                child: Icon(_icon, size: 21, color: _iconColor),
              ),
            ],
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                    height: 1.15,
                  ),
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    message,
                    style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 13,
                      height: 1.35,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: details
                        .map((detail) => _ActivityChip(label: detail))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityChip extends StatelessWidget {
  final String label;

  const _ActivityChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF374151),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              gradient: kGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .08),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.history_rounded,
              size: 40,
              color: Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Nog geen activiteiten',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Zodra u zich aanmeldt voor een wachtrij, verschijnen uw activiteiten hier.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 14,
              height: 1.4,
              color: Color(0xFF6B7280),
            ),
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
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE4E6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Er ging iets mis',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 14,
              height: 1.4,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              gradient: kGradient,
              borderRadius: BorderRadius.circular(999),
            ),
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Opnieuw proberen',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: Color(0xFF222222),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivitySummaryCard extends StatelessWidget {
  final int totalToday;
  final ActivityLogItem? latest;

  const _ActivitySummaryCard({required this.totalToday, this.latest});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 16, 18, 22),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: kGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .45),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.timeline_rounded,
              size: 26,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalToday activiteiten vandaag',
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  latest != null
                      ? 'Laatst: ${latest!.title} · ${latest!.localTime}'
                      : 'Nog geen activiteit vandaag',
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
