import 'package:flutter/material.dart';
import '../../core/constants/app_strings.dart';

/// Modal dialog ensuring legal compliance under Republic Act No. 10173 (Philippine Data Privacy Act).
class PrivacyConsentDialog extends StatelessWidget {
  const PrivacyConsentDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              AppStrings.privacyNoticeTitle,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.privacyNoticeBody,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Key Rights Protected:',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                      '• Section 16: Right to Access your intake logs anytime.'),
                  const Text(
                      '• Section 16: Right to Rectify dosage schedules.'),
                  const Text(
                      '• Section 16: Right to Erasure / complete account deletion in Settings.'),
                  const Text(
                      '• Encrypted local persistence and access-controlled cloud sync.'),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStrings.privacyDecline),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(AppStrings.privacyAccept),
        ),
      ],
    );
  }
}
