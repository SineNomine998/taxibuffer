import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';

enum NavTab { locations, queue, numbers, account }

class BottomNav extends StatelessWidget {
  final NavTab? activeTab;

  const BottomNav({super.key, this.activeTab});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: kGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                _NavItem(
                  tab: NavTab.locations,
                  active: activeTab == NavTab.locations,
                  label: 'Locaties',
                  icon: Icons.location_on_outlined,
                  onTap: () => context.go('/locations'),
                ),
                _NavItem(
                  tab: NavTab.queue,
                  active: activeTab == NavTab.queue,
                  label: 'Wachtrij',
                  icon: Icons.format_list_bulleted,
                  onTap: () => context.go('/queue'),
                ),
                _NavItem(
                  tab: NavTab.numbers,
                  active: activeTab == NavTab.numbers,
                  label: 'Nummers',
                  icon: Icons.tag,
                  onTap: () => context.go('/numbers'),
                ),
                _NavItem(
                  tab: NavTab.account,
                  active: activeTab == NavTab.account,
                  label: 'Account',
                  icon: Icons.person_outline,
                  onTap: () => context.go('/account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final NavTab tab;
  final bool active;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _NavItem({
    required this.tab,
    required this.active,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.65)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? Colors.black.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: AppColors.navInactive),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navInactive,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
