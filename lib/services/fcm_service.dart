import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/app_logger.dart';
import 'crashlytics_service.dart';
import 'notification_service.dart';

/// Top-level background message handler for FCM.
/// Executed in an isolated background thread when push notifications arrive while app is terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  AppLogger.i('Handled background FCM message ID: ${message.messageId}',
      tag: 'FCM');
}

/// Service managing Firebase Cloud Messaging for device tokens and caregiver alerts.
class FcmService {
  final FirebaseMessaging? _fcm;
  final FirebaseFirestore? _firestore;
  static bool _isListenerConfigured = false;
  static void Function(String token)? _onTokenRefreshCallback;

  FcmService({FirebaseMessaging? fcm, FirebaseFirestore? firestore})
      : _fcm = fcm ?? _resolveMessaging(),
        _firestore = firestore ?? _resolveFirestore();

  static FirebaseMessaging? _resolveMessaging() {
    if (kIsWeb || Firebase.apps.isEmpty) {
      // Never instantiate FirebaseMessaging on Web (iOS Safari/WebKit throws
      // messaging/unsupported-browser synchronously when Push API is unavailable).
      return null;
    }
    try {
      return FirebaseMessaging.instance;
    } catch (e) {
      AppLogger.w('FCM instance unavailable on this platform: $e', tag: 'FCM');
      return null;
    }
  }

  static FirebaseFirestore? _resolveFirestore() {
    if (Firebase.apps.isEmpty) return null;
    try {
      return FirebaseFirestore.instance;
    } catch (e, stack) {
      AppLogger.w('Firestore instance unavailable for FCM: $e', tag: 'FCM');
      CrashlyticsService.recordError(e, stack,
          reason: 'FcmService._resolveFirestore');
      return null;
    }
  }

  void setTokenRefreshCallback(void Function(String token) callback) {
    _onTokenRefreshCallback = callback;
  }

  Future<String?> initializeAndGetToken() async {
    if (kIsWeb) {
      // FCM web push notifications require custom service workers and registered VAPID keys
      return null;
    }
    final fcm = _fcm;
    if (fcm == null) {
      return null;
    }

    try {
      final settings = await fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await fcm.getToken();

        // Setup foreground and token refresh listeners strictly once
        if (!_isListenerConfigured) {
          _isListenerConfigured = true;

          FirebaseMessaging.onMessage.listen((RemoteMessage message) {
            AppLogger.i(
                'Foreground FCM notification received: ${message.messageId}',
                tag: 'FCM');
            final title = message.notification?.title ??
                (message.data['title'] as String?) ??
                'RemedyTrack Alert';
            final body = message.notification?.body ??
                (message.data['body'] as String?) ??
                'A scheduled medication update is available.';
            NotificationService().showCaregiverAlert(
              title: title,
              body: body,
              payload: message.data['type']?.toString(),
            );
          });

          fcm.onTokenRefresh.listen((newToken) async {
            AppLogger.i('FCM Token refreshed, persisting to user profile',
                tag: 'FCM');
            _onTokenRefreshCallback?.call(newToken);

            // Persist token refresh to active user profile
            try {
              final user = FirebaseAuth.instance.currentUser;
              final firestore = _firestore;
              if (user != null && firestore != null) {
                await firestore
                    .collection(AppConstants.colUsers)
                    .doc(user.uid)
                    .update({
                  'fcmToken': newToken,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
              }
            } catch (e) {
              AppLogger.w(
                  'Failed to persist refreshed FCM token to Firestore: $e',
                  tag: 'FCM');
            }
          });

          FirebaseMessaging.onBackgroundMessage(
              firebaseMessagingBackgroundHandler);
        }

        return token;
      }
      return null;
    } catch (e) {
      AppLogger.w('FCM initialization notice: $e', tag: 'FCM');
      return null;
    }
  }

  /// Sends a caregiver missed dose alert by persisting to Firestore /caregiver_alerts queue
  Future<void> sendCaregiverMissedAlert({
    required String dependentName,
    required String medicationName,
    required String scheduledTime,
    required String caregiverToken,
    String? patientId,
    String? caregiverId,
  }) async {
    final firestore = _firestore;
    final cleanPatientId = (patientId ?? '').trim();
    final cleanCaregiverId = (caregiverId ?? '').trim();
    final cleanToken = caregiverToken.trim();
    if (firestore != null &&
        cleanPatientId.isNotEmpty &&
        cleanCaregiverId.isNotEmpty &&
        cleanToken.isNotEmpty) {
      try {
        await firestore.collection('caregiver_alerts').add({
          'dependentName': dependentName,
          'medicationName': medicationName,
          'scheduledTime': scheduledTime,
          'caregiverToken': cleanToken,
          'patientId': cleanPatientId,
          'caregiverId': cleanCaregiverId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        AppLogger.w('Failed to write caregiver alert document: $e', tag: 'FCM');
      }
    }

    AppLogger.i(
      'Caregiver notification queued for $dependentName: Missed $medicationName at $scheduledTime',
      tag: 'FCM',
    );
  }
}
