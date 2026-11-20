import 'package:flutter/foundation.dart';
import '../core/utils/date_time_utils.dart';

/// Immutable model representing an authenticated user profile and caregiver relations.
@immutable
class UserProfile {
  final String id;
  final String email;
  final String displayName;
  final bool isCaregiver;
  final List<String> dependentIds;
  final List<String> caregiverIds;
  final String? fcmToken;
  final bool caregiverNotificationEnabled;
  final String? caregiverEmail;
  final bool emailOtpVerified;
  final String? phoneNumber;
  final bool phoneVerified;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    this.isCaregiver = false,
    this.dependentIds = const [],
    this.caregiverIds = const [],
    this.fcmToken,
    this.caregiverNotificationEnabled = false,
    this.caregiverEmail,
    this.emailOtpVerified = false,
    this.phoneNumber,
    this.phoneVerified = false,
    required this.createdAt,
  });

  UserProfile copyWith({
    String? id,
    String? email,
    String? displayName,
    bool? isCaregiver,
    List<String>? dependentIds,
    List<String>? caregiverIds,
    String? fcmToken,
    bool? caregiverNotificationEnabled,
    String? caregiverEmail,
    bool? emailOtpVerified,
    String? phoneNumber,
    bool? phoneVerified,
    DateTime? createdAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      isCaregiver: isCaregiver ?? this.isCaregiver,
      dependentIds: dependentIds ?? this.dependentIds,
      caregiverIds: caregiverIds ?? this.caregiverIds,
      fcmToken: fcmToken ?? this.fcmToken,
      caregiverNotificationEnabled:
          caregiverNotificationEnabled ?? this.caregiverNotificationEnabled,
      caregiverEmail: caregiverEmail ?? this.caregiverEmail,
      emailOtpVerified: emailOtpVerified ?? this.emailOtpVerified,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'isCaregiver': isCaregiver,
      'dependentIds': dependentIds,
      'caregiverIds': caregiverIds,
      'fcmToken': fcmToken,
      'caregiverNotificationEnabled': caregiverNotificationEnabled,
      'caregiverEmail': caregiverEmail,
      'emailOtpVerified': emailOtpVerified,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      'phoneVerified': phoneVerified,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'User',
      isCaregiver: json['isCaregiver'] as bool? ?? false,
      dependentIds: (json['dependentIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      caregiverIds: (json['caregiverIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      fcmToken: json['fcmToken'] as String?,
      caregiverNotificationEnabled:
          json['caregiverNotificationEnabled'] as bool? ?? false,
      caregiverEmail: json['caregiverEmail'] as String?,
      emailOtpVerified: json['emailOtpVerified'] as bool? ?? false,
      phoneNumber: json['phoneNumber'] as String?,
      phoneVerified: json['phoneVerified'] as bool? ?? false,
      createdAt: DateTimeUtils.tryParseFlexibleDateTime(json['createdAt']) ??
          DateTime.now(),
    );
  }
}
