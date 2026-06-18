import 'package:flutter/material.dart';
import '../core/theme.dart';

class PrimaryPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const PrimaryPillButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;

    return Opacity(
      opacity: isDisabled ? 0.6 : 1,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          gradient: kGradient,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: TextButton(
          onPressed: isDisabled ? null : onPressed,
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF161616),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: Color(0xFF161616),
                  ),
                ),
        ),
      ),
    );
  }
}
