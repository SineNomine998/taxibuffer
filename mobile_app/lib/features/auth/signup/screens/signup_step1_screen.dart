import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/dialogs.dart';
import 'package:mobile_app/core/models/tto_option.dart';
import 'package:mobile_app/features/account/services/account_service.dart';
import 'package:mobile_app/features/auth/services/auth_service.dart';
import 'package:mobile_app/features/auth/signup/signup_form_state.dart';
import 'package:provider/provider.dart';
import 'package:email_validator/email_validator.dart';
import '../../../../widgets/app_shell_scaffold.dart';
import '../../../../widgets/shell_text_field.dart';
import '../../../../widgets/primary_pill_button.dart';
import '../../../../widgets/footer_note.dart';
import '../../../../widgets/inline_error_banner.dart';

class SignupStep1Screen extends StatefulWidget {
  const SignupStep1Screen({super.key});

  @override
  State<SignupStep1Screen> createState() => _SignupStep1ScreenState();
}

class _SignupStep1ScreenState extends State<SignupStep1Screen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _rtxController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _selectedTto;
  List<TtoOption> _ttoOptions = [];
  final _authService = AuthService();
  final _accountService = AccountService();

  String? _serverError; // populate from API error response

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTtos();
  }

  Future<void> _loadTtos() async {
    try {
      final options = await _accountService.fetchTtoOptions();
      if (!mounted) return;
      setState(() {
        _ttoOptions = options;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _serverError = 'Kon TTO-lijst niet laden.';
      });
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _rtxController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final available = await _authService.isEmailAvailable(
        _emailController.text.trim(),
      );
      if (!available) {
        if (!mounted) return;
        await showAppAlert(
          context: context,
          title: 'Emailadres al in gebruik.',
          message:
              'Dit emailadres is al geregistreerd. Log in of gebruik een ander adres.',
          svgAsset: 'assets/warning-badge.svg',
        );
        return;
      }

      if (!mounted) return;

      context.read<SignupFormState>().setPersonalDetails(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim().toLowerCase(),
        taxiLicenseNumber: _rtxController.text.trim(),
        tto: _selectedTto!,
        phoneNumber: _phoneController.text.trim(),
      );
      context.push('/signup/password');
    } catch (e) {
      if (!mounted) return;
      await showAppAlert(
        context: context,
        title: 'Oeps, foutje opgetreden',
        message: e.toString(),
        svgAsset: "assets/pop-up-denied.svg",
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      showBack: true,
      onBackTap: () {
        context.go('/login');
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welkom!',
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
              if (_serverError != null)
                InlineErrorBanner(message: _serverError!),
              ShellTextField(
                label: 'Voornaam*',
                hint: 'Harold',
                controller: _firstNameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Verplicht veld' : null,
              ),
              const SizedBox(height: 20),
              ShellTextField(
                label: 'Achternaam*',
                hint: 'Finch',
                controller: _lastNameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Verplicht veld' : null,
              ),
              const SizedBox(height: 20),
              ShellTextField(
                label: 'Emailadres*',
                hint: 'harold@email.com',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Verplicht veld';
                  if (!EmailValidator.validate(v)) return 'Ongeldig emailadres';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ShellTextField(
                label: 'RTX nummer*',
                hint: '1234',
                controller: _rtxController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Verplicht veld' : null,
              ),
              const SizedBox(height: 20),
              ShellTextField(
                label: 'Telefoonnummer*',
                hint: '06 12345678',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Verplicht veld';
                  if (v.trim().length < 8) return 'Ongeldig telefoonnummer';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'TTO*',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: Color(0xFF232323),
                ),
              ),
              const SizedBox(height: 7),
              FormField<String>(
                initialValue: _selectedTto,
                validator: (_) {
                  if (_selectedTto == null || _selectedTto!.isEmpty) {
                    return 'Selecteer een TTO';
                  }
                  return null;
                },
                builder: (field) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F1F1),
                          border: Border.all(
                            color: field.hasError
                                ? Colors.red
                                : const Color(0xFFA9ACB9),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedTto,
                            isExpanded: true,
                            hint: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'Selecteer uw TTO',
                                style: TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            items: _ttoOptions.map((tto) {
                              return DropdownMenuItem<String>(
                                value: tto.value,
                                child: Text(
                                  tto.label,
                                  style: const TextStyle(
                                    fontFamily: 'DM Sans',
                                    fontSize: 17,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() => _selectedTto = value);
                              field.didChange(value);
                            },
                          ),
                        ),
                      ),
                      if (field.hasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text(
                            field.errorText!,
                            style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 13,
                              color: Colors.red,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 30),
              PrimaryPillButton(
                label: 'Volgende',
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _submit,
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
