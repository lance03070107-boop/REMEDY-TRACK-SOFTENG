import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../viewmodels/auth_viewmodel.dart';

/// Interactive 6-box OTP input screen supporting paste, autofill, resend countdown,
/// accessibility semantics, and error handling.
class VerifyOtpView extends StatefulWidget {
  final String purpose;
  final String? email;

  const VerifyOtpView({
    super.key,
    this.purpose = 'signup',
    this.email,
  });

  @override
  State<VerifyOtpView> createState() => _VerifyOtpViewState();
}

class _VerifyOtpViewState extends State<VerifyOtpView>
    with WidgetsBindingObserver {
  static const int _codeLength = AppConstants.otpCodeLength;
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late final List<FocusNode> _keyboardFocusNodes;

  int _resendCountdown = AppConstants.otpResendCooldownSeconds;
  Timer? _timer;
  bool _isSubmitting = false;
  bool _usedEmailLinkFallback = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controllers = List.generate(_codeLength, (_) => TextEditingController());
    _focusNodes = List.generate(_codeLength, (_) => FocusNode());
    _keyboardFocusNodes = List.generate(_codeLength, (_) => FocusNode());

    _startResendTimer();

    // Auto-request code on initial arrival if signup flow
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialRequest();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.purpose == 'signup' &&
        !_isSubmitting) {
      _checkVerificationStatusSilently();
    }
  }

  Future<void> _checkVerificationStatusSilently() async {
    if (!mounted) return;
    final authVm = context.read<AuthViewModel>();
    final verified = await authVm.checkEmailVerificationStatus();
    if (verified && mounted) {
      context.go('/home');
    }
  }

  void _initialRequest() {
    if (!mounted) return;
    final authVm = context.read<AuthViewModel>();
    // Only auto-request if there is an active authenticated user session
    if (authVm.isAuthenticated &&
        !authVm.isEmailOtpVerified &&
        widget.purpose == 'signup') {
      _handleResend(isInitial: true);
    }
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendCountdown = AppConstants.otpResendCooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    for (final kf in _keyboardFocusNodes) {
      kf.dispose();
    }
    super.dispose();
  }

  String get _currentCode => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // User pasted content into a box
      _handlePaste(value);
      return;
    }

    if (value.isNotEmpty) {
      if (index < _codeLength - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        if (_currentCode.length == _codeLength) {
          _handleVerify();
        }
      }
    }
  }

  void _handlePaste(String text) {
    final cleanDigits = text.replaceAll(RegExp(r'\D'), '');
    if (cleanDigits.isEmpty) return;

    for (int i = 0; i < _codeLength; i++) {
      if (i < cleanDigits.length) {
        _controllers[i].text = cleanDigits[i];
      }
    }

    final nextIndex =
        cleanDigits.length < _codeLength ? cleanDigits.length : _codeLength - 1;
    _focusNodes[nextIndex].requestFocus();

    if (_currentCode.length == _codeLength) {
      _handleVerify();
    }
  }

  Future<void> _handleResend({bool isInitial = false}) async {
    setState(() {
      _errorMessage = null;
      if (!isInitial) _infoMessage = null;
    });

    final authVm = context.read<AuthViewModel>();
    try {
      final res = await authVm.requestEmailOtp(
        purpose: widget.purpose,
        email: widget.email,
      );
      if (mounted) {
        setState(() {
          _usedEmailLinkFallback = false;
          _infoMessage = res['message'] as String? ??
              'Verification code sent to your email.';
        });
        _startResendTimer();
      }
    } on RateLimitException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } on OtpException catch (e) {
      if (!mounted) return;
      if (widget.purpose == 'signup' && authVm.isAuthenticated) {
        setState(() {
          _usedEmailLinkFallback = true;
          _infoMessage =
              'We sent a verification link to your email address. Click the link in your inbox, then tap "I Verified My Email" below.';
        });
        _startResendTimer();
      } else {
        setState(() => _errorMessage = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage =
            'Could not send verification email. Please try again.');
      }
    }
  }

  Future<void> _handleCheckLinkVerification() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final authVm = context.read<AuthViewModel>();
    try {
      final verified = await authVm.checkEmailVerificationStatus();
      if (!mounted) return;
      if (verified) {
        context.go('/home');
      } else {
        setState(() {
          _errorMessage =
              'Email not verified yet. Please check your inbox (and spam folder), click the verification link or enter the 6-digit code, and try again.';
        });
      }
    } catch (e, s) {
      if (mounted) {
        setState(() => _errorMessage = ErrorMapper.map(e, s).message);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleVerify() async {
    final code = _currentCode;
    if (code.length != _codeLength) {
      setState(() => _errorMessage = 'Please enter all 6 digits.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final authVm = context.read<AuthViewModel>();
    try {
      final success = await authVm.verifyEmailOtp(
        code,
        purpose: widget.purpose,
      );

      if (!mounted) return;

      if (success) {
        if (widget.purpose == 'signup') {
          // Signup complete -> proceed to home (or privacy dialog handled in flow)
          context.go('/home');
        } else {
          // Sensitive operation re-auth -> pop with true
          Navigator.of(context).pop(true);
        }
      }
    } on OtpException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.message;
        });
      }
    } catch (e, s) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = ErrorMapper.map(e, s).message;
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authVm = context.watch<AuthViewModel>();
    final displayEmail = widget.email ?? authVm.currentUserEmail;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop(false);
            } else {
              if (widget.purpose == 'signup' && authVm.isAuthenticated) {
                await authVm.signOut();
              }
              if (context.mounted) {
                context.go('/login');
              }
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
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
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.mark_email_read_rounded,
                        size: 42,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Verify Your Email',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'We sent a 6-digit verification code to:\n$displayEmail',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Feedback Banners
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded,
                              color: theme.colorScheme.error, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
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

                  if (_infoMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: theme.colorScheme.primary, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _infoMessage!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // 6-Box Pin Input Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(_codeLength, (index) {
                      return Semantics(
                        label: 'Digit ${index + 1} of 6',
                        textField: true,
                        child: SizedBox(
                          width: 52,
                          height: 60,
                          child: KeyboardListener(
                            focusNode: _keyboardFocusNodes[index],
                            onKeyEvent: (event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey ==
                                      LogicalKeyboardKey.backspace &&
                                  _controllers[index].text.isEmpty &&
                                  index > 0) {
                                _focusNodes[index - 1].requestFocus();
                              }
                            },
                            child: TextFormField(
                              controller: _controllers[index],
                              focusNode: _focusNodes[index],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(1),
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                              decoration: InputDecoration(
                                counterText: '',
                                contentPadding: EdgeInsets.zero,
                                filled: true,
                                fillColor: theme
                                    .colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.4),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.primary,
                                    width: 2.5,
                                  ),
                                ),
                              ),
                              onChanged: (val) => _onDigitChanged(index, val),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _handleVerify,
                    child: _isSubmitting
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : const Text(
                            'Verify Code',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),

                  // Resend Action with Countdown
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        "Didn't receive the email?",
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: (_resendCountdown > 0 || _isSubmitting)
                            ? null
                            : () => _handleResend(),
                        child: Text(
                          _resendCountdown > 0
                              ? 'Resend code in ${_resendCountdown}s'
                              : 'Resend Code',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _resendCountdown > 0
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.purpose == 'signup' && _usedEmailLinkFallback) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed:
                          _isSubmitting ? null : _handleCheckLinkVerification,
                      icon: const Icon(Icons.verified_user_outlined, size: 18),
                      label: const Text('I Verified My Email'),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Cancel / Sign out
                  Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        await authVm.signOut();
                        if (context.mounted) context.go('/login');
                      },
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Sign In to Another Account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
