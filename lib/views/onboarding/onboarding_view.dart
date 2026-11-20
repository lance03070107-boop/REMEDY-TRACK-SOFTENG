import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../services/permission_service.dart';

class OnboardingSlide {
  final IconData icon;
  final String title;
  final String description;
  final String? permissionType;

  const OnboardingSlide({
    required this.icon,
    required this.title,
    required this.description,
    this.permissionType,
  });
}

/// Onboarding screen requesting contextual permissions for alarms and background execution.
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  final PageController _pageController = PageController();
  final PermissionService _permissionService = PermissionService();
  int _currentIndex = 0;

  final List<OnboardingSlide> _slides = const [
    OnboardingSlide(
      icon: Icons.access_alarms_rounded,
      title: 'Never Miss a Prescribed Dose',
      description:
          'RemedyTrack schedules exact, loud alarms that wake your phone even when silent or battery saver is enabled.',
      permissionType: 'alarm',
    ),
    OnboardingSlide(
      icon: Icons.notifications_active_rounded,
      title: 'Interactive Lock-Screen Reminders',
      description:
          'Take, snooze, or skip medications straight from your lock-screen notification banner without opening the app.',
      permissionType: 'notification',
    ),
    OnboardingSlide(
      icon: Icons.battery_charging_full_rounded,
      title: 'Battery Saver Exemption',
      description:
          'Aggressive phone manufacturers (Samsung, Xiaomi, Oppo) kill reminder apps. RemedyTrack requests exemption to ensure alerts fire 100% on time.',
      permissionType: 'battery',
    ),
    OnboardingSlide(
      icon: Icons.security_rounded,
      title: 'Your Health Data Stays Private',
      description:
          'Protected under Philippine RA 10173. Your medication list stays private on your device and in your encrypted account, with app lock protection.',
    ),
  ];

  Future<void> _handlePermissionRequest(String type) async {
    if (type == 'alarm') {
      await _permissionService.requestExactAlarmPermission();
    } else if (type == 'notification') {
      await _permissionService.requestNotificationPermission();
    } else if (type == 'battery') {
      await _permissionService.requestIgnoreBatteryOptimization();
    }
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyOnboardingComplete, true);
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLastSlide = _currentIndex == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              // Top Skip button
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _finishOnboarding,
                  child: const Text('Skip'),
                ),
              ),

              // Page Content
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (idx) => setState(() => _currentIndex = idx),
                  itemCount: _slides.length,
                  itemBuilder: (context, index) {
                    final item = _slides[index];
                    return Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                item.icon,
                                size: 50,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              item.title,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              item.description,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                            if (item.permissionType != null) ...[
                              const SizedBox(height: 24),
                              FilledButton.tonalIcon(
                                onPressed: () => _handlePermissionRequest(
                                    item.permissionType!),
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Grant Permission Now'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Page Indicators & Bottom Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(
                      _slides.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 6),
                        width: _currentIndex == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentIndex == i
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (isLastSlide) {
                        _finishOnboarding();
                      } else {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    child: Text(isLastSlide ? 'Get Started' : 'Next'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
