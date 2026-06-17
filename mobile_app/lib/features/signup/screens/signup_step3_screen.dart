import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/features/signup/signup_form_state.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_shell_scaffold.dart';
import '../../../widgets/primary_pill_button.dart';
import '../../../widgets/secondary_pill_button.dart';
import '../../../widgets/footer_note.dart';
import 'vehicle_model.dart';

class SignupStep3Screen extends StatefulWidget {
  const SignupStep3Screen({super.key});

  @override
  State<SignupStep3Screen> createState() => _SignupStep3ScreenState();
}

class _SignupStep3ScreenState extends State<SignupStep3Screen> {
  void _finish() {
    // TODO: finalize signup via mobile_api, then navigate into authenticated shell
    context.go('/queue');
  }

  @override
  Widget build(BuildContext context) {
    final formState = context.watch<SignupFormState>();
    final current = formState.currentVehicle;
    final others = formState.otherVehicles;
    return AppShellScaffold(
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
                _VehicleCard(vehicle: current, isCurrent: true),
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
                  _VehicleCard(vehicle: v, isCurrent: false),
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
            PrimaryPillButton(label: 'Volgende', onPressed: _finish),
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

class _VehicleCard extends StatelessWidget {
  final Vehicle vehicle;
  final bool isCurrent;

  const _VehicleCard({required this.vehicle, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFFDDBE26) : const Color(0xFFF2F2F2),
        border: isCurrent ? null : Border.all(color: const Color(0xFFC7C9D2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicle.nickname,
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isCurrent ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Type: ${_capitalize(vehicle.vehicleType)}',
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 18,
                    color: Color(0xFF4A4A4A),
                  ),
                ),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 112),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isCurrent ? Colors.transparent : Colors.white,
              border: Border.all(
                color: isCurrent
                    ? const Color(0xFFF7E79A)
                    : const Color(0xFF6F6F6F),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              vehicle.licensePlate,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isCurrent ? Colors.white : const Color(0xFF484848),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
