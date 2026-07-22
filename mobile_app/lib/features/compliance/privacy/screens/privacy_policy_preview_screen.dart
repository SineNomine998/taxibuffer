import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme.dart';
import '../../../auth/signup/signup_form_state.dart';
import '../services/privacy_service.dart';

class PrivacyPolicyPreviewScreen extends StatefulWidget {
  const PrivacyPolicyPreviewScreen({super.key});

  @override
  State<PrivacyPolicyPreviewScreen> createState() =>
      _PrivacyPolicyPreviewScreenState();
}

class _PrivacyPolicyPreviewScreenState
    extends State<PrivacyPolicyPreviewScreen> {
  final _service = PrivacyService();
  final _scrollController = ScrollController();

  PrivacyPolicyData? _policy;
  bool _isLoading = true;
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
      final policy = await _service.fetchPublicPrivacyPolicy();
      if (!mounted) return;
      setState(() => _policy = policy);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;

        if (_scrollController.position.maxScrollExtent <= 0) {
          setState(() => _hasScrolledToBottom = true);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Kon privacyverklaring niet laden.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _accept() {
    final policy = _policy;
    if (policy == null) return;

    context.read<SignupFormState>().acceptPrivacyPolicy(policy.version);
    context.pop();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        title: const Text('Privacyverklaring'),
        backgroundColor: const Color(0xFFE0BD22),
        foregroundColor: const Color(0xFF222222),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gradientStart),
            )
          : _error != null
          ? Center(child: Text(_error!))
          : Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(16),
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
                        policy?.bodyNl ?? '',
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
                            'Scroll naar beneden om te bevestigen.',
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
                          onPressed: _hasScrolledToBottom ? _accept : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE0BD22),
                            foregroundColor: const Color(0xFF222222),
                            disabledBackgroundColor: const Color(0xFFE5E7EB),
                            disabledForegroundColor: const Color(0xFF9CA3AF),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: const Text(
                            'Ik heb dit gelezen en begrepen',
                            style: TextStyle(
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
    );
  }
}
