import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../viewmodels/auth_viewmodel.dart';

enum ReauthMethod { password, emailOtp, google, apple }

/// Re-authentication dialog supporting Password, Google, or Email OTP verification
/// before sensitive operations (account deletion, email change, biometric disable).
class ReauthDialog extends StatefulWidget {
  final String title;
  final String reason;
  final bool allowEmailOtp;

  const ReauthDialog({
    super.key,
    required this.title,
    required this.reason,
    this.allowEmailOtp = true,
  });

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String reason,
    bool allowEmailOtp = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ReauthDialog(
        title: title,
        reason: reason,
        allowEmailOtp: allowEmailOtp,
      ),
    );
    return result ?? false;
  }

  @override
  State<ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<ReauthDialog> {
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  ReauthMethod _selectedMethod = ReauthMethod.password;
  bool _isLoading = false;
  bool _otpRequested = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final authVm = context.read<AuthViewModel>();
    if (authVm.isGoogleLinked && !authVm.isPasswordLinked) {
      _selectedMethod = ReauthMethod.google;
    } else if (authVm.isAppleLinked && !authVm.isPasswordLinked) {
      _selectedMethod = ReauthMethod.apple;
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleRequestOtp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authVm = context.read<AuthViewModel>();
    try {
      await authVm.requestEmailOtp(purpose: 'reauth');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _otpRequested = true;
        });
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.message;
        });
      }
    } catch (e, stack) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = ErrorMapper.map(e, stack).message;
        });
      }
    }
  }

  Future<void> _handleConfirm() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authVm = context.read<AuthViewModel>();
    try {
      bool success = false;

      if (_selectedMethod == ReauthMethod.password) {
        if (_passwordController.text.isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Please enter your password.';
          });
          return;
        }
        success = await authVm.reauthenticateForSensitiveAction(
          password: _passwordController.text.trim(),
        );
      } else if (_selectedMethod == ReauthMethod.google) {
        success = await authVm.reauthenticateForSensitiveAction(
          useGoogle: true,
        );
      } else if (_selectedMethod == ReauthMethod.apple) {
        success = await authVm.reauthenticateForSensitiveAction(
          useApple: true,
        );
      } else if (_selectedMethod == ReauthMethod.emailOtp) {
        if (_otpController.text.trim().length != AppConstants.otpCodeLength) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Please enter the 6-digit verification code.';
          });
          return;
        }
        success = await authVm.reauthenticateForSensitiveAction(
          otpCode: _otpController.text.trim(),
        );
      }

      if (!mounted) return;

      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = authVm.errorMessage ?? 'Re-authentication failed.';
        });
      }
    } catch (e, stack) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = ErrorMapper.map(e, stack).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authVm = context.watch<AuthViewModel>();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.security_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.reason,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Method Segmented Switcher
              if ([
                    authVm.isPasswordLinked,
                    authVm.isGoogleLinked,
                    authVm.isAppleLinked,
                    widget.allowEmailOtp,
                  ].where((v) => v).length >
                  1) ...[
                SegmentedButton<ReauthMethod>(
                  segments: [
                    if (authVm.isPasswordLinked)
                      const ButtonSegment(
                        value: ReauthMethod.password,
                        label: Text('Password'),
                        icon: Icon(Icons.password_rounded, size: 16),
                      ),
                    if (authVm.isGoogleLinked)
                      const ButtonSegment(
                        value: ReauthMethod.google,
                        label: Text('Google'),
                        icon: Icon(Icons.g_mobiledata_rounded, size: 18),
                      ),
                    if (authVm.isAppleLinked)
                      const ButtonSegment(
                        value: ReauthMethod.apple,
                        label: Text('Apple'),
                        icon: Icon(Icons.apple_rounded, size: 18),
                      ),
                    if (widget.allowEmailOtp)
                      const ButtonSegment(
                        value: ReauthMethod.emailOtp,
                        label: Text('Email OTP'),
                        icon: Icon(Icons.email_outlined, size: 16),
                      ),
                  ],
                  selected: {_selectedMethod},
                  onSelectionChanged: (val) {
                    setState(() {
                      _selectedMethod = val.first;
                      _errorMessage = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Error banner
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        theme.colorScheme.errorContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Form inputs based on selected method
              if (_selectedMethod == ReauthMethod.password) ...[
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  maxLength: AppConstants.maxPasswordLength,
                  decoration: const InputDecoration(
                    labelText: 'Current Account Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    counterText: '',
                  ),
                ),
              ] else if (_selectedMethod == ReauthMethod.google) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You will be prompted to verify via Google Account authentication.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_selectedMethod == ReauthMethod.apple) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You will be prompted to verify via Sign in with Apple.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_selectedMethod == ReauthMethod.emailOtp) ...[
                if (!_otpRequested) ...[
                  FilledButton.tonalIcon(
                    onPressed: _isLoading ? null : _handleRequestOtp,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Send Verification Code to Email'),
                  ),
                ] else ...[
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: AppConstants.otpLength,
                    decoration: InputDecoration(
                      labelText: '${AppConstants.otpLength}-digit OTP Code',
                      prefixIcon: const Icon(Icons.pin_rounded),
                      helperText: 'Check your email inbox for the code',
                      suffixIcon: TextButton(
                        onPressed: _isLoading ? null : _handleRequestOtp,
                        child: const Text('Resend',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _handleConfirm,
          child: _isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  ),
                )
              : const Text('Confirm & Authorize'),
        ),
      ],
    );
  }
}
