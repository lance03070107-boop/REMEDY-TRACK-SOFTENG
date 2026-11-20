import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/views/widgets/main_navigation_shell.dart';

void main() {
  testWidgets(
      'MainNavigationShell renders bottom NavigationBar on mobile screens (<640px)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MainNavigationShell(
          currentLocation: '/home',
          child: Text('Dashboard Content'),
        ),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Dashboard Content'), findsOneWidget);
  });

  testWidgets(
      'MainNavigationShell renders side NavigationRail on tablet/desktop screens (>=640px)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MainNavigationShell(
          currentLocation: '/home',
          child: Text('Dashboard Content'),
        ),
      ),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Dashboard Content'), findsOneWidget);

    final brandLogoFinder =
        find.byKey(const ValueKey<String>('nav_rail_brand_logo'));
    expect(brandLogoFinder, findsOneWidget);
    final brandImage = tester.widget<Image>(brandLogoFinder);
    expect((brandImage.image as AssetImage).assetName,
        'assets/branding/app_icon.png');
    expect(find.byIcon(Icons.health_and_safety_rounded), findsNothing);
  });

  testWidgets(
      'MainNavigationShell removes Settings from bottom bar (4 primary tabs) and handles /settings safely',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MainNavigationShell(
          currentLocation: '/settings',
          child: Text('Settings Screen Content'),
        ),
      ),
    );

    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.destinations.length, 4);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Medications'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(
        find.widgetWithText(NavigationDestination, 'Settings'), findsNothing);
    expect(find.text('Settings Screen Content'), findsOneWidget);
  });
}
