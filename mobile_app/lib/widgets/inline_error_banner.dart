import 'package:flutter/material.dart';
import '../core/theme.dart';

class InlineErrorBanner extends StatelessWidget {
  final String message;

  const InlineErrorBanner({required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: AppColors.errorText,
        ),
      ),
    );
  }
}
