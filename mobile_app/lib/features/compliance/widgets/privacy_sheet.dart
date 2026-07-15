import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../privacy/services/privacy_service.dart';

class PrivacyNoticeSheet extends StatefulWidget {
  final PrivacyPolicyData? policy;
  final PrivacyService? service;

  const PrivacyNoticeSheet({this.policy, this.service, super.key});

  static Future<bool?> show(
    BuildContext context, {
    PrivacyService? service,
  }) async {
    final svc = service ?? PrivacyService();
    final policy = await svc.fetchPublicPrivacyPolicy();

    if (!context.mounted) return null;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      builder: (_) => PrivacyNoticeSheet(policy: policy, service: svc),
    );
  }

  @override
  State<PrivacyNoticeSheet> createState() => _PrivacyNoticeSheetState();
}

class _PrivacyNoticeSheetState extends State<PrivacyNoticeSheet> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        16,
        18,
        18 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.dotInactive,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(widget.policy!.title, style: AppTextStyles.title),
          const SizedBox(height: 4),
          Text(
            'Versie ${widget.policy!.version}',
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 14,
              color: AppColors.subtitleGray,
            ),
          ),
          const SizedBox(height: 14),

          // Body card
          Container(
            width: double.infinity,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Text(
                  widget.policy!.bodyNl,
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    height: 1.6,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  color: AppColors.errorText,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Actions
          _buildCloseAction(),
        ],
      ),
    );
  }

  Widget _buildCloseAction() {
    return Center(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            gradient: kGradient,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.inputBorder, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => Navigator.of(context).pop(),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 32),
              child: Text(
                'Sluiten',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF222222),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
