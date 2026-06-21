import 'package:flutter/material.dart';
import '../../../widgets/shell_text_field.dart';
import '../../../widgets/primary_pill_button.dart';
import '../../../widgets/secondary_pill_button.dart';
import '../models/account_profile.dart';

class ProfileCard extends StatelessWidget {
  final AccountProfile profile;
  final String? currentVehiclePlate;
  final bool editing;
  final GlobalKey<FormState> formKey;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController emailController;
  final TextEditingController rtxController;
  final bool isSaving;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback onLogout;

  const ProfileCard({
    required this.profile,
    required this.currentVehiclePlate,
    required this.editing,
    required this.formKey,
    required this.firstNameController,
    required this.lastNameController,
    required this.emailController,
    required this.rtxController,
    required this.isSaving,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
    required this.onLogout,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F8),
        border: Border.all(color: const Color(0xFFC9CCD5)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profielgegevens',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 18,
              color: Color(0xFF222222),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _Row(
            label: 'Naam',
            value: '${profile.firstName} ${profile.lastName}',
          ),
          _Row(label: 'RTX-nummer', value: profile.taxiLicenseNumber),
          _Row(
            label: 'E-mail',
            value: profile.email.isEmpty ? 'Niet ingesteld' : profile.email,
          ),
          _Row(
            label: 'Huidig voertuig',
            value: currentVehiclePlate ?? 'Niet ingesteld',
          ),
          const SizedBox(height: 10),

          if (!editing) ...[
            SecondaryPillButton(label: 'Gegevens wijzigen', onPressed: onEdit),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onLogout,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text(
                  'Uitloggen',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7F1D1D),
                  ),
                ),
              ),
            ),
          ] else
            Form(
              key: formKey,
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  ShellTextField(
                    label: 'Voornaam*',
                    hint: 'Voornaam',
                    controller: firstNameController,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Verplicht veld'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  ShellTextField(
                    label: 'Achternaam*',
                    hint: 'Achternaam',
                    controller: lastNameController,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Verplicht veld'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  ShellTextField(
                    label: 'E-mail*',
                    hint: 'naam@example.com',
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Verplicht veld';
                      }
                      if (!v.contains('@')) return 'Ongeldig e-mailadres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  ShellTextField(
                    label: 'RTX-nummer*',
                    hint: 'Bijv. 1234 of 1234-A1',
                    controller: rtxController,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Verplicht veld'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: PrimaryPillButton(
                          label: isSaving ? 'Bezig...' : 'Opslaan',
                          onPressed: isSaving ? () {} : onSave,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SecondaryPillButton(
                          label: 'Annuleren',
                          onPressed: onCancel,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF606060),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1D1D1D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
