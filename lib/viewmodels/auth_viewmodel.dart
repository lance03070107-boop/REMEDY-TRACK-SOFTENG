import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/errors/error_mapper.dart';
import '../core/utils/app_logger.dart';
import '../core/utils/result.dart';
import '../models/user_profile.dart';
import '../repositories/user_repository.dart';
import '../services/alarm_scheduler.dart';
import '../services/crashlytics_service.dart';
import '../services/email_otp_service.dart';
import '../services/fcm_service.dart';
import '../services/local_medication_cache.dart';
import '../services/secure_storage_service.dart';
import 'intake_viewmodel.dart';

enum PasswordStrength {
  weak,
  fair,
  good,
  strong;

  String get label {
    switch (this) {
      case PasswordStrength.weak:
        return 'Weak';
      case PasswordStrength.fair:
        return 'Fair';
      case PasswordStrength.good:
        return 'Good';
      case PasswordStrength.strong:
        return 'Strong';
    }
  }

  Color get color {
    switch (this) {
      case PasswordStrength.weak:
        return const Color(0xFFD20F39);
      case PasswordStrength.fair:
        return const Color(0xFFDF8E1D);
      case PasswordStrength.good:
        return const Color(0xFF40A02B);
      case PasswordStrength.strong:
        return const Color(0xFF1E66F5);
    }
  }
}

class AuthViewModel extends ChangeNotifier {
  final FirebaseAuth? _firebaseAuth;
  final UserRepository _userRepository;
  final FcmService _fcmService;
  final SecureStorageService _secureStorage;
  final EmailOtpService _emailOtpService;
  final bool Function() _isOnline;

  /// Invoked synchronously right before FirebaseAuth signOut or account deletion
  /// so active Firestore stream listeners are torn down before credentials are revoked.
  VoidCallback? onBeforeSignOut;

  /// Optional callback to flush pending offline intakes before signing out.
  Future<void> Function(String userId)? onFlushPendingBeforeSignOut;

  StreamSubscription<User?>? _authSubscription;
  User? _currentUser;
  UserProfile? _userProfile;
  bool _isDisposed = false;
  bool _isLoading = false;
  bool _isChangingPassword = false;
  bool _isInitializing = true;
  bool _isProfileLoading = false;
  bool _isRegistering = false;
  String? _errorMessage;
  bool _isPrivacyConsentGiven = false;

  AuthCredential? _pendingCredential;
  static bool _isGoogleInitialized = false;

  static bool _defaultOnline() => true;

  AuthViewModel({
    FirebaseAuth? firebaseAuth,
    required UserRepository userRepository,
    FcmService? fcmService,
    SecureStorageService? secureStorage,
    EmailOtpService? emailOtpService,
    bool Function()? isOnline,
  })  : _firebaseAuth = firebaseAuth ??
            (Firebase.apps.isNotEmpty ? FirebaseAuth.instance : null),
        _userRepository = userRepository,
        _fcmService = fcmService ?? FcmService(),
        _secureStorage = secureStorage ?? SecureStorageService(),
        _emailOtpService = emailOtpService ?? EmailOtpService(),
        _isOnline = isOnline ?? _defaultOnline {
    final auth = _firebaseAuth;
    if (auth != null) {
      _currentUser = auth.currentUser;
      _initAuth(auth);
    } else {
      _isInitializing = false;
    }
    checkStoredConsent();
  }

  User? get currentUser => _currentUser;
  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  bool get isChangingPassword => _isChangingPassword;
  bool get isInitializing => _isInitializing;
  bool get isProfileLoading => _isProfileLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;
  bool get isPrivacyConsentGiven => _isPrivacyConsentGiven;
  AuthCredential? get pendingCredential => _pendingCredential;

  bool get isEmailOtpVerified {
    if (_currentUser == null) return false;
    if (_isRegistering) return false;
    if (isGoogleLinked || isAppleLinked) return true;
    if (_currentUser?.emailVerified == true) return true;
    if (_userProfile != null) {
      return _userProfile!.emailOtpVerified;
    }
    // While profile is loading from Firestore, return cached verification state
    return _cachedEmailOtpVerified;
  }

  bool _cachedEmailOtpVerified = true;

  String get currentUserId => _currentUser?.uid ?? '';
  String get currentUserEmail => _currentUser?.email ?? '';
  String get currentUserDisplayName =>
      _userProfile?.displayName.isNotEmpty == true
          ? _userProfile!.displayName
          : (_currentUser?.displayName ?? 'User');

  bool get isGoogleLinked =>
      _currentUser?.providerData
          .any((p) => p.providerId == GoogleAuthProvider.PROVIDER_ID) ??
      false;

  bool get isAppleLinked =>
      _currentUser?.providerData.any((p) => p.providerId == 'apple.com') ??
      false;

  bool get isPasswordLinked =>
      _currentUser?.providerData
          .any((p) => p.providerId == EmailAuthProvider.PROVIDER_ID) ??
      false;

  /// True when the signed-in user has an email/password credential attached.
  bool get hasPasswordProvider => isPasswordLinked;

  static bool isPasswordCompliant(String password) {
    if (password.length < 8) return false;
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    return hasLetter && hasNumber;
  }

  static PasswordStrength evaluatePasswordStrength(String password) {
    if (password.length < 8) return PasswordStrength.weak;
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
    final hasSpecial = RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);

    if (!hasLetter || !hasNumber) return PasswordStrength.weak;
    if (password.length >= 12 && hasUpper && hasSpecial) {
      return PasswordStrength.strong;
    }
    if (password.length >= 10 || (hasUpper && hasSpecial)) {
      return PasswordStrength.good;
    }
    return PasswordStrength.fair;
  }

  void _initAuth(FirebaseAuth auth) {
    _authSubscription?.cancel();
    _authSubscription = auth.authStateChanges().listen(
      (User? user) async {
        try {
          _currentUser = user;
          if (user != null) {
            if (_isRegistering) {
              // Registration flow is actively creating and persisting the unverified profile;
              // avoid racing with _loadUserProfile.
              return;
            }
            _isProfileLoading = true;
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('remedy_active_user_id', user.uid);
            } catch (e, s) {
              AppLogger.w('Prefs write skipped during auth init: $e',
                  tag: 'AuthVM', error: e, stackTrace: s);
            }
            await CrashlyticsService.setUserIdentifier(user.uid);
            await _secureStorage.write(SecureStorageService.keyUserId, user.uid);
            if (user.email != null) {
              await _secureStorage.write(
                  SecureStorageService.keyUserEmail, user.email!);
            }
            await _loadUserProfile(user.uid);
          } else {
            _userProfile = null;
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('remedy_active_user_id');
            } catch (e, s) {
              AppLogger.w('Prefs cleanup skipped during auth init: $e',
                  tag: 'AuthVM', error: e, stackTrace: s);
            }
            await CrashlyticsService.setUserIdentifier(null);
            await _secureStorage.delete(SecureStorageService.keyUserId);
            await _secureStorage.delete(SecureStorageService.keyUserEmail);
          }
        } catch (e, s) {
          AppLogger.w('Auth state sync notice: $e',
              tag: 'AuthVM', error: e, stackTrace: s);
        } finally {
          _isProfileLoading = false;
          _isInitializing = false;
          notifyListeners();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.w('Auth state stream error: $error',
            tag: 'AuthVM', error: error, stackTrace: stackTrace);
        _isProfileLoading = false;
        _isInitializing = false;
        notifyListeners();
      },
    );
  }

  Future<void> checkStoredConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isPrivacyConsentGiven =
          prefs.getBool(AppConstants.keyPrivacyAccepted) ?? false;
      notifyListeners();
    } catch (e, s) {
      AppLogger.w('Stored consent check notice: $e',
          tag: 'AuthVM', error: e, stackTrace: s);
    }
  }

  Future<void> acceptPrivacyConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyPrivacyAccepted, true);
    _isPrivacyConsentGiven = true;
    notifyListeners();
  }

  Future<void> _loadUserProfile(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedEmailOtpVerified = prefs.getBool('remedy_verified_$uid') ?? false;

      _userProfile = await _userRepository.getUserProfile(uid);
      if (_userProfile != null) {
        final verified = (_currentUser?.emailVerified ?? false) ||
            _userProfile!.emailOtpVerified ||
            _cachedEmailOtpVerified ||
            isGoogleLinked ||
            isAppleLinked;
        _cachedEmailOtpVerified = verified;
        await prefs.setBool('remedy_verified_$uid', verified);
      } else {
        String? token;
        try {
          token = await _fcmService.initializeAndGetToken().timeout(
              const Duration(milliseconds: 800),
              onTimeout: () => null);
        } catch (e, s) {
          AppLogger.w('FCM token init failed during profile hydration',
              tag: 'AuthVM', error: e, stackTrace: s);
        }
        final emailFallback = currentUserEmail;
        final nameFallback = (_currentUser?.displayName?.isNotEmpty ?? false)
            ? _currentUser!.displayName!
            : 'Patient';
        final verifiedByProvider = isGoogleLinked ||
            isAppleLinked ||
            (_currentUser?.emailVerified ?? false);
        _cachedEmailOtpVerified = verifiedByProvider;
        await prefs.setBool('remedy_verified_$uid', verifiedByProvider);

        // Client always creates users/{uid} with emailOtpVerified: false;
        // server-side verifyEmailOtp or Firebase Auth email_verified claim establishes verification.
        final newProfile = UserProfile(
          id: uid,
          email: emailFallback,
          displayName: nameFallback,
          fcmToken: token,
          emailOtpVerified: false,
          createdAt: DateTime.now(),
        );
        try {
          await _userRepository.saveUserProfile(newProfile);
        } catch (e, s) {
          AppLogger.w('Non-fatal profile auto-init error: $e',
              tag: 'AuthVM', error: e, stackTrace: s);
        }
        _userProfile = newProfile;
      }
    } catch (e, s) {
      AppLogger.w('Error loading user profile: $e',
          tag: 'AuthVM', error: e, stackTrace: s);
    }
    notifyListeners();
  }

  Future<bool> signInWithEmail(String email, String password) async {
    _setLoading(true);
    final auth = _firebaseAuth;

    if (auth == null) {
      _errorMessage =
          'Firebase connection is unavailable. Please check your network connection.';
      _setLoading(false);
      return false;
    }

    try {
      _isProfileLoading = true;
      final credential = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _currentUser = credential.user;
      if (_currentUser != null) {
        await _secureStorage.write(
            SecureStorageService.keyUserId, _currentUser!.uid);
        await _loadUserProfile(_currentUser!.uid);
      }
      _isProfileLoading = false;
      _errorMessage = null;
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _isProfileLoading = false;
      _errorMessage = _getFriendlyFirebaseAuthError(e.code, e.message);
      _setLoading(false);
      return false;
    } catch (e) {
      _isProfileLoading = false;
      _errorMessage =
          'An unexpected error occurred. Please verify your connection.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> registerWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    final normalizedEmail = email.trim().toLowerCase();
    final trimmedName = displayName.trim();

    if (trimmedName.isEmpty) {
      _errorMessage = 'Please enter your full name.';
      notifyListeners();
      return false;
    }

    if (!isPasswordCompliant(password)) {
      _errorMessage =
          'Password must be at least 8 characters and include at least one letter and one number.';
      notifyListeners();
      return false;
    }

    _setLoading(true);
    final auth = _firebaseAuth;

    if (auth == null) {
      _errorMessage =
          'Firebase connection is unavailable. Cannot register account.';
      _setLoading(false);
      return false;
    }

    _isRegistering = true;
    _isProfileLoading = true;
    _cachedEmailOtpVerified = false;
    try {
      UserCredential credential;
      try {
        credential = await auth.createUserWithEmailAndPassword(
          email: normalizedEmail,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          // Recover gracefully if an unverified account was created in an interrupted signup attempt
          try {
            credential = await auth.signInWithEmailAndPassword(
              email: normalizedEmail,
              password: password,
            );
            final existingProfile = credential.user != null
                ? await _userRepository.getUserProfile(credential.user!.uid)
                : null;
            final alreadyVerified = (credential.user?.emailVerified ?? false) ||
                (existingProfile?.emailOtpVerified ?? false);
            if (alreadyVerified) {
              _userProfile = existingProfile;
              _errorMessage =
                  'An account with this email is already verified. Signing you in...';
              _isProfileLoading = false;
              _isRegistering = false;
              _setLoading(false);
              return true;
            }
          } catch (e, s) {
            AppLogger.w('Auto sign-in on existing email failed: $e',
                tag: 'AuthVM', error: e, stackTrace: s);
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      _currentUser = credential.user;
      if (_currentUser != null) {
        try {
          await _currentUser!.updateDisplayName(trimmedName);
        } catch (e, s) {
          AppLogger.w('Failed to update Firebase display name',
              tag: 'AuthVM', error: e, stackTrace: s);
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('remedy_active_user_id', _currentUser!.uid);
        await CrashlyticsService.setUserIdentifier(_currentUser!.uid);
        await _secureStorage.write(
            SecureStorageService.keyUserId, _currentUser!.uid);
        await _secureStorage.write(
            SecureStorageService.keyUserEmail, normalizedEmail);

        String? token;
        try {
          token = await _fcmService.initializeAndGetToken();
        } catch (e, s) {
          AppLogger.w('FCM token init failed during registration',
              tag: 'AuthVM', error: e, stackTrace: s);
        }

        final profile = UserProfile(
          id: _currentUser!.uid,
          email: normalizedEmail,
          displayName: trimmedName,
          fcmToken: token,
          emailOtpVerified: false,
          createdAt: DateTime.now(),
        );
        _userProfile = profile;
        _cachedEmailOtpVerified = false;
        await prefs.setBool('remedy_verified_${_currentUser!.uid}', false);
        try {
          await _userRepository.saveUserProfile(profile);
        } catch (e, s) {
          AppLogger.w('Profile write warning during signup: $e',
              tag: 'AuthVM', error: e, stackTrace: s);
        }
      }
      _isProfileLoading = false;
      _isRegistering = false;
      _errorMessage = null;
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _isProfileLoading = false;
      _isRegistering = false;
      _errorMessage = _getFriendlyFirebaseAuthError(e.code, e.message);
      _setLoading(false);
      return false;
    } catch (e) {
      _isProfileLoading = false;
      _isRegistering = false;
      _errorMessage =
          'Registration failed. Please check your internet connection and try again.';
      _setLoading(false);
      return false;
    }
  }

  Future<void> _ensureGoogleInitialized() async {
    if (!_isGoogleInitialized) {
      try {
        final serverClientId = AppConstants.googleServerClientId.isNotEmpty
            ? AppConstants.googleServerClientId
            : null;
        await GoogleSignIn.instance.initialize(
          serverClientId: serverClientId,
        );
        _isGoogleInitialized = true;
      } catch (e, s) {
        AppLogger.w('GoogleSignIn init: $e',
            tag: 'AuthVM', error: e, stackTrace: s);
      }
    }
  }

  Future<bool> signInWithGoogle({bool lightweightOnly = false}) async {
    if (!lightweightOnly) _setLoading(true);
    final auth = _firebaseAuth;

    if (auth == null) {
      if (!lightweightOnly) {
        _errorMessage = 'Firebase is not initialized. Cannot sign in.';
        _setLoading(false);
      }
      return false;
    }

    try {
      if (kIsWeb) {
        if (lightweightOnly) {
          // On web, silent session recovery is managed by authStateChanges
          return false;
        }
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        _isProfileLoading = true;
        final userCredential = await auth.signInWithPopup(googleProvider);
        _currentUser = userCredential.user;
        if (_currentUser != null) {
          await _secureStorage.write(
              SecureStorageService.keyUserId, _currentUser!.uid);
          await _loadUserProfile(_currentUser!.uid);
        }
        _isProfileLoading = false;
        _errorMessage = null;
        _setLoading(false);
        return true;
      }

      await _ensureGoogleInitialized();
      final GoogleSignInAccount? account;
      if (lightweightOnly) {
        final future = GoogleSignIn.instance.attemptLightweightAuthentication();
        account = future != null ? await future : null;
      } else {
        account = await GoogleSignIn.instance.authenticate();
      }

      if (account == null) {
        if (!lightweightOnly) _setLoading(false);
        return false;
      }

      _isProfileLoading = true;
      final googleAuth = account.authentication;
      final idToken = googleAuth.idToken;
      String? accessToken;
      try {
        final authClient =
            await account.authorizationClient.authorizationForScopes(['email']);
        accessToken = authClient?.accessToken;
      } catch (e, stack) {
        unawaited(CrashlyticsService.recordError(e, stack));
      }

      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken,
      );

      final userCredential = await auth.signInWithCredential(credential);
      _currentUser = userCredential.user;
      if (_currentUser != null) {
        await _secureStorage.write(
            SecureStorageService.keyUserId, _currentUser!.uid);
        await _loadUserProfile(_currentUser!.uid);
      }
      _isProfileLoading = false;
      _errorMessage = null;
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _isProfileLoading = false;
      if (!lightweightOnly) {
        if (e.code == 'account-exists-with-different-credential') {
          _pendingCredential = e.credential;
          _errorMessage =
              'An account already exists with this email address. Please sign in with your password to link your Google account.';
        } else {
          _errorMessage = _getFriendlyFirebaseAuthError(e.code, e.message);
        }
      }
      _setLoading(false);
      return false;
    } on GoogleSignInException catch (e) {
      _isProfileLoading = false;
      if (!lightweightOnly) {
        if (e.code == GoogleSignInExceptionCode.canceled) {
          _errorMessage = null;
        } else if (e.code ==
                GoogleSignInExceptionCode.clientConfigurationError ||
            (e.description?.contains('serverClientId') ?? false)) {
          final desc = e.description?.trim();
          _errorMessage = (desc != null && desc.isNotEmpty && desc != 'null')
              ? 'Google Sign-In notice: $desc'
              : 'Google Sign-In configuration error. Please sign in with Email & Password below.';
        } else {
          _errorMessage =
              'Google Sign-In failed: ${e.description ?? e.code.name}';
        }
      }
      _setLoading(false);
      return false;
    } catch (e) {
      _isProfileLoading = false;
      if (!lightweightOnly) {
        _errorMessage = 'Google Sign-In failed. Please try again.';
      }
      _setLoading(false);
      return false;
    }
  }

  Future<bool> signInWithApple() async {
    _setLoading(true);
    final auth = _firebaseAuth;

    if (auth == null) {
      _errorMessage = 'Firebase is not initialized. Cannot sign in.';
      _setLoading(false);
      return false;
    }

    try {
      if (kIsWeb) {
        final appleProvider = OAuthProvider('apple.com');
        appleProvider.addScope('email');
        appleProvider.addScope('name');
        _isProfileLoading = true;
        final userCredential = await auth.signInWithPopup(appleProvider);
        _currentUser = userCredential.user;
        if (_currentUser != null) {
          await _secureStorage.write(
              SecureStorageService.keyUserId, _currentUser!.uid);
          await _loadUserProfile(_currentUser!.uid);
        }
        _isProfileLoading = false;
        _errorMessage = null;
        _setLoading(false);
        return true;
      }

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      _isProfileLoading = true;
      final OAuthCredential credential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential = await auth.signInWithCredential(credential);
      _currentUser = userCredential.user;
      if (_currentUser != null) {
        await _secureStorage.write(
            SecureStorageService.keyUserId, _currentUser!.uid);
        await _loadUserProfile(_currentUser!.uid);
      }
      _isProfileLoading = false;
      _errorMessage = null;
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _isProfileLoading = false;
      if (e.code == 'account-exists-with-different-credential') {
        _pendingCredential = e.credential;
        _errorMessage =
            'An account already exists with this email. Sign in with your primary method to link Apple.';
      } else {
        _errorMessage = _getFriendlyFirebaseAuthError(e.code, e.message);
      }
      _setLoading(false);
      return false;
    } catch (e) {
      _isProfileLoading = false;
      _errorMessage = 'Sign in with Apple failed. Please try again.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> linkGoogleAccount() async {
    if (_currentUser == null) return false;
    _setLoading(true);
    try {
      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        await _currentUser!.linkWithPopup(googleProvider);
        _errorMessage = null;
        _setLoading(false);
        notifyListeners();
        return true;
      }

      await _ensureGoogleInitialized();
      final account = await GoogleSignIn.instance.authenticate();
      final googleAuth = account.authentication;
      String? accessToken;
      try {
        final authClient =
            await account.authorizationClient.authorizationForScopes(['email']);
        accessToken = authClient?.accessToken;
      } catch (e, stack) {
        unawaited(CrashlyticsService.recordError(e, stack));
      }

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: accessToken,
      );

      await _currentUser!.linkWithCredential(credential);
      _errorMessage = null;
      _setLoading(false);
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _getFriendlyFirebaseAuthError(e.code, e.message);
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Failed to link Google account.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> unlinkGoogleAccount() async {
    if (_currentUser == null) return false;
    if (_currentUser!.providerData.length <= 1) {
      _errorMessage =
          'Cannot unlink Google account without another sign-in method linked.';
      notifyListeners();
      return false;
    }
    _setLoading(true);
    try {
      await _currentUser!.unlink(GoogleAuthProvider.PROVIDER_ID);
      _errorMessage = null;
      _setLoading(false);
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _getFriendlyFirebaseAuthError(e.code, e.message);
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Failed to unlink Google account.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> linkPendingCredential() async {
    if (_currentUser == null || _pendingCredential == null) return false;
    _setLoading(true);
    try {
      await _currentUser!.linkWithCredential(_pendingCredential!);
      _pendingCredential = null;
      _errorMessage = null;
      _setLoading(false);
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _getFriendlyFirebaseAuthError(e.code, e.message);
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Failed to link account credentials.';
      _setLoading(false);
      return false;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    _setLoading(true);
    final auth = _firebaseAuth;
    if (auth == null) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      _errorMessage = null;
      _setLoading(false);
      return;
    }
    try {
      await auth.sendPasswordResetEmail(email: email.trim());
      _errorMessage = null;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _getFriendlyFirebaseAuthError(e.code, e.message);
    } catch (e) {
      _errorMessage = 'Failed to send password reset email.';
    } finally {
      _setLoading(false);
    }
  }

  static String _getFriendlyFirebaseAuthError(String code, String? fallback) {
    return ErrorMapper.map(FirebaseAuthException(code: code, message: fallback))
        .message;
  }

  /// Attempts to flush pending offline intakes (if online) and returns the number
  /// of unsynced doses still queued for the signed-in user.
  Future<int> flushAndCountUnsyncedIntakes() async {
    final uid = currentUserId;
    if (uid.isEmpty) return 0;
    if (_isOnline() && onFlushPendingBeforeSignOut != null) {
      try {
        await onFlushPendingBeforeSignOut!(uid)
            .timeout(const Duration(seconds: 6));
      } catch (e, s) {
        AppLogger.w('Pre-signOut pending intake flush notice: $e',
            tag: 'AuthViewModel', error: e, stackTrace: s);
      }
    }
    return IntakeViewModel.getPendingBackgroundIntakeCount(uid);
  }

  Future<void> signOut({bool discardPendingIntakes = true}) async {
    final uid = currentUserId;
    if (uid.isNotEmpty && _isOnline() && onFlushPendingBeforeSignOut != null) {
      try {
        await onFlushPendingBeforeSignOut!(uid)
            .timeout(const Duration(seconds: 6));
      } catch (e, s) {
        AppLogger.w('Best-effort pending intake flush before signOut: $e',
            tag: 'AuthViewModel', error: e, stackTrace: s);
      }
    }

    // Cancel all active Firestore stream listeners BEFORE revoking auth credentials
    // so stream listeners never emit permission-denied errors or leak stale data.
    try {
      onBeforeSignOut?.call();
    } catch (e, s) {
      AppLogger.w('onBeforeSignOut callback notice: $e',
          tag: 'AuthViewModel', error: e, stackTrace: s);
    }

    final auth = _firebaseAuth;
    if (auth != null) {
      await auth.signOut();
      _currentUser = null;
    }
    try {
      await AlarmScheduler().cancelAllAlarms();
    } catch (e, s) {
      AppLogger.w('Failed to cancel alarms during signOut: $e',
          tag: 'AuthViewModel', error: e, stackTrace: s);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remedy_active_user_id');
    if (discardPendingIntakes) {
      await prefs.remove('pending_background_intakes');
    }
    await prefs.remove('remedy_active_dose_alarm_ids');

    await LocalMedicationCache.clear();
    await _secureStorage.deleteAll();
    await CrashlyticsService.setUserIdentifier(null);
    _userProfile = null;
    notifyListeners();
  }

  Future<bool> deleteAccountAndData({String? reauthPassword}) async {
    _setLoading(true);
    try {
      final user = _currentUser;
      if (user != null) {
        if (reauthPassword != null &&
            reauthPassword.isNotEmpty &&
            user.email != null) {
          final credential = EmailAuthProvider.credential(
            email: user.email!,
            password: reauthPassword,
          );
          await user.reauthenticateWithCredential(credential);
        }

        // Tear down active Firestore streams before erasing user documents
        try {
          onBeforeSignOut?.call();
        } catch (e, s) {
          AppLogger.w('onBeforeSignOut notice before account deletion: $e',
              tag: 'AuthViewModel', error: e, stackTrace: s);
        }

        final uid = user.uid;
        await _userRepository.deleteAllUserData(uid);
        try {
          await user.delete();
        } on FirebaseAuthException catch (e) {
          // Server-side deleteUserData already erases the Firebase Auth user.
          if (e.code != 'user-not-found' && e.code != 'user-disabled') {
            rethrow;
          }
        }
      }

      await signOut();
      _errorMessage = null;
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
      _setLoading(false);
      return false;
    } catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
      _setLoading(false);
      return false;
    }
  }

  Future<Map<String, dynamic>> requestEmailOtp({
    required String purpose,
    String? email,
  }) async {
    final targetEmail = (email ?? currentUserEmail).trim().toLowerCase();
    try {
      return await _emailOtpService.requestEmailOtp(
        purpose: purpose,
        email: targetEmail,
      );
    } catch (e) {
      // If Cloud Functions OTP delivery is unavailable on the Firebase project during signup,
      // also dispatch Firebase Auth's native verification email link as a resilient fallback.
      if (purpose == 'signup' && _currentUser != null) {
        try {
          await _currentUser!.sendEmailVerification();
        } catch (e, s) {
          AppLogger.w('Fallback Firebase verification email failed',
              tag: 'AuthVM', error: e, stackTrace: s);
        }
      }
      rethrow;
    }
  }

  /// Sends a native Firebase Authentication verification email link and returns true if dispatched.
  Future<bool> sendFirebaseVerificationLink() async {
    final user = _currentUser;
    if (user == null) return false;
    try {
      await user.sendEmailVerification();
      return true;
    } catch (e, s) {
      AppLogger.w('sendEmailVerification failed: $e',
          tag: 'AuthVM', error: e, stackTrace: s);
      return false;
    }
  }

  /// Checks whether the user has verified their email via Firebase Auth's verification link
  /// or server-side Firestore `emailOtpVerified` flag, and syncs local + Firestore state.
  Future<bool> checkEmailVerificationStatus() async {
    final user = _currentUser;
    if (user == null) return false;
    try {
      await user.reload();
      _currentUser = _firebaseAuth?.currentUser ?? user;
      await _currentUser?.getIdToken(true);
    } catch (e, s) {
      AppLogger.w('User reload failed during verification check',
          tag: 'AuthVM', error: e, stackTrace: s);
    }

    try {
      final freshProfile = await _userRepository.getUserProfile(user.uid);
      if (freshProfile != null) {
        _userProfile = freshProfile;
      }
    } catch (e, s) {
      AppLogger.w('Profile refresh failed during verification check',
          tag: 'AuthVM', error: e, stackTrace: s);
    }

    if ((_currentUser?.emailVerified ?? false) ||
        (_userProfile?.emailOtpVerified ?? false)) {
      _cachedEmailOtpVerified = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('remedy_verified_${user.uid}', true);
      } catch (e, s) {
        AppLogger.w('Failed to persist local verified cache',
            tag: 'AuthVM', error: e, stackTrace: s);
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> verifyEmailOtp(
    String code, {
    required String purpose,
  }) async {
    _setLoading(true);
    try {
      final success = await _emailOtpService.verifyEmailOtp(
        code: code,
        purpose: purpose,
      );

      if (success) {
        if (purpose == 'signup') {
          try {
            await _currentUser?.reload();
            _currentUser = _firebaseAuth?.currentUser ?? _currentUser;
            await _currentUser?.getIdToken(true);
          } catch (e, s) {
            AppLogger.w('Token reload failed after OTP verification',
                tag: 'AuthVM', error: e, stackTrace: s);
          }

          // Server-side verifyEmailOtp Cloud Function has persisted emailOtpVerified: true
          // and updated the JWT custom claim; refresh profile from Firestore without client self-certification.
          try {
            if (currentUserId.isNotEmpty) {
              final freshProfile =
                  await _userRepository.getUserProfile(currentUserId);
              if (freshProfile != null) {
                _userProfile = freshProfile;
              }
            }
          } catch (e, s) {
            AppLogger.w('Profile reload notice after OTP verify: $e',
                tag: 'AuthVM', error: e, stackTrace: s);
          }

          _cachedEmailOtpVerified = true;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('remedy_verified_$currentUserId', true);
          } catch (e, s) {
            AppLogger.w('Non-fatal local verification cache write: $e',
                tag: 'AuthVM', error: e, stackTrace: s);
          }
        }
        _errorMessage = null;
        _setLoading(false);
        notifyListeners();
        return true;
      }
      _setLoading(false);
      return false;
    } catch (e) {
      _setLoading(false);
      rethrow;
    }
  }

  Future<bool> reauthenticateForSensitiveAction({
    String? password,
    bool useGoogle = false,
    bool useApple = false,
    String? otpCode,
  }) async {
    _setLoading(true);
    _errorMessage = null;

    final user = _currentUser;
    if (user == null) {
      _errorMessage = 'No active session found.';
      _setLoading(false);
      return false;
    }

    try {
      if (password != null && password.isNotEmpty) {
        if (user.email == null) {
          _errorMessage = 'Current account does not have an associated email.';
          _setLoading(false);
          return false;
        }
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: password,
        );
        await user.reauthenticateWithCredential(credential);
        _setLoading(false);
        return true;
      }

      if (useGoogle) {
        if (kIsWeb) {
          final googleProvider = GoogleAuthProvider();
          await user.reauthenticateWithPopup(googleProvider);
          _setLoading(false);
          return true;
        }

        await _ensureGoogleInitialized();
        final account = await GoogleSignIn.instance.authenticate();
        final googleAuth = account.authentication;
        String? accessToken;
        try {
          final authClient = await account.authorizationClient
              .authorizationForScopes(['email']);
          accessToken = authClient?.accessToken;
        } catch (e, s) {
          AppLogger.w('Google reauth email scope access token unavailable',
              tag: 'AuthVM', error: e, stackTrace: s);
        }

        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
          accessToken: accessToken,
        );
        await user.reauthenticateWithCredential(credential);
        _setLoading(false);
        return true;
      }

      if (useApple) {
        if (kIsWeb) {
          final appleProvider = OAuthProvider('apple.com');
          appleProvider.addScope('email');
          appleProvider.addScope('name');
          await user.reauthenticateWithPopup(appleProvider);
          _setLoading(false);
          return true;
        }

        final appleCredential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );
        final OAuthCredential credential = OAuthProvider('apple.com').credential(
          idToken: appleCredential.identityToken,
          accessToken: appleCredential.authorizationCode,
        );
        await user.reauthenticateWithCredential(credential);
        _setLoading(false);
        return true;
      }

      if (otpCode != null && otpCode.isNotEmpty) {
        final verified = await _emailOtpService.verifyEmailOtp(
          code: otpCode,
          purpose: 'reauth',
        );
        _setLoading(false);
        return verified;
      }

      _errorMessage = 'No valid re-authentication method provided.';
      _setLoading(false);
      return false;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _getFriendlyFirebaseAuthError(e.code, e.message);
      _setLoading(false);
      return false;
    } catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
      _setLoading(false);
      return false;
    }
  }

  /// Changes the signed-in password user's password after re-authenticating with [currentPassword].
  /// Maps every Firebase Auth failure code to a clear, user-friendly error message and never logs passwords.
  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_isChangingPassword) {
      return const Failure(
        ValidationException('A password update is already in progress.'),
      );
    }

    final user = _currentUser;
    if (user == null || user.email == null || user.email!.trim().isEmpty) {
      const err = AuthException(
        'Your session has expired. Please sign in again.',
        code: 'NO_ACTIVE_SESSION',
      );
      _errorMessage = err.message;
      notifyListeners();
      return const Failure(err);
    }

    if (!hasPasswordProvider) {
      const err = ValidationException(
        'This account signs in with Google/Apple. Use "Set a password" or manage your password with that provider.',
        code: 'NO_PASSWORD_PROVIDER',
      );
      _errorMessage = err.message;
      notifyListeners();
      return const Failure(err);
    }

    if (currentPassword.isEmpty) {
      const err = ValidationException(
        'Please enter your current password.',
        code: 'CURRENT_PASSWORD_REQUIRED',
      );
      _errorMessage = err.message;
      notifyListeners();
      return const Failure(err);
    }

    final newPasswordValidation = _validateNewPassword(
      newPassword,
      currentPassword: currentPassword,
    );
    if (newPasswordValidation != null) {
      _errorMessage = newPasswordValidation.message;
      notifyListeners();
      return Failure(newPasswordValidation);
    }

    if (!_isOnline()) {
      const err = NetworkException(
        'You are offline. Connect to the internet to change your password.',
        code: 'OFFLINE',
      );
      _errorMessage = err.message;
      notifyListeners();
      return const Failure(err);
    }

    _isChangingPassword = true;
    _setLoading(true);
    _errorMessage = null;

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!.trim(),
        password: currentPassword,
      );
      await user
          .reauthenticateWithCredential(credential)
          .timeout(const Duration(seconds: 15));
      await user
          .updatePassword(newPassword)
          .timeout(const Duration(seconds: 15));
      try {
        await user.getIdToken(true).timeout(const Duration(seconds: 10));
      } catch (_) {}

      _errorMessage = null;
      return const Success(null);
    } on FirebaseAuthException catch (e, stack) {
      final mapped = _mapChangePasswordAuthError(e);
      _errorMessage = mapped.message;
      if (e.code == 'user-not-found' ||
          e.code == 'user-token-expired' ||
          e.code == 'user-disabled') {
        await signOut(discardPendingIntakes: false);
      }
      if (mapped is UnknownException) {
        unawaited(CrashlyticsService.recordError(
          FirebaseAuthException(code: e.code),
          stack,
          reason: 'changePassword unexpected FirebaseAuthException',
        ));
      }
      return Failure(mapped);
    } on TimeoutException {
      const err = NetworkException(
        'Network error. Check your connection and try again.',
        code: 'NETWORK_TIMEOUT',
      );
      _errorMessage = err.message;
      return const Failure(err);
    } catch (e, stack) {
      const err = UnknownException(
        'Could not change password. Please try again.',
        code: 'CHANGE_PASSWORD_FAILED',
      );
      _errorMessage = err.message;
      unawaited(CrashlyticsService.recordError(
        Exception('changePassword failed: ${e.runtimeType}'),
        stack,
        reason: 'changePassword unexpected error',
      ));
      return const Failure(err);
    } finally {
      _isChangingPassword = false;
      _setLoading(false);
    }
  }

  /// Links an email/password credential to a Google/Apple-only account so the user can also sign in with a password.
  Future<Result<void>> setPassword({required String newPassword}) async {
    if (_isChangingPassword) {
      return const Failure(
        ValidationException('A password update is already in progress.'),
      );
    }

    final user = _currentUser;
    if (user == null || user.email == null || user.email!.trim().isEmpty) {
      const err = AuthException(
        'Your session has expired. Please sign in again.',
        code: 'NO_ACTIVE_SESSION',
      );
      _errorMessage = err.message;
      notifyListeners();
      return const Failure(err);
    }

    if (hasPasswordProvider) {
      const err = ValidationException(
        'A password is already set on this account. Use Change Password instead.',
        code: 'PROVIDER_ALREADY_LINKED',
      );
      _errorMessage = err.message;
      notifyListeners();
      return const Failure(err);
    }

    final validationError = _validateNewPassword(newPassword);
    if (validationError != null) {
      _errorMessage = validationError.message;
      notifyListeners();
      return Failure(validationError);
    }

    if (!_isOnline()) {
      const err = NetworkException(
        'You are offline. Connect to the internet to set a password.',
        code: 'OFFLINE',
      );
      _errorMessage = err.message;
      notifyListeners();
      return const Failure(err);
    }

    _isChangingPassword = true;
    _setLoading(true);
    _errorMessage = null;

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!.trim(),
        password: newPassword,
      );
      await user
          .linkWithCredential(credential)
          .timeout(const Duration(seconds: 15));
      try {
        await user.reload().timeout(const Duration(seconds: 10));
        _currentUser = _firebaseAuth?.currentUser ?? user;
        await _currentUser?.getIdToken(true);
      } catch (_) {}

      _errorMessage = null;
      return const Success(null);
    } on FirebaseAuthException catch (e, stack) {
      final AppException mapped;
      switch (e.code) {
        case 'provider-already-linked':
          mapped = const ValidationException(
            'A password is already set on this account.',
            code: 'PROVIDER_ALREADY_LINKED',
          );
          break;
        case 'credential-already-in-use':
        case 'email-already-in-use':
          mapped = const AuthException(
            'This email is already linked to another password account.',
            code: 'CREDENTIAL_ALREADY_IN_USE',
          );
          break;
        default:
          mapped = _mapChangePasswordAuthError(e);
      }
      _errorMessage = mapped.message;
      if (mapped is UnknownException) {
        unawaited(CrashlyticsService.recordError(
          FirebaseAuthException(code: e.code),
          stack,
          reason: 'setPassword unexpected FirebaseAuthException',
        ));
      }
      return Failure(mapped);
    } on TimeoutException {
      const err = NetworkException(
        'Network error. Check your connection and try again.',
        code: 'NETWORK_TIMEOUT',
      );
      _errorMessage = err.message;
      return const Failure(err);
    } catch (e, stack) {
      const err = UnknownException(
        'Could not set password. Please try again.',
        code: 'SET_PASSWORD_FAILED',
      );
      _errorMessage = err.message;
      unawaited(CrashlyticsService.recordError(
        Exception('setPassword failed: ${e.runtimeType}'),
        stack,
        reason: 'setPassword unexpected error',
      ));
      return const Failure(err);
    } finally {
      _isChangingPassword = false;
      _setLoading(false);
    }
  }

  ValidationException? _validateNewPassword(
    String newPassword, {
    String? currentPassword,
  }) {
    if (newPassword.isEmpty) {
      return const ValidationException(
        'Please enter a new password.',
        code: 'NEW_PASSWORD_REQUIRED',
      );
    }
    if (newPassword != newPassword.trim()) {
      return const ValidationException(
        'New password cannot start or end with spaces.',
        code: 'PASSWORD_WHITESPACE',
      );
    }
    if (newPassword.length < AppConstants.minPasswordLength ||
        newPassword.length > AppConstants.maxPasswordLength) {
      return const ValidationException(
        'New password must be between ${AppConstants.minPasswordLength} and ${AppConstants.maxPasswordLength} characters.',
        code: 'PASSWORD_LENGTH',
      );
    }
    if (!isPasswordCompliant(newPassword)) {
      return const ValidationException(
        'New password must be at least ${AppConstants.minPasswordLength} characters and include both letters and numbers.',
        code: 'WEAK_PASSWORD',
      );
    }
    if (currentPassword != null && newPassword == currentPassword) {
      return const ValidationException(
        'New password must be different from your current password.',
        code: 'PASSWORD_UNCHANGED',
      );
    }
    return null;
  }

  static AppException _mapChangePasswordAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return AuthException(
          'Current password is incorrect.',
          code: e.code,
        );
      case 'weak-password':
        return ValidationException(
          'New password is too weak. Use at least 8 characters with letters and numbers.',
          code: e.code,
        );
      case 'requires-recent-login':
        return AuthException(
          'For security, please sign in again and retry.',
          code: e.code,
        );
      case 'too-many-requests':
        return RateLimitException(
          'Too many attempts. Please wait a few minutes and try again.',
          code: e.code,
        );
      case 'network-request-failed':
        return NetworkException(
          'Network error. Check your connection and try again.',
          code: e.code,
        );
      case 'user-mismatch':
        return AuthException(
          'Account credentials do not match the signed-in user.',
          code: e.code,
        );
      case 'user-not-found':
      case 'user-token-expired':
        return AuthException(
          'Your session has expired. Please sign in again.',
          code: e.code,
        );
      case 'user-disabled':
        return AuthException(
          'This account has been disabled. Please contact support.',
          code: e.code,
        );
      default:
        return UnknownException(
          'Could not change password. Please try again.',
          code: e.code,
        );
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _authSubscription?.cancel();
    super.dispose();
  }
}
