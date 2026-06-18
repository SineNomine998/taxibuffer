import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'app_header.dart';
import 'bottom_nav.dart';

class AppShellScaffold extends StatelessWidget {
  final Widget child;
  final bool showHelp;
  final VoidCallback? onHelpTap;
  final bool showBack;
  final VoidCallback? onBackTap;
  final NavTab? activeTab;

  const AppShellScaffold({
    super.key,
    required this.child,
    this.showHelp = false,
    this.onHelpTap,
    this.showBack = false,
    this.onBackTap,
    this.activeTab,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.shellBg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            color: AppColors.cardBg,
            child: Column(
              children: [
                AppHeader(
                  showHelp: showHelp,
                  onHelpTap: onHelpTap,
                  showBack: showBack,
                  onBackTap: onBackTap,
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: activeTab != null
          ? SizedBox(
              width: double.infinity,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: BottomNav(activeTab: activeTab),
                ),
              ),
            )
          : null,
    );
  }
}
