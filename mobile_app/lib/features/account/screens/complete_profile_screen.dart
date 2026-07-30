import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/models/tto_option.dart';
import 'package:mobile_app/features/account/account_state.dart';
import 'package:mobile_app/features/account/models/account_profile.dart';
import 'package:mobile_app/features/account/profile_gate_state.dart';
import 'package:provider/provider.dart';

import '../../../widgets/app_shell_scaffold.dart';
import '../../../widgets/primary_pill_button.dart';
import '../../../widgets/shell_text_field.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  String? _selectedTto;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  Future<void> _load() async {
    try {
      await context.read<AccountState>().load();

      if (!mounted) return;

      final profile = context.read<AccountState>().profile;

      _phoneController.text = profile?.phoneNumber ?? '';
      _selectedTto = profile?.tto.isNotEmpty == true ? profile!.tto : null;

      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Kon profielgegevens niet laden.';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final accountState = context.read<AccountState>();
    final current = accountState.profile;

    if (current == null) return;

    setState(() => _saving = true);

    try {
      await accountState.updateProfile(
        AccountProfile(
          firstName: current.firstName,
          lastName: current.lastName,
          email: current.email,
          taxiLicenseNumber: current.taxiLicenseNumber,
          tto: _selectedTto!,
          phoneNumber: _phoneController.text.trim(),
        ),
      );

      if (!mounted) return;

      context.read<ProfileGateState>().markCompleted();

      final next = GoRouterState.of(context).uri.queryParameters['next'];
      context.go(next?.isNotEmpty == true ? next! : '/locations');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Profiel kon niet worden opgeslagen.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountState = context.watch<AccountState>();
    final ttos = accountState.ttoOptions;

    return AppShellScaffold(
      child: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Profiel aanvullen',
                        style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Vul uw TTO en telefoonnummer in om de app te blijven gebruiken.',
                        style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 15,
                          color: Color(0xFF313131),
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 12),
                      ],

                      const Text(
                        'TTO*',
                        style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 7),

                      DropdownButtonFormField<String>(
                        initialValue: _selectedTto,
                        isExpanded: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFF1F1F1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        hint: const Text('Selecteer uw TTO'),
                        items: ttos.map((TtoOption tto) {
                          return DropdownMenuItem<String>(
                            value: tto.value,
                            child: Text(tto.label),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedTto = value);
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Selecteer een TTO';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      ShellTextField(
                        label: 'Telefoonnummer*',
                        hint: '06 12345678',
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Verplicht veld';
                          }
                          if (value.trim().length < 8) {
                            return 'Ongeldig telefoonnummer';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 30),

                      PrimaryPillButton(
                        label: 'Opslaan',
                        isLoading: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
