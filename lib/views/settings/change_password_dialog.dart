import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/status_colors.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../widgets/custom_text_field.dart';

/// Dialog allowing password-authenticated users to change their password
/// (or Google/Apple-only users to set a password for email sign-in).
class ChangePasswordDialog extends StatefulWidget {
  final bool isSetPasswordMode;

  const ChangePasswordDialog({
    super.key,
    this.isSetPasswordMode = false,
  });

  static Future<bool> show(
    BuildContext context, {
    bool isSetPasswordMode = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangePasswordDialog(
        isSetPasswordMode: isSetPasswordMode,
      ),
    );
    return result ?? false;
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;
  bool _isSendingReset = false;
  String _newPasswordInput = '';
  String? _inlineError;
  String? _inlineInfo;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(_onNewPasswordChanged);
  }

  void _onNewPasswordChanged() {
    if (_newPasswordInput != _newPasswordController.text) {
      setState(() {
        _newPasswordInput = _newPasswordController.text;
        _inlineError = null;
      });
    }
  }

  @override
  void dispose() {
    _newPasswordController.removeListener(_onNewPasswordChanged);
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleForgotCurrentPassword() async {
    final authVm = context.read<AuthViewModel>();
    final email = authVm.currentUserEmail.trim();
    if (email.isEmpty) {
      setState(() {
        _inlineError = 'No email address is associated with this account.';
      });
      return;
    }

    setState(() {
      _isSendingReset = true;
      _inlineError = null;
      _inlineInfo = null;
    });

    await authVm.sendPasswordReset(email);
    if (!mounted) return;

    setState(() {
      _isSendingReset = false;
      if (authVm.errorMessage != null) {
        _inlineError = authVm.errorMessage;
      } else {
        _inlineInfo =
            'Password reset email sent to $email. Check your inbox or spam folder.';
      }
    });
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;
    setState(() {
      _inlineError = null;
      _inlineInfo = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    final authVm = context.read<AuthViewModel>();

    final result = widget.isSetPasswordMode
        ? await authVm.setPassword(newPassword: _newPasswordController.text)
        : await authVm.changePassword(
            currentPassword: _currentPasswordController.text,
            newPassword: _newPasswordController.text,
          );

    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmitting = false;
        _inlineError = result.errorOrNull?.message ??
            authVm.errorMessage ??
            'Could not update password. Please try again.';
      });
    }
  }

  Widget _buildPasswordStrengthMeter(ThemeData theme) {
    if (_newPasswordInput.isEmpty) {
      return const SizedBox.shrink();
    }

    final strength = AuthViewModel.evaluatePasswordStrength(_newPasswordInput);
    final hasMinLength =
        _newPasswordInput.length >= AppConstants.minPasswordLength;
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(_newPasswordInput);
    final hasNumber = RegExp(r'[0-9]').hasMatch(_newPasswordInput);

    int activeBars = 1;
    switch (strength) {
      case PasswordStrength.weak:
        activeBars = 1;
        break;
      case PasswordStrength.fair:
        activeBars = 2;
        break;
      case PasswordStrength.good:
        activeBars = 3;
        break;
      case PasswordStrength.strong:
        activeBars = 4;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            for (int i = 0; i < 4; i++)
              Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < 3 ? 6.0 : 0.0),
                  decoration: BoxDecoration(
                    color: i < activeBars
                        ? strength.color
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Security: ${strength.label}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: strength.color,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${_newPasswordInput.length} chars',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildRequirementRow(
          theme,
          'At least ${AppConstants.minPasswordLength} characters',
          hasMinLength,
        ),
        _buildRequirementRow(theme, 'Contains at least one letter', hasLetter),
        _buildRequirementRow(theme, 'Contains at least one number', hasNumber),
      ],
    );
  }

  Widget _buildRequirementRow(ThemeData theme, String text, bool satisfied) {
    final takenColor =
        StatusColors.of(context)?.taken ?? const Color(0xFF40A02B);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(
            satisfied
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 14,
            color:
                satisfied ? takenColor : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: satisfied
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: satisfied ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authVm = context.watch<AuthViewModel>();
    final isBusy = _isSubmitting || authVm.isChangingPassword;
    final titleText =
        widget.isSetPasswordMode ? 'Set a Password' : 'Change Password';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.lock_reset_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titleText,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.isSetPasswordMode
                        ? 'Create a password so you can also sign in with your email address.'
                        : 'Verify your current password and choose a strong new password. Other signed-in devices may need to sign in again.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!widget.isSetPasswordMode) ...[
                    CustomTextField(
                      controller: _currentPasswordController,
                      label: 'Current Password',
                      hint: 'Enter current password',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: _obscureCurrent,
                      enabled: !isBusy,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.password],
                      maxLength: AppConstants.maxPasswordLength,
                      suffixIcon: IconButton(
                        tooltip: _obscureCurrent
                            ? 'Show current password'
                            : 'Hide current password',
                        icon: Icon(
                          _obscureCurrent
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscureCurrent = !_obscureCurrent),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Please enter your current password.';
                        }
                        return null;
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: (isBusy || _isSendingReset)
                            ? null
                            : _handleForgotCurrentPassword,
                        child: Text(
                          _isSendingReset
                              ? 'Sending reset link...'
                              : 'Forgot current password?',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  CustomTextField(
                    controller: _newPasswordController,
                    label: 'New Password',
                    hint: 'At least 8 characters with letters & numbers',
                    prefixIcon: Icons.vpn_key_outlined,
                    obscureText: _obscureNew,
                    enabled: !isBusy,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    maxLength: AppConstants.maxPasswordLength,
                    suffixIcon: IconButton(
                      tooltip: _obscureNew
                          ? 'Show new password'
                          : 'Hide new password',
                      icon: Icon(
                        _obscureNew
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please enter a new password.';
                      }
                      if (v != v.trim()) {
                        return 'Password cannot start or end with spaces.';
                      }
                      if (v.length < AppConstants.minPasswordLength ||
                          v.length > AppConstants.maxPasswordLength) {
                        return 'Password must be ${AppConstants.minPasswordLength}-${AppConstants.maxPasswordLength} characters.';
                      }
                      if (!AuthViewModel.isPasswordCompliant(v)) {
                        return 'Password must include both letters and numbers.';
                      }
                      if (!widget.isSetPasswordMode &&
                          v == _currentPasswordController.text) {
                        return 'New password must be different from your current password.';
                      }
                      return null;
                    },
                  ),
                  _buildPasswordStrengthMeter(theme),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: _confirmPasswordController,
                    label: 'Confirm New Password',
                    hint: 'Re-enter new password',
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: _obscureConfirm,
                    enabled: !isBusy,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    maxLength: AppConstants.maxPasswordLength,
                    onFieldSubmitted: (_) => _handleSubmit(),
                    suffixIcon: IconButton(
                      tooltip: _obscureConfirm
                          ? 'Show confirm password'
                          : 'Hide confirm password',
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please confirm your new password.';
                      }
                      if (v != _newPasswordController.text) {
                        return 'Passwords do not match.';
                      }
                      return null;
                    },
                  ),
                  if (_inlineInfo != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _inlineInfo!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  if (_inlineError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer
                            .withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _inlineError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isBusy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: isBusy ? null : _handleSubmit,
          child: isBusy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  ),
                )
              : Text(widget.isSetPasswordMode
                  ? 'Set Password'
                  : 'Update Password'),
        ),
      ],
    );
  }
}
