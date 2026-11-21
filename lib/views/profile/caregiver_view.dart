import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/status_colors.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/caregiver_viewmodel.dart';
import '../../viewmodels/intake_viewmodel.dart';
import '../../viewmodels/inventory_viewmodel.dart';
import '../../viewmodels/medication_viewmodel.dart';

/// Caregiver linking screen implementing:
/// 1. 6-character single-use pairing code generation with 24-hour countdown timer.
/// 2. Pairing code redemption dialog.
/// 3. Bi-directional link management with instant revocation.
/// 4. Profile switching into Caregiver Read-Only mode.
class CaregiverView extends StatefulWidget {
  const CaregiverView({super.key});

  @override
  State<CaregiverView> createState() => _CaregiverViewState();
}

class _CaregiverViewState extends State<CaregiverView> {
  final TextEditingController _codeController = TextEditingController();
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authVm = context.read<AuthViewModel>();
      if (authVm.isAuthenticated) {
        context
            .read<CaregiverViewModel>()
            .loadCaregiverData(authVm.currentUserId);
      }
    });

    // Tick countdown every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    if (d <= Duration.zero) return 'Expired';
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  void _showRedeemDialog() {
    _codeController.clear();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Pairing Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the ${AppConstants.caregiverInviteCodeLength}-character single-use pairing code shared by the patient to link as their caregiver.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) {
                  final cleaned = newValue.text
                      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
                      .toUpperCase();
                  final truncated =
                      cleaned.length > AppConstants.caregiverInviteCodeLength
                          ? cleaned.substring(
                              0, AppConstants.caregiverInviteCodeLength)
                          : cleaned;
                  return TextEditingValue(
                    text: truncated,
                    selection: TextSelection.collapsed(
                      offset: truncated.length,
                    ),
                  );
                }),
              ],
              maxLength: AppConstants.caregiverInviteCodeLength,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                labelText: 'Pairing Code',
                hintText: 'e.g. ABC234',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final code = _codeController.text
                  .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
                  .toUpperCase();
              if (code.length != AppConstants.caregiverInviteCodeLength) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Please enter a valid 6-character code.')),
                );
                return;
              }
              Navigator.pop(ctx);
              final authVm = context.read<AuthViewModel>();
              final caregiverVm = context.read<CaregiverViewModel>();
              final success = await caregiverVm.redeemPairingCode(
                code: code,
                caregiverId: authVm.currentUserId,
                caregiverName: authVm.currentUserDisplayName,
              );

              if (mounted) {
                final scheme = Theme.of(context).colorScheme;
                final statusColors = StatusColors.of(context);
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(caregiverVm.successMessage ??
                          'Caregiver link established!'),
                      backgroundColor:
                          statusColors?.taken ?? scheme.secondary,
                    ),
                  );
                } else if (caregiverVm.errorMessage != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(caregiverVm.errorMessage!),
                      backgroundColor: scheme.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Link Account'),
          ),
        ],
      ),
    );
  }

  void _confirmRevoke({
    required String patientId,
    required String caregiverId,
    required String displayName,
    required bool isDependent,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Caregiver Access?'),
        content: Text(
          isDependent
              ? 'Are you sure you want to stop caring for $displayName? You will immediately lose read access to their schedules and medication balances.'
              : 'Are you sure you want to revoke $displayName\'s caregiver access? They will no longer be able to view your medication records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final authVm = context.read<AuthViewModel>();
              final caregiverVm = context.read<CaregiverViewModel>();
              final messenger = ScaffoldMessenger.of(context);
              final takenColor = StatusColors.of(context)?.taken ??
                  Theme.of(context).colorScheme.secondary;
              final errorColor = Theme.of(context).colorScheme.error;
              await caregiverVm.revokeCaregiverAccess(
                patientId: patientId,
                caregiverId: caregiverId,
                currentUserId: authVm.currentUserId,
              );
              if (mounted) {
                if (caregiverVm.successMessage != null) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(caregiverVm.successMessage!),
                      backgroundColor: takenColor,
                    ),
                  );
                } else if (caregiverVm.errorMessage != null) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(caregiverVm.errorMessage!),
                      backgroundColor: errorColor,
                    ),
                  );
                }
              }
            },
            child: const Text('Revoke Access'),
          ),
        ],
      ),
    );
  }

  void _switchProfile(String? targetProfileId, String? targetName) {
    final caregiverVm = context.read<CaregiverViewModel>();
    final authVm = context.read<AuthViewModel>();
    final medVm = context.read<MedicationViewModel>();
    final intakeVm = context.read<IntakeViewModel>();
    final invVm = context.read<InventoryViewModel>();

    caregiverVm.setActiveProfile(targetProfileId, targetName);

    final effectiveUid = targetProfileId ?? authVm.currentUserId;
    medVm.listenToMedications(
      effectiveUid,
      isOwnProfile: targetProfileId == null,
    );
    intakeVm.listenToIntakeLogs(effectiveUid);
    invVm.listenToInventory(
      effectiveUid,
      isOwnProfile: targetProfileId == null,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          targetProfileId == null
              ? 'Switched back to your personal profile.'
              : 'Switched to $targetName (Caregiver Read-Only Mode).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caregiverVm = context.watch<CaregiverViewModel>();
    final authVm = context.watch<AuthViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Caregiver & Linking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh links',
            onPressed: () =>
                caregiverVm.loadCaregiverData(authVm.currentUserId),
          ),
        ],
      ),
      body: caregiverVm.isLoading &&
              caregiverVm.myCaregivers.isEmpty &&
              caregiverVm.myDependents.isEmpty &&
              caregiverVm.activeInvite == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  caregiverVm.loadCaregiverData(authVm.currentUserId),
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  if (caregiverVm.errorMessage != null) ...[
                    Material(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                caregiverVm.errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Dismiss',
                              visualDensity: VisualDensity.compact,
                              onPressed: caregiverVm.clearMessages,
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Caregiver Mode Info Banner
                  Card(
                    color: theme.colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.family_restroom,
                              size: 36, color: theme.colorScheme.secondary),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Share With a Caregiver (Private & Protected)',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        theme.colorScheme.onSecondaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Caregivers can only view your schedule, dose history, and remaining medicine count. You can remove their access at any time.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme
                                        .colorScheme.onSecondaryContainer
                                        .withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ==========================================
                  // SECTION 1: MY CAREGIVERS (Patient Role)
                  // ==========================================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'My Caregivers',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        '${caregiverVm.myCaregivers.length} Linked',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Active Pairing Code Card (if exists)
                  if (caregiverVm.activeInvite != null &&
                      !caregiverVm.activeInvite!.isExpired) ...[
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.5)),
                      ),
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.4),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Active Pairing Code',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (StatusColors.of(context)?.lowStock ??
                                            theme.colorScheme.tertiary)
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.timer_outlined,
                                          size: 14,
                                          color: StatusColors.of(context)
                                                  ?.lowStock ??
                                              theme.colorScheme.tertiary),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDuration(caregiverVm
                                            .activeInvite!.timeRemaining),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: StatusColors.of(context)
                                                  ?.lowStock ??
                                              theme.colorScheme.tertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Builder(
                              builder: (context) {
                                final inviteCode =
                                    caregiverVm.activeInvite!.code;
                                void copyCode() {
                                  Clipboard.setData(
                                      ClipboardData(text: inviteCode));
                                  ScaffoldMessenger.of(context)
                                    ..clearSnackBars()
                                    ..showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Pairing code copied to clipboard!'),
                                      ),
                                    );
                                }

                                return Semantics(
                                  button: true,
                                  label: 'Copy pairing code $inviteCode',
                                  child: Material(
                                    color: theme.colorScheme.surface,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                          color:
                                              theme.colorScheme.outlineVariant),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      key: const ValueKey<String>(
                                          'caregiver_pairing_code_tile'),
                                      onTap: copyCode,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 12),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Flexible(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  inviteCode,
                                                  style: const TextStyle(
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.w900,
                                                    letterSpacing: 6,
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.copy_rounded),
                                              tooltip: 'Copy Code',
                                              onPressed: copyCode,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Share this 6-character code with your caregiver. Single-use only (expires in 24 hours).',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Button to generate new code
                  OutlinedButton.icon(
                    onPressed: caregiverVm.isMutating
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final takenBg = StatusColors.of(context)?.taken ??
                                theme.colorScheme.secondary;
                            final errorBg = theme.colorScheme.error;
                            final invite =
                                await caregiverVm.generatePairingCode(
                              patientId: authVm.currentUserId,
                              patientName: authVm.currentUserDisplayName,
                            );
                            if (!mounted) return;
                            if (invite != null) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Pairing code generated: ${invite.code}'),
                                  backgroundColor: takenBg,
                                ),
                              );
                            } else {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    caregiverVm.errorMessage ??
                                        'Unable to generate pairing code. Please try again.',
                                  ),
                                  backgroundColor: errorBg,
                                ),
                              );
                            }
                          },
                    icon: caregiverVm.isMutating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.vpn_key_rounded),
                    label: Text(
                      caregiverVm.isMutating
                          ? 'Generating Pairing Code...'
                          : (caregiverVm.activeInvite != null &&
                                  !caregiverVm.activeInvite!.isExpired
                              ? 'Generate New Pairing Code'
                              : 'Generate 24h Pairing Code'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // List of linked caregivers
                  if (caregiverVm.myCaregivers.isEmpty)
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'No caregivers currently linked. Tap "Generate 24h Pairing Code" above to invite a caregiver.',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    ...caregiverVm.myCaregivers.map((rel) {
                      final shortId = rel.caregiverId.length >= 6
                          ? rel.caregiverId.substring(0, 6)
                          : rel.caregiverId;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        tileColor: theme.colorScheme.surfaceContainerHigh,
                        leading: const CircleAvatar(
                            child: Icon(Icons.person_outline)),
                        title: Text(rel.caregiverName ?? 'Caregiver ($shortId)'),
                        subtitle: const Text('Read-Only Access • Linked'),
                        trailing: TextButton(
                          onPressed: () => _confirmRevoke(
                            patientId: rel.patientId,
                            caregiverId: rel.caregiverId,
                            displayName: rel.caregiverName ?? 'Caregiver',
                            isDependent: false,
                          ),
                          child: Text('Revoke',
                              style: TextStyle(color: theme.colorScheme.error)),
                        ),
                      );
                    }),

                  const SizedBox(height: 32),

                  // ==========================================
                  // SECTION 2: MY DEPENDENTS (Caregiver Role)
                  // ==========================================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'My Dependents & Patients',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        '${caregiverVm.myDependents.length} Linked',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  FilledButton.icon(
                    onPressed: _showRedeemDialog,
                    icon: const Icon(Icons.add_link_rounded),
                    label: const Text('Enter Pairing Code to Link Patient'),
                  ),
                  const SizedBox(height: 12),

                  // Personal profile tile (Me)
                  ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    tileColor: caregiverVm.activeProfileId == null
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHigh,
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text('${authVm.currentUserDisplayName} (My Data)'),
                    subtitle: const Text('Full Edit & Logging Privileges'),
                    trailing: caregiverVm.activeProfileId == null
                        ? Icon(Icons.check_circle,
                            color: StatusColors.of(context)?.taken ??
                                theme.colorScheme.secondary)
                        : TextButton(
                            onPressed: () => _switchProfile(null, null),
                            child: const Text('Switch Here'),
                          ),
                    onTap: () => _switchProfile(null, null),
                  ),
                  const SizedBox(height: 8),

                  // Dependents profile tiles
                  if (caregiverVm.myDependents.isEmpty)
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'You are not currently linked as a caregiver for any patients. Tap "Enter Pairing Code" above if a patient gave you a code.',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    ...caregiverVm.myDependents.map((rel) {
                      final isSelected =
                          caregiverVm.activeProfileId == rel.patientId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          tileColor: isSelected
                              ? theme.colorScheme.secondaryContainer
                              : theme.colorScheme.surfaceContainerHigh,
                          leading: CircleAvatar(
                            backgroundColor:
                                isSelected ? theme.colorScheme.secondary : null,
                            child: const Icon(Icons.family_restroom),
                          ),
                          title: Text(rel.patientName),
                          subtitle: Text(
                            isSelected
                                ? 'Currently Viewing (Read-Only Mode)'
                                : 'Tap to switch profile',
                            style: TextStyle(
                              color: isSelected
                                  ? theme.colorScheme.secondary
                                  : null,
                              fontWeight: isSelected ? FontWeight.bold : null,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSelected)
                                Icon(Icons.visibility,
                                    color: theme.colorScheme.primary)
                              else
                                TextButton(
                                  onPressed: () => _switchProfile(
                                      rel.patientId, rel.patientName),
                                  child: const Text('View'),
                                ),
                              IconButton(
                                icon: Icon(Icons.link_off_rounded,
                                    color: theme.colorScheme.error, size: 20),
                                tooltip: 'Revoke Link',
                                onPressed: () => _confirmRevoke(
                                  patientId: rel.patientId,
                                  caregiverId: rel.caregiverId,
                                  displayName: rel.patientName,
                                  isDependent: true,
                                ),
                              ),
                            ],
                          ),
                          onTap: () =>
                              _switchProfile(rel.patientId, rel.patientName),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
