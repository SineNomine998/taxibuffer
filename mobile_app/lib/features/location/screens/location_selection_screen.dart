import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/permissions/queue_permission_gate.dart';
import 'package:mobile_app/features/queue/queue_state.dart';
import 'package:provider/provider.dart';
import '../../../core/dialogs.dart';
import '../../../core/theme.dart';
import '../../../widgets/app_shell_scaffold.dart';
import '../../../widgets/bottom_nav.dart';
import '../models/pickup_zone.dart';
import '../services/location_service.dart';

class LocationSelectionScreen extends StatefulWidget {
  const LocationSelectionScreen({super.key});

  @override
  State<LocationSelectionScreen> createState() =>
      _LocationSelectionScreenState();
}

class _LocationSelectionScreenState extends State<LocationSelectionScreen>
    with WidgetsBindingObserver {
  final _locationService = LocationService();
  List<PickupZone> _queues = [];
  bool _isLoading = true;
  String? _loadError;
  int? _submittingQueueId;
  final _permissionGate = QueuePermissionGate();
  QueuePermissionStatus? _permissionStatus;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadQueues();
      _checkQueuePermissions();
    });
  }

  Future<void> _checkQueuePermissions() async {
    try {
      final status = await _permissionGate.check();

      if (!mounted) return;

      setState(() {
        _permissionStatus = status;
      });

      if (!status.canJoinQueue) {
        await _showPermissionRequiredDialog();
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _permissionStatus = const QueuePermissionStatus(
          locationGranted: false,
          locationPermanentlyDenied: false,
          notificationGranted: false,
          notificationPermanentlyDenied: false,
        );
      });
    }
  }

  Future<void> _showPermissionRequiredDialog() async {
    if (!mounted) return;

    final accepted = await showAppConfirm(
      context: context,
      title: 'Toestemmingen vereist',
      message:
          'Voor een eerlijke wachtrij zijn locatie en meldingen verplicht. '
          'Locatie controleert of u in de bufferzone bent. Meldingen zorgen dat u uw beurt niet mist.',
      confirmLabel: 'Toestemmingen geven',
      cancelLabel: 'Later',
    );

    if (accepted != true || !mounted) return;

    final status = await _permissionGate.requestMissingPermissions();

    if (!mounted) return;

    setState(() {
      _permissionStatus = status;
    });

    if (status.canJoinQueue) {
      return;
    }

    final openSettings = await showAppConfirm(
      context: context,
      title: 'Instellingen openen',
      message:
          'Locatie of meldingen zijn nog uitgeschakeld. Open de app-instellingen om dit handmatig aan te zetten.',
      confirmLabel: 'Open instellingen',
      cancelLabel: 'Later',
    );

    if (openSettings == true) {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _loadQueues() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final state = await _locationService.fetchQueuesState();

      if (!mounted) return;

      final queueState = context.read<QueueState>();

      if (state.hasActiveQueue) {
        queueState.setActiveEntry(state.activeEntryUuid!);
      } else {
        queueState.clearActiveEntry();
      }

      setState(() => _queues = state.queues);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onRegister(PickupZone zone) async {
    final permissionStatus = _permissionStatus;

    if (permissionStatus == null || !permissionStatus.canJoinQueue) {
      await _showPermissionRequiredDialog();
      return;
    }

    setState(() => _submittingQueueId = zone.queueId);

    try {
      final position = await _locationService.getCurrentPosition();

      final result = await _locationService.validateLocation(
        lat: position.latitude,
        lng: position.longitude,
        queueId: zone.queueId,
      );

      if (!result.isValid) {
        if (!mounted) return;
        await showAppAlert(
          context: context,
          title: 'Geweigerd',
          message:
              result.errorMessage ?? 'U bevindt zich niet in de bufferzone.',
          svgAsset: 'assets/pop-up-denied.svg',
        );
        return;
      }

      final entryUuid = await _locationService.joinQueue(
        queueId: zone.queueId,
        lat: position.latitude,
        lng: position.longitude,
      );

      if (!mounted) return;

      context.read<QueueState>().setActiveEntry(entryUuid);
      context.go('/queue/$entryUuid');
    }
    // TODO: Display permission pop-up again if the user tries to sign up for a queue after declining the permission.
    on LocationPermissionDeniedException catch (e) {
      if (!mounted) return;
      await showAppAlert(
        context: context,
        title: 'Locatie Fout',
        message: e.permanently
            ? 'Locatie-toestemming is permanent geweigerd. Schakel dit in via de instellingen van uw apparaat.'
            : 'Locatie-toestemming geweigerd. Schakel locatievoorziening in en probeer opnieuw.',
        svgAsset: 'assets/pop-up-denied.svg',
      );
    } catch (e) {
      if (!mounted) return;
      await showAppAlert(
        context: context,
        title: 'Fout',
        message: e.toString().replaceFirst('Exception: ', ''),
        svgAsset: 'assets/pop-up-denied.svg',
      );
    }
  }

  Future<void> _onEmptyBack() async {
    final confirmed = await showAppConfirm(
      context: context,
      title: 'Terug naar login',
      message:
          'Weet u zeker dat u terug wilt? U moet uw gegevens opnieuw invoeren.',
    );
    if (confirmed == true && mounted) {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkQueuePermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool alreadyInQueue = context.watch<QueueState>().isInQueue;
    final permissionStatus = _permissionStatus;
    final bool permissionsOk = permissionStatus?.canJoinQueue ?? false;

    return AppShellScaffold(
      showHelp: true,
      onHelpTap: () => context.push('/locations/info'),
      activeTab: NavTab.locations,
      child: RefreshIndicator(
        onRefresh: _loadQueues,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welkom terug!',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Meld u hier aan voor de wachtrij',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),

              const SizedBox(height: 14),

              if (alreadyInQueue)
                GestureDetector(
                  onTap: () {
                    final entryUuid = context
                        .read<QueueState>()
                        .activeEntryUuid;

                    if (entryUuid == null || entryUuid.isEmpty) return;

                    context.go('/queue/$entryUuid');
                  },
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x38E0BD22),
                      border: Border.all(color: const Color(0x99E0BD22)),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'U staat al in een wachtrij  →',
                          style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2F2F2F),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.gradientStart,
                    ),
                  ),
                )
              else if (_loadError != null)
                _ErrorState(message: _loadError!, onRetry: _loadQueues)
              else if (_queues.isEmpty)
                _EmptyState(onBack: _onEmptyBack)
              else ...[
                if (_permissionStatus != null &&
                    !_permissionStatus!.canJoinQueue)
                  _PermissionRequiredCard(
                    onPressed: _showPermissionRequiredDialog,
                  ),
                for (final zone in _queues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _LocationCard(
                      zone: zone,
                      isSubmitting: _submittingQueueId == zone.queueId,
                      alreadyInQueue: alreadyInQueue,
                      permissionsOk: permissionsOk,
                      onRegister: () => _onRegister(zone),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final PickupZone zone;
  final bool isSubmitting;
  final bool alreadyInQueue;
  final bool permissionsOk;
  final VoidCallback onRegister;

  const _LocationCard({
    required this.zone,
    required this.isSubmitting,
    required this.alreadyInQueue,
    required this.permissionsOk,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = !zone.isActive || alreadyInQueue || !permissionsOk;
    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Container(
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
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 96,
                child: zone.imageUrl != null
                    ? Image.network(zone.imageUrl!, fit: BoxFit.cover)
                    : Image.asset(
                        'assets/cruise-terminal.png',
                        fit: BoxFit.cover,
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        zone.name,
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        zone.address ??
                            'Wilhelminakade 699, 3072 AP, Rotterdam',
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: disabled ? null : kGradient,
                            color: disabled ? const Color(0xFFE5E7EB) : null,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: TextButton(
                            onPressed: disabled || isSubmitting
                                ? null
                                : onRegister,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF222222),
                                    ),
                                  )
                                : Text(
                                    !zone.isActive
                                        ? 'Gesloten'
                                        : alreadyInQueue
                                        ? 'Actieve wachtrij'
                                        : !permissionsOk
                                        ? 'Toestemming nodig'
                                        : 'Aanmelden',
                                    style: const TextStyle(
                                      fontFamily: 'DM Sans',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF222222),
                                    ),
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
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onBack;
  const _EmptyState({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Text('📍', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          const Text(
            'Geen locaties beschikbaar',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Er zijn momenteel geen actieve ophaallocaties. Probeer het later opnieuw.',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 15,
              color: Color(0xFF6B7280),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: onBack,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
              ),
            ),
            child: const Text(
              '← Terug naar Inloggen',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF444444),
              ),
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

class _PermissionRequiredCard extends StatelessWidget {
  final VoidCallback onPressed;

  const _PermissionRequiredCard({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7D6),
        border: Border.all(color: const Color(0xFFE0BD22)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Toestemmingen vereist',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'U kunt pas aanmelden wanneer locatie en meldingen zijn ingeschakeld.',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 14,
              color: Color(0xFF4B5563),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onPressed,
            child: const Text('Toestemmingen instellen'),
          ),
        ],
      ),
    );
  }
}
