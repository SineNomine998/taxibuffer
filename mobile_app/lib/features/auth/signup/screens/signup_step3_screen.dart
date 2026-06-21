import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/dialogs.dart';
import 'package:mobile_app/features/auth/services/auth_service.dart';
import 'package:mobile_app/features/auth/signup/signup_form_state.dart';
import 'package:provider/provider.dart';
import '../../../../widgets/app_shell_scaffold.dart';
import '../../../../widgets/primary_pill_button.dart';
import '../../../../widgets/secondary_pill_button.dart';
import '../../../../widgets/footer_note.dart';
import '../widgets/vehicle_card.dart';

class SignupStep3Screen extends StatefulWidget {
  const SignupStep3Screen({super.key});

  @override
  State<SignupStep3Screen> createState() => _SignupStep3ScreenState();
}

class _SignupStep3ScreenState extends State<SignupStep3Screen> {
  final _authService = AuthService();
  bool _isLoading = false;

  Future<void> _finish() async {
    final SignupFormState signupFormState = context.read<SignupFormState>();
    final firstName = signupFormState.firstName;
    final lastName = signupFormState.lastName;
    final email = signupFormState.email;
    final taxiLicenseNumber = signupFormState.taxiLicenseNumber;
    final password = signupFormState.password;
    final passwordConfirm = signupFormState.passwordConfirm;
    final vehicles = signupFormState.vehicles.map((v) => v.toJson()).toList();

    if (signupFormState.firstName.isEmpty ||
        signupFormState.lastName.isEmpty ||
        signupFormState.email.isEmpty ||
        signupFormState.taxiLicenseNumber.isEmpty ||
        signupFormState.password.isEmpty) {
      showAppAlert(
        context: context,
        title: "Onvolledige gegevens",
        message: "Er ontbreken gegevens uit een eerdere stap. Begin opnieuw.",
      );
      return;
    }

    if (signupFormState.vehicles.isEmpty) {
      showAppAlert(
        context: context,
        title: "Voertuig vereist",
        message: "Voeg minstens één voertuig toe om door te gaan.",
        svgAsset: 'assets/warning-badge.svg',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.signup(
        firstName: firstName,
        lastName: lastName,
        email: email,
        taxiLicenseNumber: taxiLicenseNumber,
        password: password,
        passwordConfirm: passwordConfirm,
        vehicles: vehicles,
      );

      if (!mounted) return;

      // On success:
      signupFormState.reset();
      context.go('/queue');
    } catch (e) {
      if (!mounted) return;

      await showAppAlert(
        context: context,
        title: "Account kon niet worden aangemaakt. Probeer opnieuw.",
        message: "Er is iets misgegaan.",
        svgAsset: 'assets/pop-up-denied.svg',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = context.watch<SignupFormState>();
    final current = formState.currentVehicle;
    final others = formState.otherVehicles;
    return AppShellScaffold(
      showBack: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Voertuig',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Maak hier een account aan.',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 15,
                color: Color(0xFF313131),
              ),
            ),
            const SizedBox(height: 18),

            if (formState.vehicles.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Nog geen voertuigen toegevoegd.',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF5D1B1B),
                  ),
                ),
              )
            else ...[
              if (current != null) ...[
                const Text(
                  'Huidig voertuig',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF222222),
                  ),
                ),
                const SizedBox(height: 8),
                VehicleCard(vehicle: current, isCurrent: true),
              ],
              if (others.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Andere voertuigen',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF222222),
                  ),
                ),
                const SizedBox(height: 8),
                for (final v in others) ...[
                  VehicleCard(vehicle: v, isCurrent: false),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _SmallActionButton(
                          label: 'Maak huidig',
                          onTap: () => context
                              .read<SignupFormState>()
                              .setCurrentVehicle(v),
                        ),
                        const SizedBox(width: 10),
                        _SmallActionButton(
                          label: 'Verwijder',
                          onTap: () =>
                              context.read<SignupFormState>().removeVehicle(v),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],

            const SizedBox(height: 16),
            SecondaryPillButton(
              label: '+ Voertuig toevoegen',
              onPressed: () => context.push('/signup/vehicle/add'),
            ),
            const SizedBox(height: 12),
            PrimaryPillButton(
              label: 'Volgende',
              isLoading: _isLoading,
              onPressed: _isLoading ? null : _finish,
            ),
            const SizedBox(height: 24),
            const FooterNote(),
          ],
        ),
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SmallActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE0BD22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF222222),
          ),
        ),
      ),
    );
  }
}
