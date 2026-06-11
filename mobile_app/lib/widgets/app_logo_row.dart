import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mobile_app/core/theme.dart';

class AppLogoRow extends StatelessWidget {
  const AppLogoRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset('assets/logo.svg', height: 44),
        const SizedBox(width: 14),
        const Text('TAXIBUFFER', style: AppTextStyles.brandLabel),
      ],
    );
  }
}