import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/app_logger.dart';
import '../../core/validation/medication_validator.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../widgets/custom_text_field.dart';
import 'privacy_consent_dialog.dart';

/// User login view supporting Email/Password, Google Sign-In, and Sign in with Apple.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Attempt One Tap / lightweight Google sign-in after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptLightweightSignIn();
    });
  }

  Future<void> _attemptLightweightSignIn() async {
    final authVm = context.read<AuthViewModel>();
    if (!authVm.isAuthenticated) {
      try {
        await authVm.signInWithGoogle(lightweightOnly: true);
      } catch (e, s) {
        AppLogger.d('Lightweight Google sign-in skipped: $e', tag: 'LoginView');
        AppLogger.w('Lightweight Google sign-in error',
            tag: 'LoginView', error: e, stackTrace: s);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    final authVm = context.read<AuthViewModel>();
    final success = await authVm.signInWithEmail(
      _emailController.text,
      _passwordController.text,
    );
    if (!mounted) return;
    if (success) {
      // GoRouter redirect automatically returns user to destination or /home
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final authVm = context.read<AuthViewModel>();
    if (!authVm.isPrivacyConsentGiven) {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const PrivacyConsentDialog(),
      );
      if (accepted == true) {
        await authVm.acceptPrivacyConsent();
      } else {
        return;
      }
    }

    if (!mounted) return;
    await authVm.signInWithGoogle();
  }

  Future<void> _handleAppleSignIn() async {
    final authVm = context.read<AuthViewModel>();
    if (!authVm.isPrivacyConsentGiven) {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const PrivacyConsentDialog(),
      );
      if (accepted == true) {
        await authVm.acceptPrivacyConsent();
      } else {
        return;
      }
    }

    if (!mounted) return;
    await authVm.signInWithApple();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authVm = context.watch<AuthViewModel>();
    final bool isAppleSupported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 108,
                        height: 108,
                        decoration: BoxDecoration(
                          color: const Color(0xFF9BD1F2),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.18),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/branding/app_icon.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.medication_rounded,
                            size: 48,
                            color: Color(0xFF24445C),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppStrings.loginTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.loginSubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: theme.brightness == Brightness.dark
                            ? theme.colorScheme.surfaceContainerLow
                            : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.55),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (authVm.errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer
                                    .withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: theme.colorScheme.error
                                      .withValues(alpha: 0.5),
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
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onErrorContainer,
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
                            controller: _emailController,
                            label: AppStrings.emailLabel,
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            maxLength: AppConstants.maxEmailLength,
                            validator: MedicationValidator.validateEmail,
                          ),
                          const SizedBox(height: 18),
                          CustomTextField(
                            controller: _passwordController,
                            label: AppStrings.passwordLabel,
                            prefixIcon: Icons.lock_outline,
                            obscureText: _obscurePassword,
                            maxLength: AppConstants.maxPasswordLength,
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                            validator: (v) =>
                                MedicationValidator.validatePassword(
                              v,
                              isSignIn: true,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.go('/forgot-password'),
                              child: const Text(AppStrings.forgotPassword),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: authVm.isLoading ? null : _handleSignIn,
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
                                    AppStrings.signInButton,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Social Sign-In Divider
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
                    // Google Sign-In Button
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
                        'Continue with Google',
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
                        onPressed: authVm.isLoading ? null : _handleAppleSignIn,
                        icon: const Icon(Icons.apple_rounded, size: 24),
                        label: const Text(
                          'Sign in with Apple',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account?",
                          style: theme.textTheme.bodyMedium,
                        ),
                        TextButton(
                          onPressed: () => context.go('/register'),
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Legal Disclaimer
                    Text(
                      AppStrings.medicalDisclaimer,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
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
