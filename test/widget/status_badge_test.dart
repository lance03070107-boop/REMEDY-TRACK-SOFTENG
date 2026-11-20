import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/constants/app_strings.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/models/intake_log.dart';
import 'package:remedy_track/views/widgets/status_badge.dart';

void main() {
  testWidgets('StatusBadge renders both text label and icon for Taken status',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: StatusBadge(status: DoseStatus.taken),
        ),
      ),
    );

    expect(find.text(AppStrings.statusTaken), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets(
      'StatusBadge renders Peach low-stock badge when isLowStock is true',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: StatusBadge(
            status: DoseStatus.pending,
            isLowStock: true,
          ),
        ),
      ),
    );

    expect(find.text(AppStrings.statusLowStock), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
