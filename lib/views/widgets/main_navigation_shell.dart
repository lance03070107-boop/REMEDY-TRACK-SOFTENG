import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_strings.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/caregiver_viewmodel.dart';
import '../../viewmodels/intake_viewmodel.dart';
import '../../viewmodels/inventory_viewmodel.dart';
import '../../viewmodels/medication_viewmodel.dart';
import 'offline_banner.dart';

/// Responsive Material 3 Expressive navigation shell.
/// Uses a bottom [NavigationBar] on mobile screens (< 640dp) and
/// an adaptive side [NavigationRail] on tablets and desktop (>= 640dp).
class MainNavigationShell extends StatefulWidget {
  final Widget child;
  final String currentLocation;

  const MainNavigationShell({
    super.key,
    required this.child,
    required this.currentLocation,
  });

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  String? _boundUid;
  bool? _boundIsOwnProfile;

  void _ensureStreamsBound() {
    if (!mounted) return;
    AuthViewModel? authVm;
    CaregiverViewModel? caregiverVm;
    try {
      authVm = context.read<AuthViewModel>();
      caregiverVm = context.read<CaregiverViewModel>();
    } catch (_) {
      return;
    }
    if (!authVm.isAuthenticated) {
      _boundUid = null;
      _boundIsOwnProfile = null;
      return;
    }
    final uid = caregiverVm.activeProfileId ?? authVm.currentUserId;
    final isOwnProfile = !caregiverVm.isCaregiverMode;
    if (uid.isEmpty) return;

    if (_boundUid != uid || _boundIsOwnProfile != isOwnProfile) {
      _boundUid = uid;
      _boundIsOwnProfile = isOwnProfile;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          context.read<MedicationViewModel>().listenToMedications(
                uid,
                isOwnProfile: isOwnProfile,
              );
          context.read<InventoryViewModel>().listenToInventory(
                uid,
                isOwnProfile: isOwnProfile,
              );
          context.read<IntakeViewModel>().listenToIntakeLogs(uid);
        } catch (_) {}
      });
    }
  }

  int _calculateSelectedIndex(String location) {
    if (location.startsWith('/medications')) return 1;
    if (location.startsWith('/inventory')) return 2;
    if (location.startsWith('/insights') ||
        location.startsWith('/history') ||
        location.startsWith('/reports')) {
      return 3;
    }
    return 0; // Default to /home (including when viewing /settings)
  }

  void _onDestinationSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/medications');
        break;
      case 2:
        context.go('/inventory');
        break;
      case 3:
        context.go('/insights');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch auth and caregiver active profile so stream subscriptions automatically
    // attach or switch regardless of which route the user entered on.
    try {
      context.select<AuthViewModel, String>((vm) => vm.currentUserId);
      context.select<CaregiverViewModel, String?>((vm) => vm.activeProfileId);
      _ensureStreamsBound();
    } catch (_) {}

    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width >= 640;
    final selectedIndex = _calculateSelectedIndex(widget.currentLocation);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) =>
                  _onDestinationSelected(context, index),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Tooltip(
                  message: AppStrings.appName,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF9BD1F2),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.16),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/branding/app_icon.png',
                      key: const ValueKey<String>('nav_rail_brand_logo'),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.health_and_safety_rounded,
                        color: theme.colorScheme.onPrimaryContainer,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.today_outlined),
                  selectedIcon: Icon(Icons.today_rounded),
                  label: Text(AppStrings.navHome),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.medication_outlined),
                  selectedIcon: Icon(Icons.medication_rounded),
                  label: Text(AppStrings.navMedications),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2_rounded),
                  label: Text(AppStrings.navInventory),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights_rounded),
                  label: Text(AppStrings.navInsights),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: OfflineBanner(child: widget.child)),
          ],
        ),
      );
    }

    return Scaffold(
      body: OfflineBanner(child: widget.child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) =>
            _onDestinationSelected(context, index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today_rounded),
            label: AppStrings.navHome,
          ),
          NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            selectedIcon: Icon(Icons.medication_rounded),
            label: AppStrings.navMedications,
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: AppStrings.navInventory,
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: AppStrings.navInsights,
          ),
        ],
      ),
    );
  }
}
