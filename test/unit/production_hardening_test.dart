import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/constants/app_constants.dart';
import 'package:remedy_track/core/errors/app_exception.dart';
import 'package:remedy_track/core/errors/error_mapper.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/core/theme/status_colors.dart';
import 'package:remedy_track/core/utils/date_time_utils.dart';
import 'package:remedy_track/core/validation/medication_validator.dart';
import 'package:remedy_track/models/medication.dart';

void main() {
  group('Production Hardening Verification', () {
    test('AppConstants enforces unified asia-southeast1 region and 9999 stock cap',
        () {
      expect(AppConstants.cloudFunctionsRegion, 'asia-southeast1');
      expect(AppConstants.maxStock, 9999.0);
      expect(AppConstants.minStock, 0.0);
    });

    test('MedicationValidator enforces 0-9999 stock bounds and rejects NaN/Inf',
        () {
      expect(MedicationValidator.validateStock('0', form: MedicationForm.tablet),
          isNull);
      expect(
          MedicationValidator.validateStock('9999', form: MedicationForm.tablet),
          isNull);
      expect(
          MedicationValidator.validateStock('10000', form: MedicationForm.tablet),
          isNotNull);
      expect(
          MedicationValidator.validateStock('-1', form: MedicationForm.tablet),
          isNotNull);
      expect(
          MedicationValidator.validateStock('NaN', form: MedicationForm.syrup),
          isNotNull);
      expect(
          MedicationValidator.validateStock('Infinity',
              form: MedicationForm.syrup),
          isNotNull);
    });

    test('ErrorMapper maps network, timeout, and validation errors cleanly',
        () {
      final socketMapped =
          ErrorMapper.map(const SocketException('No route to host'));
      expect(socketMapped, isA<NetworkException>());

      final timeoutMapped = ErrorMapper.map(TimeoutException('Timed out'));
      expect(timeoutMapped, isA<NetworkException>());

      final validationMapped =
          ErrorMapper.map(const ValidationException('Invalid dose'));
      expect(validationMapped, isA<ValidationException>());
    });

    testWidgets('StatusColors.of(context) resolves from AppTheme light & dark',
        (tester) async {
      StatusColors? lightStatus;
      StatusColors? darkStatus;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              lightStatus = StatusColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          themeAnimationDuration: Duration.zero,
          home: Builder(
            builder: (context) {
              darkStatus = StatusColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      expect(lightStatus, isNotNull);
      expect(darkStatus, isNotNull);
      expect(lightStatus!.taken, isNot(equals(darkStatus!.taken)));
    });

    test('MedicationValidator enforces form-specific whole vs decimal doses',
        () {
      expect(
        MedicationValidator.validateDoseAmount('0.5',
            form: MedicationForm.capsule),
        isNotNull,
      );
      expect(
        MedicationValidator.validateDoseAmount('0.5',
            form: MedicationForm.drops),
        isNotNull,
      );
      expect(
        MedicationValidator.validateDoseAmount('0.5',
            form: MedicationForm.inhaler),
        isNotNull,
      );
      expect(
        MedicationValidator.validateDoseAmount('2',
            form: MedicationForm.capsule),
        isNull,
      );
      expect(
        MedicationValidator.validateDoseAmount('0.5',
            form: MedicationForm.tablet),
        isNull,
      );
      expect(
        MedicationValidator.validateDoseAmount('2.5',
            form: MedicationForm.syrup),
        isNull,
      );
      expect(MedicationValidator.validateDoseAmount('0.5'), isNull);
    });

    test('MedicationValidator enforces character limits across text inputs',
        () {
      expect(
        MedicationValidator.validateNotes('a' * AppConstants.maxNotesLength),
        isNull,
      );
      expect(
        MedicationValidator.validateNotes(
            'a' * (AppConstants.maxNotesLength + 1)),
        isNotNull,
      );

      expect(
        MedicationValidator.validateSkipReason(
            'b' * AppConstants.maxSkipReasonLength),
        isNull,
      );
      expect(
        MedicationValidator.validateSkipReason(
            'b' * (AppConstants.maxSkipReasonLength + 1)),
        isNotNull,
      );

      expect(MedicationValidator.validateDisplayName('A'), isNotNull);
      expect(MedicationValidator.validateDisplayName('Al'), isNull);
      expect(
        MedicationValidator.validateDisplayName(
            'n' * (AppConstants.maxDisplayNameLength + 1)),
        isNotNull,
      );

      expect(MedicationValidator.validateEmail(''), isNotNull);
      expect(
        MedicationValidator.validateEmail(
            '${'a' * AppConstants.maxEmailLength}@example.com'),
        isNotNull,
      );
      expect(MedicationValidator.validateEmail('patient@remedytrack.ph'),
          isNull);

      expect(MedicationValidator.validatePassword('short1', isSignIn: false),
          isNotNull);
      expect(MedicationValidator.validatePassword('short1', isSignIn: true),
          isNull);
      expect(
        MedicationValidator.validatePassword(
            '${'a' * AppConstants.maxPasswordLength}1',
            isSignIn: false),
        isNotNull,
      );
      expect(
          MedicationValidator.validatePassword('SafePass123', isSignIn: false),
          isNull);
    });

    test('DateTimeUtils.tryParseFlexibleDateTime handles mixed date payloads',
        () {
      final exact = DateTime(2026, 11, 13, 8, 30);
      expect(DateTimeUtils.tryParseFlexibleDateTime(exact), equals(exact));

      final ts = Timestamp.fromMillisecondsSinceEpoch(1700000000500);
      expect(
        DateTimeUtils.tryParseFlexibleDateTime(ts)?.millisecondsSinceEpoch,
        equals(1700000000500),
      );

      expect(
        DateTimeUtils.tryParseFlexibleDateTime({
          'seconds': 1700000000,
          'nanoseconds': 250000000,
        })?.millisecondsSinceEpoch,
        equals(1700000000250),
      );

      expect(
        DateTimeUtils.tryParseFlexibleDateTime({
          '_seconds': 1700000000,
          '_nanoseconds': 500000000,
        })?.millisecondsSinceEpoch,
        equals(1700000000500),
      );

      expect(
        DateTimeUtils.tryParseFlexibleDateTime(1700000000000)
            ?.millisecondsSinceEpoch,
        equals(1700000000000),
      );

      expect(
        DateTimeUtils.tryParseFlexibleDateTime('2026-11-13T08:30:00.000Z')
            ?.isUtc,
        isTrue,
      );

      expect(DateTimeUtils.tryParseFlexibleDateTime('not-a-date'), isNull);
      expect(DateTimeUtils.tryParseFlexibleDateTime(null), isNull);
    });
  });
}
