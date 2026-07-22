import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/models/vehicle.dart';
import 'package:mobile_app/features/auth/signup/signup_form_state.dart';
import 'package:provider/provider.dart';
import '../../../../widgets/app_shell_scaffold.dart';
import '../../../../widgets/shell_text_field.dart';
import '../../../../widgets/primary_pill_button.dart';
import '../../../../widgets/secondary_pill_button.dart';
import '../../../../widgets/footer_note.dart';
import '../../../../widgets/inline_error_banner.dart';

class VehicleAddScreen extends StatefulWidget {
  const VehicleAddScreen({super.key});

  @override
  State<VehicleAddScreen> createState() => _VehicleAddScreenState();
}

class _VehicleAddScreenState extends State<VehicleAddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  final _plateController = TextEditingController();
  String _vehicleType = 'auto';
  bool _setAsCurrent = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final hasNoVehicles = context.read<SignupFormState>().vehicles.isEmpty;

      if (hasNoVehicles) {
        setState(() => _setAsCurrent = true);
      }
    });
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final form = context.read<SignupFormState>();

    final shouldBeCurrent = _setAsCurrent || form.vehicles.isEmpty;

    form.addVehicle(
      Vehicle(
        nickname: _nicknameController.text.trim(),
        licensePlate: _plateController.text.trim().toUpperCase(),
        vehicleType: _vehicleType,
        isCurrent: shouldBeCurrent,
      ),
    );

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      showBack: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Voertuig toevoegen',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Voeg kenteken en bijnaam toe',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 15,
                  color: Color(0xFF313131),
                ),
              ),
              const SizedBox(height: 18),
              if (_serverError != null)
                InlineErrorBanner(message: _serverError!),
              ShellTextField(
                label: 'Bijnaam*',
                hint: 'Taxi 1',
                controller: _nicknameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Verplicht veld' : null,
              ),
              const SizedBox(height: 20),
              ShellTextField(
                label: 'Kenteken*',
                hint: '38HTTS',
                controller: _plateController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Verplicht veld' : null,
              ),
              const SizedBox(height: 20),
              const Text(
                'Voertuigtype*',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: Color(0xFF232323),
                ),
              ),
              const SizedBox(height: 7),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F1F1),
                  border: Border.all(color: const Color(0xFFA9ACB9)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _vehicleType,
                    isExpanded: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    icon: const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.keyboard_arrow_down),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'auto',
                        child: Text(
                          'Auto',
                          style: TextStyle(fontFamily: 'DM Sans', fontSize: 18),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'busje',
                        child: Text(
                          'Busje',
                          style: TextStyle(fontFamily: 'DM Sans', fontSize: 18),
                        ),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _vehicleType = v ?? 'auto'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: _setAsCurrent,
                    onChanged: (v) =>
                        setState(() => _setAsCurrent = v ?? false),
                    activeColor: const Color(0xFFE0BD22),
                  ),
                  const Expanded(
                    child: Text(
                      'Maak dit mijn huidige voertuig',
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF222222),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              PrimaryPillButton(label: 'Opslaan', onPressed: _save),
              const SizedBox(height: 12),
              SecondaryPillButton(
                label: 'Terug',
                onPressed: () => context.pop(),
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
