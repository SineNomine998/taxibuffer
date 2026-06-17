import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/dialogs.dart';
import 'package:mobile_app/core/theme.dart';
import 'package:mobile_app/widgets/app_logo_row.dart';
import 'package:mobile_app/widgets/footer_note.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty) {
      await showAppAlert(
        context: context,
        title: 'Emailadres vereist',
        message: 'Vul uw emailadres in.',
        svgAsset: 'assets/warning-badge.svg',
      );
      return;
    }
    if (password.isEmpty) {
      await showAppAlert(
        context: context,
        title: 'Wachtwoord vereist',
        message: 'Vul uw wachtwoord in.',
        svgAsset: 'assets/warning-badge.svg',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.login(email: email, password: password);

      if (!mounted) return;

      // Navigate after successful login
      context.go('/home');
    } catch (e) {
      if (!mounted) return;

      // on failure:
      await showAppAlert(
        context: context,
        title: 'Toegang Geweigerd',
        message: 'Ongeldige inloggegevens.',
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
    return Scaffold(
      body: Container(
        decoration: kGradientBg,
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 36),
              child: Column(
                children: [
                  const Spacer(),
                  const AppLogoRow(),
                  const SizedBox(height: 10),
                  Text(
                    'Meld je hieronder aan met je account en wachtwoord',
                    style: AppTextStyles.lead.copyWith(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  _LabeledInput(
                    label: 'Emailadres',
                    hint: 'naam@email.nl',
                    obscure: false,
                    controller: _emailController,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Vul uw emailadres in.'
                        : null,
                  ),
                  _LabeledInput(
                    label: 'Wachtwoord',
                    hint: '••••••••',
                    obscure: true,
                    controller: _passwordController,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Vul uw wachtwoord in.'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? CircularProgressIndicator()
                        : Text('Inloggen'),
                  ),
                  const SizedBox(height: 25),
                  GestureDetector(
                    onTap: () => context.go('/signup'),
                    child: RichText(
                      text: TextSpan(
                        style: AppTextStyles.lead.copyWith(
                          fontSize: 14,
                          color: AppColors.textSubtle,
                        ),
                        children: [
                          const TextSpan(text: 'Geen account? '),
                          TextSpan(
                            text: 'Maak er een aan',
                            style: AppTextStyles.registerLink,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => context.go('/password-reset'),
                    child: Text(
                      'Wachtwoord vergeten?',
                      style: AppTextStyles.registerLink,
                    ),
                  ),
                  const Spacer(),
                  const FooterNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledInput extends StatelessWidget {
  final String label;
  final String hint;
  final bool obscure;
  final TextEditingController? controller;
  final String? Function(String?)? validator;

  const _LabeledInput({
    required this.label,
    required this.hint,
    required this.obscure,
    this.controller,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.inputBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscure,
            validator: validator,
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 15,
              color: AppColors.textDark,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 15,
                color: AppColors.textDark.withValues(alpha: 0.45),
              ),
              contentPadding: const EdgeInsets.all(14),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}
