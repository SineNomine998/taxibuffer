import 'package:flutter/material.dart';
import 'package:mobile_app/core/theme.dart';

class FooterNote extends StatelessWidget {
  const FooterNote({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Coding the Curbs® in samenwerking met Gemeente Rotterdam',
      style: AppTextStyles.footer,
      textAlign: TextAlign.center,
    );
  }
}