import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/theme.dart';
import 'package:mobile_app/features/queue/queue_location_tracker.dart';
import 'package:mobile_app/widgets/screen_header.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationSoundEnabled = true;
  String _versionText = '';
  bool locationAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadLocationDetails();
  }

  Future<void> _loadLocationDetails() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();

    setState(() {
      locationAvailable =
          enabled &&
          permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever;
    });
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();

    setState(() {
      _versionText = 'v${packageInfo.version}+${packageInfo.buildNumber}';
    });
  }

  void _showNotImplemented(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is nog niet beschikbaar.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationTracker = context.watch<QueueLocationTracker>();

    return Scaffold(
      backgroundColor: AppColors.cardBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            ScreenHeader(
              title: 'Instellingen',
              subtitle: 'Pas de app naar wens aan',
              onBack: () => Navigator.pop(context),
            ),
            const SizedBox(height: 18),
            _SettingsHeaderCard(
              version: _versionText,
              trackingActive: locationTracker.isRunning,
            ),
            _SettingsSection(
              title: 'Meldingen en locatie',
              description: 'Beheer meldingen en live tracking.',
              children: [
                _SettingsSwitchTile(
                  icon: Icons.volume_up_outlined,
                  title: 'Meldingsgeluid',
                  value: _notificationSoundEnabled,
                  onChanged: (value) {
                    setState(() {
                      _notificationSoundEnabled = value;
                    });
                  },
                ),
                _SettingsNavigationTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Pushmeldingen testen',
                  onTap: () => _showNotImplemented('Pushmeldingen testen'),
                ),
                _SettingsStatusTile(
                  icon: Icons.location_on_outlined,
                  title: 'Locatiestatus',
                  status: locationAvailable ? 'Aan' : 'Uit',
                  active: locationAvailable,
                ),
                _SettingsStatusTile(
                  icon: Icons.my_location_outlined,
                  title: "Locatietracking",
                  status: locationTracker.isRunning ? 'Actief' : 'Niet actief',
                  active: locationTracker.isRunning,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              title: 'Taal',
              description: 'Pas de taal van de app aan.',
              children: [
                _SettingsNavigationTile(
                  icon: Icons.language_outlined,
                  title: 'Taal',
                  trailingText: 'Nederlands',
                  onTap: () => _showNotImplemented('Taal wijzigen'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              title: 'Privacy en gegevens',
              description: 'Privacyverklaring en voorwaarden.',
              children: [
                _SettingsNavigationTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacyverklaring',
                  onTap: () => _showNotImplemented('Privacyverklaring'),
                ),
                _SettingsNavigationTile(
                  icon: Icons.description_outlined,
                  title: 'Gebruiksvoorwaarden',
                  onTap: () => _showNotImplemented('Gebruiksvoorwaarden'),
                ),
                _SettingsNavigationTile(
                  icon: Icons.history_outlined,
                  title: 'Mijn activiteiten',
                  onTap: () => context.push('/settings/activity'),
                ),
                _SettingsNavigationTile(
                  icon: Icons.delete_outline_rounded,
                  title: "Verwijder mijn gegevens",
                  destructive: true,
                  onTap: () => _showNotImplemented("Gegevens verwijderen"),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              title: 'Help en over',
              description: 'Ondersteuning en informatie.',
              children: [
                _SettingsNavigationTile(
                  icon: Icons.help_outline_rounded,
                  title: 'Veelgestelde vragen',
                  onTap: () => _showNotImplemented('Veelgestelde vragen'),
                ),
                _SettingsNavigationTile(
                  icon: Icons.report_problem_outlined,
                  title: 'Probleem melden',
                  onTap: () => _showNotImplemented('Probleem melden'),
                ),
                _SettingsInfoTile(
                  icon: Icons.info_outline_rounded,
                  title: 'Over de app',
                  value: _versionText,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  final IconData icon;
  final bool destructive;

  const _SettingsIcon(this.icon, {this.destructive = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: destructive ? const Color(0xFFFEE2E2) : null,
        gradient: destructive ? null : kGradient,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 21,
        color: destructive ? const Color(0xFFDC2626) : const Color(0xFF333333),
      ),
    );
  }
}

class _SettingsHeaderCard extends StatelessWidget {
  final String version;
  final bool trackingActive;

  const _SettingsHeaderCard({
    required this.version,
    required this.trackingActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(22),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .45),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              size: 30,
              color: Color(0xFF333333),
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            'Chauffeur',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF333333),
            ),
          ),

          const Text(
            'TaxiBuffer',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF555555),
            ),
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: trackingActive
                      ? const Color(0xFFE7F7EA)
                      : Colors.white.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Icon(
                      trackingActive
                          ? Icons.location_on_rounded
                          : Icons.location_off_rounded,
                      size: 16,
                      color: trackingActive
                          ? const Color(0xFF16803C)
                          : const Color(0xFF555555),
                    ),

                    const SizedBox(width: 6),

                    Text(
                      trackingActive
                          ? 'Tracking actief'
                          : 'Tracking niet actief',
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: trackingActive
                            ? const Color(0xFF16803C)
                            : const Color(0xFF555555),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              Text(
                version,
                style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF555555),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final String description;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.description,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        description,
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, indent: 70, endIndent: 20),
          ],
        ],
      ),
    );
  }
}

class _SettingsNavigationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingText;
  final bool destructive;
  final VoidCallback onTap;

  const _SettingsNavigationTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailingText,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      leading: _SettingsIcon(icon, destructive: destructive),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1F2937),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null) ...[
            Text(
              trailingText!,
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(width: 6),
          ],
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
        ],
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      secondary: Icon(icon, color: const Color(0xFF4B5563)),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1F2937),
        ),
      ),
      activeThumbColor: AppColors.gradientStart,
    );
  }
}

class _SettingsStatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String status;
  final bool active;

  const _SettingsStatusTile({
    required this.icon,
    required this.title,
    required this.status,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      leading: Icon(icon, color: const Color(0xFF4B5563)),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1F2937),
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE7F8ED) : const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF9CA3AF),
                shape: BoxShape.circle,
              ),
            ),

            const SizedBox(width: 7),

            Text(
              status,
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active
                    ? const Color(0xFF15803D)
                    : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _SettingsInfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      leading: Icon(icon, color: const Color(0xFF4B5563)),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1F2937),
        ),
      ),
      trailing: Text(
        value,
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 14,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }
}
