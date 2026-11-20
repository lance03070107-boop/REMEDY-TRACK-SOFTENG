import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../services/biometric_service.dart';
import '../../viewmodels/auth_viewmodel.dart';

/// Wraps the entire application with a non-destructive lifecycle lock overlay.
/// When the app resumes after exceeding the user's configured timeout, an opaque
/// lock screen is presented while preserving all underlying route states.
class AppLockOverlay extends StatefulWidget {
  final Widget child;

  const AppLockOverlay({super.key, required this.child});

  @override
  State<AppLockOverlay> createState() => AppLockOverlayState();
}

class AppLockOverlayState extends State<AppLockOverlay>
    with WidgetsBindingObserver {
  final BiometricService _biometricService = BiometricService();
  bool _isLocked = false;
  DateTime? _pausedAt;
  String? _lockErrorMessage;
  bool _isAuthenticating = false;
  bool _hasCheckedColdStartForSession = false;
  bool _sawUnauthenticated = false;
  AuthViewModel? _authVm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkColdStartLock());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextAuthVm = context.read<AuthViewModel?>();
    if (_authVm != nextAuthVm) {
      _authVm?.removeListener(_onAuthChanged);
      _authVm = nextAuthVm;
      _authVm?.addListener(_onAuthChanged);
    }
  }

  void _onAuthChanged() {
    final authVm = _authVm;
    if (authVm == null) return;
    if (!authVm.isAuthenticated) {
      if (!authVm.isInitializing) {
        _sawUnauthenticated = true;
      }
      _hasCheckedColdStartForSession = false;
      if (_isLocked && mounted) {
        setState(() {
          _isLocked = false;
          _lockErrorMessage = null;
        });
      }
      return;
    }
    if (authVm.currentUser != null && !authVm.isEmailOtpVerified) {
      _sawUnauthenticated = true;
      return;
    }
    if (!authVm.isInitializing && !_hasCheckedColdStartForSession) {
      if (_sawUnauthenticated) {
        // Skip immediate cold-start prompt right after interactive login/registration
        _hasCheckedColdStartForSession = true;
        return;
      }
      unawaited(_checkColdStartLock());
    }
  }

  Future<void> _checkColdStartLock() async {
    if (kIsWeb || !mounted) return;
    if (AppRouter.isAlarmRingingActive) return;

    final authVm = context.read<AuthViewModel>();
    if (authVm.isInitializing ||
        !authVm.isAuthenticated ||
        (authVm.currentUser != null && !authVm.isEmailOtpVerified)) {
      return;
    }
    if (_hasCheckedColdStartForSession) return;
    _hasCheckedColdStartForSession = true;

    final prefs = await SharedPreferences.getInstance();
    final isBiometricEnabled =
        prefs.getBool(AppConstants.keyBiometricEnabled) ?? false;
    if (!isBiometricEnabled || !mounted) return;

    setState(() {
      _isLocked = true;
      _lockErrorMessage = null;
    });
    await _attemptUnlock();
  }

  @override
  void dispose() {
    _authVm?.removeListener(_onAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;

    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _checkAndTriggerLock();
    }
  }

  Future<void> _checkAndTriggerLock() async {
    if (kIsWeb) return;
    if (AppRouter.isAlarmRingingActive) {
      // Allow user to interact with the alarm ringing screen immediately without biometric lock blocking
      return;
    }
    final authVm = context.read<AuthViewModel>();
    if (!authVm.isAuthenticated ||
        (authVm.currentUser != null && !authVm.isEmailOtpVerified)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final isBiometricEnabled =
        prefs.getBool(AppConstants.keyBiometricEnabled) ?? false;
    if (!isBiometricEnabled) return;

    final timeoutSeconds = prefs.getInt(AppConstants.keyLockTimeoutSeconds) ??
        AppConstants.defaultLockTimeoutSeconds;

    if (_pausedAt != null) {
      final elapsedSeconds = DateTime.now().difference(_pausedAt!).inSeconds;
      if (elapsedSeconds >= timeoutSeconds) {
        setState(() {
          _isLocked = true;
          _lockErrorMessage = null;
        });
        await _attemptUnlock();
      }
    }
  }

  Future<void> _attemptUnlock() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _lockErrorMessage = null;
    });

    final result = await _biometricService.authenticateDetailed();
    if (!mounted) return;

    setState(() {
      _isAuthenticating = false;
      if (result.isSuccess) {
        _isLocked = false;
        _lockErrorMessage = null;
        _pausedAt = null;
      } else {
        _lockErrorMessage = result.message;
      }
    });
  }

  Future<void> _handleSignOut() async {
    setState(() {
      _isLocked = false;
      _lockErrorMessage = null;
      _pausedAt = null;
    });
    await context.read<AuthViewModel>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLockedNow = _isLocked && !AppRouter.isAlarmRingingActive;

    return Stack(
      children: [
        widget.child,
        if (isLockedNow)
          Material(
            color: theme.colorScheme.surface,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.25),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.lock_rounded,
                              size: 48,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'RemedyTrack Locked',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Your health and medication records are protected by device security.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_lockErrorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer
                                  .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.colorScheme.error
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: theme.colorScheme.error,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _lockErrorMessage!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onErrorContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _isAuthenticating ? null : _attemptUnlock,
                          icon: _isAuthenticating
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.fingerprint_rounded),
                          label: Text(
                            _isAuthenticating
                                ? 'Authenticating...'
                                : 'Unlock Now',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _handleSignOut,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
