import 'package:flutter/foundation.dart';

/// Represents a bi-directional caregiver-patient relationship.
/// In accordance with RA 10173, access is strictly READ-ONLY and revocable at any time.
@immutable
class CaregiverRelationship {
  final String id;
  final String patientId;
  final String patientName;
  final String caregiverId;
  final String? caregiverName;
  final String status; // 'active', 'revoked'
  final List<String> permissions;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const CaregiverRelationship({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.caregiverId,
    this.caregiverName,
    required this.status,
    this.permissions = const ['view_adherence', 'receive_alerts'],
    required this.createdAt,
    this.updatedAt,
  });

  bool get isActive => status == 'active';

  factory CaregiverRelationship.fromJson(Map<String, dynamic> json) {
    return CaregiverRelationship(
      id: json['id'] as String? ?? '',
      patientId: json['patientId'] as String? ?? '',
      patientName: json['patientName'] as String? ?? 'Patient',
      caregiverId: json['caregiverId'] as String? ?? '',
      caregiverName: json['caregiverName'] as String?,
      status: json['status'] as String? ?? 'active',
      permissions: (json['permissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['view_adherence', 'receive_alerts'],
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] is String
              ? DateTime.parse(json['createdAt'] as String)
              : (json['createdAt'] as dynamic).toDate() as DateTime)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? (json['updatedAt'] is String
              ? DateTime.parse(json['updatedAt'] as String)
              : (json['updatedAt'] as dynamic).toDate() as DateTime?)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'caregiverId': caregiverId,
      if (caregiverName != null) 'caregiverName': caregiverName,
      'status': status,
      'permissions': permissions,
      'createdAt': createdAt.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

/// Represents a single-use 6-character pairing invitation code with 24-hour expiration.
@immutable
class CaregiverInvite {
  final String code;
  final String patientId;
  final String patientName;
  final String status; // 'pending', 'accepted', 'expired'
  final DateTime createdAt;
  final DateTime expiresAt;

  const CaregiverInvite({
    required this.code,
    required this.patientId,
    required this.patientName,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get timeRemaining {
    final diff = expiresAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  factory CaregiverInvite.fromJson(Map<String, dynamic> json) {
    return CaregiverInvite(
      code: json['code'] as String? ?? '',
      patientId: json['patientId'] as String? ?? '',
      patientName: json['patientName'] as String? ?? 'Patient',
      status: json['status'] as String? ?? 'pending',
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] is String
              ? DateTime.parse(json['createdAt'] as String)
              : (json['createdAt'] as dynamic).toDate() as DateTime)
          : DateTime.now(),
      expiresAt: json['expiresAt'] != null
          ? (json['expiresAt'] is String
              ? DateTime.parse(json['expiresAt'] as String)
              : (json['expiresAt'] as dynamic).toDate() as DateTime)
          : DateTime.now().add(const Duration(hours: 24)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'patientId': patientId,
      'patientName': patientName,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
    };
  }
}
