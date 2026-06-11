import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/theme.dart';
import 'package:mobile_app/widgets/app_logo_row.dart';
import 'package:mobile_app/widgets/footer_note.dart';
import 'package:mobile_app/widgets/pill_button.dart';

class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});
  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  final _controller = PageController();
  int _page = 0;

  final _pages = [
    _InfoPage(
      title: 'Welkom!',
      body:
          'In de Taxi Buffer meld je je eenvoudig aan zodra je in de '
          'bufferzone staat.\n\nJe ontvangt automatisch een oproep '
          'wanneer je aan de beurt bent.',
    ),
    _InfoPage(
      title: 'Waarom dit systeem?',
      body:
          'Met de Taxi Buffer voorkomen we files en overlast op de pier.'
          '\n\nZo houden we het veilig voor passagiers en eerlijk voor '
          'alle chauffeurs.',
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      context.go('/login'); // GoRouter
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: kGradientBg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
            child: Column(
              children: [
                const AppLogoRow(),
                const SizedBox(height: 32),

                // Page content
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemCount: _pages.length,
                    itemBuilder: (_, i) => _pages[i],
                  ),
                ),

                // Dots
                _DotsIndicator(count: _pages.length, current: _page),
                const SizedBox(height: 20),

                PillButton(
                  label: _page == _pages.length - 1 ? 'Aan de slag' : 'Verder',
                  onPressed: _next,
                ),
                const SizedBox(height: 20),
                const FooterNote(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  final int count;
  final int current;

  const _DotsIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: isActive ? 16 : 12,
          height: isActive ? 16 : 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? AppColors.dotActive : AppColors.dotInactive,
            border: Border.all(
              color: isActive
                  ? Colors.black.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.12),
              width: 2,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _InfoPage extends StatelessWidget {
  final String title;
  final String body;

  const _InfoPage({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: AppTextStyles.title, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(body, style: AppTextStyles.lead, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
