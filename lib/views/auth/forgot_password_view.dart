import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/validation/medication_validator.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../widgets/custom_text_field.dart';

/// Dedicated password reset screen that dispatches reset links without revealing
/// whether an account exists, preventing email enumeration attacks.
class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSent = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSendReset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final authVm = context.read<AuthViewModel>();
    await authVm.sendPasswordReset(_emailController.text.trim());

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _isSent = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _isSent ? _buildSuccessView(theme) : _buildFormView(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                Icons.lock_reset_rounded,
                size: 44,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Reset Password',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Enter your registered email address and we will send you secure instructions to reset your password.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          CustomTextField(
            controller: _emailController,
            label: AppStrings.emailLabel,
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            maxLength: AppConstants.maxEmailLength,
            validator: MedicationValidator.validateEmail,
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _isLoading ? null : _handleSendReset,
            child: _isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : const Text(
                    'Send Reset Link',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: () => context.go('/login'),
              child: const Text('Back to Sign In'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF40A02B).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 48,
              color: Color(0xFF40A02B),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Check Your Email',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            'If an account is registered with ${_emailController.text.trim()}, you will receive password reset instructions within a few minutes.\n\nTo safeguard user privacy under RA 10173, we do not confirm whether an account exists.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () => context.go('/login'),
          child: const Text('Return to Sign In'),
        ),
      ],
    );
  }
}
