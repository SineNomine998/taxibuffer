import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

  String? _serverError; // populate from API error response

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _rtxController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<SignupFormState>().setPersonalDetails(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      email: _emailController.text.trim(),
      taxiLicenseNumber: _rtxController.text.trim(),
    );
    context.push('/signup/password');
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
              const SizedBox(height: 30),
              PrimaryPillButton(label: 'Volgende', onPressed: _submit),
              const SizedBox(height: 24),
              const FooterNote(),
            ],
          ),
        ),
      ),
    );
  }
}
