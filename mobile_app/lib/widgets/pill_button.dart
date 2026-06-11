import 'package:flutter/material.dart';
import 'package:mobile_app/core/theme.dart';

class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const PillButton({required this.label, required this.onPressed, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Text(label, style: AppTextStyles.buttonText),
      ),
    );
  }
}
