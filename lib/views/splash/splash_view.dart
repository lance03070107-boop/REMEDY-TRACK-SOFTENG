import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/app_logger.dart';
import '../../viewmodels/auth_viewmodel.dart';

/// Splash screen styled in Mocha Base (#1e1e2e) with Blue/Teal branding.
/// Checks auth state, onboarding status, and biometric lock before routing.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.forward();
    _evaluateNextRoute();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _evaluateNextRoute() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;

      // Never redirect if full-screen alarm ringing screen is currently active
      if (AppRouter.isAlarmRingingActive) return;

      final prefs = await SharedPreferences.getInstance();
      final onboardingDone =
          prefs.getBool(AppConstants.keyOnboardingComplete) ?? false;

      if (!mounted) return;

      if (!onboardingDone) {
        context.go('/onboarding');
        return;
      }

      final authVm = context.read<AuthViewModel>();

      // Wait until AuthViewModel finishes restoring Firebase authentication session
      int attempts = 0;
      while (authVm.isInitializing && attempts < 25 && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      if (!mounted) return;

      if (authVm.isAuthenticated) {
        context.go('/home');
      } else {
        context.go('/login');
      }
    } catch (e, s) {
      AppLogger.w('Navigation evaluation notice in SplashView: $e',
          tag: 'SplashView', error: e, stackTrace: s);
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const deepBrandBlue = Color(0xFF163247);
    const babyBlueAccent = Color(0xFFA7D8F0);
    const softBlueSurface = Color(0xFFF4FAFE);

    return Scaffold(
      backgroundColor: isDark ? deepBrandBlue : softBlueSurface,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 148,
                  height: 148,
                  decoration: BoxDecoration(
                    color: deepBrandBlue,
                    borderRadius: BorderRadius.circular(36),
                    boxShadow: [
                      BoxShadow(
                        color: (isDark ? babyBlueAccent : deepBrandBlue)
                            .withValues(alpha: 0.22),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/branding/splash_logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.medication_rounded,
                      size: 64,
                      color: babyBlueAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  AppStrings.appName,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: isDark ? Colors.white : const Color(0xFF24445C),
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.appTagline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? const Color(0xFFDDF2FC)
                        : const Color(0xFF4E6678),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
