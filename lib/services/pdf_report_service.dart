import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/utils/date_time_utils.dart';
import '../models/adherence_pattern.dart';
import '../models/intake_log.dart';
import '../models/medication.dart';

/// Generates standardized clinical intake and adherence reports ready for doctor appointments.
class PdfReportService {
  Future<Uint8List> generateDoctorReport({
    required String patientName,
    required String patientEmail,
    required double adherencePercentage,
    required List<Medication> medications,
    required List<IntakeLog> logs,
    required DateTime startDate,
    required DateTime endDate,
    MissedDosePattern? pattern,
  }) async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final rangeFormat = DateFormat('MMM dd, yyyy');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'RemedyTrack Medication Report',
                      style: const pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Patient: $patientName ($patientEmail)',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                    pw.Text(
                      'Reporting Period: ${rangeFormat.format(startDate)} - ${rangeFormat.format(endDate)}',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: adherencePercentage >= 80
                        ? PdfColors.green100
                        : PdfColors.amber100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'On-Time Rate',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                      pw.Text(
                        '${adherencePercentage.toStringAsFixed(1)}%',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: adherencePercentage >= 80
                              ? PdfColors.green900
                              : PdfColors.amber900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.Divider(height: 24),

            // Active Medications Section
            pw.Text(
              'Prescribed Medication Summary',
              style: const pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: [
                'Medication',
                'Dosage Strength',
                'Form',
                'Amount per Dose',
              ],
              data: medications.map((m) {
                return [
                  m.name,
                  m.strength,
                  m.form.name,
                  '${m.doseAmount}',
                ];
              }).toList(),
              headerStyle: const pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellHeight: 22,
            ),
            if (pattern != null) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Most Commonly Missed Time',
                style: const pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Pattern Summary: ${pattern.insightSentence}',
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.blueGrey800),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: [
                  'Time Slot',
                  'Window',
                  'Missed Count',
                  '% of Missed Doses'
                ],
                data: [
                  [
                    'Morning',
                    '05:00 - 11:59',
                    '${pattern.timeOfDayCounts[TimeBucket.morning] ?? 0}',
                    pattern.totalMissed > 0
                        ? '${(((pattern.timeOfDayCounts[TimeBucket.morning] ?? 0) / pattern.totalMissed) * 100).toStringAsFixed(1)}%'
                        : '0.0%',
                  ],
                  [
                    'Afternoon',
                    '12:00 - 16:59',
                    '${pattern.timeOfDayCounts[TimeBucket.afternoon] ?? 0}',
                    pattern.totalMissed > 0
                        ? '${(((pattern.timeOfDayCounts[TimeBucket.afternoon] ?? 0) / pattern.totalMissed) * 100).toStringAsFixed(1)}%'
                        : '0.0%',
                  ],
                  [
                    'Evening',
                    '17:00 - 20:59',
                    '${pattern.timeOfDayCounts[TimeBucket.evening] ?? 0}',
                    pattern.totalMissed > 0
                        ? '${(((pattern.timeOfDayCounts[TimeBucket.evening] ?? 0) / pattern.totalMissed) * 100).toStringAsFixed(1)}%'
                        : '0.0%',
                  ],
                  [
                    'Night',
                    '21:00 - 04:59',
                    '${pattern.timeOfDayCounts[TimeBucket.night] ?? 0}',
                    pattern.totalMissed > 0
                        ? '${(((pattern.timeOfDayCounts[TimeBucket.night] ?? 0) / pattern.totalMissed) * 100).toStringAsFixed(1)}%'
                        : '0.0%',
                  ],
                ],
                headerStyle: const pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                cellHeight: 18,
              ),
            ],
            pw.SizedBox(height: 24),

            // Detailed Intake History
            pw.Text(
              'Detailed Dose Log History',
              style: const pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: [
                'Scheduled Time',
                'Medication',
                'Status',
                'Recorded Time',
                'Notes'
              ],
              data: logs.map((log) {
                final rawNotes = log.notes ?? '';
                final cleanNotes = (rawNotes.startsWith('Recorded via ') ||
                        rawNotes.startsWith('Skipped via '))
                    ? ''
                    : rawNotes;
                return [
                  dateFormat.format(log.scheduledTime),
                  log.medicationName,
                  log.status.name.toUpperCase(),
                  log.recordedTime != null
                      ? dateFormat.format(log.recordedTime!)
                      : '--',
                  cleanNotes,
                ];
              }).toList(),
              headerStyle: const pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellHeight: 20,
            ),
            pw.SizedBox(height: 32),

            // RA 10173 & Medical Disclaimer Footer
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                'NOTICE: This medication record was generated with RemedyTrack under the Philippine Data Privacy Act (RA 10173). Share it with your doctor or pharmacist during visits. RemedyTrack is a reminder tool and does not provide medical advice or diagnoses.',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<void> printOrShareReport(Uint8List pdfData, String filename) async {
    await Printing.sharePdf(bytes: pdfData, filename: filename);
  }
}
