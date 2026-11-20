import 'app_exception.dart';

/// Types of dosage safety risks identified by RemedyTrack safeguards.
enum ClinicalSafetyRisk {
  duplicateDose,
  doseStacking,
  prnMinInterval,
  prnMaxDailyDose,
  expiredMedication,
}

/// Exception thrown or surfaced when a dosage action triggers a safety check.
class ClinicalSafetyException extends AppException {
  final ClinicalSafetyRisk risk;
  final String? clinicalRecommendation;
  final Map<String, dynamic>? safetyContext;

  const ClinicalSafetyException({
    required this.risk,
    required String message,
    this.clinicalRecommendation,
    this.safetyContext,
    String? code,
    dynamic details,
  }) : super(
          message,
          code: code ?? 'DOSAGE_SAFETY_CHECK',
          details: details ?? safetyContext,
        );

  @override
  String toString() =>
      clinicalRecommendation != null && clinicalRecommendation!.trim().isNotEmpty
          ? '$message\n$clinicalRecommendation'
          : message;
}
