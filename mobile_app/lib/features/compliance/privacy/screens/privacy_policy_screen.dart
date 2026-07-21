import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/features/auth/auth_gate_state.dart';
import 'package:mobile_app/features/compliance/terms_of_use/terms_gate_state.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/api_client.dart';
import '../../../../core/theme.dart';
import '../privacy_gate_state.dart';
import '../services/privacy_service.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  final String? next;

  const PrivacyPolicyScreen({super.key, this.next});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  final _service = PrivacyService();
  final _scrollController = ScrollController();

  PrivacyPolicyData? _policy;
  bool _isLoading = true;
  bool _isAccepting = false;
  bool _hasScrolledToBottom = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();

    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;

      final position = _scrollController.position;
      final reachedBottom = position.pixels >= position.maxScrollExtent - 80;

      if (reachedBottom && !_hasScrolledToBottom) {
        setState(() => _hasScrolledToBottom = true);
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final policy = await _service.fetchPrivacyPolicy();

      if (!mounted) return;

      if (policy.accepted) {
        context.read<PrivacyGateState>().markAccepted();
        context.go(widget.next ?? '/locations');
        return;
      }

      setState(() => _policy = policy);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;

        if (_scrollController.position.maxScrollExtent <= 0) {
          setState(() => _hasScrolledToBottom = true);
        }
      });
    } on ApiAuthException {
      if (!mounted) return;

      context.read<AuthGateState>().markUnauthenticated();
      context.read<PrivacyGateState>().reset();
      context.read<TermsGateState>().reset();

      final next = widget.next?.isNotEmpty == true
          ? widget.next!
          : '/locations';
      context.go('/login?next=${Uri.encodeComponent(next)}');
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon privacyverklaring niet laden. Probeer opnieuw.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _accept() async {
    final policy = _policy;
    if (policy == null || _isAccepting) return;

    setState(() => _isAccepting = true);

    try {
      await _service.acceptPrivacyPolicy(policy.version);

      if (!mounted) return;

      context.read<AuthGateState>().markAuthenticated();
      context.read<PrivacyGateState>().markAccepted();

      final target = resolvePostAuthTarget(widget.next);
      context.go(target);
    } on ApiAuthException {
      if (!mounted) return;

      context.read<AuthGateState>().markUnauthenticated();
      context.read<PrivacyGateState>().reset();
      context.read<TermsGateState>().reset();

      context.go('/login?next=${Uri.encodeComponent('/locations')}');
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kon privacyverklaring niet accepteren.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isAccepting = false);
      }
    }
  }

  String resolvePostAuthTarget(String? next) {
    if (next == null || next.trim().isEmpty) return '/locations';

    final uri = Uri.tryParse(next);
    if (uri == null) return '/locations';

    final path = uri.path;

    final blockedPaths = {
      '/',
      '/info',
      '/login',
      '/signup',
      '/privacy',
      '/privacy-preview',
      '/terms',
      '/terms-preview',
      '/password-reset',
      '/password-reset/sent',
    };

    if (blockedPaths.contains(path)) return '/locations';
    if (path.startsWith('/signup')) return '/locations';
    if (!path.startsWith('/')) return '/locations';

    return next;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;

    if (policy == null || policy.bodyNl.trim().isEmpty) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: const Color(0xFFF7F7F7),
          body: SafeArea(
            child: _ErrorState(
              message: 'Privacyverklaring kon niet worden geladen.',
              onRetry: _load,
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        body: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.gradientStart,
                  ),
                )
              : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            policy.title,
                            style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Lees deze verklaring en bevestig deze om TaxiBuffer te gebruiken.',
                            style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 14,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: Text(
                            policy.bodyNl,
                            style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 14,
                              height: 1.45,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                      child: Column(
                        children: [
                          if (!_hasScrolledToBottom)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Scroll naar beneden om verder te gaan.',
                                style: TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 13,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: !_hasScrolledToBottom || _isAccepting
                                  ? null
                                  : _accept,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE0BD22),
                                foregroundColor: const Color(0xFF222222),
                                disabledBackgroundColor: const Color(
                                  0xFFE5E7EB,
                                ),
                                disabledForegroundColor: const Color(
                                  0xFF9CA3AF,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              child: Text(
                                _isAccepting
                                    ? 'Bezig...'
                                    : 'Ik heb dit gelezen en begrepen',
                                style: const TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 15,
                color: Color(0xFF8A1C1C),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: onRetry,
              child: const Text('Opnieuw proberen'),
            ),
          ],
        ),
      ),
    );
  }
}
