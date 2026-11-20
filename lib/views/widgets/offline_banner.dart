import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/connectivity_service.dart';

/// Non-blocking banner displaying network connection status at the top of the interface.
/// When offline, notifies user that Firestore offline persistence is queueing changes.
class OfflineBanner extends StatelessWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService?>();
    final isOnline = connectivity?.isOnline ?? true;
    final theme = Theme.of(context);

    return Column(
      children: [
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 300),
          crossFadeState:
              isOnline ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 18,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Working offline. Doses & changes are saved locally and will sync automatically.',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
