import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme.dart';
import '../../../../widgets/app_shell_scaffold.dart';
import '../../../../widgets/primary_pill_button.dart';
import '../../../../widgets/footer_note.dart';

class PasswordResetSentScreen extends StatelessWidget {
  const PasswordResetSentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 32),
        child: Column(
          children: [
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: kGradient,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: const Text('✉', style: TextStyle(fontSize: 34)),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Reset-link verzonden',
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Als dit e-mailadres bij een account hoort, ontvangt u een bericht met instructies.',
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 15,
                      color: Color(0xFF6B7280),
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Controleer ook uw spamfolder.',
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 15,
                      color: Color(0xFF6B7280),
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  PrimaryPillButton(
                    label: 'Terug naar login',
                    onPressed: () => context.go('/login'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const FooterNote(),
          ],
        ),
      ),
    );
  }
}
