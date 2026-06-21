import 'dart:math' as math;
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

  static const double _maxWidth = 420;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.shellBg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shellWidth = math.min(constraints.maxWidth, _maxWidth);

            return Center(
              child: SizedBox(
                width: shellWidth,
                height: constraints.maxHeight,
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
            );
          },
        ),
      ),
      bottomNavigationBar: activeTab == null
          ? null
          : LayoutBuilder(
              builder: (context, constraints) {
                final shellWidth = math.min(constraints.maxWidth, _maxWidth);

                return Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: 1,
                  child: SizedBox(
                    width: shellWidth,
                    child: BottomNav(activeTab: activeTab),
                  ),
                );
              },
            ),
    );
  }
}
