import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/features/signup/signup_form_state.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_shell_scaffold.dart';
import '../../../widgets/shell_text_field.dart';
import '../../../widgets/secondary_pill_button.dart';
import '../../../widgets/footer_note.dart';
import '../../../widgets/inline_error_banner.dart';

class SignupStep2Screen extends StatefulWidget {
  const SignupStep2Screen({super.key});

  @override
  State<SignupStep2Screen> createState() => _SignupStep2ScreenState();
}

class _SignupStep2ScreenState extends State<SignupStep2Screen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _repeatController = TextEditingController();
  String? _serverError;

  @override
  void dispose() {
    _passwordController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<SignupFormState>().setPassword(_passwordController.text);
    context.push('/signup/vehicle');
  }

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Wachtwoord',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Maak een wachtwoord aan',
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
                label: 'Wachtwoord*',
                hint: 'Vul uw wachtwoord in',
                controller: _passwordController,
                obscure: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Verplicht veld';
                  if (v.length < 8) return 'Minimaal 8 tekens';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ShellTextField(
                label: 'Herhaal wachtwoord*',
                hint: 'Herhaal uw wachtwoord',
                controller: _repeatController,
                obscure: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Verplicht veld';
                  if (v != _passwordController.text) {
                    return 'Wachtwoorden komen niet overeen';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),
              SecondaryPillButton(label: 'Volgende', onPressed: _submit),
              const SizedBox(height: 24),
              const FooterNote(),
            ],
          ),
        ),
      ),
    );
  }
}
