import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/validation/medication_validator.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../widgets/custom_text_field.dart';
import 'privacy_consent_dialog.dart';

/// User registration view requiring RA 10173 consent acceptance before account creation.
/// Features a real-time password strength meter and compliance feedback.
class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _privacyConsentAccepted = false;
  String _currentPasswordInput = '';

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    if (_currentPasswordInput != _passwordController.text) {
      setState(() {
        _currentPasswordInput = _passwordController.text;
      });
    }
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_privacyConsentAccepted) {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const PrivacyConsentDialog(),
      );

      if (accepted == true) {
        if (!mounted) return;
        setState(() => _privacyConsentAccepted = true);
        await context.read<AuthViewModel>().acceptPrivacyConsent();
      } else {
        return;
      }
    }

    if (!mounted) return;
    final authVm = context.read<AuthViewModel>();
    final normalizedEmail = _emailController.text.trim().toLowerCase();
    final success = await authVm.registerWithEmail(
      normalizedEmail,
      _passwordController.text,
      _nameController.text.trim(),
    );

    if (success && mounted) {
      if (authVm.isEmailOtpVerified) {
        context.go('/home');
      } else {
        context.go(
          '/verify-otp?purpose=signup&email=${Uri.encodeComponent(normalizedEmail)}',
        );
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final authVm = context.read<AuthViewModel>();
    if (!_privacyConsentAccepted) {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const PrivacyConsentDialog(),
      );
      if (accepted == true) {
        setState(() => _privacyConsentAccepted = true);
        await authVm.acceptPrivacyConsent();
      } else {
        return;
      }
    }

    if (!mounted) return;
    await authVm.signInWithGoogle();
  }

  Widget _buildPasswordStrengthMeter(ThemeData theme) {
    if (_currentPasswordInput.isEmpty) {
      return const SizedBox.shrink();
    }

    final strength =
        AuthViewModel.evaluatePasswordStrength(_currentPasswordInput);
    final hasMinLength = _currentPasswordInput.length >= 8;
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(_currentPasswordInput);
    final hasNumber = RegExp(r'[0-9]').hasMatch(_currentPasswordInput);

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
              '${_currentPasswordInput.length} chars',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildRequirementRow(theme, 'At least 8 characters', hasMinLength),
        _buildRequirementRow(theme, 'Contains at least one letter', hasLetter),
        _buildRequirementRow(theme, 'Contains at least one number', hasNumber),
      ],
    );
  }

  Widget _buildRequirementRow(ThemeData theme, String text, bool satisfied) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(
            satisfied
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 14,
            color: satisfied
                ? const Color(0xFF40A02B)
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: satisfied
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: satisfied ? FontWeight.w600 : FontWeight.normal,
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
    final bool isAppleSupported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

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
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppStrings.registerTitle,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.registerSubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (authVm.errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer
                              .withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                theme.colorScheme.error.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded,
                                color: theme.colorScheme.error, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                authVm.errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    CustomTextField(
                      controller: _nameController,
                      label: 'Full Name',
                      prefixIcon: Icons.person_outline,
                      maxLength: AppConstants.maxDisplayNameLength,
                      validator: MedicationValidator.validateDisplayName,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _emailController,
                      label: AppStrings.emailLabel,
                      prefixIcon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      maxLength: AppConstants.maxEmailLength,
                      validator: MedicationValidator.validateEmail,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _passwordController,
                      label: AppStrings.passwordLabel,
                      prefixIcon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      maxLength: AppConstants.maxPasswordLength,
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) {
                        final lenErr = MedicationValidator.validatePassword(v);
                        if (lenErr != null) return lenErr;
                        if (!AuthViewModel.isPasswordCompliant(v!)) {
                          return 'Password must be at least ${AppConstants.minPasswordLength} chars and include both letters and numbers.';
                        }
                        return null;
                      },
                    ),
                    _buildPasswordStrengthMeter(theme),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _confirmPasswordController,
                      label: AppStrings.confirmPasswordLabel,
                      prefixIcon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      maxLength: AppConstants.maxPasswordLength,
                      validator: (v) => v != _passwordController.text
                          ? 'Passwords do not match'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: _privacyConsentAccepted,
                          onChanged: (val) {
                            setState(
                                () => _privacyConsentAccepted = val ?? false);
                          },
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final accepted = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => const PrivacyConsentDialog(),
                              );
                              if (accepted == true) {
                                setState(() => _privacyConsentAccepted = true);
                              }
                            },
                            child: Text(
                              'I accept the Philippine Data Privacy Act (RA 10173) Consent Agreement',
                              style: theme.textTheme.bodySmall?.copyWith(
                                decoration: TextDecoration.underline,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: authVm.isLoading ? null : _handleRegister,
                      child: authVm.isLoading
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : const Text(
                              AppStrings.registerButton,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),
                    // Social Sign-In Options
                    Row(
                      children: [
                        Expanded(child: Divider(color: theme.dividerColor)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            'OR',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: theme.dividerColor)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: authVm.isLoading ? null : _handleGoogleSignIn,
                      icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                      label: const Text(
                        'Sign up with Google',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isAppleSupported) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: authVm.isLoading
                            ? null
                            : () => authVm.signInWithApple(),
                        icon: const Icon(Icons.apple_rounded, size: 24),
                        label: const Text(
                          'Sign up with Apple',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Already have an account?'),
                        TextButton(
                          onPressed: () => context.go('/login'),
                          child: const Text(
                            'Sign In',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
