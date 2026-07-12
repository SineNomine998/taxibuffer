import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/models/vehicle.dart';
import 'package:mobile_app/features/account/widgets/add_vehicle_card.dart';
import 'package:mobile_app/features/account/widgets/edit_vehicle_sheet.dart';
import 'package:mobile_app/features/account/widgets/profile_card.dart';
import 'package:mobile_app/features/account/widgets/vehicles_card.dart';
import 'package:mobile_app/features/privacy/privacy_gate_state.dart';
import 'package:provider/provider.dart';
import '../../../core/dialogs.dart';
import '../../../core/theme.dart';
import '../../../widgets/app_shell_scaffold.dart';
import '../../../widgets/bottom_nav.dart';
import '../../../widgets/footer_note.dart';
import '../../auth/services/auth_service.dart';
import '../account_state.dart';
import '../models/account_profile.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _editingProfile = false;
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;
  late TextEditingController _rtxController;
  final _profileFormKey = GlobalKey<FormState>();
  bool _isSavingProfile = false;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _emailController = TextEditingController();
    _rtxController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AccountState>().load().then((_) => _syncControllers());
    });
  }

  void _syncControllers() {
    final profile = context.read<AccountState>().profile;
    if (profile == null) return;
    _firstNameController.text = profile.firstName;
    _lastNameController.text = profile.lastName;
    _emailController.text = profile.email;
    _rtxController.text = profile.taxiLicenseNumber;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _rtxController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    setState(() => _isSavingProfile = true);
    try {
      await context.read<AccountState>().updateProfile(
        AccountProfile(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          email: _emailController.text.trim(),
          taxiLicenseNumber: _rtxController.text.trim(),
        ),
      );
      if (!mounted) return;
      setState(() => _editingProfile = false);
    } catch (e) {
      if (!mounted) return;
      await showAppAlert(
        context: context,
        title: 'Fout',
        message: e.toString(),
        svgAsset: "assets/pop-up-denied.svg",
      );
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _openEditVehicleSheet(Vehicle vehicle) async {
    final editedVehicle = await showModalBottomSheet<Vehicle>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return EditVehicleSheet(vehicle: vehicle);
      },
    );

    if (editedVehicle == null || !mounted) return;

    try {
      await context.read<AccountState>().adjustVehicle(editedVehicle);

      if (!mounted) return;

      await showAppAlert(
        context: context,
        title: 'Voertuig bijgewerkt',
        message: 'De voertuiggegevens zijn opgeslagen.',
        svgAsset: 'assets/check-badge.svg',
      );
    } catch (e) {
      if (!mounted) return;

      await showAppAlert(
        context: context,
        title: 'Fout',
        message: e.toString(),
        svgAsset: 'assets/pop-up-denied.svg',
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showAppConfirm(
      context: context,
      title: 'Uitloggen',
      message: 'Weet u zeker dat u wilt uitloggen?',
      confirmLabel: 'Uitloggen',
    );

    if (confirmed != true || !context.mounted) return;

    await AuthService().logout();

    if (!mounted) return;

    context.read<PrivacyGateState>().reset();

    if (!mounted) return;

    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AccountState>();

    return AppShellScaffold(
      activeTab: NavTab.account,
      child: RefreshIndicator(
        onRefresh: () => context.read<AccountState>().load(),
        color: AppColors.gradientStart,
        child: state.isLoading && state.profile == null
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.gradientStart,
                ),
              )
            : state.loadError != null && state.profile == null
            ? _ErrorState(
                message: state.loadError!,
                onRetry: () => context.read<AccountState>().load(),
              )
            : state.profile == null
            ? _ErrorState(
                message: "Accountgegevens konden niet worden geladen.",
                onRetry: () => context.read<AccountState>().load(),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Account',
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Beheer uw profiel en voertuigen',
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 16,
                        color: Color(0xFF313131),
                      ),
                    ),
                    const SizedBox(height: 14),

                    ProfileCard(
                      profile: state.profile!,
                      currentVehiclePlate: state.currentVehicle?.licensePlate,
                      editing: _editingProfile,
                      formKey: _profileFormKey,
                      firstNameController: _firstNameController,
                      lastNameController: _lastNameController,
                      emailController: _emailController,
                      rtxController: _rtxController,
                      isSaving: _isSavingProfile,
                      onEdit: () => setState(() => _editingProfile = true),
                      onCancel: () {
                        _syncControllers();
                        setState(() => _editingProfile = false);
                      },
                      onSave: _saveProfile,
                      onLogout: _logout,
                    ),
                    const SizedBox(height: 14),

                    VehiclesCard(
                      vehicles: state.vehicles,
                      onSetCurrent: (v) async {
                        try {
                          await state.setCurrentVehicle(v);
                        } catch (e) {
                          if (!context.mounted) return;
                          await showAppAlert(
                            context: context,
                            title: 'Fout',
                            message: e.toString(),
                            svgAsset: "assets/pop-up-denied.svg",
                          );
                        }
                      },
                      onRemove: (v) async {
                        try {
                          await state.removeVehicle(v);
                        } catch (e) {
                          if (!context.mounted) return;
                          await showAppAlert(
                            context: context,
                            title: 'Fout',
                            message: e.toString(),
                            svgAsset: "assets/pop-up-denied.svg",
                          );
                        }
                      },
                      onAdjust: _openEditVehicleSheet,
                    ),
                    const SizedBox(height: 14),

                    AddVehicleCard(
                      onAdd: (vehicle) async {
                        try {
                          await context.read<AccountState>().addVehicle(
                            vehicle,
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          await showAppAlert(
                            context: context,
                            title: 'Fout',
                            message: e.toString(),
                            svgAsset: "assets/pop-up-denied.svg",
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    const FooterNote(),
                  ],
                ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              child: const Text('Opnieuw proberen'),
            ),
          ],
        ),
      ),
    );
  }
}
