import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/theme.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final bool showHelp;
  final VoidCallback? onHelpTap;
  final bool showBack;
  final VoidCallback? onBackTap;

  const AppHeader({
    super.key,
    this.showHelp = false,
    this.onHelpTap,
    this.showBack = false,
    this.onBackTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(110);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      decoration: const BoxDecoration(gradient: kGradient),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset('assets/logo.svg', height: 28),
              const SizedBox(width: 12),
              const Text(
                'TAXIBUFFER',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  fontSize: 20,
                  color: Color(0xFF333333),
                ),
              ),
            ],
          ),
          if (showBack)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: onBackTap ?? () => Navigator.of(context).maybePop(),
                child: const SizedBox(
                  width: 36,
                  child: Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
            ),
          if (showHelp)
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                onTap: onHelpTap,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'i',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.black,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
