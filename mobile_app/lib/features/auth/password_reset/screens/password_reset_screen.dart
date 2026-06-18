import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/dialogs.dart';
import 'package:mobile_app/features/auth/services/auth_service.dart';
import '../../../../widgets/app_shell_scaffold.dart';
import '../../../../widgets/primary_pill_button.dart';
import '../../../../widgets/shell_text_field.dart';
import '../../../../widgets/footer_note.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_recheck);
  }

  void _recheck() {
    final valid = _emailController.text.trim().contains('@');
    if (valid != _isValid) setState(() => _isValid = valid);
  }

  @override
  void dispose() {
    _emailController.removeListener(_recheck);
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _authService.requestPasswordReset(_emailController.text.trim());
      if (!mounted) return;
      context.go('/password-reset/sent');
    } catch (e) {
      if (!mounted) return;
      await showAppAlert(
        context: context,
        title: 'Fout',
        message: e.toString(),
        svgAsset: 'assets/pop-up-denied.svg',
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
                'Wachtwoord vergeten',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Vul uw e-mailadres in. U ontvangt een link om een nieuw wachtwoord in te stellen.',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 15,
                  color: Color(0xFF313131),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(color: const Color(0xFFECEEF3)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ShellTextField(
                      label: 'E-mailadres',
                      hint: 'naam@email.nl',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Verplicht veld';
                        }
                        if (!v.contains('@')) return 'Ongeldig e-mailadres';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    Opacity(
                      opacity: _isValid && !_isLoading ? 1.0 : 0.4,
                      child: IgnorePointer(
                        ignoring: !_isValid || _isLoading,
                        child: PrimaryPillButton(
                          label: _isLoading ? 'Bezig...' : 'Stuur reset-link',
                          onPressed: _submit,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: const Center(
                        child: Text(
                          'Terug naar login',
                          style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
