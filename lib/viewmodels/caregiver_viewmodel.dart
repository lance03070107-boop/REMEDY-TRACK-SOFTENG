import 'dart:async';
import 'package:flutter/material.dart';
import '../core/errors/app_exception.dart';
import '../core/errors/error_mapper.dart';
import '../models/caregiver_relationship.dart';
import '../models/user_profile.dart';
import '../repositories/caregiver_repository.dart';
import '../repositories/user_repository.dart';
import '../services/crashlytics_service.dart';
import '../services/fcm_service.dart';

/// ViewModel managing Caregiver linking, single-use pairing codes (24h expiry),
/// dependent profile switching, and read-only mode enforcement.
class CaregiverViewModel extends ChangeNotifier {
  final CaregiverRepository _caregiverRepository;
  final UserRepository _userRepository;
  final FcmService _fcmService;

  List<CaregiverRelationship> _myCaregivers = [];
  List<CaregiverRelationship> _myDependents = [];
  List<UserProfile> _dependents = [];
  CaregiverInvite? _activeInvite;
  String? _activeProfileId;
  String? _activeProfileName;
  bool _isLoading = false;
  bool _isMutating = false;
  String? _errorMessage;
  String? _successMessage;

  CaregiverViewModel({
    CaregiverRepository? caregiverRepository,
    required UserRepository userRepository,
    FcmService? fcmService,
  })  : _caregiverRepository =
            caregiverRepository ?? FirebaseCaregiverRepository(),
        _userRepository = userRepository,
        _fcmService = fcmService ?? FcmService();

  List<CaregiverRelationship> get myCaregivers => _myCaregivers;
  List<CaregiverRelationship> get myDependents => _myDependents;
  List<UserProfile> get dependents => _dependents;
  CaregiverInvite? get activeInvite => _activeInvite;
  String? get activeProfileId => _activeProfileId;
  String? get activeProfileName => _activeProfileName;
  String? get activeProfileEmail {
    final id = _activeProfileId;
    if (id == null) return null;
    return _dependents
        .cast<UserProfile?>()
        .firstWhere((p) => p?.id == id, orElse: () => null)
        ?.email;
  }

  bool get isCaregiverMode => _activeProfileId != null;
  bool get isLoading => _isLoading;
  bool get isMutating => _isMutating;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  /// Clears caregiver state on sign-out or account switch to prevent cross-account leakage.
  void resetState() {
    _myCaregivers = [];
    _myDependents = [];
    _dependents = [];
    _activeInvite = null;
    _activeProfileId = null;
    _activeProfileName = null;
    _isLoading = false;
    _isMutating = false;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  /// Sets the active viewing profile. When [profileId] is non-null,
  /// the app switches into Caregiver Read-Only mode for that dependent.
  void setActiveProfile(String? profileId, [String? profileName]) {
    _activeProfileId = profileId;
    _activeProfileName = profileName;
    notifyListeners();
  }

  /// Refreshes all caregiver relationships and active pairing invitations.
  Future<void> loadCaregiverData(String currentUserId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _caregiverRepository.getCaregiversForPatient(currentUserId),
        _caregiverRepository.getDependentsForCaregiver(currentUserId),
        _caregiverRepository.getActiveInvite(currentUserId),
      ]);

      _myCaregivers = results[0] as List<CaregiverRelationship>;
      _myDependents = results[1] as List<CaregiverRelationship>;
      _activeInvite = results[2] as CaregiverInvite?;

      // Fetch user profile objects for dependents
      final dependentProfiles = <UserProfile>[];
      for (final rel in _myDependents) {
        final profile = await _userRepository.getUserProfile(rel.patientId);
        if (profile != null) {
          dependentProfiles.add(profile);
        }
      }
      _dependents = dependentProfiles;
    } catch (e, stack) {
      _errorMessage = ErrorMapper.map(e, stack).message;
      unawaited(CrashlyticsService.recordError(e, stack));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Generates a single-use 6-character alphanumeric pairing code valid for 24 hours.
  Future<CaregiverInvite?> generatePairingCode({
    required String patientId,
    required String patientName,
  }) async {
    if (patientId.trim().isEmpty) {
      _errorMessage = 'Please sign in again before generating a pairing code.';
      notifyListeners();
      return null;
    }

    _isMutating = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final invite = await _caregiverRepository.createPairingInvite(
        patientId: patientId,
        patientName: patientName,
      );
      _activeInvite = invite;
      _successMessage = 'New pairing code generated: ${invite.code}';
      return invite;
    } catch (e, stack) {
      if (e is AppException) {
        _errorMessage = e.message;
      } else {
        _errorMessage = ErrorMapper.map(e, stack).message;
        unawaited(CrashlyticsService.recordError(e, stack));
      }
      return null;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Redeems a 6-character single-use pairing code to establish bi-directional linkage.
  Future<bool> redeemPairingCode({
    required String code,
    required String caregiverId,
    required String caregiverName,
  }) async {
    _isMutating = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final rel = await _caregiverRepository.acceptPairingInvite(
        code: code,
        caregiverId: caregiverId,
        caregiverName: caregiverName,
      );
      _successMessage = 'Successfully linked to ${rel.patientName}.';
      await loadCaregiverData(caregiverId);
      return true;
    } catch (e, stack) {
      if (e is AppException) {
        _errorMessage = e.message;
      } else {
        _errorMessage = ErrorMapper.map(e, stack).message;
        unawaited(CrashlyticsService.recordError(e, stack));
      }
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Revokes caregiver access bi-directionally.
  Future<void> revokeCaregiverAccess({
    required String patientId,
    required String caregiverId,
    required String currentUserId,
  }) async {
    _isMutating = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      await _caregiverRepository.revokeRelationship(
        patientId: patientId,
        caregiverId: caregiverId,
        revokedBy: currentUserId,
      );

      // If active profile was this patient, reset to self
      if (_activeProfileId == patientId) {
        _activeProfileId = null;
        _activeProfileName = null;
      }

      _successMessage = 'Caregiver link successfully revoked.';
      await loadCaregiverData(currentUserId);
    } catch (e, stack) {
      if (e is AppException) {
        _errorMessage = e.message;
      } else {
        _errorMessage = ErrorMapper.map(e, stack).message;
        unawaited(CrashlyticsService.recordError(e, stack));
      }
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Legacy load dependents method preserved for backwards compatibility.
  Future<void> loadDependents(List<String> dependentIds) async {
    _isLoading = true;
    notifyListeners();

    _dependents = [];
    for (final id in dependentIds) {
      final profile = await _userRepository.getUserProfile(id);
      if (profile != null) {
        _dependents.add(profile);
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Dispatches missed-dose alert to caregiver's device.
  Future<void> notifyCaregiverOnMissedDose({
    required String dependentName,
    required String medicationName,
    required String scheduledTime,
    required String caregiverToken,
    String? patientId,
    String? caregiverId,
  }) async {
    await _fcmService.sendCaregiverMissedAlert(
      dependentName: dependentName,
      medicationName: medicationName,
      scheduledTime: scheduledTime,
      caregiverToken: caregiverToken,
      patientId: patientId,
      caregiverId: caregiverId,
    );
  }
}
