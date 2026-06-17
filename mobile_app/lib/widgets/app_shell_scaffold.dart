import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'app_header.dart';
import 'bottom_nav.dart';

class AppShellScaffold extends StatelessWidget {
  final Widget child;
  final bool showHelp;
  final VoidCallback? onHelpTap;
  final NavTab? activeTab; // null = no bottom nav (signup flow)

  const AppShellScaffold({
    super.key,
    required this.child,
    this.showHelp = false,
    this.onHelpTap,
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
                AppHeader(showHelp: showHelp, onHelpTap: onHelpTap),
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
