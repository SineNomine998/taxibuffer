import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../widgets/app_shell_scaffold.dart';
import '../../../widgets/secondary_pill_button.dart';
import '../../../widgets/footer_note.dart';

class LocationSelectionInfoScreen extends StatelessWidget {
  const LocationSelectionInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      showBack: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informatie',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 12),
            const _InfoQA(
              question: 'Wanneer kan ik me aanmelden?',
              answer:
                  'Alleen als je in de bufferzone staat. Dit gebeurt automatisch via je locatie.',
            ),
            const _InfoQA(
              question: 'Hoe werkt de oproep?',
              answer:
                  'Zodra er plek is bij de pier, krijg je een melding. Je kan dan doorrijden naar de ophaallocatie.',
            ),
            const _InfoQA(
              question: 'Wat als ik niet reageer op de oproep?',
              answer:
                  'Je verliest je plek in de wachtrij en moet opnieuw aanmelden.',
            ),
            const _InfoQA(
              question: 'Is het gratis?',
              answer: 'Ja, het gebruik is gratis.',
            ),
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: 200,
                child: SecondaryPillButton(
                  label: 'Ga terug',
                  onPressed: () => context.pop(),
                ),
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

class _InfoQA extends StatelessWidget {
  final String question;
  final String answer;

  const _InfoQA({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 16,
            height: 1.5,
            color: Color(0xFF4B4B4B),
          ),
          children: [
            TextSpan(
              text: '$question\n',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF4B4B4B),
              ),
            ),
            TextSpan(text: answer),
          ],
        ),
      ),
    );
  }
}
