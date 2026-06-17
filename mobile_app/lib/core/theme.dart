import 'package:flutter/material.dart';

class AppColors {
  static const gradientStart = Color(0xFFE0BD22);
  static const gradientEnd = Color(0xFFFEF508);
  static const textDark = Color(0xFF161616);
  static const textMuted = Color(0xFF595959);
  static const textSubtle = Color(0xFF222222);
  static const white = Color(0xFFFFFFFF);
  static const dotInactive = Color(0x26000000);
  static const dotActive = Color(0xFF161616);
  static const shellBg = Color(0xFFECEFF4);
  static const cardBg = Color(0xFFF6F6FC);
  static const surfaceCard = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFECEEF3);
  static const inputBorder = Color(0xFFA9ACB9);
  static const inputFill = Color(0xFFF8F8FB);
  static const titleDark = Color(0xFF111827);
  static const subtitleGray = Color(0xFF6B7280);
  static const errorBg = Color(0xFFFBEAEA);
  static const errorText = Color(0xFF8A1C1C);
  static const navInactive = Color(0xFF2F2F2F);
}

const kGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  stops: [-0.0405, 1.1602],
  colors: [AppColors.gradientStart, AppColors.gradientEnd],
);

// Reusable gradient background (which is used on almost every screen)
BoxDecoration get kGradientBg => const BoxDecoration(gradient: kGradient);

class AppTextStyles {
  static const brandLabel = TextStyle(
    fontFamily: 'DM Sans',
    fontWeight: FontWeight.w800,
    fontSize: 30,
    letterSpacing: 6,
    color: AppColors.textDark,
  );
  static const title = TextStyle(
    fontFamily: 'DM Sans',
    fontWeight: FontWeight.w700,
    fontSize: 22,
    color: AppColors.textDark,
  );
  static const lead = TextStyle(
    fontFamily: 'DM Sans',
    fontWeight: FontWeight.w400,
    fontSize: 15,
    height: 1.6,
    color: AppColors.textDark,
  );
  static const label = TextStyle(
    fontFamily: 'DM Sans',
    fontWeight: FontWeight.w700,
    fontSize: 14,
    color: AppColors.textDark,
  );
  static const footer = TextStyle(
    fontFamily: 'DM Sans',
    fontWeight: FontWeight.w300,
    fontSize: 12,
    fontStyle: FontStyle.italic,
    color: AppColors.textMuted,
  );
  static const buttonText = TextStyle(
    fontFamily: 'DM Sans',
    fontWeight: FontWeight.w800,
    fontSize: 16,
    color: AppColors.textMuted,
  );
  static const registerLink = TextStyle(
    fontFamily: 'DM Sans',
    fontSize: 14,
    color: AppColors.textDark,
    decoration: TextDecoration.underline,
    decorationColor: AppColors.textDark,
  );
}
