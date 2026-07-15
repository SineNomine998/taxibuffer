import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/config/api_client.dart';
import 'package:mobile_app/core/theme.dart';
import 'package:mobile_app/features/compliance/terms_of_use/terms_gate_state.dart';
import 'package:mobile_app/widgets/primary_pill_button.dart';
import 'package:provider/provider.dart';

import '../models/terms_of_use_data.dart';
import '../services/terms_service.dart';

class TermsOfUseScreen extends StatefulWidget {
  final String? next;

  const TermsOfUseScreen({super.key, this.next});

  @override
  State<TermsOfUseScreen> createState() => _TermsOfUseScreenState();
}

class _TermsOfUseScreenState extends State<TermsOfUseScreen> {
  final TermsService _service = TermsService();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _accepting = false;
  bool _canAccept = false;
  String? _error;
  TermsOfUseData? _terms;

  @override
  void initState() {
    super.initState();
    _load();

    _scrollController.addListener(() {
      if (!_scrollController.hasClients || _canAccept) return;

      final position = _scrollController.position;

      if (position.pixels >= position.maxScrollExtent - 40) {
        setState(() => _canAccept = true);
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final terms = await _service.fetchTermsOfUse();

      if (!mounted) return;

      if (terms.accepted) {
        context.read<TermsGateState>().markAccepted();
        context.go(widget.next ?? '/locations');
        return;
      }

      setState(() {
        _terms = terms;
        _canAccept = terms.bodyNl.length < 900;
      });
    } on ApiAuthException {
      return;
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Kon gebruiksvoorwaarden niet laden.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _accept() async {
    final terms = _terms;
    if (terms == null || _accepting || !_canAccept) return;

    setState(() => _accepting = true);

    try {
      await _service.acceptTermsOfUse(terms.version);

      if (!mounted) return;

      context.read<TermsGateState>().markAccepted();
      final target = widget.next?.isNotEmpty == true
          ? widget.next!
          : '/locations';
      context.go(target);
    } on ApiAuthException {
      return;
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accepteren mislukt. Probeer opnieuw.')),
      );
    } finally {
      if (mounted) {
        setState(() => _accepting = false);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terms = _terms;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.gradientStart,
                ),
              )
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : terms == null
            ? _ErrorState(
                message: 'Geen gebruiksvoorwaarden gevonden.',
                onRetry: _load,
              )
            : Column(
                children: [
                  _Header(title: terms.title),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          terms.bodyNl,
                          style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 14,
                            height: 1.55,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: Column(
                      children: [
                        if (!_canAccept)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Scroll naar beneden om verder te gaan.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 13,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        PrimaryPillButton(
                          label: _accepting
                              ? 'Bezig...'
                              : 'Akkoord en doorgaan',
                          onPressed: _canAccept && !_accepting ? _accept : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;

  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? 'Gebruiksvoorwaarden' : title,
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Lees en accepteer de voorwaarden om TaxiBuffer te gebruiken.',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 15,
              height: 1.35,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE4E6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Er ging iets mis',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 14,
              height: 1.4,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              gradient: kGradient,
              borderRadius: BorderRadius.circular(999),
            ),
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Opnieuw proberen',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: Color(0xFF222222),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
