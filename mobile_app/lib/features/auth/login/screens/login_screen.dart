import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/dialogs.dart';
import 'package:mobile_app/core/navigation/post_auth_target.dart';
import 'package:mobile_app/core/theme.dart';
import 'package:mobile_app/features/auth/auth_gate_state.dart';
import 'package:mobile_app/features/compliance/terms_of_use/terms_gate_state.dart';
import 'package:mobile_app/features/compliance/privacy/privacy_gate_state.dart';
import 'package:mobile_app/features/compliance/privacy/services/privacy_service.dart';
import 'package:mobile_app/widgets/app_logo_row.dart';
import 'package:mobile_app/widgets/footer_note.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LoginScreen extends StatefulWidget {
  final String? next;

  const LoginScreen({super.key, this.next});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _secureStorage = const FlutterSecureStorage();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberEmail = true;

  static const _rememberedEmailKey = 'remembered_login_email';

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedEmail() async {
    final rememberedEmail = await _secureStorage.read(key: _rememberedEmailKey);

    if (!mounted) return;

    if (rememberedEmail != null && rememberedEmail.isNotEmpty) {
      _emailController.text = rememberedEmail;
      setState(() {
        _rememberEmail = true;
      });
    }
  }

  Future<void> _submit() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      await showAppAlert(
        context: context,
        title: 'Gegevens vereist',
        message: 'Vul uw emailadres en wachtwoord in.',
        svgAsset: 'assets/warning-badge.svg',
      );
      return;
    }

    setState(() => _isLoading = true);

    final authGate = context.read<AuthGateState>();
    final privacyGate = context.read<PrivacyGateState>();
    final termsGate = context.read<TermsGateState>();

    try {
      await _authService.login(email: email, password: password);
    } catch (_) {
      if (!mounted) return;

      authGate.markUnauthenticated();
      privacyGate.reset();
      termsGate.reset();

      setState(() => _isLoading = false);

      await showAppAlert(
        context: context,
        title: 'Toegang geweigerd',
        message: 'Ongeldige inloggegevens.',
        svgAsset: 'assets/pop-up-denied.svg',
      );

      return;
    }

    try {
      if (_rememberEmail) {
        await _secureStorage.write(key: _rememberedEmailKey, value: email);
      } else {
        await _secureStorage.delete(key: _rememberedEmailKey);
      }

      TextInput.finishAutofillContext();

      final bootstrap = await PrivacyService().fetchBootstrapStatus();

      if (!mounted) return;

      final target = resolvePostAuthTarget(widget.next);

      if (bootstrap.privacyPolicyRequired) {
        privacyGate.reset();
        termsGate.reset();
        authGate.markAuthenticated();

        context.go('/privacy?next=${Uri.encodeComponent(target)}');
        return;
      }

      privacyGate.markAccepted();

      if (bootstrap.termsOfUseRequired) {
        termsGate.reset();
        authGate.markAuthenticated();

        context.go('/terms?next=${Uri.encodeComponent(target)}');
        return;
      }

      termsGate.markAccepted();

      authGate.markAuthenticated();

      context.go(target);
    } catch (e, stackTrace) {
      debugPrint('Post-login flow failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      authGate.markAuthenticated();
      privacyGate.reset();
      termsGate.reset();

      context.go('/locations');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: kGradientBg,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: AutofillGroup(
                      child: Form(
                        key: _formKey,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: constraints.maxWidth * 0.06,
                            vertical: constraints.maxHeight * 0.045,
                          ),
                          child: Column(
                            children: [
                              const Spacer(),

                              const AppLogoRow(),
                              SizedBox(height: constraints.maxHeight * 0.012),

                              Text(
                                'Meld je hieronder aan met je account en wachtwoord',
                                style: AppTextStyles.lead.copyWith(
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              SizedBox(height: constraints.maxHeight * 0.04),

                              _LabeledInput(
                                label: 'Emailadres',
                                hint: 'naam@email.nl',
                                obscure: false,
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [
                                  AutofillHints.username,
                                  AutofillHints.email,
                                ],
                                textInputAction: TextInputAction.next,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Vul uw emailadres in.'
                                    : null,
                              ),

                              SizedBox(height: constraints.maxHeight * 0.018),

                              _LabeledInput(
                                label: 'Wachtwoord',
                                hint: '••••••••',
                                obscure: _obscurePassword,
                                controller: _passwordController,
                                keyboardType: TextInputType.visiblePassword,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) {
                                  if (!_isLoading) _submit();
                                },
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: AppColors.textSubtle,
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Vul uw wachtwoord in.'
                                    : null,
                              ),

                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberEmail,
                                    onChanged: (value) {
                                      setState(
                                        () => _rememberEmail = value ?? true,
                                      );
                                    },
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(
                                          () =>
                                              _rememberEmail = !_rememberEmail,
                                        );
                                      },
                                      child: Text(
                                        'E-mailadres onthouden',
                                        style: AppTextStyles.lead.copyWith(
                                          fontSize: 13,
                                          color: AppColors.textSubtle,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              SizedBox(height: constraints.maxHeight * 0.03),

                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _submit,
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Inloggen'),
                                ),
                              ),

                              SizedBox(height: constraints.maxHeight * 0.03),

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

                              SizedBox(height: constraints.maxHeight * 0.01),

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
                ),
              );
            },
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
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  const _LabeledInput({
    required this.label,
    required this.hint,
    required this.obscure,
    this.controller,
    this.validator,
    this.suffixIcon,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.onFieldSubmitted,
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
            keyboardType: keyboardType,
            autofillHints: autofillHints,
            textInputAction: textInputAction,
            onFieldSubmitted: onFieldSubmitted,
            autocorrect: false,
            enableSuggestions: !obscure,
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
              suffixIcon: suffixIcon,
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
